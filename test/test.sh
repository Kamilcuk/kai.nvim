#!/bin/bash
(
	set -xeu
	cd "$(dirname "${BASH_SOURCE[0]}")"/..
	lua-language-server --check="$PWD" --checklevel=Information
	cd test
	VADER_OUTPUT_FILE=/dev/stderr vim +'Vader! *' >/dev/null
)
