---
title: Deployment Maintenance Page
parent: Developer Guide
nav_order: 10
---

# Deployment Maintenance Page

CEDAR cannot show an in-app modal while the Shiny process is restarting. During
a container replacement, the browser is talking to nginx, not to the Shiny app,
so friendly downtime messages have to come from nginx as static fallbacks.

CEDAR supports two separate proxy-level messages:

| Mode | Marker | Use |
|:--|:--|:--|
| Restarting | `restarting.flag` | Short GitHub deploy restart while the Shiny container is replaced and warmed. |
| Maintenance | `maintenance.flag` | Manual extended downtime for longer operational work. |

Users who already have CEDAR open may see the in-app restart overlay from
`www/cedar-disconnect.js` instead of the nginx static page. That overlay also
reloads the page every 10 seconds, because Shiny websocket reconnects are not
reliable after the backing container has been replaced.

The production deploy workflow supports the restart pattern:

1. Pull the new code.
2. Build the new Docker image while the old app continues serving users.
3. Clear any marker stranded by an earlier deploy, then write a short-lived one.
4. Replace the Shiny container.
5. Poll the local Shiny health check.
6. Remove the restart marker as soon as that health check passes.

## The marker is cleared three times, deliberately

The marker decides what every visitor sees, so removing it cannot depend on the
deploy script surviving to the end. A deploy that reaches the droplet over SSH
can lose its connection at any point, and a dropped connection does not run a
bash `EXIT` trap — which is how one stranded flag kept the site on the restart
page long after the container came up healthy within seconds.

| When | Covers |
|:--|:--|
| Start of a deploy, before writing a new marker | A marker stranded by the previous deploy, whatever killed it |
| Immediately after the health check passes | A connection lost during post-deploy work, when the app is already serving |
| `EXIT` trap | An ordinary failure earlier in the script |

A marker found at the start of a deploy is reported as a workflow warning: it
means the previous deploy did not finish cleanly, and is worth reading the log
for even though the site recovers on its own.

Deploys can be days apart, so for a marker stranded before the health check the
first line of defense is a host-side sweeper. This one clears any restart marker
older than fifteen minutes; a deploy that legitimately takes longer than that
has bigger problems than the marker:

```cron
*/5 * * * * find /var/www/cedar-maintenance -name restarting.flag -mmin +15 -delete
```

That path must match `CEDAR_RESTARTING_FLAG`. The sweeper deliberately does not
touch `maintenance.flag` — extended maintenance is manual and stays until it is
removed by hand.

## Files

The static page lives at:

```text
deploy/nginx/cedar-restarting.html
```

The extended maintenance page lives at:

```text
deploy/nginx/cedar-maintenance.html
```

The example nginx fragment lives at:

```text
deploy/nginx/cedar-maintenance.conf.example
```

The default CI restart marker path is:

```text
/var/www/cedar-maintenance/restarting.flag
```

Set the GitHub Actions secret `CEDAR_RESTARTING_FLAG` if the production server
uses a different host-side marker path. If nginx runs in Docker, this must be
the path on the host, not the path inside the nginx container.

## Server Setup

On the production server, copy the static page to the directory nginx will read:

```bash
sudo mkdir -p /var/www/cedar-maintenance
sudo cp deploy/nginx/cedar-restarting.html /var/www/cedar-maintenance/cedar-restarting.html
sudo cp deploy/nginx/cedar-maintenance.html /var/www/cedar-maintenance/cedar-maintenance.html
```

Then adapt the nginx server block using
`deploy/nginx/cedar-maintenance.conf.example`. The important pieces are:

- separate marker checks for `maintenance.flag` and `restarting.flag`
- maintenance taking precedence if both flags exist
- `proxy_intercept_errors on;` in the CEDAR proxy location
- `Cache-Control: no-store` so browsers do not keep downtime pages

After editing nginx:

```bash
sudo nginx -t
sudo systemctl reload nginx
```

Once this is installed, ordinary GitHub deploys should show the restart page
only while CEDAR is actually being replaced and warmed. Extended maintenance is
manual: create `maintenance.flag` to show the longer downtime page and remove it
when CEDAR should be available again.
