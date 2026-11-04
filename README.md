# patreon-dl-docker

[![CI](https://github.com/justinmpowers/patreon-dl-docker/actions/workflows/ci.yml/badge.svg)](https://github.com/justinmpowers/patreon-dl-docker/actions/workflows/ci.yml)

Run [patreon-dl](https://github.com/patrickkfkan/patreon-dl) in Docker: automatically download posts from the Patreon creators you support, on a schedule, and browse them in a local web UI.

- **Scheduled downloader**: runs patreon-dl daily (or on any cron schedule) and only fetches what's new.
- **Web UI**: `patreon-dl-server` for browsing everything you've downloaded.
- **Ready to run**: prebuilt image for `amd64` and `arm64` (Raspberry Pi, most NAS boxes). Runs as a non-root user and bundles FFmpeg (videos) and Deno (embedded YouTube videos).

> [!IMPORTANT]
> This downloads only content your own Patreon account already has access to. Please respect creators' terms and don't redistribute what you download. This project is not affiliated with Patreon or with patreon-dl.

## Quick start

You need [Docker](https://docs.docker.com/get-docker/) with Compose v2 (included in Docker Desktop).

```bash
git clone https://github.com/justinmpowers/patreon-dl-docker.git
cd patreon-dl-docker
cp .env.example .env
cp main.conf.example main.conf
```

Open `main.conf` and set two things:

```ini
target.url = https://www.patreon.com/CREATOR/posts
cookie = <your Patreon cookie — see below>
```

Start it:

```bash
docker compose pull
docker compose up -d
```

The first download starts right away. Follow it with `docker compose logs -f patreon-dl-download`, and open **http://localhost:3900** to browse. The web UI comes up a few seconds after that first download starts.

### Getting your Patreon cookie

patreon-dl signs in to Patreon with your browser's session cookie:

1. Sign in to patreon.com in a desktop browser and open Developer Tools (F12) → **Network** tab.
2. Visit a creator's page and click any request whose name starts with `posts`.
3. Under **Request Headers**, right-click the **Cookie** value → **Copy value**. Copy the *whole* value.
4. Paste it after `cookie =` in `main.conf`.

There are screenshots on the [patreon-dl wiki](https://github.com/patrickkfkan/patreon-dl/wiki/How-to-obtain-Cookie). The cookie gives full access to your Patreon account, so keep it private. It stops working when you sign out or Patreon expires it. If patron-only posts start showing up as locked, paste in a fresh cookie and run `docker compose restart patreon-dl-download`.

## Configuration

### `.env`: schedule, ports, logging

| Variable | Default | Description |
|---|---|---|
| `CRON_SCHEDULE` | `0 12 * * *` | When downloads run ([cron format](https://crontab.guru/)). Default: daily at noon. |
| `TZ` | `UTC` | Timezone for the schedule, e.g. `America/New_York`. |
| `RUN_ON_START` | `1` | Run a download as soon as the container starts (`0` to wait for the schedule). |
| `SERVER_PORT` | `3900` | Host port for the web UI. |
| `SERVER_BIND` | `127.0.0.1` | Interface the web UI listens on. See [Web UI access](#web-ui-access). |
| `LOG_LEVEL` | `info` | `debug`, `info`, `warn`, `error` or `none`. |
| `IMAGE` | `ghcr.io/justinmpowers/patreon-dl-docker:latest` | Image to run, e.g. to pin a release tag. |

Changes take effect with `docker compose up -d`.

### `main.conf`: what to download

[`main.conf.example`](main.conf.example) is a minimal starting point. By default it downloads everything you have access to. Every option is documented in [upstream's example config](https://github.com/patrickkfkan/patreon-dl/blob/master/example.conf). Some common setups:

```ini
[downloader]
# Several creators, comma-separated
target.url = https://www.patreon.com/creator1/posts,https://www.patreon.com/creator2/posts

[include]
# ZIP attachments only (e.g. 3D-printing model packs); "!" = case-insensitive
content.media = attachment
preview.media = 0
attachments.by.filename = !*.zip

# Only posts published from this date on
posts.published.after = 2025-01-01
```

Downloads, logs and patreon-dl's database are written to `./data`. After editing `main.conf`, run `docker compose restart patreon-dl-download`.

## Everyday commands

```bash
# Download now instead of waiting for the schedule
docker compose exec patreon-dl-download run-download-batch.sh

# Follow logs
docker compose logs -f patreon-dl-download
docker compose logs -f patreon-dl-server

# Run any patreon-dl command, e.g. list a creator's tiers
docker compose run --rm patreon-dl-download patreon-dl --list-tiers CREATOR

# Update to the latest version
git pull && docker compose pull && docker compose up -d

# Stop everything
docker compose down
```

## Web UI access

The web UI has **no login**, so by default it only accepts connections from the machine it runs on. To reach it from other devices on your home network, set this in `.env` and run `docker compose up -d`:

```bash
SERVER_BIND=0.0.0.0
```

Only do this on a network you trust. For access from outside your home, use a VPN (such as Tailscale or WireGuard) or a reverse proxy with authentication. Never forward the port directly to the internet.

## Building the image yourself

```bash
docker compose up -d --build

# Or with a different patreon-dl version:
docker compose build --build-arg PATREON_DL_VERSION=3.9.0
```

## Troubleshooting

**`/data is not writable by uid 1000`**: Docker created `./data` as root, or your user's ID isn't 1000 (check with `id -u`). Fix it with `sudo chown -R 1000:1000 ./data`.

**`Config file not found` or `main.conf` is a directory**: an earlier run started before `main.conf` existed. Run `rmdir main.conf && cp main.conf.example main.conf`, then fill it in again.

**Web UI doesn't load and its log says `Waiting for the first download`**: the UI needs the database the downloader creates when it first runs. Check `docker compose logs patreon-dl-download`. With `RUN_ON_START=0`, the UI waits for the first scheduled run.

**Patron-only posts are skipped or saved as locked**: the cookie is missing, incomplete or expired. Copy a fresh one (see [above](#getting-your-patreon-cookie)).

**Permission denied on Fedora/RHEL (SELinux) or with Podman**: add `:z` to each volume (`./data:/data:z`, and `bind: {selinux: z}` on the `main.conf` mount). With rootless Podman, also add `userns_mode: keep-id` to both services.

## Advanced: container modes

The image picks its behavior from the `MODE` environment variable:

| `MODE` | What it does |
|---|---|
| `server` (default) | Runs the web UI on `PORT` (default `3000`) serving `DATA_DIR`. |
| `download-cron` | Downloads on `CRON_SCHEDULE` using [supercronic](https://github.com/aptible/supercronic). |
| `download` | Runs a single download and exits. Handy for an external scheduler. |
| `download-batch` | Downloads every `BATCH_INTERVAL_SECONDS` (default `21600`) in a simple loop. |

Paths can be overridden with `CONFIG_FILE` (default `/config/main.conf`) and `DATA_DIR` (default `/data`). Passing a command, e.g. `docker run … patreon-dl --help`, runs it directly.

## Security notes

- `main.conf` holds your session cookie. It is git-ignored, excluded from the Docker build context, and mounted read-only into the downloader only.
- The containers mount only `./data` (plus `main.conf` for the downloader), so the web UI can't serve your config or anything else on the host.
- Everything runs as the non-root `node` user (uid 1000). The supercronic binary is checksum-verified, and Deno sandboxes patreon-dl's YouTube downloader.
- The published image is rebuilt weekly to pick up Debian security updates.

## Credits

All the actual downloading is done by [patreon-dl](https://github.com/patrickkfkan/patreon-dl) by patrickkfkan. This repository just packages it for Docker. Licensed under the [MIT License](LICENSE).
