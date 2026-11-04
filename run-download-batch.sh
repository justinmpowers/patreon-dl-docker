#!/usr/bin/env sh
# Runs a single patreon-dl download pass. Used by every download MODE in
# docker-entrypoint.sh and by the supercronic schedule.
set -eu

CONFIG_FILE="${CONFIG_FILE:-/config/main.conf}"
DATA_DIR="${DATA_DIR:-/data}"
LOG_LEVEL="${LOG_LEVEL:-info}"

timestamp() { date -u +%Y-%m-%dT%H:%M:%SZ; }

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Config file not found at $CONFIG_FILE" >&2
  exit 1
fi

if grep -Eq '^[[:space:]]*target\.url[[:space:]]*=.*patreon\.com/CREATOR/' "$CONFIG_FILE"; then
  echo "$CONFIG_FILE still has the example target.url — set it to the creator(s) you want to download." >&2
  exit 1
fi

echo "[$(timestamp)] Starting download batch"
# -o overrides out.dir from the config so output always lands in the mounted volume.
# -y skips patreon-dl's interactive confirmation prompt.
if patreon-dl -C "$CONFIG_FILE" -o "$DATA_DIR" -y --log-level "$LOG_LEVEL"; then
  echo "[$(timestamp)] Download batch completed successfully"
else
  rc=$?
  echo "[$(timestamp)] Download batch failed with exit code $rc" >&2
  exit "$rc"
fi
