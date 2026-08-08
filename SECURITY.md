# Reporting a vulnerability

Use GitHub's [private vulnerability
reporting](https://github.com/mineiro/rpms/security/advisories/new) rather than
a public issue. It stays private until there is a fix to point at.

## What belongs here, and what belongs upstream

This repository is packaging only. Where to report depends on which half of the
problem it is:

- **In the packaging** — a spec that installs something with the wrong
  permissions, a scriptlet that does something it should not, a source fetched
  from somewhere it should not be, a weakness in the build path. Report it here.
- **In the software itself** — a bug in gaffer's own code. Report it in
  [mineiro/gaffer](https://github.com/mineiro/gaffer/security), which is where a
  fix would be released from. A packaging repository cannot fix it; it can only
  package the release that does.

If you are not sure which it is, report it here and it will be routed.

## What to expect

This is one person's software. There is no SLA, but reports are read, and a
report that turns out to be real will get a fix and credit if you want it.

For how the packaging path is protected and what it deliberately does not
defend against, see [docs/security.md](docs/security.md).
