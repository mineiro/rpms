#!/bin/sh
# Parse every spec and report anything rpm itself objects to.
#
# Deliberately cheap: this is the check you can run before every commit, not a
# substitute for a mock build. A spec that fails to parse cannot possibly build,
# and finding that out here costs a second instead of a COPR round trip.
set -eu

cd "$(dirname "$0")/.."
status=0

for spec in packages/*/*.spec; do
    name=$(basename "$spec")
    if ! out=$(rpmspec -P "$spec" 2>&1 >/dev/null); then
        printf '%s: FAILED TO PARSE\n%s\n' "$name" "$out"
        status=1
        continue
    fi

    # A spec whose Version does not appear in its own Source0 is usually a
    # half-finished bump: the version was changed but the URL still points at
    # the previous tarball.
    version=$(rpmspec -P "$spec" | awk '/^Version:/ { print $2; exit }')
    source0=$(rpmspec -P "$spec" | awk '/^Source0:/ { print $2; exit }')
    case "$source0" in
    *"$version"*) ;;
    *) printf '%s: Source0 does not mention version %s\n' "$name" "$version"; status=1 ;;
    esac

    printf '%s: ok (%s)\n' "$name" "$version"
done

exit $status
