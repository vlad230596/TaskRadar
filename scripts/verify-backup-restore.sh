#!/bin/sh
#
# Restores a plain SQL dump into a throwaway PostgreSQL container and checks
# that what came back is a usable TaskRadar database.
#
# Usage: verify-backup-restore.sh DUMP_PATH [EXPECTED_MIGRATION]
#
# A backup nobody has restored is a hypothesis, not a backup: a dump can be
# byte-perfect and still useless (truncated mid-stream, taken against the wrong
# database, missing the migration history the app needs). Run this after setting
# up backups and periodically thereafter.
#
# The container is isolated with --network none and capped resources, so a
# hostile dump cannot reach anything, and the supplied dump file is DELETED at
# the end -- never pass the only retained copy.
set -eu

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "usage: $0 DUMP_PATH [EXPECTED_MIGRATION]" >&2
  exit 64
fi

readonly dump_path=$1
readonly expected_migration=${2:-}
readonly container=taskradar-restore-verify

cleanup() {
  /usr/bin/docker rm -f "$container" >/dev/null 2>&1 || true
  rm -f -- "$dump_path"
}
trap cleanup EXIT HUP INT TERM

test -s "$dump_path"
if /usr/bin/docker ps -a --format '{{.Names}}' | grep -Fx "$container" >/dev/null; then
  echo "container already exists: $container" >&2
  exit 65
fi

# Same PostgreSQL version as production: a dump restored into a different major
# version can succeed here and still fail where it matters.
/usr/bin/docker run \
  --detach \
  --rm \
  --name "$container" \
  --network none \
  --memory 384m \
  --cpus 1 \
  --env POSTGRES_HOST_AUTH_METHOD=trust \
  postgres:17.6-alpine >/dev/null

attempt=0
until /usr/bin/docker exec "$container" pg_isready -U postgres -d postgres >/dev/null 2>&1; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 30 ]; then
    echo 'temporary PostgreSQL did not become ready' >&2
    exit 1
  fi
  sleep 1
done

/usr/bin/docker exec "$container" createdb -U postgres restorecheck
# ON_ERROR_STOP is what turns "psql printed some errors and exited 0" into a
# failed verification.
/usr/bin/docker exec -i "$container" \
  psql -X -v ON_ERROR_STOP=1 -U postgres -d restorecheck \
  <"$dump_path" >/dev/null

query() {
  /usr/bin/docker exec "$container" \
    psql -X -A -t -U postgres -d restorecheck -c "$1"
}

# Checked by name rather than by counting tables: a count has to be edited
# every time the schema grows, and then nobody remembers whether the new number
# is right. These four are what the application cannot work without.
for table in projects tasks notes _prisma_migrations; do
  exists=$(query "select count(*) from information_schema.tables \
    where table_schema = 'public' and table_type = 'BASE TABLE' and table_name = '$table'")
  if [ "$exists" != '1' ]; then
    echo "restored database is missing the table: $table" >&2
    exit 1
  fi
done

# Prisma records every migration it applied. An empty (or only rolled-back)
# history means the dump came from a database the schema was never deployed to,
# which no amount of table-existence checking would reveal on its own.
applied=$(query "select count(*) from _prisma_migrations \
  where finished_at is not null and rolled_back_at is null")
if [ "$applied" -lt 1 ]; then
  echo 'restored database has no successfully applied Prisma migration' >&2
  exit 1
fi

latest=$(query "select migration_name from _prisma_migrations \
  where finished_at is not null and rolled_back_at is null \
  order by finished_at desc limit 1")

if [ -n "$expected_migration" ] && [ "$latest" != "$expected_migration" ]; then
  echo "latest applied migration is '$latest', expected '$expected_migration'" >&2
  exit 1
fi

echo "restore verified: projects/tasks/notes present, $applied migration(s) applied, latest '$latest'"
