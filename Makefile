# Entry points for working on packages here. Everything real lives in
# packages/<name>/Makefile; this only routes to it.

SHELL := /bin/bash
PACKAGES_DIR := packages
OUTDIR ?= $(CURDIR)/dist/srpm

.PHONY: help list check-specs check-sources record-sources srpm mock

help:
	@echo "make list                    packages in this repository"
	@echo "make check-specs             parse and lint every spec"
	@echo "make check-sources           fetch sources and check their checksums"
	@echo "make record-sources PACKAGE=gaffer   print sources.sha256 lines for a bump"
	@echo "make srpm PACKAGE=gaffer     build one package's SRPM"
	@echo "make mock PACKAGE=gaffer     rebuild that SRPM in a clean chroot"

list:
	@ls -1 $(PACKAGES_DIR)

check-specs:
	@./scripts/check-specs.sh

# PACKAGE is optional here: with no argument every package is checked, which is
# what CI runs. Downloading on each run is the point — the checksum only proves
# anything if something re-fetches and compares.
check-sources:
	@set -e; \
	for dir in $(if $(PACKAGE),$(PACKAGES_DIR)/$(PACKAGE),$(PACKAGES_DIR)/*); do \
		echo "==> $$(basename $$dir)"; \
		$(MAKE) --no-print-directory -C "$$dir" check-sources; \
	done

record-sources:
	@test -n "$(PACKAGE)" || { echo "PACKAGE is required, e.g. make record-sources PACKAGE=gaffer"; exit 1; }
	@./scripts/record-sources.sh "$(PACKAGES_DIR)/$(PACKAGE)"

srpm:
	@test -n "$(PACKAGE)" || { echo "PACKAGE is required, e.g. make srpm PACKAGE=gaffer"; exit 1; }
	@$(MAKE) -C "$(PACKAGES_DIR)/$(PACKAGE)" srpm OUTDIR="$(OUTDIR)"

# The gate that matters before pushing: COPR builds in a clean chroot, so a
# build that only works against your installed packages is not yet packaged.
mock:
	@test -n "$(PACKAGE)" || { echo "PACKAGE is required"; exit 1; }
	@srpm=$$(ls -t $(OUTDIR)/$(PACKAGE)-*.src.rpm 2>/dev/null | head -1); \
	test -n "$$srpm" || { echo "no SRPM yet; run: make srpm PACKAGE=$(PACKAGE)"; exit 1; }; \
	echo "rebuilding $$srpm"; \
	mock -r fedora-44-x86_64 --rebuild "$$srpm"
