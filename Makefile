SHELL := /bin/bash

.PHONY: check test download inspect verify

check:
	shellcheck scripts/*.sh scripts/lib/*.sh tests/*.sh

test:
	./tests/run.sh

download:
	./scripts/download-flex.sh --channel stable

inspect:
	@test -n "$(IMAGE)" || (echo "usage: make inspect IMAGE=path/to/image.bin"; exit 2)
	sudo ./scripts/inspect-image.sh "$(IMAGE)"

verify:
	@test -n "$(IMAGE)" || (echo "usage: make verify IMAGE=path/to/image.bin"; exit 2)
	sudo ./scripts/verify-image.sh "$(IMAGE)"
