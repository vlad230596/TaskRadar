#!/bin/sh
#
# Streams the TaskRadar production database to stdout as a plain SQL dump.
# Installed on the VDS as /usr/local/sbin/taskradar-backup-export-root
# (root:root 0755) and reachable only through the forced SSH command in
# taskradar-backup-forced-command.sh plus the single sudo rule in
# deploy/taskradar-backup.sudoers.
#
# Takes no arguments on purpose: the backup account cannot choose a different
# database, a different format or a different destination. Nothing is written to
# disk on the VDS -- the dump exists only in the SSH stream, so a compromised
# server does not accumulate copies of the data.
set -eu

readonly app_dir=/opt/taskradar

cd "$app_dir"

# Only .env is needed here: every variable the backend service requires is in
# it, and BACKEND_IMAGE has a default in compose.prod.yaml, so this keeps the
# export working independently of .release.env.
exec /usr/bin/docker compose --env-file .env -f compose.prod.yaml \
  exec -T postgres sh -ceu 'exec pg_dump \
    --username="$POSTGRES_USER" \
    --dbname="$POSTGRES_DB" \
    --format=plain \
    --no-owner \
    --no-privileges'
