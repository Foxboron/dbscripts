CASES ?= cases
JOBS ?= $(shell nproc)
BATS_ARGS ?= --jobs $(JOBS) --verbose-run

test:
	BUILDDIR=/build PATH=$(CURDIR)/../:$(CURDIR)/../cron-jobs/:$(PATH) bats $(BATS_ARGS) $(CASES)

test-coverage:
	BUILDDIR=/build PATH=$(CURDIR)/../:$(CURDIR)/../cron-jobs/:$(PATH) kcov \
		--include-path=$(CURDIR)/../ \
		--exclude-path=$(CURDIR)/../test,$(CURDIR)/../cron-jobs/makepkg.conf,$(CURDIR)/../config \
		$(COVERAGE_DIR) \
		bats $(BATS_ARGS) $(CASES)

.PHONY: test test-coverage
