#!/bin/ash
set -e

/wait-for ${MONGODB_HOST:-mongo}:27017

exec "$@"
