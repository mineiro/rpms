# mineiro-rpms

Fedora packaging for the software built at [mineiro.io](https://mineiro.io).

One repository, many packages, one COPR project: **`mineiro/rpms`**. Each
directory under `packages/` is a self-contained package.

| package                   | what it is                           |
|---------------------------|--------------------------------------|
| [gaffer](packages/gaffer) | Daemon and CLI for Elgato Key Lights |

## Installing

```sh
sudo dnf copr enable mineiro/rpms
sudo dnf install gaffer
```

If you enabled `mineiro/gaffer` before packaging moved here, switch with
`sudo dnf copr disable mineiro/gaffer` first.

## Why packaging lives apart from the source

Each project's own repository builds and releases that project; this one turns
those releases into RPMs. The split is not tidiness — it removes a class of
problem outright.

A source repository has commits that are not releases, so its packaging needs a
scheme to tell the two apart, and that scheme has to be wired into a webhook
that races a git push. Getting it subtly wrong produces a package that looks
released and is not.

This repository only ever packages releases. `Release:` is a plain integer, the
source is a tarball that already exists at a tag, and there is nothing to race.

## Working on a package

```sh
make list                      # what is here
make check-specs               # parse and sanity-check every spec
make srpm PACKAGE=gaffer       # fetch upstream, vendor, build the SRPM
make mock PACKAGE=gaffer       # rebuild it in a clean chroot — the real gate
```

`make srpm` fetches the released tarball and vendors its dependencies, because
Fedora build roots have no network. `make mock` is what decides whether it is
actually packaged: a build that only works against your installed system is not.

- [Packaging policy](docs/packaging-policy.md) — what belongs here, and the rules
- [COPR setup](docs/copr-setup.md) — project layout, and moving a package here
