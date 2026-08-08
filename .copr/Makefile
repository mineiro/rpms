# Shared SRPM builder for every package in this repository.
#
# COPR's SCM source with `make_srpm` runs this from inside the package's
# subdirectory, passing `spec` and `outdir`. That is what makes a monorepo
# work: each COPR package points at `packages/<name>` and they all share this
# file.
#
# The job is narrow: fetch the upstream tarball, vendor its dependencies
# because Fedora build roots have no network, and build the SRPM. Nothing here
# knows anything about a specific package.
#
# Rust only, for now. Go and Node variants exist in utility-belt and can be
# lifted across when a package needs them — the shape is the same, only the
# vendoring command differs.

.PHONY: prepare srpm

# COPR passes an absolute path; every rpm command below wants the bare name.
specfile = $(notdir $(spec))

# COPR runs this from inside packages/<name>, so the repository root has to be
# derived from where this file is rather than from the working directory.
repo_root = $(patsubst %/.copr,%,$(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST))))))

# A spec needs vendoring when it declares a vendor tarball *and* builds with
# cargo. Both halves matter: Source1 alone could be anything, and a cargo
# BuildRequires alone might be a package whose sources are already bundled.
define is_rust_vendor_spec
	[ -n "$(spec)" ] && rpmspec -P "./$(specfile)" | grep -q '^Source1:' && \
	rpmspec -P "./$(specfile)" | grep -Eq '^BuildRequires:[[:space:]]+(cargo|cargo-rpm-macros|rust|rust-packaging)([[:space:]]|$$)'
endef

# Installed here rather than in the COPR chroot config so the requirement
# travels with the repository and a local `mock` run behaves the same way.
prepare:
	@pkgs="rpm-build rpmdevtools"; \
	if $(is_rust_vendor_spec); then \
		pkgs="$$pkgs cargo"; \
	fi; \
	dnf -y install --setopt=install_weak_deps=0 --nodocs $$pkgs

srpm: prepare
	@test -n "$(spec)" || { echo "COPR did not pass 'spec'"; exit 1; }
	@test -n "$(outdir)" || { echo "COPR did not pass 'outdir'"; exit 1; }
	@# Only Source0 is fetched. Source1 is the vendor tarball, which does not
	@# exist upstream — it is produced below, from Source0.
	@if $(is_rust_vendor_spec); then \
		spectool -g --source 0 -R "./$(specfile)"; \
	else \
		spectool -g -R "./$(specfile)"; \
	fi
	@# The one check on what was actually downloaded. COPR signs whatever comes
	@# out of this build and dnf installs it with scriptlets that run as root,
	@# so an unverified tarball here is an unverified tarball on every machine
	@# that enabled the repository. Fail closed: a missing checker is a failure,
	@# not a skipped step.
	@test -f "$(repo_root)/scripts/verify-sources.sh" || { \
		echo "scripts/verify-sources.sh not found under $(repo_root)"; \
		echo "refusing to build from sources nothing has checked"; \
		exit 1; \
	}
	@sh "$(repo_root)/scripts/verify-sources.sh" "./$(specfile)" \
		"." "./sources" "$$(rpm --eval '%{_sourcedir}')" "$$HOME/rpmbuild/SOURCES"
	@# Patches live in patches/ so they are reviewable next to the spec, but
	@# rpmbuild expects them beside it.
	@if ls ./patches/*.patch >/dev/null 2>&1; then \
		cp -f ./patches/*.patch ./; \
	fi
	@if $(is_rust_vendor_spec); then \
		set -e; \
		vendor_name="$$(rpmspec -P "./$(specfile)" | awk '/^Source1:[[:space:]]*/ { print $$2; exit }' | xargs basename)"; \
		src0_name="$$(rpmspec -P "./$(specfile)" | awk '/^Source0:[[:space:]]*/ { print $$2; exit }' | xargs basename)"; \
		tmpdir="$$(mktemp -d)"; \
		trap 'rm -rf "$$tmpdir"' EXIT; \
		src0_path="./$$src0_name"; \
		: "spectool writes to _sourcedir, which differs between COPR, mock and"; \
		: "a local rpmdev tree — so look where each of them would have put it"; \
		: "rather than assuming one layout."; \
		rpm_sourcedir="$$(rpm --eval '%{_sourcedir}' 2>/dev/null || true)"; \
		for candidate in "./sources/$$src0_name" "$$rpm_sourcedir/$$src0_name" "$$HOME/rpmbuild/SOURCES/$$src0_name"; do \
			[ -f "$$src0_path" ] && break; \
			[ -f "$$candidate" ] && src0_path="$$candidate"; \
		done; \
		[ -f "$$src0_path" ] || { echo "Source0 not found after fetch: $$src0_name"; exit 1; }; \
		[ "$$src0_path" = "./$$src0_name" ] || cp -f "$$src0_path" "./$$src0_name"; \
		tar -xf "./$$src0_name" -C "$$tmpdir"; \
		srcdir="$$(find "$$tmpdir" -mindepth 1 -maxdepth 1 -type d | head -1)"; \
		[ -n "$$srcdir" ] || { echo "no directory inside $$src0_name"; exit 1; }; \
		: "--locked so the vendored tree matches the committed Cargo.lock, which"; \
		: "is the same tree upstream tested. CARGO_HOME is kept inside the temp"; \
		: "directory so a build cannot poison the caller's cargo cache."; \
		( cd "$$srcdir" && CARGO_HOME="$$tmpdir/cargo-home" cargo vendor --locked vendor >/dev/null ); \
		tar -cJf "./$$vendor_name" -C "$$srcdir" vendor; \
		rm -rf "$$tmpdir"; \
		trap - EXIT; \
	fi
	rpmbuild -bs \
		--define "_sourcedir $${PWD}" \
		--define "_specdir $${PWD}" \
		--define "_builddir $${PWD}" \
		--define "_srcrpmdir $(outdir)" \
		--define "_rpmdir $${PWD}" \
		--define "_buildrootdir $${PWD}/.build" \
		"./$(specfile)"
