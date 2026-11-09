# syntax=docker/dockerfile:1

# ---- Pinned third-party binaries ----
FROM denoland/deno:bin-2.9.8 AS deno-bin

FROM curlimages/curl:8.23.0 AS supercronic-fetch
ARG TARGETARCH
ARG SUPERCRONIC_VERSION=0.2.51
# Checksums from https://github.com/aptible/supercronic/releases/tag/v0.2.51
ARG SUPERCRONIC_SHA256_AMD64=cc232108374e8e2b537045f2d5eaa1229f619db314c3ba6a14d38b35dc0aa123
ARG SUPERCRONIC_SHA256_ARM64=4ae22576a78223d8ccdf5f3b3660a5cbb5288416bf0ca96afc4a36d195932b94
WORKDIR /tmp
# sha256sum is the last stage of the pipe, so its exit code propagates without
# pipefail (this image's ash shell doesn't need bash for that).
# hadolint ignore=DL4006
RUN curl -fsSLO "https://github.com/aptible/supercronic/releases/download/v${SUPERCRONIC_VERSION}/supercronic-linux-${TARGETARCH}" \
 && case "$TARGETARCH" in \
      amd64) echo "${SUPERCRONIC_SHA256_AMD64}  supercronic-linux-${TARGETARCH}" | sha256sum -c - ;; \
      arm64) echo "${SUPERCRONIC_SHA256_ARM64}  supercronic-linux-${TARGETARCH}" | sha256sum -c - ;; \
      *) echo "Unsupported architecture: $TARGETARCH" >&2; exit 1 ;; \
    esac \
 && chmod +x "supercronic-linux-${TARGETARCH}" \
 && mv "supercronic-linux-${TARGETARCH}" supercronic

# ---- Final image ----
FROM node:26-bookworm-slim

# Debian stable only receives security fixes, so packages are intentionally left
# unpinned: exact version pins disappear from the mirrors after each point
# release and break the build.
# hadolint ignore=DL3008
RUN apt-get update \
 && apt-get install -y --no-install-recommends ffmpeg ca-certificates tini \
 && rm -rf /var/lib/apt/lists/*

ARG PATREON_DL_VERSION=3.9.0
RUN npm install -g "patreon-dl@${PATREON_DL_VERSION}" \
 && npm cache clean --force

# Deno sandboxes patreon-dl's built-in YouTube embed downloader; without it, that
# code runs unisolated. Supercronic replaces system cron so the scheduler can run
# as a non-root user (system cron needs root to manage /etc/cron.d).
COPY --from=deno-bin /deno /usr/local/bin/deno
COPY --from=supercronic-fetch /tmp/supercronic /usr/local/bin/supercronic
COPY --chmod=755 docker-entrypoint.sh run-download-batch.sh /usr/local/bin/

# The base image already provides a "node" user at uid/gid 1000, which matches the
# typical single-user Linux host, so a bind-mounted ./data needs no chown. /data is
# pre-created with that owner so named/anonymous volumes start out writable too.
RUN mkdir /data && chown node:node /data
USER node
WORKDIR /app
VOLUME ["/data"]
EXPOSE 3000

ENTRYPOINT ["tini", "--", "docker-entrypoint.sh"]
