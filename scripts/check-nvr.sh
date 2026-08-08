#!/bin/sh
# A package change must carry a Version or Release bump.
#
# COPR rebuilds a package when a push touches its directory. If neither Version
# nor Release moved, the rebuild produces a *different artefact under the same
# NVR* — and dnf keys on NEVRA, so it will never offer it as an update. Whoever
# installed the old 0.2.0-1 keeps it forever; whoever installs tomorrow gets the
# new one. Two different binaries answering to one name, with nothing to tell
# them apart.
#
# That is the same failure that caused packaging to be split out of the source
# repositories in the first place: an artefact that claims to be a release and
# is not. `Release:` is an integer precisely so that this costs one character.
#
# The trigger is *any* file under packages/<name>/, not just the spec. That is
# deliberate and matches what COPR actually watches — a change to the local
# Makefile does not alter what gets built, but it does cause a rebuild, and the
# rebuild is what collides.
#
# Usage: check-nvr.sh <base-ref>
set -eu

base=${1:-}
if [ -z "$base" ]; then
    echo "usage: check-nvr.sh <base-ref>" >&2
    exit 2
fi

if ! mergebase=$(git merge-base "$base" HEAD 2>/dev/null); then
    # Shallow clone or an unrelated base: better to say so than to pass quietly.
    printf 'cannot find a merge base with %s — fetch more history\n' "$base" >&2
    exit 1
fi

changed=$(git diff --name-only "$mergebase" HEAD -- packages/ || true)
if [ -z "$changed" ]; then
    echo "no package changed; nothing to bump"
    exit 0
fi

status=0

for pkg in $(printf '%s\n' "$changed" | awk -F/ 'NF >= 2 { print $2 }' | sort -u); do
    spec=$(git ls-tree --name-only HEAD "packages/$pkg/" | grep '\.spec$' | head -1 || true)

    if [ -z "$spec" ]; then
        printf '%s: package removed; nothing to bump\n' "$pkg"
        continue
    fi

    if ! old=$(git show "$mergebase:$spec" 2>/dev/null); then
        printf '%s: new package, so its NVR is new by construction\n' "$pkg"
        continue
    fi

    new=$(git show "HEAD:$spec")

    old_v=$(printf '%s\n' "$old" | awk '/^Version:/ { print $2; exit }')
    old_r=$(printf '%s\n' "$old" | awk '/^Release:/ { print $2; exit }')
    new_v=$(printf '%s\n' "$new" | awk '/^Version:/ { print $2; exit }')
    new_r=$(printf '%s\n' "$new" | awk '/^Release:/ { print $2; exit }')

    if [ "$old_v" = "$new_v" ] && [ "$old_r" = "$new_r" ]; then
        printf '%s: files changed but the NVR did not (%s-%s)\n' "$pkg" "$new_v" "$new_r"
        printf '    changed:\n'
        printf '%s\n' "$changed" | grep "^packages/$pkg/" | sed 's/^/      /'
        printf '\n'
        printf '    This rebuilds in COPR and overwrites %s-%s with different bits.\n' "$new_v" "$new_r"
        printf '    dnf keys on NEVRA, so nobody who already installed it will ever\n'
        printf '    be offered the new one. Bump Release, and say why in %%changelog.\n'
        status=1
    else
        printf '%s: ok (%s-%s -> %s-%s)\n' "$pkg" "$old_v" "$old_r" "$new_v" "$new_r"
    fi
done

exit $status
