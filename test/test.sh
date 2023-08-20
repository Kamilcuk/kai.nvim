#!/bin/bash
if (($#)); then
	files="$*"
else
	files="*"
fi
(
	set -xeu
	cd "$(dirname "${BASH_SOURCE[0]}")"/..
	#lua-language-server --check="$PWD" --checklevel=Information
	cd test
	env VADER_OUTPUT_FILE=/dev/stderr nvim +"Vader! $files" >/dev/null
)
