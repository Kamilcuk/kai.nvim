#!/bin/sh
(
	set -xeu
	VADER_OUTPUT_FILE=/dev/stderr vim +'Vader! *' >/dev/null
)
