SHELL=/bin/bash -o pipefail

CASES ?= cases
JOBS ?= $(shell nproc)
BATS_ARGS ?= --jobs $(JOBS) --verbose-run
COVERAGE_DIR ?= .

test:
	BUILDDIR=/build PATH=$(CURDIR)/../:$(CURDIR)/../cron-jobs/:$(PATH) bats $(BATS_ARGS) $(CASES) | tee $(COVERAGE_DIR)/bats-report.xml

test-coverage:
	BUILDDIR=/build PATH=$(CURDIR)/../:$(CURDIR)/../cron-jobs/:$(PATH) kcov \
		--include-path=$(CURDIR)/../ \
		--exclude-path=$(CURDIR)/../test,$(CURDIR)/../cron-jobs/makepkg.conf,$(CURDIR)/../config \
		$(COVERAGE_DIR) \
		bats $(BATS_ARGS) $(CASES)

.PHONY: test test-coverage
