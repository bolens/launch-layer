.PHONY: test test-unit test-integration test-hub test-all lint lint-hub shellcheck check-hub-git check-dependency-pins check check-hub check-all check-version bump-version tui-screenshots

SHELL := /bin/bash
BATS ?= bats
HUB_PM := bash scripts/hub-pm.sh
# Parallel across bats files when GNU parallel (or rush) is available.
# Keep tests within a file serial — several suites share setup state.
BATS_JOBS ?= $(shell nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)
BATS_PARALLEL := $(shell if command -v parallel >/dev/null 2>&1 || command -v rush >/dev/null 2>&1; then echo --jobs $(BATS_JOBS) --no-parallelize-within-files; fi)

test: test-integration test-unit

test-unit:
	$(BATS) $(BATS_PARALLEL) test/unit

test-integration:
	$(BATS) $(BATS_PARALLEL) test/integration

test-hub:
	$(HUB_PM) test

test-all: test test-hub

lint shellcheck:
	shellcheck -x -P lib -a --severity=warning launchlayer test/helpers.bash scripts/*.sh

lint-hub:
	$(HUB_PM) lint

check-hub-git:
	bash scripts/check-staged-hub-secrets.sh

check-dependency-pins:
	bash scripts/check-dependency-pins.sh

check-version:
	bash scripts/check-version.sh

# Example: make bump-version VERSION=0.10.0
bump-version:
	@[[ -n "$(VERSION)" ]] || { echo "usage: make bump-version VERSION=X.Y.Z" >&2; exit 2; }
	bash scripts/bump-version.sh "$(VERSION)"

# Shell gate (matches CI shell suite). Hub is separate — see check-hub / check-all.
check: shellcheck check-hub-git check-dependency-pins test

check-hub: lint-hub test-hub

check-all: check check-hub

tui-screenshots:
	bash scripts/tui-screenshots/regenerate.sh
