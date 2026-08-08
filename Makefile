# Entry points for working on packages here. Everything real lives in
# packages/<name>/Makefile; this only routes to it.

SHELL := /bin/bash
PACKAGES_DIR := packages
OUTDIR ?= $(CURDIR)/dist/srpm

.PHONY: help list check-specs srpm mock

help:
	@echo "make list                    packages in this repository"
	@echo "make check-specs             parse and lint every spec"
	@echo "make srpm PACKAGE=gaffer     build one package's SRPM"
	@echo "make mock PACKAGE=gaffer     rebuild that SRPM in a clean chroot"

list:
	@ls -1 $(PACKAGES_DIR)

check-specs:
	@./scripts/check-specs.sh

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
