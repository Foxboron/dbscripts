IMAGE:=dbscripts/test
NETWORK:=none
RUN_OPTIONS:=--rm --network=$(NETWORK) -v $(PWD):/dbscripts:ro --tmpfs=/tmp:exec -w /dbscripts/test
CASES ?= cases
JOBS ?= $(shell nproc)
BATS_ARGS ?= --jobs $(JOBS) --verbose-run
DOCKER ?= podman

test-image:
	$(DOCKER) build --pull -t $(IMAGE) test

test: test-image
	$(DOCKER) run $(RUN_OPTIONS) $(IMAGE) make CASES=$(CASES) BATS_ARGS="$(BATS_ARGS)" test

test-coverage: test-image
	rm -rf ${PWD}/coverage
	mkdir -m 777 ${PWD}/coverage
	$(DOCKER) run  $(RUN_OPTIONS) -v ${PWD}/coverage:/coverage -e COVERAGE_DIR=/coverage $(IMAGE) make test-coverage

dev-env: test-image
	$(DOCKER) run $(RUN_OPTIONS) --tty --interactive $(IMAGE) /bin/bash

check:
	shellcheck -S error db-* testing2x

.PHONY: test-image test test-coverage check
