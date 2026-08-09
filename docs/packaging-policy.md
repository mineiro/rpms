# Packaging policy

## What belongs here

Packaging, and only packaging. A spec, its patches, and the metadata needed to
build them. If a change would be needed even without RPM — a build flag, an
install path, a unit file — it belongs upstream, in the project's own
repository.

The test: **this repository should only ever package releases.** It has no
opinion about anything between two tags. That is the whole reason it exists
separately, and it is what removes the snapshot-versus-release machinery that a
source repo needs and gets wrong.

## Rules

- **`Release:` is a plain integer.** Bump it for *any* change inside
  `packages/<name>/`, not only ones that alter what is built; reset it to 1 on a
  version bump. COPR rebuilds when a push touches the directory, so a change
  without a bump publishes a different file under an existing NVR — and dnf,
  which keys on NEVRA, will never offer it as an update. CI enforces this.
- **Vendor from the released tarball, never from a checkout.** `cargo vendor
  --locked` so the vendored tree matches the `Cargo.lock` upstream tested.
- **Every download has a recorded checksum.** `sources.sha256` beside the spec,
  checked on every build. A failing checksum is never fixed by updating the
  checksum — see [security.md](security.md).
- **Patches are numbered and explained.** A patch with no comment saying why it
  exists and when it can be dropped becomes permanent by accident.
- **The `License:` field is the *effective* licence of the shipped binary.**
  Statically linked Rust binaries carry their whole dependency tree, so every
  `OR` in that tree has already been resolved to one choice. Verify it against
  `%{cargo_license_summary}` in the build log after any dependency change —
  Fedora treats a wrong License field as a review blocker.
- **A build that only works on your machine is not packaged.** `mock` in a clean
  chroot is the gate, because that is what COPR does.

## Upstream version bumps

Bumping a package here means the upstream released something. The sequence is:

1. `Version:` to the new release, `Release:` back to `1`.
2. `make record-sources PACKAGE=<name>` — paste the printed lines into
   `sources.sha256`, updating the tag and commit in the comment above them. The
   build will refuse to proceed until the new tarball has a recorded checksum.
3. `make srpm PACKAGE=<name>` — this fetches the new tarball and re-vendors.
4. `make mock PACKAGE=<name>`.
5. Add a `%changelog` entry describing the *packaging* change, not the upstream
   changelog. Upstream keeps its own; duplicating it here means maintaining two.
