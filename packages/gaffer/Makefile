# Build this package's SRPM locally, the same way COPR will.
#
# The point is to be able to rehearse a packaging change without pushing:
# `make srpm PACKAGE=gaffer` from the repository root lands here.

SHELL := /bin/bash

SPEC ?= $(firstword $(wildcard *.spec))
OUTDIR ?= $(CURDIR)/../../dist/srpm
SOURCEDIR ?= $(CURDIR)/sources

.PHONY: srpm vendor check-sources clean

srpm:
	@test -n "$(SPEC)" || { echo "no .spec file here"; exit 1; }
	@mkdir -p "$(OUTDIR)" "$(SOURCEDIR)"
	@if ls patches/*.patch >/dev/null 2>&1; then cp -f patches/*.patch "$(SOURCEDIR)"/; fi
	spectool -g --source 0 -C "$(SOURCEDIR)" "$(SPEC)"
	@sh ../../scripts/verify-sources.sh "$(SPEC)" "$(SOURCEDIR)"
	$(MAKE) vendor SPEC="$(SPEC)" SOURCEDIR="$(SOURCEDIR)"
	rpmbuild -bs \
		--define "_sourcedir $(SOURCEDIR)" \
		--define "_specdir $(CURDIR)" \
		--define "_builddir $(CURDIR)" \
		--define "_srcrpmdir $(OUTDIR)" \
		--define "_rpmdir $(CURDIR)" \
		--define "_buildrootdir $(CURDIR)/.build" \
		"$(SPEC)"

# Mirrors .copr/Makefile's vendoring. Kept separate rather than shared because
# the COPR copy runs in a throwaway container and this one runs on a machine
# whose cargo cache should not be touched.
vendor:
	@vendor_name="$$(rpmspec -P "$(SPEC)" | awk '/^Source1:[[:space:]]*/ { print $$2; exit }' | xargs basename)"; \
	src0_name="$$(rpmspec -P "$(SPEC)" | awk '/^Source0:[[:space:]]*/ { print $$2; exit }' | xargs basename)"; \
	if [ -z "$$vendor_name" ]; then echo "no Source1; nothing to vendor"; exit 0; fi; \
	command -v cargo >/dev/null 2>&1 || { echo "cargo is required to build $$vendor_name"; exit 1; }; \
	src0_path="$(SOURCEDIR)/$$src0_name"; \
	[ -f "$$src0_path" ] || { echo "Source0 not found: $$src0_path"; exit 1; }; \
	tmpdir="$$(mktemp -d)"; \
	trap 'rm -rf "$$tmpdir"' EXIT; \
	tar -xf "$$src0_path" -C "$$tmpdir"; \
	srcdir="$$(find "$$tmpdir" -mindepth 1 -maxdepth 1 -type d | head -1)"; \
	[ -n "$$srcdir" ] || { echo "no directory inside $$src0_name"; exit 1; }; \
	( cd "$$srcdir" && CARGO_HOME="$$tmpdir/cargo-home" cargo vendor --locked vendor >/dev/null ); \
	tar -cJf "$(SOURCEDIR)/$$vendor_name" -C "$$srcdir" vendor; \
	rm -rf "$$tmpdir"; trap - EXIT; \
	echo "generated $(SOURCEDIR)/$$vendor_name"

# Fetch and check, without building anything. Kept separate from `srpm` so CI
# can run it on every pull request against a fresh download: that is what turns
# sources.sha256 from a record of what was downloaded once into a check that
# upstream has not moved the tag since.
check-sources:
	@mkdir -p "$(SOURCEDIR)"
	spectool -g --source 0 -C "$(SOURCEDIR)" "$(SPEC)"
	@sh ../../scripts/verify-sources.sh "$(SPEC)" "$(SOURCEDIR)"

clean:
	rm -rf .build $(SOURCEDIR)/*.tar.* *.tar.* *.patch
