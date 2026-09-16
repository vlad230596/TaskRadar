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
# SSH_ORIGINAL_COMMAND. Refusing when it is non-empty makes an attempt to use
# the key for anything else fail visibly instead of being silently ignored.
if [ -n "${SSH_ORIGINAL_COMMAND:-}" ]; then
  echo 'This key may only export the TaskRadar PostgreSQL backup.' >&2
  exit 64
fi

exec /usr/bin/sudo -n /usr/local/sbin/taskradar-backup-export-root
