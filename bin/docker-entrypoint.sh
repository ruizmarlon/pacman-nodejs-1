#!/bin/ash
set -e

/wait-for ${MONGODB_HOST}:27017

exec "$@"
