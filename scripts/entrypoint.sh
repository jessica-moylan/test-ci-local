#!/bin/sh
set -e

# FMX
mkdir -p /nsls2/data/${ENDSTATION}/shared/config/bluesky/logs
touch /nsls2/data/${ENDSTATION}/shared/config/bluesky/logs/startup_log.log

exec "$@"
