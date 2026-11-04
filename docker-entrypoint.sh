#!/usr/bin/env sh
set -eu

MODE="${MODE:-server}"
DATA_DIR="${DATA_DIR:-/data}"
PORT="${PORT:-3000}"
LOG_LEVEL="${LOG_LEVEL:-info}"
CONFIG_FILE="${CONFIG_FILE:-/config/main.conf}"
CRON_SCHEDULE="${CRON_SCHEDULE:-0 12 * * *}"
RUN_ON_START="${RUN_ON_START:-1}"
BATCH_INTERVAL_SECONDS="${BATCH_INTERVAL_SECONDS:-21600}"

# run-download-batch.sh (also invoked by supercronic) reads these.
export CONFIG_FILE DATA_DIR LOG_LEVEL

# An explicit command bypasses MODE, e.g.
#   docker compose run --rm patreon-dl-download patreon-dl --help
if [ "$#" -gt 0 ]; then
  exec "$@"
fi

require_config() {
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "Config file not found at $CONFIG_FILE" >&2
    echo "Mount your config file, for example: -v ./main.conf:/config/main.conf:ro" >&2
    exit 1
  fi
}

# A ./data that didn't exist before the first `docker compose up` gets created
# by Docker as root, which this non-root container can't write to.
require_writable_data() {
  if [ ! -w "$DATA_DIR" ]; then
    echo "$DATA_DIR is not writable by uid $(id -u)." >&2
    echo "Fix it on the host with: sudo chown -R $(id -u):$(id -g) ./data" >&2
    exit 1
  fi
}

case "$MODE" in
  download)
    require_config
    require_writable_data
    exec run-download-batch.sh
    ;;

  download-cron)
    require_config
    require_writable_data
    if [ "$RUN_ON_START" = "1" ]; then
      run-download-batch.sh || true
    fi

    # supercronic runs as the container's own (non-root) user and inherits its
    # environment, so the variables exported above reach every scheduled run.
    # tini (PID 1) already reaps zombies, hence -no-reap; -passthrough-logs keeps
    # patreon-dl's output readable instead of wrapping each line in logfmt.
    CRONTAB_FILE="$(mktemp)"
    printf '%s %s\n' "$CRON_SCHEDULE" /usr/local/bin/run-download-batch.sh > "$CRONTAB_FILE"
    echo "Configured cron schedule: $CRON_SCHEDULE (TZ=${TZ:-UTC})"
    exec supercronic -no-reap -passthrough-logs "$CRONTAB_FILE"
    ;;

  download-batch)
    # Simple fixed-interval loop; download-cron is usually the better choice.
    require_config
    require_writable_data
    if [ "$RUN_ON_START" != "1" ]; then
      echo "Delaying first batch by $BATCH_INTERVAL_SECONDS seconds"
      sleep "$BATCH_INTERVAL_SECONDS"
    fi
    while true; do
      run-download-batch.sh || true
      echo "Sleeping for $BATCH_INTERVAL_SECONDS seconds"
      sleep "$BATCH_INTERVAL_SECONDS"
    done
    ;;

  server)
    require_writable_data
    # patreon-dl-server exits if its database is missing; the downloader creates
    # it within seconds of starting its first run.
    DB_FILE="$DATA_DIR/.patreon-dl/db.sqlite"
    if [ ! -f "$DB_FILE" ]; then
      echo "Waiting for the first download to create $DB_FILE ..."
      while [ ! -f "$DB_FILE" ]; do
        sleep 5
      done
    fi
    exec patreon-dl-server -i "$DATA_DIR" -p "$PORT" --log-level "$LOG_LEVEL"
    ;;

  *)
    echo "Unknown MODE: $MODE" >&2
    echo "Supported MODE values: server, download, download-cron, download-batch" >&2
    exit 1
    ;;
esac
