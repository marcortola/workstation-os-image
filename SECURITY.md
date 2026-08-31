# Security

## What this repository is

A personal Fedora bootc image for one workstation. It is public so it can be
read and forked, not because it is a supported product.

## Scope

This image layers on `ghcr.io/ublue-os/base-main`, which layers on Fedora, and
adds packages from six third-party repositories (Terra, three COPRs, Docker CE,
Insync). Almost every CVE that appears in a scan of the published image belongs
to one of those layers rather than to anything written here.

Report upstream where the code lives:

| Layer | Report to |
|---|---|
| Fedora packages | https://bugzilla.redhat.com |
| The ublue base image | https://github.com/ublue-os/main |
| niri, DankMaterialShell, Docker, Insync, Terra packages | their own trackers |
| Anything in this repository | see below |

## What is in scope here

The build and trust machinery: `Containerfile`, `build_files/`, the shipped
`system_files/` overlay, `tooling/validate/`, `tooling/scrub/`, and the GitHub
Actions workflows. Concretely, a report is in scope if it describes a way to

- get unreviewed content into the published image,
- weaken or bypass the signature chain (`build_files/40-signing.sh`,
  `tooling/validate/source-images`, the `cosign` steps in
  `.github/workflows/build.yml`),
- extract a secret from CI, or
- make one of the gates in `tooling/validate/` pass while the condition it
  asserts is false.

## Reporting

Open a private security advisory on this repository. If you would rather not,
open a normal issue that says only that you have something to report and how to
reach you, without the detail.

There is no bounty and no response-time commitment: this is one person's
workstation image.

## What the image already does

- Base and brew images are pinned by digest and `cosign`-verified before the
  build (`tooling/validate/source-images`).
- Published images are signed, and `:latest` is only ever moved onto a digest
  whose signature has been verified.
- The machine enforces that: `policy.json` is deny-by-default and requires a
  `sigstoreSigned` entry for this image's scope.
- Third-party RPM keys are vendored and fingerprint-pinned, and every vendored
  repository is restricted to an `includepkgs` allowlist.
- `gitleaks` plus hand-written filters in `tooling/scrub/` gate every capture of
  personal configuration, because `gitleaks` does not recognise the key shapes
  the AI CLIs use.
