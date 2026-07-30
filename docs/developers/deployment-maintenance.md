---
title: Deployment Maintenance Page
parent: Developer Guide
nav_order: 10
---

# Deployment Maintenance Page

CEDAR cannot show an in-app modal while the Shiny process is restarting. During
a container replacement, the browser is talking to nginx, not to the Shiny app,
so the friendly restart message has to come from nginx as a static fallback.

The production deploy workflow supports this pattern:

1. Pull the new code.
2. Build the new Docker image while the old app continues serving users.
3. Write a short-lived maintenance marker file.
4. Replace the Shiny container.
5. Poll the local Shiny health check.
6. Remove the maintenance marker.

## Files

The static page lives at:

```text
deploy/nginx/cedar-restarting.html
```

The example nginx fragment lives at:

```text
deploy/nginx/cedar-maintenance.conf.example
```

The default marker path is:

```text
/var/www/cedar-maintenance/maintenance.flag
```

Set the GitHub Actions secret `CEDAR_MAINTENANCE_FLAG` if the production server
uses a different marker path.

## Server Setup

On the production server, copy the static page to the directory nginx will read:

```bash
sudo mkdir -p /var/www/cedar-maintenance
sudo cp deploy/nginx/cedar-restarting.html /var/www/cedar-maintenance/cedar-restarting.html
```

Then adapt the nginx server block using
`deploy/nginx/cedar-maintenance.conf.example`. The important pieces are:

- `error_page 502 503 504 /cedar-restarting.html;`
- the marker-file check returning `503`
- `proxy_intercept_errors on;` in the CEDAR proxy location
- `Cache-Control: no-store` so browsers do not keep the restart page

After editing nginx:

```bash
sudo nginx -t
sudo systemctl reload nginx
```

Once this is installed, ordinary GitHub deploys should show the static restart
page only while CEDAR is actually being replaced and warmed.
