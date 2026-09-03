# Out-of-Tree Kernel Modules

The record for the decision not to consume `ghcr.io/ublue-os/akmods`: what the
request was, why the shape every upstream uses does not port to an image that
keeps its base kernel, and what would have to be true to revisit.

**Every ublue image that consumes akmods throws away the base kernel and boots
the one shipped inside the akmods image. This image does not, so the akmods pin
would have to chase the base pin forever — and the drivers it would have bought
bind nothing on this hardware.**

---

## Context

The question arrived on 2026-09-03 by way of an upstream pull request adding
openrazer to ublue's akmods build, and the goal behind it was changing keyboard
RGB colours. Both halves of that turned out to be dead on this machine.

The keyboard has no RGB. `/sys/class/leds/` carries exactly one keyboard entry,
`asus::kbd_backlight`, with `max_brightness=3` — a four-level white backlight —
and the system has no multicolour LED device bound at all:

```
$ ls /sys/class/leds/*/multi_intensity
ls: cannot access '/sys/class/leds/*/multi_intensity': No such file or directory
```

No Razer keyboard has ever been attached. Every Razer device in the machine's
whole journal is one product:

```
$ journalctl -k | grep -oE "idVendor=1532, idProduct=[0-9a-f]{4}" | sort -u
idVendor=1532, idProduct=0f43
```

`1532:0f43` is a Razer Laptop Cooling Pad, and openrazer does not support it —
`grep -ril 0f43` over a fresh clone of openrazer master returns nothing, while a
supported accessory id such as `0f19` appears in five files including the
accessory driver header and the shipped udev rules. The kernel already binds
both of the pad's HID interfaces to `hid-generic`, which is the complete and
correct driver for a device that exposes nothing but HID.

The hardware is an ASUS Zenbook 14 UX3405CA: Intel Arrow Lake, Arc 140T
integrated graphics, no discrete GPU.

---

## Decision

Do not consume akmods. The repository was left unchanged; this record exists so
the survey behind that is not run a second time.

### Why the upstream shape does not port

bluefin, bazzite and aurora all pull a tag of the form
`<flavor>-<fedora>-<kernel_release>` and install the kmod RPMs by path, never
through a repository — bluefin with a `skopeo copy` inside its `RUN`, bazzite
and aurora with a bind mount from a named stage. That part is small and would
port cleanly.

The part that does not port sits immediately above it. Verbatim from bazzite's
`install-kernel-akmods`:

```bash
# Remove Existing Kernel
for pkg in kernel kernel{-core,-modules,-modules-core,-modules-extra,-tools-libs,-tools}; do
    rpm --erase "${pkg}" --nodeps
done

# cleanup leftovers that are not covered by kernel-* packages for some reason
rm -rf /usr/lib/modules

dnf5 -y install \
    /tmp/kernel-rpms/kernel-[0-9]*.rpm \
    ...
dnf5 versionlock add kernel kernel-devel kernel-devel-matched kernel-core kernel-modules
```

The kernel comes out of the akmods image. That is why their tag can never
mismatch: akmods *is* their kernel source, and the lockstep is structural rather
than maintained. bluefin and aurora reach the same place from the other
direction — their Justfiles read the `ostree.linux` label off the akmods tag and
feed it back as a build argument, so the image follows akmods.

This image keeps the base kernel and pins the base by digest, so the dependency
inverts: the kernel is already fixed and the akmods pin has to follow it. The
two are not synchronised. Measured on the day:

| Pin | `ostree.linux` |
|---|---|
| `ghcr.io/ublue-os/base-main` at the pinned digest | `7.1.10-200.fc44.x86_64` |
| `ghcr.io/ublue-os/akmods:main-44` | `7.1.12-200.fc44.x86_64` |

A kernel-matched tag did exist and verified against the vendored key, so the
mechanism was reachable. The cost is what carrying it means: a second image
reference that Renovate cannot maintain, because the correct tag is not a
version bump but a string that must equal a label on a *different* image; a gate
to prove the two agree, since nothing else would; a resync chore on every weekly
base bump; and a red build whenever akmods lags base-main, on the critical path
of an OS upgrade. No upstream carries any of that, because none of them has the
problem.

### What it would have cost, measured

- **Installed size, negligible.** `kmod-openrazer` 135,996 B plus its userspace
  half 46,264 B — about 178 KB. The akmods stage itself is 324 MiB but is
  bind-mounted, so it reaches no layer.
- **Build time, real.** One uncached 324 MiB stage pull per build. A stage pull
  is not covered by the registry layer cache the workflow already uses.
- **Trust, the smallest part.** Same authority as the base and the brew stage,
  same vendored `build_files/keys/ublue-os.pub`, and
  `tooling/validate/source-images` would have covered a digest-pinned reference
  with no edit at all — its grep matches any `@sha256:` in the Containerfile.
  Installing RPMs by path from a cosign-verified image is a stronger anchor than
  a vendored `.repo` file, not a weaker one.
- **The userspace half does not resolve.** Terra's `openrazer-3.12.4` requires
  `openrazer-kmod = 3.12.4`; the kernel-matched akmods build provides
  `openrazer-kmod = 100.0.0.git.723.878ab5a5`. Both packages also own
  `/usr/lib/udev/rules.d/99-razer.rules`. Which of the two namings you get
  depends on which kernel the base pin lands on, which is not a footing to build
  on. bazzite sidesteps it by baking only the kmod and layering the daemon
  post-boot from a `ujust` recipe.
- **Secure Boot, not a factor.** `mokutil --sb-state` reports `SecureBoot
  disabled` on this machine, so module signatures are not enforced and no MOK
  enrollment would have been needed. The modules are dual-signed by ublue
  regardless; the signature is simply not checked here.

---

## What lost

**Adopt akmods with openrazer, the literal request.** Four modules —
`razerkbd`, `razermouse`, `razerkraken`, `razeraccessory` — declare 267 distinct
`1532:*` product aliases between them and none is `0f43`. The shipped udev rules
never match it either, so the device would not even be tagged. The observable
effect of adopting would have been four idle modules in `lsmod`.

**Adopt the mechanism with `v4l2loopback` as the payload instead.** A real
driver with a real use, but not one that had been asked for. It pays the full
lockstep tax on the chance of wanting a virtual camera later, and the mechanism
is roughly half a day of work whenever that day arrives.

**Bake the mechanism and install nothing.** Scaffolding with no consumer, which
still has to be kept green through every base bump. Rejected on the same
reasoning as the previous one, with less to show for it.

**Layer the daemon post-boot, as bazzite's recipe does.** Layered packages on a
bootc host are the thing this repository exists to avoid, and the kmod
underneath would still bind nothing.

**Take openrazer from Terra alone, without akmods.** It would have meant one
line appended to the `includepkgs` allowlist in `build_files/repos/terra.repo`
and one entry in `build_files/packages/terra.list`, which is mechanical. It runs
into the same unsatisfiable `openrazer-kmod` dependency, because the userspace
package needs the module either way.

---

## What akmods would not have fixed

The broader question — whether consuming akmods improves hardware compatibility
in general — is worth answering here because it is the reason someone would
reach for it again. It does not. akmods is a fixed list of named out-of-tree
drivers, not a hardware-enablement layer. Against this machine:

| Driver | For | Applies here |
|---|---|---|
| `v4l2loopback` | virtual camera | plausible, unused today |
| `vhba` | CDemu virtual optical drive | niche |
| `framework-laptop`, `system76` | those vendors' hardware | no |
| `kvmfr` | Looking Glass GPU passthrough | no discrete GPU |
| `zenergy`, `ryzen_smu` | AMD Zen sensors | Intel |
| `nct6687d` | a desktop board sensor chip | no |
| `xone`, `gcadapter`, `new-lg4ff`, `hid-tmff2`, `t150-driver`, `hid-fanatecff` | Xbox dongle, GameCube adapter, racing wheels | no |
| `evdi` | DisplayLink | no DisplayLink device has been attached |
| `sc0710` | a capture card | no |
| `openrazer` | Razer peripherals | the one attached pad is unsupported |
| nvidia, zfs (separate images) | — | no NVIDIA, no ZFS |

Broad enablement on a current Fedora kernel comes from the kernel itself. This
laptop's platform support is already in-tree and loaded — `asus_wmi`,
`asus_nb_wmi` and `asus_armoury`, the last exposing firmware attributes through
`firmware_attributes_class`. akmods exists for the handful of drivers that
cannot be upstreamed, and none of them is one this machine wants.

---

## When to revisit

- A kmod is genuinely needed. `v4l2loopback` is the likeliest, `vhba` next.
  Once the stage exists, each additional module is one glob.
- A supported Razer peripheral is actually attached — a keyboard, mouse, Kraken
  headset, or an accessory openrazer claims.
- The base stops being digest-pinned, or this image starts shipping its own
  kernel. Either would remove the inversion, and with it most of the cost above.

The pad's own Chroma lighting is a separate question and not a kernel one:
without upstream support it would mean speaking the Razer HID protocol over
`hidraw` from userspace.

---

## Where to go next

[../supply-chain.md](../supply-chain.md) owns the digest pins and the cosign
verification a new stage would have joined,
[../build-and-ci.md](../build-and-ci.md) owns the build's stages and its caching,
and [../subsystems/packages.md](../subsystems/packages.md) owns where a package
is allowed to come from.
