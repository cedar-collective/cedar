---
title: Installing on a Droplet
parent: Operations
grand_parent: Developer Guide
nav_order: 0
---

# Installing CEDAR on a Droplet

The order of work for standing up a production CEDAR on a fresh Linux server
(a DigitalOcean droplet at UNM), from an empty machine to a GitHub push that
deploys. Each step links to the page that owns its detail. "Production"
below is the UNM droplet as read on 2026-11-19.

## 1. The machine

- **Operating system.** Production runs Ubuntu 22.04 LTS. Any current Linux
  that runs Docker Engine with the Compose plugin will do.
- **Memory.** Production has 4 vCPUs, 8 GiB and a 4 GiB swap file; don't go
  below that. The image build peaks near 3.2 GiB, a second full copy of the
  class list in one R process has been killed for memory, and the refresh's
  measure-table stage (about 1.2 GiB) runs beside the live app.
- **Disk.** Production has 25 GB, and that is tight: the deploy refuses to
  start with less than 2 GiB free after pruning Docker build cache
  ([Release Runbook: no space left on
  device](release-runbook.html#if-github-deploy-fails-with-no-space-left-on-device)).
  Choose 50 GB or more for a new server, for several images, the data
  directory and its backups.
- **Docker.** Install Docker Engine and the Compose plugin
  (`docker compose version` must work), then create the external network the
  Compose file expects:

  ```bash
  docker network create shiny-net
  ```

## 2. The checkout

Clone the repository where the deploy workflow will find it (the GitHub
secret `CEDAR_PATH`). Production uses `/root/cedar`:

```bash
git clone https://github.com/cedar-collective/cedar.git /root/cedar
cd /root/cedar
```

Production also has `/root/shiny`, an older copy of the app from before the
current layout. Nothing runs from it; a new server doesn't need it.

## 3. Machine-local configuration

None of these is committed; none may be copied into a PR.

1. `config/shiny_config.R`, from `config/shiny_config_template.R`, with
   `cedar_use_small_data <- FALSE` and the term settings reviewed
   ([Installation: institutional instance](installation.html#institutional-instance-restricted-data-and-production-style-docker)).
2. `.env` beside `docker-compose.yml`:

   ```bash
   CEDAR_DATA_DIR=/path/to/approved/data
   CEDAR_DFW_PASSWORD=...   # opens instructor-level results; empty keeps them closed
   ```

   A `.Renviron` does not reach the app; only what `docker-compose.yml`
   passes does.
3. `CEDAR_INSTITUTION` if the institution is not `unm`: its mapping files
   live in `institution/<id>/` in the repository, not on the server.

## 4. Data

`CEDAR_DATA_DIR` holds the `cedar_*` tables the transform writes, and is
mounted into the container at `data/`. Two ways to fill it:

- **Copy** a reviewed set of normalized tables from another instance over a
  secure channel. Access, retention and backup of this directory are the
  institution's ([Installation](installation.html#institutional-instance-restricted-data-and-production-style-docker)).
- **Fetch and transform** with mrgather: clone mrgather
  (`cedar-collective/mrgather`, a private repository) beside CEDAR
  (`/root/mrgather` in production), put the MyReports credentials in its
  `.env`, and run the first refresh by hand
  ([Release Runbook: data refresh](release-runbook.html#3-data-refresh)).
  A first refresh needs a terminal for MyReports' 2FA prompt.

The app stops at startup without the measure tables and the student-term
table; the transform builds them, and a stale one names the command that
rebuilds it.

## 5. First start

```bash
docker compose up -d --build
docker logs -f cedar-shiny        # until the app reports it is listening
curl -fsS -o /dev/null http://localhost:3838/ && echo up
```

The first build on a small droplet takes several times longer than on a
laptop. Registration > Projections needs a published bundle in `output/`;
`restart-cedar.sh --update` builds one when it is missing
([Release Runbook: projection artifact](release-runbook.html#projection-artifact)).

## 6. nginx and the restart page

Put nginx in front of port 3838 and install the restart and maintenance
pages once ([Deployment Maintenance Page: server setup](deployment-maintenance.html#server-setup)).

Production runs nginx in Docker, as its own Compose project in
`/root/shiny-proxy` (container `shiny-proxy-nginx-1`), publishing ports 80
and 443. It mounts three host directories:

| Host | In the container | For |
|---|---|---|
| `/etc/letsencrypt` | `/etc/letsencrypt` | the certificates |
| `/root/shiny-proxy/certbot-webroot` | `/var/www/certbot` | the certificate challenge |
| `/root/shiny-proxy/flags` | `/var/maintenance` | the restart and maintenance markers and pages |

Because nginx is in Docker, `CEDAR_RESTARTING_FLAG` is the restart marker's
path on the host, under `/root/shiny-proxy/flags`.

**TLS.** Certificates come from Let's Encrypt through certbot on the host,
with the webroot authenticator writing into `certbot-webroot`. The system
`certbot.timer` renews them, and a deploy hook
(`/etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh`) reloads nginx in
its container:

```bash
docker exec shiny-proxy-nginx-1 nginx -s reload
```

## 7. Deploys from GitHub

Pushing to `main` runs `.github/workflows/deploy.yml`, which reaches the
server over SSH, updates the checkout, rebuilds stale tables, builds the
image and replaces the container. Set these repository secrets:

| Secret | Holds |
|---|---|
| `DROPLET_HOST` | the server's address |
| `DROPLET_USER` | the SSH user |
| `DROPLET_SSH_KEY` | a private key whose public half is in that user's `authorized_keys` |
| `CEDAR_PATH` | the checkout from step 2 |
| `CEDAR_RESTARTING_FLAG` | the host path of the restart marker, if not the default |

Run the workflow once by hand and watch it through its health check.

## 8. The daily refresh

Add the refresh to the server's crontab, keeping its term window current
(`scripts/README.md`, "Adding this to crontab"):

```cron
2 10 * * * /root/cedar/scripts/restart-cedar.sh --mode production --update -s 202680 -e 202710 --hard-restart >> /var/log/cedar-update.log 2>&1
```

Keep `--hard-restart` on a scheduled job. Without it the script touches
`restart.txt`: Shiny Server starts a new R process for new sessions and, with
`app_idle_timeout 0`, never ends the old one, which holds its memory (over a
gigabyte, and more in swap) until the container next restarts (ISSUES M69).
The hard restart ends every open session, so schedule it for when nobody is
reading.

A refresh that cannot answer a 2FA prompt stops rather than waiting, and a
report that did not arrive is marked failed while the others load
([scripts/README.md](https://github.com/cedar-collective/cedar/blob/main/scripts/README.md)).

## 9. Check it

Walk the [post-deploy smoke test](release-runbook.html#6-post-deploy-smoke-test),
and Admin > Data & Usage for each table's pull date.
