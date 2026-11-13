#!/bin/sh
#
# Streams the TaskRadar task pictures (the `attachments-data` volume) to stdout
# as a tar archive. Installed on the VDS as
# /usr/local/sbin/taskradar-backup-export-attachments-root (root:root 0755) and
# reachable only through the forced SSH command in
# taskradar-backup-forced-command.sh (`attachments`) plus its own sudo rule in
# deploy/taskradar-backup.sudoers -- the same design as the database exporter,
# export-production-backup.sh, and for the same reasons: no arguments, nothing
# written to disk on the VDS.
#
# First, the daily sweep of orphaned files (src/scripts/sweepAttachments.ts):
# files of attachments whose task was deleted. It runs here because this is the
# one thing on the server that already happens every day, and right before the
# archive so the archive does not carry files no row points at. Its report goes
# to stderr -- stdout is the archive -- and its failure does not stop the
# backup: a missed sweep costs some disk, a missed backup costs data.
#
# The archive is taken from inside the backend container, which mounts the
# volume, so this needs no knowledge of the volume's name or path on the host.
# Pull the database first and this second (pull-production-backup.ps1 does):
# a picture uploaded in between is then in the archive without a row, which a
# restore tolerates, rather than a row without its picture.
set -eu

readonly app_dir=/opt/taskradar

cd "$app_dir"

compose() {
  /usr/bin/docker compose --env-file .env -f compose.prod.yaml "$@"
}

if ! compose exec -T backend node dist/scripts/sweepAttachments.js >&2; then
  echo 'warning: the attachment sweep failed; exporting anyway' >&2
fi

# `exec` needs a program, not the shell function above, hence the full command.
exec /usr/bin/docker compose --env-file .env -f compose.prod.yaml \
  exec -T backend tar -C /var/lib/taskradar/attachments -cf - .
