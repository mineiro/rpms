#!/bin/sh
# Check fetched sources against the checksums recorded beside the spec.
#
# This is the only place the contents of a download are ever checked. Downstream
# of here, COPR signs whatever the build produces and dnf installs it with
# scriptlets that run as root — so if the wrong bytes get this far, nothing else
# is going to notice.
#
# What it defends against: `Source0` points at a tag, and a tag is a mutable
# pointer. Whoever can push to the upstream repository can move `v0.2.0` to a
# different commit, and every rebuild from that moment on quietly packages
# different code under a version that was already reviewed and released. The
# recorded checksum turns that from silent into a failed build.
#
# Only remote sources are checked. A generated source — the vendor tarball —
# cannot have a checksum recorded ahead of time because it is produced during
# the build. Its integrity comes from the other direction: it is built from an
# already-verified Source0, and `cargo vendor --locked` checks every crate it
# downloads against the `Cargo.lock` inside that tarball.
#
# Usage: verify-sources.sh <spec> <dir> [dir...]
#   Looks for each source in the given directories, in order.
set -eu

if [ $# -lt 2 ]; then
    echo "usage: verify-sources.sh <spec> <dir> [dir...]" >&2
    exit 2
fi

spec=$1
shift
specname=$(basename "$spec")
specdir=$(CDPATH= cd -- "$(dirname -- "$spec")" && pwd)
manifest="$specdir/sources.sha256"

if [ ! -f "$manifest" ]; then
    printf '%s: no sources.sha256 beside the spec\n' "$specname" >&2
    printf '  every package records the checksum of what it downloads.\n' >&2
    printf '  see docs/security.md for how to add one.\n' >&2
    exit 1
fi

# A remote source has a URL; a generated one is a bare filename. Collected into
# a variable rather than piped, so the loop runs in this shell and its failures
# survive it.
remote=$(rpmspec -P "$spec" | awk '/^Source[0-9]*:[[:space:]]/ { print $2 }' | grep '://' || true)

if [ -z "$remote" ]; then
    printf '%s: no remote sources to check\n' "$specname"
    exit 0
fi

status=0
checked=0

for url in $remote; do
    name=$(basename "$url")

    # Comment lines never match, so the manifest stays readable.
    expected=$(awk -v n="$name" '$2 == n { print $1; exit }' "$manifest")
    if [ -z "$expected" ]; then
        printf '%s: no checksum recorded for %s\n' "$specname" "$name" >&2
        printf '  a version bump changes this filename, so record the new one:\n' >&2
        printf '  make record-sources PACKAGE=%s\n' "$(basename "$specdir")" >&2
        status=1
        continue
    fi

    path=
    for dir in "$@"; do
        if [ -f "$dir/$name" ]; then
            path="$dir/$name"
            break
        fi
    done

    if [ -z "$path" ]; then
        printf '%s: %s was never fetched (looked in: %s)\n' "$specname" "$name" "$*" >&2
        status=1
        continue
    fi

    actual=$(sha256sum "$path" | awk '{ print $1 }')
    if [ "$actual" != "$expected" ]; then
        printf '%s: CHECKSUM MISMATCH for %s\n' "$specname" "$name" >&2
        printf '  expected %s\n' "$expected" >&2
        printf '  actual   %s\n' "$actual" >&2
        printf '\n' >&2
        printf '  The tarball at this URL is not the one that was reviewed.\n' >&2
        printf '  Do not update the checksum to make this pass until you know\n' >&2
        printf '  why it changed — a moved tag looks exactly like this.\n' >&2
        status=1
        continue
    fi

    printf '%s: %s ok\n' "$specname" "$name"
    checked=$((checked + 1))
done

# A stale entry is not dangerous, but it usually means a bump left the old
# checksum behind, and the next reader cannot tell which line is live.
awk '$1 !~ /^#/ && NF == 2 { print $2 }' "$manifest" | while read -r recorded; do
    case " $(for u in $remote; do basename "$u"; done | tr '\n' ' ') " in
    *" $recorded "*) ;;
    *) printf '%s: note: sources.sha256 still lists %s, which the spec no longer fetches\n' "$specname" "$recorded" ;;
    esac
done

[ "$status" -eq 0 ] && printf '%s: %d source(s) verified\n' "$specname" "$checked"
exit "$status"
