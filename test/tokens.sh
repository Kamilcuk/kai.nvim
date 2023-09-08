#!/bin/bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
set -x
# nvim +"Vader! ./tokens.vader"
env VADER_OUTPUT_FILE=/dev/stderr nvim +"Vader! ./tokens.vader" >/dev/null
