#!/usr/bin/env bash
#
# TaskRadar production deployment: the API image and the web client image, in
# one approved release. Installed on the VDS as
# /usr/local/sbin/taskradar-deploy (root:root 0755) and invoked over SSH by the
# release workflow through the single sudo rule in
# deploy/taskradar-deploy.sudoers.
#
# The script is the whole trust boundary: the deploy account can run it and
# nothing else, so every argument is validated here rather than trusted because
# "CI sent it".
set -Eeuo pipefail

umask 077

readonly APP_DIR='/opt/taskradar'
readonly COMPOSE_FILE='compose.prod.yaml'
readonly RELEASE_ENV='.release.env'
readonly BACKUP_DIR='/var/backups/taskradar'
readonly LOCK_FILE='/run/lock/taskradar-deploy.lock'

if [[ $# -ne 4 ]]; then
  echo 'Usage: taskradar-deploy VERSION BACKEND_IMAGE WEB_IMAGE GHCR_USER' >&2
  exit 64
fi

readonly VERSION="$1"
readonly BACKEND_IMAGE="$2"
readonly WEB_IMAGE="$3"
readonly GHCR_USER="$4"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo 'Version must be a SemVer core such as 1.0.0.' >&2
  exit 64
fi

# Digest reference only, never a tag. A tag can be moved to different content
# after it was approved; a digest cannot, which is what makes the deployed image
# immutable. The repository owner is left open so the pattern does not hardcode
# a GitHub account, but the image name is pinned so this script can only ever
# deploy TaskRadar's own backend.
if [[ ! "$BACKEND_IMAGE" =~ ^ghcr\.io/[a-z0-9_.-]+/taskradar-backend@sha256:[a-f0-9]{64}$ ]]; then
  echo 'Backend image must be an approved GHCR digest reference.' >&2
  exit 64
fi
# The web client (F10), by digest and under its own name, for the same reasons.
# Two images rather than one: they are built from different sources and only the
# API image goes anywhere near the database, so a mix-up between the two names
# has to fail here rather than start a static file server as the backend.
if [[ ! "$WEB_IMAGE" =~ ^ghcr\.io/[a-z0-9_.-]+/taskradar-web@sha256:[a-f0-9]{64}$ ]]; then
  echo 'Web image must be an approved GHCR digest reference.' >&2
  exit 64
fi
if [[ ! "$GHCR_USER" =~ ^[A-Za-z0-9-]+$ ]]; then
  echo 'Invalid GHCR username.' >&2
  exit 64
fi

# The registry token arrives on stdin, not as an argument: arguments are visible
# to every process on the host through /proc.
IFS= read -r GHCR_TOKEN
if [[ -z "$GHCR_TOKEN" ]]; then
  echo 'GHCR token is required on stdin.' >&2
  exit 64
fi

# Per-tenant lock. Two overlapping releases would interleave a migration with a
# container restart; this makes the second one fail fast instead.
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo 'Another TaskRadar deployment is already running.' >&2
  exit 75
fi

cd "$APP_DIR"
test -f .env
test -f "$COMPOSE_FILE"

set -a
# shellcheck disable=SC1091
source .env
set +a
: "${APP_ORIGIN:?APP_ORIGIN must be set in /opt/taskradar/.env}"

cleanup() {
  GHCR_TOKEN=''
  docker logout ghcr.io >/dev/null 2>&1 || true
}
trap cleanup EXIT

printf '%s\n' "$GHCR_TOKEN" | docker login ghcr.io --username "$GHCR_USER" --password-stdin >/dev/null
docker pull "$BACKEND_IMAGE"
docker pull "$WEB_IMAGE"

# Identity of the artifact, checked from the image label before anything starts.
# The label is set at build time by the release workflow.
#
# The backend now also serves GET /version, which reports the same value over
# HTTP; this check is kept rather than replaced because the two prove different
# things. The label says "the digest I was told to deploy really is release X",
# and it says so *before* the container runs, so a mismatch aborts the release
# without touching the running one. /version can only be asked afterwards, and
# what it adds is confirmation that the container now serving the public origin
# is the one just deployed. Adding that second check here is a worthwhile
# follow-up (see DEPLOYMENT.md); it is not done in this pass because nothing in
# this script has ever been executed.
readonly IMAGE_VERSION="$(docker image inspect --format '{{ index .Config.Labels "org.opencontainers.image.version" }}' "$BACKEND_IMAGE")"
readonly BUILD_DATE="$(docker image inspect --format '{{ index .Config.Labels "org.opencontainers.image.created" }}' "$BACKEND_IMAGE")"
if [[ "$IMAGE_VERSION" != "$VERSION" ]]; then
  echo "Image version label ($IMAGE_VERSION) does not match release $VERSION." >&2
  exit 65
fi

# The same question asked of the web image. Both are labelled by one workflow
# run, so a mismatch here means one of the two digests came from a different
# release -- which is exactly the mix-up that would otherwise be discovered by a
# browser talking to an API it no longer agrees with.
readonly WEB_IMAGE_VERSION="$(docker image inspect --format '{{ index .Config.Labels "org.opencontainers.image.version" }}' "$WEB_IMAGE")"
if [[ "$WEB_IMAGE_VERSION" != "$VERSION" ]]; then
  echo "Web image version label ($WEB_IMAGE_VERSION) does not match release $VERSION." >&2
  exit 65
fi

# .release.env holds everything about the *current* release and is generated
# here, never edited by hand. Keeping the previous copy is what makes a rollback
# a one-liner: re-run Compose with .release.env.previous.
if [[ -f "$RELEASE_ENV" ]]; then
  cp "$RELEASE_ENV" "${RELEASE_ENV}.previous"
fi
cat >"${RELEASE_ENV}.next" <<EOF
APP_VERSION=$VERSION
BUILD_DATE=$BUILD_DATE
BACKEND_IMAGE=$BACKEND_IMAGE
WEB_IMAGE=$WEB_IMAGE
EOF
mv "${RELEASE_ENV}.next" "$RELEASE_ENV"

compose=(docker compose --env-file .env --env-file "$RELEASE_ENV" -f "$COMPOSE_FILE")

# Database first and on its own: the migration step needs it healthy, and the
# backend must not start before the schema is in place.
"${compose[@]}" up -d postgres --wait --wait-timeout 120

# Pre-migration dump. On the very first release this produces a valid dump of an
# empty database, which is the correct outcome rather than a special case worth
# branching on. From the second release onwards it is the only thing standing
# between a bad migration and lost data, because reverting the container does not
# revert the schema.
install -d -m 700 "$BACKUP_DIR"
readonly BACKUP_PATH="$BACKUP_DIR/before-release-${VERSION}-$(date -u +%Y%m%d-%H%M%SZ).dump"
"${compose[@]}" exec -T postgres \
  pg_dump -U "${POSTGRES_USER:-taskradar}" -d "${POSTGRES_DB:-taskradar}" -Fc \
  >"$BACKUP_PATH"
test -s "$BACKUP_PATH"
chmod 600 "$BACKUP_PATH"
sha256sum "$BACKUP_PATH"

# Schema migration as a separate one-off container (see the `migrate` service in
# compose.prod.yaml for why it is not part of the backend's startup). --no-deps
# because PostgreSQL was already started and waited for above; non-zero here
# aborts the release before any new code serves a request.
"${compose[@]}" run --rm --no-deps migrate

# --no-build: this host never builds images, it only runs approved ones.
"${compose[@]}" up -d --no-build --wait --wait-timeout 180

# Verify through the real public origin, not from inside the Compose network, so
# a broken Caddy site block or a missing ingress network attachment is caught
# here and not by the phone.
readonly HEALTH_JSON="$(curl --fail --silent --show-error --max-time 15 "$APP_ORIGIN/health")"
if [[ "$HEALTH_JSON" != *'"status":"ok"'* ]]; then
  echo "Unexpected /health response through $APP_ORIGIN: $HEALTH_JSON" >&2
  exit 70
fi

# The auth guard denies everything that is not in PUBLIC_ROUTES, so an
# authenticated route must answer 401 -- not 404 (Caddy matcher missing) and not
# 502 (backend unreachable). Cheap, needs no credentials, and catches the two
# ways a working /health can still coexist with a broken deployment.
readonly GUARDED_STATUS="$(curl --silent --show-error --max-time 15 --output /dev/null \
  --write-out '%{http_code}' "$APP_ORIGIN/board")"
if [[ "$GUARDED_STATUS" != '401' ]]; then
  echo "Expected 401 from $APP_ORIGIN/board, got $GUARDED_STATUS." >&2
  exit 70
fi

# And the other half of the origin: the web client, served from `/` through the
# same site block by a different container. Checked by its loader script rather
# than by the status code alone, because nginx's stock welcome page -- what an
# image with a mis-copied site directory serves -- answers 200 just as happily.
# `flutter_bootstrap.js` is the one string every `flutter build web` index.html
# contains and nothing else on this origin does.
#
# What this does *not* prove is which release's bundle it is: every version's
# index.html contains that string. That question is answered before anything
# starts, by the image label checked above.
readonly WEB_INDEX="$(curl --fail --silent --show-error --max-time 15 "$APP_ORIGIN/")"
if [[ "$WEB_INDEX" != *'flutter_bootstrap.js'* ]]; then
  echo "The web client is not being served through $APP_ORIGIN/." >&2
  exit 70
fi

echo "TaskRadar $VERSION deployed successfully (built $BUILD_DATE): API and web client."
echo "Pre-migration dump: $BACKUP_PATH"
