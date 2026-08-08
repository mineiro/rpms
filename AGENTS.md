# Working in this repository

Fedora packaging for the software built at mineiro.io. Packaging only — see
[docs/packaging-policy.md](docs/packaging-policy.md) for where the line is.

## The one rule that shapes everything else

**This repository only ever packages releases.** It has no opinion about
anything between two tags, and nothing here should ever need one.

That is why the packaging was split out of the source repositories rather than
left where it started. A source repo has commits that are not releases, so its
packaging needs a scheme to distinguish the two, and that scheme ends up wired
into a webhook racing a git push. gaffer had exactly that, and it produced a
package that claimed to be a release and was not — twice, for two different
reasons, both invisible until the built artefact was inspected.

Here, `Release:` is an integer a human types, `Source0` is a tarball that
already exists at a tag, and there is nothing to race. If a change would
reintroduce a notion of "which commit is this", it belongs upstream instead.

## Layout

```
packages/<name>/
  <name>.spec       the package
  package.env       metadata for the helper scripts and COPR
  patches/          numbered, each explaining why it exists
  sources/          fetched tarballs — gitignored, never committed
  Makefile          local SRPM build, mirroring what COPR does
.copr/Makefile      what COPR actually runs; shared by every package
```

COPR invokes `.copr/Makefile` from inside the package directory, passing `spec`
and `outdir`. That is the whole mechanism behind a monorepo: each COPR package
entry sets a different `Subdirectory` and they share one builder.

## Before pushing

```sh
make check-specs               # cheap: every spec parses, versions agree
make srpm PACKAGE=<name>       # fetch, vendor, build the SRPM
make mock PACKAGE=<name>       # rebuild in a clean chroot
```

`make mock` is the gate that matters. COPR builds in a clean chroot with no
network, so a build that succeeds only against your installed system is not
packaged yet — it just happens to work where you tried it.

## Vendoring

Fedora build roots have no network, so Rust dependencies are vendored into
Source1 from the released Source0 tarball. Two details are load-bearing:

- **`cargo vendor --locked`**, so the vendored tree is the one upstream's
  `Cargo.lock` pins and tested. Without `--locked` a build silently resolves a
  different dependency tree than upstream ever ran.
- **`CARGO_HOME` inside the temp directory**, so packaging cannot write into the
  caller's cargo cache.

## Licence fields

For a statically linked Rust binary the `License:` field is the *effective*
licence of what ships — the whole dependency tree, with every `OR` already
resolved to one choice. It is not upstream's own licence.

Re-verify it against the `LICENSE SUMMARY` block that `%{cargo_license_summary}`
prints into the build log after any dependency change. Fedora treats a wrong
License field as a review blocker, and dependency bumps change it silently.

## Adding a package

See [docs/copr-setup.md](docs/copr-setup.md). When moving one out of its source
repository, the order is not negotiable: the old source keeps building until the
new one is proven, or the package is uninstallable in between.
