SHELL := /bin/bash
.DEFAULT_GOAL := help
.NOTPARALLEL:

CONFIGURATION ?= release
REMOTE ?= origin
export CONFIGURATION VERSION REMOTE SIGNING_IDENTITY NOTARY_PROFILE

.PHONY: help build run test smoke check verify package installer screenshots version release release-check
help:
	@printf '%s\n' 'Marknote · 墨笺' '' \
	  'make build                 Build dist/墨笺.app (release by default)' \
	  'make run                   Build and open the app' \
	  'make test                  Run core tests' \
	  'make smoke                 Run native AppKit / WebKit integration tests' \
	  'make check                 Check scripts, documentation, and release tooling' \
	  'make verify                Run all local checks and native tests' \
	  'make package               Create versioned ZIP + DMG with SHA-256 checksums' \
	  'make installer             Build and verify the drag-to-install DMG' \
	  'make screenshots           Refresh real product screenshots in docs/images' \
	  'make version VERSION=1.2.0 Update version and increment build number' \
	  'make release-check         Read-only release preflight (requires GitHub)' \
	  'make release               Push version tag; wait for CI to publish assets' '' \
	  'Options: CONFIGURATION=debug, REMOTE=origin, VERSION=1.1.0'

build:
	bash Scripts/build.sh "$$CONFIGURATION"
run: build
	open 'dist/墨笺.app'
test:
	bash Scripts/test.sh
smoke:
	bash Scripts/smoke-test.sh "$$CONFIGURATION"
check:
	python3 Scripts/check.py
	python3 -m unittest discover -s Tests/ReleaseTests -v
verify: check test smoke
package:
	bash Scripts/package.sh
installer: package
screenshots:
	bash Scripts/screenshots.sh
version:
	python3 Scripts/version.py set "$$VERSION"
release-check:
	python3 Scripts/release.py check
release:
	python3 Scripts/release.py start
