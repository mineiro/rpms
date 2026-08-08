#!/bin/sh
# Print the sources.sha256 lines for a package's current sources.
#
# Prints rather than writes, on purpose. The whole value of a recorded checksum
# is that a human looked at the bytes once and said "this is the release". A tool
# that rewrites the file on demand turns a failed verification into a one-command
# formality, which is precisely the moment an attacker is counting on.
#
# So: run this on a version bump, read what it says, paste it in.
#
# Usage: record-sources.sh <package-dir>
set -eu

if [ $# -ne 1 ]; then
    echo "usage: record-sources.sh <package-dir>" >&2
    exit 2
fi

pkgdir=$1
[ -d "$pkgdir" ] || { printf 'no such package directory: %s\n' "$pkgdir" >&2; exit 1; }

spec=$(ls "$pkgdir"/*.spec 2>/dev/null | head -1)
[ -n "$spec" ] || { printf 'no spec in %s\n' "$pkgdir" >&2; exit 1; }

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

printf '# fetching sources for %s\n' "$(basename "$spec")" >&2

for url in $(rpmspec -P "$spec" | awk '/^Source[0-9]*:[[:space:]]/ { print $2 }' | grep '://' || true); do
    name=$(basename "$url")
    printf '#   %s\n' "$url" >&2
    curl -sSL --fail --proto '=https' --tlsv1.2 "$url" -o "$tmpdir/$name"
    printf '%s  %s\n' "$(sha256sum "$tmpdir/$name" | awk '{ print $1 }')" "$name"
done

printf '\n' >&2
printf '# Paste the above into %s/sources.sha256.\n' "$pkgdir" >&2
printf '# If a line replaces an existing one for the same upstream version,\n' >&2
printf '# the tarball changed under a version that was already released —\n' >&2
printf '# find out why before you accept it.\n' >&2
