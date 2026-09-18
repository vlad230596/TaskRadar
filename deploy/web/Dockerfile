# The TaskRadar web client image (`taskradar-web`): the Flutter web bundle and a
# static server, nothing else.
#
# ## Why the Flutter build is not in this file
#
# There is no builder stage here. `flutter build web` happens in the release
# workflow, on a runner that already has the SDK cached, and only its output
# enters this build. A builder stage would mean downloading the Flutter SDK plus
# a Dart toolchain into a layer on every release -- minutes and hundreds of
# megabytes for a step the workflow performs anyway for the Windows and Android
# artifacts.
#
# The consequence is that this Dockerfile cannot be built from a bare checkout:
# it expects a prepared context holding `nginx.conf` and `site/` (the contents of
# `app/build/web`). The release workflow assembles that context; see
# `.github/workflows/release.yml`.
FROM nginx:1.29-alpine

# Replaces the stock default server block, which listens on :80 and serves the
# nginx welcome page.
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY site/ /usr/share/nginx/html/

# Unprivileged, so the container does not need CAP_NET_BIND_SERVICE. The shared
# Caddy reaches this over the `taskradar-ingress` network by the alias
# `taskradar-web`; nothing is published on the host.
EXPOSE 8080
