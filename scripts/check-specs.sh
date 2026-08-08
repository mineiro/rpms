#!/bin/sh
# Parse every spec and report anything rpm itself objects to, plus the few
# things rpm is perfectly happy with and we are not.
#
# Deliberately cheap: this is the check you can run before every commit, not a
# substitute for a mock build. A spec that fails to parse cannot possibly build,
# and finding that out here costs a second instead of a COPR round trip.
#
# The policy checks below exist because a spec is a program that runs as root on
# other people's machines, and this repository builds whatever is on `main`
# without a human in the loop. They are a tripwire, not a sandbox: they catch a
# change that should have been noticed in review, not a determined attacker.
set -eu

cd "$(dirname "$0")/.."
status=0

# Where a source may be downloaded from. Anything else has to be added here in a
# commit of its own, which is the point — a source URL is the one line in a spec
# that decides what code ends up in the package.
allowed_source_hosts="github.com"

# Patterns that have no business in a spec here. Every one of them is either a
# way to pull in code that is not a declared source, or a way to hide what a
# scriptlet does. Comments are stripped before this runs, so mentioning one in
# prose is fine.
suspicious='curl|wget|netcat|\bnc\b|/dev/tcp|base64[[:space:]]+(-d|--decode)|\beval\b|chmod[[:space:]]+777'

for spec in packages/*/*.spec; do
    name=$(basename "$spec")
    pkgdir=$(dirname "$spec")

    # Before rpmspec, not after. `%(...)` runs a shell command when the spec is
    # *parsed*, so by the time we could ask rpm about it, it would already have
    # run — here, in CI, on a runner with a checkout. Nothing in this repository
    # needs it.
    if grep -n '%(' "$spec" >/dev/null 2>&1; then
        printf '%s: contains %%(...), which executes a shell command at parse time\n' "$name"
        grep -n '%(' "$spec" | sed 's/^/    /'
        status=1
        continue
    fi

    if ! out=$(rpmspec -P "$spec" 2>&1 >/dev/null); then
        printf '%s: FAILED TO PARSE\n%s\n' "$name" "$out"
        status=1
        continue
    fi

    parsed=$(rpmspec -P "$spec")
    spec_status=0

    # A spec whose Version does not appear in its own Source0 is usually a
    # half-finished bump: the version was changed but the URL still points at
    # the previous tarball.
    version=$(printf '%s\n' "$parsed" | awk '/^Version:/ { print $2; exit }')
    source0=$(printf '%s\n' "$parsed" | awk '/^Source0:/ { print $2; exit }')
    case "$source0" in
    *"$version"*) ;;
    *) printf '%s: Source0 does not mention version %s\n' "$name" "$version"; spec_status=1 ;;
    esac

    # Every source that is downloaded must come from somewhere we trust over a
    # transport that cannot be rewritten in flight, and must have a checksum
    # recorded. The hash itself is checked at build time by verify-sources.sh;
    # what is checked here is that nobody added a source without recording one.
    for url in $(printf '%s\n' "$parsed" | awk '/^Source[0-9]*:[[:space:]]/ { print $2 }' | grep '://' || true); do
        case "$url" in
        https://*) ;;
        *)
            printf '%s: source is not https: %s\n' "$name" "$url"
            spec_status=1
            continue
            ;;
        esac

        host=${url#https://}
        host=${host%%/*}
        allowed=no
        for candidate in $allowed_source_hosts; do
            [ "$host" = "$candidate" ] && allowed=yes
        done
        if [ "$allowed" = no ]; then
            printf '%s: source host %s is not in the allowlist (%s)\n' "$name" "$host" "$allowed_source_hosts"
            printf '    add it to allowed_source_hosts in scripts/check-specs.sh if it belongs\n'
            spec_status=1
            continue
        fi

        basename_url=$(basename "$url")
        if [ ! -f "$pkgdir/sources.sha256" ] ||
            ! awk -v n="$basename_url" '$2 == n { found = 1 } END { exit !found }' "$pkgdir/sources.sha256"; then
            printf '%s: no checksum recorded for %s\n' "$name" "$basename_url"
            printf '    make record-sources PACKAGE=%s\n' "$(basename "$pkgdir")"
            spec_status=1
        fi
    done

    # Comments stripped first: this is about what the spec *does*, and a comment
    # explaining why something is absent should not trip it.
    if body=$(printf '%s\n' "$parsed" | sed 's/^[[:space:]]*#.*//' | grep -nEi "$suspicious"); then
        printf '%s: suspicious construct in spec\n' "$name"
        printf '%s\n' "$body" | sed 's/^/    /'
        printf '    if this is genuinely needed, say why in a comment and widen\n'
        printf '    the pattern in scripts/check-specs.sh deliberately\n'
        spec_status=1
    fi

    # Not a failure — visibility. These run as root on every install, and the
    # point is that a PR adding one cannot pass through CI unremarked.
    scriptlets=$(grep -oE '^%(pre|post|preun|postun|pretrans|posttrans|trigger[a-z]*)\b' "$spec" | sort -u | tr '\n' ' ' || true)
    if [ -n "$scriptlets" ]; then
        printf '%s: runs as root on install: %s\n' "$name" "$scriptlets"
    fi

    if [ "$spec_status" -eq 0 ]; then
        printf '%s: ok (%s)\n' "$name" "$version"
    else
        printf '%s: FAILED the checks above\n' "$name"
        status=1
    fi
done

exit $status
