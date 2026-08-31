# Upgrade Download Size

The record for the change that cut `bootc upgrade` from 1.42 GB to roughly
0.80 GB: what the 1.4 GB actually was, which four routes were taken, and which
five were measured and rejected.

**Every upgrade re-downloaded the whole image delta, because the delta was one
blob.**

---

## Context

A routine `sudo bootc upgrade` on 2026-08-31 reported:

```
layers already present: 260; layers needed: 6 (1.4 GB)
Fetched layers: 1.32 GiB in 55 seconds (24.38 MiB/s)
```

That is the daily steady state, not an outlier. The nightly cron skips
`--cache-from` by design, so the packages layer is rebuilt from scratch every
night and republished with a new digest whether or not a package changed.

Measured against the registry:

| Image | Layers | Bytes |
|---|---|---|
| `ghcr.io/ublue-os/base-main` (pinned digest) | 259 | 3,104,287,625 |
| `ghcr.io/marcortola/workstation-os-image:latest` | 266 | 4,671,812,442 |

The base is already rechunked and pinned, so its 259 layers are fetched once and
never again — that is the "260 layers already present". The seven this image
adds are the entire recurring cost:

| idx | bytes | source | churns? |
|---|---|---|---|
| 259 | 1,353,786,927 | `RUN 10-repos.sh && 20-packages.sh` | every build |
| 260 | 152,132,477 | `COPY --from=brew` | **never** — byte-stable across builds |
| 261 | 29,882,060 | `COPY --from=toolchain /staging/ /` | every build, on mtimes alone |
| 262 | 112,266 | `COPY system_files/ /` | every build |
| 263 | 635 | `COPY image.env` | every build |
| 264 | 31,610,223 | `RUN 30-desktop … 99-check-build` | every build |
| 265 | 229 | `RUN rm -rf /run/systemd && lint` | every build |

Six churning layers = 1,415,392,340 B = 1.3182 GiB, which is the reported
figure exactly. **95.6% of it is one blob**, arriving as a single HTTP stream
that measured 25.7 MB/s, so no amount of fetch parallelism touches it.

Two of the remaining layers turned out to be pure waste rather than payload:

- **Layer 264 was 98.6% a second copy of the rpmdb.** `90-cleanup.sh` ended with
  `ln -f /usr/share/rpm/rpmdb.sqlite /usr/lib/sysimage/rpm-ostree-base-db/`, and
  `ln -f` against a file that lives in a lower layer makes overlayfs copy the
  whole 90 MB database up to create the link. The blob carried
  `-rw-r--r-- 0/0 90222592 usr/lib/sysimage/rpm-ostree-base-db/rpmdb.sqlite`
  plus a zero-length hardlink entry for the original.
- **Layer 261 churned on timestamps only.** 49.7 MiB of its 49.75 MiB is
  bit-identical build to build — the two compiled binaries are reproducible, and
  the fonts come from a checksummed release — but the nerd-fonts tarball carries
  its own mtimes and `install -d` stamps the rest with the build date, and a
  layer's blob digest covers tar mtimes.

---

## Decision

Four changes, in the order of bytes returned per unit of risk.

| Change | Where | Recurring saving |
|---|---|---|
| Push as zstd level 10 | `.github/workflows/build.yml` | -330,482,179 B (-23.4%) |
| Drop `fcitx5-chinese-addons`, exclude `qt6-qtwebengine` | `build_files/packages/` | ~-141,709,068 B (-10.0%) |
| Move the rpmdb relink into the packages layer | `build_files/25-rpmdb.sh` | ~-31,489,000 B (-2.2%) |
| Zero `/staging` mtimes | `build_files/00-toolchain.sh` | -29,882,060 B (-2.1%) |

Together: roughly 1.42 GB to 0.80-0.85 GB, and a fetch of ~55 s to ~31 s. The
interactive command does not fall proportionally — measured post-download work
(unpack and import ~20 s, checkout 4.7 s, composefs 3.2 s, `/etc` merge 255 ms,
sudo and manifest ~4 s) is a ~39 s floor that no byte cut reaches.

### Why zstd and not `zstd:chunked`

`zstd:chunked` is the obvious answer and it is the wrong one here. bootc's
ostree backend fetches whole blobs by digest — `ostree-ext`
`unencapsulate.rs` calls `proxy.get_blob(img, layer.digest(), size)` with the
full compressed size — and `generic_decompress.rs` explicitly discards the
chunked table of contents. The partial-fetch feature that justifies the format
is unreachable from this code path. Measured on the real packages layer, the TOC
made it **11.2% larger** than plain zstd: 1,327,920,629 B against 1,194,198,572 B.

Plain zstd, by contrast, is decoded natively (`ImageLayerZstd => ZstdDecompressor`)
and the installed bootc 1.16.10 links `libzstd.so.1`.

### Why `--force-compression=false` is not optional

buildah sets `forceCompressionFormat = true` on its own whenever
`--compression-format` is passed and `--force-compression` is not
(`cmd/buildah/push.go`). Without the explicit `false`, the push recompresses and
re-uploads all 266 layers — including the base's 259 — which costs ~3.5 GB of
upload per build and hands every machine a full 4.67 GB re-download of an image
it already holds. The change inverts itself if the second flag is dropped, so
`tooling/validate/image-build` pins both literals.

### Why level 10 and not 19

containers/image maps the level through `zstd.EncoderLevelFromZstd`, and
klauspost maps anything `>= 10` to `SpeedBestCompression`. Levels 10, 15 and 19
produce byte-identical output; only the number differs.

---

## What lost

Five routes were investigated to the point of a measurement and rejected. They
are recorded because each is the obvious next idea.

**Rechunking with `hhd-dev/rechunk`.** The only lever that attacks layer
*granularity* rather than layer *size*, and the reason base-main has 259 layers
at all — so it stays the correct answer if -40% ever stops being enough. It is
not an inserted CI step. It needs `sudo buildah`, and the workflow's GHCR
credential lives in `$XDG_RUNTIME_DIR/containers/auth.json`, which root does not
share, so `--cache-to` and the three rootless `podman run` gates break together.
The action emits `oci:<dir>` rather than a storage tag and deletes its input
image unless `keep-ref` is set. Every existing gate — the 29 sections of
`99-check-build.sh`, `bootc container lint --fatal-warnings` — would run against
a pre-rechunk intermediate that is then discarded, while
`tooling/validate/image-build` still passed. Its floor is not zero either:
rechunk forces everything unowned by an RPM into one dedicated `unpackaged`
layer, measured at 125,052,002 B gzip and dirty every build. And the one-time
full re-download recurs weekly, because `renovate.json5` bumps the base "before
6am on monday" and after rechunking the base's 259 shared blobs no longer exist
in this image. Realistic band ~300-750 MB, centred near -60%. If it is
revisited, evaluate `rpm-ostree compose build-chunked-oci --bootc
--format-version=2` first — it needs none of rechunk's `/etc` relocation or
passwd/group rewriting.

**Splitting the packages `RUN` by churn rate.** Intuitively free, actually
negative. `hadolint` DL3059 fires K-1 times because every split `RUN` needs the
same bind + cache + tmpfs trio, which fails `lint.yml` and
`tooling/validate/all`; the only silencer is an `ignored:` entry, which
`AGENTS.md` forbids. Independent of the lint, all the split `RUN`s bind-mount
the same `ctx` stage and therefore share one cache key, so editing a file neither
reads re-executes both. And every split writes its own intermediate rpmdb into
its own layer: honest cost 185-280 MB, midpoint **+16.4%**.

**Making the packages layer cache-hit.** Two production CI logs show the `ctx`
`COPY` already hitting the remote cache under ordinary `actions/checkout`
mtimes, and the packages `RUN` missing anyway — buildah zeroes tar timestamps
before digesting for cache keys (`digester.go`), so normalizing mtimes on the
checkout cannot change any cache key. Left open: **no `RUN` layer has ever been
observed restoring from the registry cache.** All 14 `Cache pulled from remote`
lines across two runs are `FROM`/`ARG`/`LABEL`/`COPY` steps. `--cache-to` is
therefore paying upload cost for no download benefit on the layers that matter,
and diagnosing that needs `buildah bud --log-level=debug` across two consecutive
push builds.

**Prefetching with `bootc upgrade --download-only`.** The wall-clock win is real
and larger than expected — the second step is a sub-second metadata flip — but
it is a second system-update path, which is what `50-services.sh` and the
preset's `disable bootc-fetch-apply-updates.timer` exist to forbid.
`tooling/audit/deployment` reads `rpm-ostree status --json`, whose key set has no
download-only field, so it would report "reboot required to adopt the staged
deployment" for a deployment a reboot *discards*. The GUI update button is pinned
to `systemctl start uupd.service` by `99-check-build.sh` and by a polkit rule
scoped to that unit and verb, and uupd has no `--from-downloaded`, so the fast
path cannot reach it. A prefetch landing after uupd's nightly stage locks an
already-armed deployment.

**Rescheduling `uupd.timer` past the nightly publish.** Salvageable, low value,
and the obvious drop-in is wrong: `OnCalendar=` is a list, so a drop-in carrying
only a new time *adds* a second trigger and doubles the daily fetch. It needs an
empty `OnCalendar=` to reset first. It also saves nothing on any day that
carries a daytime push publish, and 2026-08-31 carried five.

---

## What it cost

- **A new build script.** `25-rpmdb.sh` is the first use of a numbering gap since
  the convention was written, which is what the gaps are for.
- **A split mechanism.** The rpmdb relink now lives in `25-rpmdb.sh` while
  `90-cleanup.sh` keeps journal reconciliation only, because an `rpm -q` read
  after the packages layer still leaves `-shm`/`-wal` beside the database. Two
  files, one concern — so `99-check-build.sh` gained an inode-equality assertion
  that the hard link survived to the end of the build. A copy-up cannot preserve
  an inode, so that single comparison detects any future step that writes the
  rpmdb and silently puts the 30 MB back.
- **An unverified assumption, deliberately shipped.** No image on ghcr.io was
  found serving zstd layers; base-main and bluefin are 100% gzip. Only a local
  `registry:2` was tested. bootc's `store.rs` does carry a diff_id fallback for
  exactly this case ("try to find a layer with the same diff_id but a different
  blob digest (e.g. due to recompression)"), but it has never been executed
  against a real zstd tag from this registry. If the first upgrade after this
  lands reports ~266 layers needed rather than ~6, that fallback is what did not
  fire, and reverting the two push flags restores gzip.
- **One-time dev-container churn.** `create_dev.fish` fingerprints
  `/etc/os-release` as part of its cache key, and this change rewrites `NAME` and
  `PRETTY_NAME`, so every dev container rebuilds once.

---

## Where to go next

[../build-and-ci.md](../build-and-ci.md) owns the current publishing shape and
the build-script table. [../operating.md](../operating.md) covers upgrading and
rolling back a machine. [../supply-chain.md](../supply-chain.md) owns the
signing order that the tag-digest assertion protects.
