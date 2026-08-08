# COPR setup

This repository is built by COPR's **SCM** source type, one COPR package entry
per directory under `packages/`. The shared `.copr/Makefile` generates the SRPM
inside COPR; nothing package-specific lives outside `packages/<name>/`.

## One project for the whole repository

Everything here builds into **`mineiro/rpms`**. The repository and the COPR
project are the same thing to anyone using them: one project to configure, one
chroot set to maintain, one repoclosure to run, one place to look when something
is missing.

The alternative — a project per product — buys each package its own enable line
and costs a separate project to keep in step for every package added. That trade
only pays when the packages have genuinely different audiences, which is not the
case for one person's software.

**gaffer moved.** It was previously built in `mineiro/gaffer`, which its README
told people to enable. Anyone who did needs to switch:

```sh
sudo dnf copr disable mineiro/gaffer
sudo dnf copr enable mineiro/rpms
```

## Adding a package

In the COPR project, add a package with:

- **Type**: `SCM`
- **Clone URL**: `https://github.com/mineiro/rpms.git`
- **Committish**: `main`
- **Subdirectory**: `packages/<name>`
- **Spec file**: `<name>.spec`
- **Build SRPM with**: `make_srpm`
- **Auto-rebuild**: on, so a push that touches the package rebuilds it

## Moving a package here from its source repository

The order matters — the old source must keep building until the new one works,
or the package becomes uninstallable in between:

1. Add the package here and check `make srpm PACKAGE=<name>` succeeds.
2. Rebuild the SRPM under `mock` for at least one target chroot.
3. Repoint the existing COPR package at this repository and subdirectory.
4. Trigger a build and confirm the resulting NVR.
5. Only then remove the spec and `.copr/` from the source repository.
