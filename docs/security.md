# Security model

This repository turns upstream releases into RPMs that COPR signs and other
people's machines install as root. That sentence is the whole threat model: a
change that lands here is a change that runs on someone else's computer, with
no further review, because COPR rebuilds `main` automatically.

So the question this document answers is not "is the code good" but **what
would an attacker have to compromise, and what would notice.**

## The chain

Each link is only worth as much as the check on the one before it.

```
upstream tag  ──▶  tarball  ──▶  vendored crates  ──▶  SRPM  ──▶  COPR  ──▶  signed RPM  ──▶  root
   (mutable)      sha256 in       Cargo.lock          .copr/    builds       COPR key       %post
                sources.sha256    checksums          Makefile   main
```

**Upstream tag → tarball.** `Source0` points at a tag, and a tag is a mutable
pointer: whoever can push to `mineiro/gaffer` can move `v0.2.0` to a different
commit, and every rebuild from then on packages different code under a version
that was already reviewed. Two things stand in the way. Upstream has a ruleset
that blocks updating and deleting `v*` tags, which is the actual fix. And
`packages/<name>/sources.sha256` records the sha256 of the exact bytes, checked
by `scripts/verify-sources.sh` on every build — local, COPR, and CI — so if the
first control is ever removed or bypassed, the second one fails the build.

CI re-downloads and re-compares on every push and pull request. That is what
makes the checksum a live check rather than a note about what was downloaded
once.

**Tarball → vendored crates.** `cargo vendor --locked` resolves exactly the
tree that upstream's `Cargo.lock` pins, and cargo verifies each crate against
the checksum in that lockfile. Because the lockfile comes from inside the
verified tarball, the whole dependency tree inherits Source0's guarantee. This
is why `--locked` is not a style preference.

**SRPM → RPM.** `.copr/Makefile` is the program COPR runs. It is the highest
value file in the repository: it executes on COPR's builders on every push to
`main`. It is owned in `CODEOWNERS` and covered by the `main` ruleset.

**RPM → root.** Spec scriptlets run as root on install. `check-specs.sh` prints
which scriptlets a package has on every run, so a pull request that adds one
cannot pass through CI unremarked.

**RPM → the machine that already has it.** A verified chain is worth nothing if
the name at the end of it is ambiguous. COPR rebuilds a package when a push
touches its directory, so a change without a `Release:` bump publishes a second,
different *file* under a name that already identified one — and dnf, which keys
on NEVRA, never offers it as an update. `scripts/check-nvr.sh` fails the build
in that case.

It is tempting to argue that a rebuild from a tree whose changes cannot reach
the artefact — a comment, the local Makefile, this file — produces identical
bits anyway, and that the check is therefore pedantic. Two rebuilds of 0.2.0-2
from an identical tree, `mock`ed on fedora-44-x86_64, say otherwise, but not in
the way the loose version of the argument expects:

```
gaffer-0.2.0-2.fc44.src.rpm      e0bc4021…  vs  39aa708f…   differ
gaffer-0.2.0-2.fc44.x86_64.rpm   683ece1f…  vs  a2c76161…   differ
/usr/bin/gafferd                 ae18758f…  vs  ae18758f…   identical
/usr/bin/gaffer                                             identical
```

Every published file differs on every rebuild — `cargo vendor` re-runs and its
tarball is not byte-reproducible, and RPM headers carry a build time. But the
compiled binaries are identical, because `SOURCE_DATE_EPOCH` is pinned from the
changelog date. The non-determinism lives entirely in the packaging containers
and never reaches `/usr/bin`.

So the claim "a rebuild silently changes the code users are running" is **false
here**, and stating it that way would be a liability: it invites someone to test
it, find the binaries match, and discard the rule along with the bad argument.
The narrower claim survives and is enough on its own —

> A same-NVR rebuild publishes a *different file* under a name that is supposed
> to identify its bytes. Any checksum or signature recorded against the first
> stops matching, two mirrors can serve different files for one NVR, and the
> second overwrites the first — so the pair can never be compared afterwards.

That holds whether or not the payload happens to be identical, which is exactly
why the rule does not depend on measuring the payload. Measured on one chroot,
comparing the two shipped binaries; `debuginfo` and `debugsource` embed build
paths and were not compared.

## What the checks actually stop

`scripts/check-specs.sh` runs on every push and pull request:

- **`%(...)` anywhere in a spec.** This executes a shell command when the spec
  is *parsed* — including when CI parses it. The check runs on the raw file
  before `rpmspec` is ever invoked, because after that it would be too late.
- **Sources that are not `https://`**, or whose host is not in the allowlist at
  the top of the script. A source URL is the single line in a spec that decides
  what code goes into the package.
- **Sources with no recorded checksum.** A version bump changes the tarball
  filename, so a forgotten checksum is a hard failure rather than a silent
  fetch of something nobody looked at.
- **Network and obfuscation tools in a spec** — `curl`, `wget`, `/dev/tcp`,
  `base64 -d`, `eval`. These are how a scriptlet pulls in code that is not a
  declared source.

These are a tripwire, not a sandbox. They catch a change that should have been
noticed in review. They will not stop someone who is determined and patient,
and they are not meant to.

## What is not defended

Being explicit about this is more useful than a longer list of controls.

- **A compromised COPR project.** COPR holds the signing key. Anyone who can
  reach it can sign anything, and nothing in this repository would know.
- **Upstream compromised before the release.** If malicious code is in the
  tagged commit, every check here passes — it faithfully packages what upstream
  released. Source integrity is not source trustworthiness.
- **A stolen credential belonging to the maintainer.** The `main` ruleset
  requires a pull request and signed commits with no bypass, which raises the
  cost, but a single maintainer who can merge their own pull requests is a
  single point of failure by construction. The fix is a second reviewer, not
  another rule.
- **The Fedora build root and crates.io.** Both are trusted wholesale.

## Version bumps

The checksum has to be updated deliberately, which is the point:

```sh
make record-sources PACKAGE=<name>   # prints the lines; it does not write them
```

Paste the output into `packages/<name>/sources.sha256` with the new tag and
commit in the comment above it, then bump `Version:` and reset `Release:` to 1.

## If a checksum ever fails

**Do not update the checksum to make the build pass.** A moved tag and a
re-uploaded tarball look exactly like a legitimate change from the inside, and
updating the recorded hash is the one action that converts the alarm into a
silent success.

Instead: check whether the tag still points at the commit recorded in
`sources.sha256`, and compare the two tarballs. If the tag moved, find out who
moved it before packaging anything from it.

## Reporting

See [SECURITY.md](../SECURITY.md).
