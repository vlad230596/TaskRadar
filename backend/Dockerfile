# TaskRadar backend image (Fastify + Prisma).
#
# Two properties of this backend are platform-bound and drive every choice below.
#
#   1. `bcrypt` is a native addon. It publishes prebuilt binaries for glibc Linux
#      only. On Alpine/musl npm finds no prebuild and falls back to compiling it
#      with node-gyp, which means python3 + make + g++ inside the build stage and
#      a binary welded to that exact libc and NAPI version. A Debian ("bookworm")
#      base gets the prebuild and needs no toolchain at all, so that is what both
#      stages use.
#
#   2. Prisma resolves its query engine and schema engine per platform. Running
#      `prisma generate` *inside this image* is what guarantees the engine matches
#      the libc that will actually execute the queries, and it is the reason
#      `binaryTargets` does not have to be pinned in prisma/schema.prisma.
#
# Consequence: the two stages MUST share one base image. Switching the runtime
# stage to Alpine without moving the build stage with it produces an image that
# builds, starts, and then fails on the first login (bcrypt) or the first query
# (engine target) -- both with errors that point nowhere near this file.

ARG NODE_IMAGE=node:24.19.0-bookworm-slim

# Kept in step with the `prisma` devDependency in package.json. CI fails the
# build when the two drift apart, because a CLI whose version differs from
# @prisma/client can generate a client the runtime refuses to load.
ARG PRISMA_CLI_VERSION=6.19.3

ARG APP_VERSION=dev
ARG BUILD_DATE=unknown


# ---------------------------------------------------------------------------
# Build stage: typecheck and compile TypeScript to dist/.
# ---------------------------------------------------------------------------
FROM ${NODE_IMAGE} AS build

WORKDIR /app

# Dependencies first, so editing src/ does not invalidate the npm layer.
COPY package.json package-lock.json ./
RUN npm ci

COPY tsconfig.json ./
COPY prisma ./prisma
COPY src ./src

# Generation has to precede the compile, not follow it: the typed model
# delegates (`prisma.project`, `prisma.task`, ...) only exist in the *generated*
# client, so without this step tsc fails on every repository call with
# "Property 'project' does not exist on type 'PrismaClient'".
RUN npx prisma generate

RUN npm run build


# ---------------------------------------------------------------------------
# Runtime stage: production dependencies, compiled output, no TypeScript.
# ---------------------------------------------------------------------------
FROM ${NODE_IMAGE} AS runtime

ARG PRISMA_CLI_VERSION
ARG APP_VERSION
ARG BUILD_DATE

# Read by the deploy script to confirm that the digest it pulled really is the
# release it was told to deploy (this backend exposes no /version route).
LABEL org.opencontainers.image.version=$APP_VERSION \
      org.opencontainers.image.created=$BUILD_DATE

ENV NODE_ENV=production \
    PORT=3001 \
    APP_VERSION=$APP_VERSION \
    BUILD_DATE=$BUILD_DATE

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# `prisma` is a devDependency, yet `prisma migrate deploy` has to run from this
# exact image: same schema, same engines, same libc as the code that will query
# the database afterwards. Installing the CLI explicitly keeps the production
# dependency tree lean while still shipping it. `--no-save` leaves
# package.json/package-lock.json untouched, so the lockfile committed to the
# repository stays the single source of truth for what the app depends on.
RUN npm install --no-save --no-audit --no-fund "prisma@${PRISMA_CLI_VERSION}"

# Schema and migrations are part of the image on purpose. A release is then one
# immutable artifact that carries the schema it expects, so the migration step
# cannot accidentally apply a different repository checkout than the code.
COPY prisma ./prisma
RUN npx prisma generate

COPY --from=build /app/dist ./dist

# Fail the *build* rather than the first login request if the native bcrypt
# binary does not match this image (wrong libc, wrong NAPI version, stale
# prebuild). Requiring @prisma/client additionally proves that the generate step
# above actually produced a loadable client.
RUN node -e "require('bcrypt'); require('@prisma/client');"

# node:* images ship an unprivileged `node` user (uid 1000). Everything under
# /app is root-owned and only read at runtime, which is what lets the container
# run with a read-only root filesystem (see compose.prod.yaml).
USER node

EXPOSE 3001

# Note on configuration: src/server.ts calls dotenv with the repo-root `.env`,
# resolved two levels above the compiled file -- inside this image that is
# `/.env`, which does not exist. A missing file is a no-op for dotenv, and
# dotenv never overrides variables that are already set, so in production every
# setting comes from the container environment and nothing is read from disk.
# Do not create /.env in the image or mount one there: that would reintroduce a
# second, invisible source of truth for the secrets.
CMD ["node", "dist/server.js"]
