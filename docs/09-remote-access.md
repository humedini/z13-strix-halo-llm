# 09. Remote access: Tailscale only, loopback everywhere

## The principle

This is a tablet. It joins café, hotel and conference Wi-Fi. Anything bound to `0.0.0.0` is exposed to whoever else is on that network, and the inference stack as installed by default includes an unauthenticated API and a web UI whose first visitor becomes admin.

So the rule for this machine is: **every service binds loopback, and Tailscale is the only ingress.** A wrong or missing firewall rule then cannot expose anything, because there is nothing listening on a LAN address to expose.

```
tailnet client --TLS--> tailscaled
                          ├─ :443    -> 127.0.0.1:3000   Open WebUI
                          ├─ :11434  -> 127.0.0.1:11435  nginx shim -> 127.0.0.1:11434 Ollama
                          ├─ :13305  -> 127.0.0.1:13305  Lemonade
                          └─ :22     -> sshd (bound to the tailnet address, not 0.0.0.0)
```

This is verified after every change with:

```bash
ss -tln | grep -E ':3000|:11434|:11435|:13305|:22 '
```

Nothing in that output should ever show `0.0.0.0` or `*` as the local address.

## Tailscale serve

Rather than binding services to the Tailscale interface directly, `tailscale serve` proxies them from loopback and terminates TLS with automatically issued certificates:

```bash
sudo tailscale serve --bg --https=443   http://127.0.0.1:3000
sudo tailscale serve --bg --https=11434 http://127.0.0.1:11435
sudo tailscale serve --bg --https=13305 http://127.0.0.1:13305
```

Requirements: MagicDNS on, and HTTPS certificates enabled in the Tailscale admin console under the **DNS** page (not Settings, despite what older guides say). Arbitrary HTTPS ports work.

Two things to know:

**You must type `https://`** for the non-443 ports. A browser given `host:13305` defaults to plain HTTP, and Tailscale's listener answers `Client sent an HTTP request to an HTTPS server`. The bare hostname on 443 works without a scheme.

**`sudo tailscale set --operator=$USER`** lets your account run `tailscale serve` and `tailscale cert` without root. Not done on this build, so every routing change needs sudo.

## Ollama returns 403 behind any proxy

Ollama validates the `Host` header as a DNS rebinding guard and accepts only `localhost` and `127.0.0.1`. Tailscale serve forwards the `.ts.net` hostname, so **every proxied request is rejected with 403** and an empty body.

`OLLAMA_ORIGINS` does not fix this. It governs the `Origin` header for CORS, not `Host`. Confirmed by testing: a request with an allowed `Origin` still gets 403.

The documented fix is `OLLAMA_HOST=0.0.0.0`, which makes the check permissive. That also binds the unauthenticated API to every interface, which is the exact thing this whole setup exists to avoid. Rejected.

Instead, an nginx shim on loopback rewrites the header, script `08-ollama-proxy.sh`:

```nginx
server {
    listen 127.0.0.1:11435;
    client_max_body_size 0;           # model pushes are large; the 1 MB default breaks them
    location / {
        proxy_pass http://127.0.0.1:11434;
        proxy_set_header Host 127.0.0.1:11434;    # the actual fix
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_buffering off;              # otherwise token streaming arrives in one lump
        proxy_cache off;
        proxy_read_timeout 3600s;         # the 60 s default kills long generations
        proxy_send_timeout 3600s;
    }
}
```

Tailscale serve points at 11435; Ollama itself never moves off loopback.

**Installing nginx enables a default site on `0.0.0.0:80`.** Delete `/etc/nginx/sites-enabled/default` or you have just re-opened the kind of exposure you were closing.

Lemonade does not have this problem. It accepts any `Host` header, so it is proxied directly with no shim.

## Open WebUI

Runs in Docker. Two changes from the installer's default:

**Host networking, bound to loopback.** The installer publishes `-p 3000:8080` on all interfaces. This build runs it with `--network=host -e HOST=127.0.0.1 -e PORT=3000`, which both keeps it off the LAN and lets it reach Ollama on `127.0.0.1:11434`. With bridge networking and Ollama on loopback, the container cannot reach Ollama at all, because `host.docker.internal` is the bridge gateway, not loopback.

**Its Ollama URL lives in the database.** `OLLAMA_BASE_URL` seeds the value on first run only. After that the setting in the `open-webui` volume wins, so recreating the container with a new env var does not change it. The symptom after moving to host networking:

```
Cannot connect to host host.docker.internal:11434 [Name or service not known]
```

That name correctly does not resolve in host network mode. Fix it in **Admin Panel → Settings → Connections → Ollama API**, set to `http://127.0.0.1:11434`.

**Claim the admin account immediately.** First visitor becomes admin. Then disable signup.

**API keys are hidden twice.** The feature must be enabled by an admin under **Admin Panel → Settings → Authentication → Enable API Keys**. Then on the Account page, the keys section is collapsed behind a **Show** button next to "Secrets", so the page looks empty until you click it. The environment variable is `ENABLE_API_KEYS`, plural.

Script `06-lockdown-and-serve.sh` does the container recreation and serve setup; `scripts/owui-import.py` is not included in this repository because it is specific to one chat database, but the approach is: Open WebUI stores history as an ID-linked tree with `parentId`/`childrenIds`, and `POST /api/v1/chats/new` with that structure creates a navigable chat.

## SSH

`openssh-server` is not installed on a fresh Ubuntu 26.04 desktop. Script `20-ssh-server.sh` installs it bound to the Tailscale addresses and loopback:

```
ListenAddress <tailscale-ip>
ListenAddress 127.0.0.1
ListenAddress <tailscale-ipv6>
PermitRootLogin no
X11Forwarding no
```

Never `0.0.0.0`. Password auth is left on initially, because `authorized_keys` is empty on a fresh machine and disabling it first locks you out. Copy a key over, then add `PasswordAuthentication no`.

Tailscale SSH (`tailscale set --ssh`) was considered and not used. If your tailnet ACL runs SSH in `check` mode, it forces a browser re-approval roughly every 12 hours, which cannot be done headless. Regular sshd over the tailnet has no such friction.

## A firewall would break all of this

Generic Ubuntu advice says `sudo ufw enable`. That defaults to deny incoming, and Tailscale adds no iptables rules of its own on this setup, so it would cut off SSH, Open WebUI, Ollama and Lemonade in one move, including your only SSH route. If you want a firewall: `sudo ufw allow in on tailscale0` **first**, then enable.

## Why not just bind to the Tailscale interface

You could bind each service to `100.x.y.z` directly and skip serve. It works. The reasons not to: services then depend on tailscaled being up before they start, you get no TLS, and if anything ever falls back to `0.0.0.0` you have no second layer. Serve keeps every service on loopback, which is a posture that survives mistakes.
