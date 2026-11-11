#!/bin/sh
#
# Forced command for the taskradar-backup SSH key. Installed on the VDS as
# /usr/local/bin/taskradar-backup-export and referenced from
# ~taskradar-backup/.ssh/authorized_keys:
#
#   restrict,command="/usr/local/bin/taskradar-backup-export" ssh-ed25519 AAAA... taskradar-backup
#
# `restrict` disables port forwarding, agent forwarding, X11 and pty allocation;
# the forced command replaces whatever the client asked for. Together they mean
# the key is not "a shell that happens to run a backup" but a one-purpose pipe.
set -eu

# A forced command still receives the client's requested command in
# SSH_ORIGINAL_COMMAND. Exactly two requests are understood, each mapped to a
# fixed exporter that takes no arguments:
#
#   (nothing)      the PostgreSQL dump (export-production-backup.sh)
#   attachments    the task pictures as a tar (export-production-attachments.sh)
#
# Anything else is refused visibly instead of being silently ignored. The word
# is compared, never passed on, so the client still cannot choose what runs.
case "${SSH_ORIGINAL_COMMAND:-}" in
  '')
    exec /usr/bin/sudo -n /usr/local/sbin/taskradar-backup-export-root
    ;;
  attachments)
    exec /usr/bin/sudo -n /usr/local/sbin/taskradar-backup-export-attachments-root
    ;;
  *)
    echo 'This key may only export the TaskRadar backup (database, or "attachments").' >&2
    exit 64
    ;;
esac
