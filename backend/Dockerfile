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
# Consequence: all stages MUST share one base image -- the runtime takes the
# client (and its query engine) generated in the build stage, and the migrate
# image resolves the schema engine the same way. Switching the runtime
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
# Migrate target (`taskradar-migrate`): the Prisma CLI, the schema and the
# migrations -- nothing else.
#
# It is a separate image because the CLI is by far the heaviest thing Prisma
# brings: the CLI itself, the schema engine, and its own dependencies (`effect`,
# `typescript`) add up to ~170 MB that the API never loads. Shipped inside the
# backend image, every running container carried them just so that the one-off
# `migrate` service could exist. Here they are paid for once per Prisma version:
# the npm layer only changes when PRISMA_CLI_VERSION does, so a release that
# changes code but not Prisma adds nothing but the prisma/ directory.
#
# The engines are resolved inside this image, on the same base as the others,
# so the schema engine matches the libc it runs on. No package.json is involved:
# `prisma` pins its own dependencies to exact versions, so installing it by
# version alone is reproducible, and it keeps the application's dependency tree
# (Fastify, bcrypt, the client) out of an image that never starts the app.
# ---------------------------------------------------------------------------
FROM ${NODE_IMAGE} AS migrate

ARG PRISMA_CLI_VERSION

WORKDIR /app

RUN npm install --no-audit --no-fund --no-package-lock "prisma@${PRISMA_CLI_VERSION}" \
 && npm cache clean --force \
 && rm -rf /root/.cache

# Schema and migrations are part of the image on purpose. A release is then one
# immutable artifact that carries the schema it expects, so the migration step
# cannot accidentally apply a different repository checkout than the code.
COPY prisma ./prisma

# Fail the build rather than the deploy if the CLI cannot start on this base.
RUN CHECKPOINT_DISABLE=1 /app/node_modules/.bin/prisma --version

# Last for the same reason as in the runtime stage: values that change on every
# release must not invalidate the cache of the layers above.
ARG APP_VERSION
ARG BUILD_DATE
LABEL org.opencontainers.image.version=$APP_VERSION \
      org.opencontainers.image.created=$BUILD_DATE

USER node

CMD ["/app/node_modules/.bin/prisma", "migrate", "deploy"]


# ---------------------------------------------------------------------------
# Deps stage: the production node_modules, without the Prisma CLI.
#
# Assembled here and copied into the runtime as a single layer. Done in the
# runtime stage directly (as it used to be), the image carried costs that had
# nothing to do with running the app, and together they took it past 1 GB: npm's
# download cache (~180 MB under /root/.npm) stayed in the layer, `prisma
# generate` rewrote files inside node_modules so the client was stored twice,
# and the CLI rode along for the migrate service's sake.
#
# The generated client is taken from the build stage, which already ran
# `prisma generate` on this same base image -- so the query engine in it matches
# the runtime's libc, and the CLI never has to be installed here. The stub that
# @prisma/client's postinstall writes when it finds no CLI is removed first, so
# nothing of it survives next to the real client.
# ---------------------------------------------------------------------------
FROM ${NODE_IMAGE} AS deps

WORKDIR /app

COPY package.json package-lock.json ./
# `--omit=optional` is what actually keeps the CLI out; `--omit=dev` alone does
# not. @prisma/client declares `prisma` and `typescript` as optional peers, so
# the lockfile marks them -- and ~40 packages under them, `effect` included --
# `devOptional`, and npm only drops a devOptional package when both dev and
# optional are omitted. With `--omit=dev` alone the 0.10.1 image still carried
# the whole CLI. The app has no optional production dependencies today; if one
# is ever added (a platform-specific prebuild, say), it has to be handled here.
#
# The `test` makes that regression fail the build instead of silently doubling
# the image again.
RUN npm ci --omit=dev --omit=optional --no-audit --no-fund \
 && npm cache clean --force \
 && rm -rf node_modules/.prisma \
 && test ! -e node_modules/prisma \
 && test ! -e node_modules/typescript

COPY --from=build /app/node_modules/.prisma ./node_modules/.prisma


# ---------------------------------------------------------------------------
# Runtime stage (`taskradar-backend`, the default target): production
# dependencies, compiled output, no TypeScript and no Prisma CLI.
# ---------------------------------------------------------------------------
FROM ${NODE_IMAGE} AS runtime

ENV NODE_ENV=production \
    PORT=3001

WORKDIR /app

COPY package.json package-lock.json ./
COPY --from=deps /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist

# Fail the *build* rather than the first login request if the native bcrypt
# binary does not match this image (wrong libc, wrong NAPI version, stale
# prebuild). Constructing a PrismaClient additionally proves that the client
# copied from the build stage is the generated one and not the postinstall stub,
# which loads fine and only throws when instantiated.
# The URL is a dummy: the constructor validates it but does not connect.
RUN DATABASE_URL=postgresql://build@127.0.0.1:5432/build \
    node -e "require('bcrypt'); new (require('@prisma/client').PrismaClient)();"

# The release identity comes last on purpose. Both values change on every
# release, and an ARG or ENV invalidates the build cache for every instruction
# after it; declared at the top, they made each release rebuild -- and the VDS
# download -- the whole dependency layer even when package-lock.json had not
# changed. Here they cost nothing: LABEL and ENV add metadata, not a layer.
ARG APP_VERSION
ARG BUILD_DATE

# Read by the deploy script to confirm that the digest it pulled really is the
# release it was told to deploy -- i.e. it describes the *artifact*, before
# anything runs.
#
# The same two values also become ENV below and are what `GET /version` reports,
# which answers a different question: what is running right now, asked over the
# network. Both exist on purpose; the label is checkable without starting a
# container, the route is checkable without access to the Docker socket.
LABEL org.opencontainers.image.version=$APP_VERSION \
      org.opencontainers.image.created=$BUILD_DATE

ENV APP_VERSION=$APP_VERSION \
    BUILD_DATE=$BUILD_DATE

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
