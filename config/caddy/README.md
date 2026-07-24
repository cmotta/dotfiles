# Local HTTPS dev proxy (Caddy)

One loopback-bound reverse proxy that gives every local service a stable
`https://<name>.localhost:8443` hostname. Terminates TLS locally so Chromium's
HTTPS-upgrade of `http://localhost:PORT` stops breaking plain-HTTP dev servers,
and port numbers stop being load-bearing.

`config/caddy → ~/.config/caddy` (symlinked by `install.sh`). This machine runs
on **port 8443 as your user** via a LaunchAgent — no root, no privileged
binding. The mini PCs stay on Tailscale Serve.

## Invariants

1. Every site block imports `(dev)`, which does `bind 127.0.0.1`. Without it,
   Caddy listens on all interfaces and publishes the dev stack to the network.
2. The internal root CA private key never leaves the machine — never into
   dotfiles or backups. It lives under `~/Library/Application Support/Caddy`;
   `pki/` and `data/` in this dir are gitignored defensively (the live key is
   never here). Anyone who controls the running proxy (its admin API on
   `localhost:2019`) can make it serve a trusted cert for any domain — which is
   why the proxy runs as your user, not root: no privilege boundary is crossed.
3. Treat any unauthenticated admin/SQL UI (e.g. a DuckDB UI on `:4213`) as a
   distinct risk class: arbitrary queries with filesystem read/write. Keep it
   loopback-only — no Tailscale Serve endpoint, no `flush_interval`, no extra
   exposure. The proxy only gives it a nicer name, never a wider reach.
4. A fresh clone of any work repo runs identically without Caddy installed.

## First-time setup

```sh
brew install caddy
./install.sh              # symlinks config, writes the resolved LaunchAgent plist
# then run the commands install.sh prints, IN THIS ORDER (no sudo):
cp config/caddy/com.caddyserver.caddy.resolved.plist \
   ~/Library/LaunchAgents/com.caddyserver.caddy.plist
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.caddyserver.caddy.plist
caddy trust               # queries the now-running proxy on :2019 (may prompt for keychain)
# restart the browser — Brave caches cert verification aggressively
```

**Order matters.** `caddy trust` fetches the CA from the running proxy's admin
API (`localhost:2019`); the CA doesn't exist until Caddy runs once. Trusting
before loading fails with `connect: connection refused`. `caddy trust` installs
into the login keychain and may pop a keychain-auth dialog — that's expected,
not sudo.

## Managing sites

```sh
devproxy add studio 3000   # https://studio.localhost:8443 -> 127.0.0.1:3000 (+ /etc/hosts)
devproxy rm  studio
devproxy ls
```

`devproxy` validates the name (lowercase/digits/hyphens) and port (1-65535)
before touching `/etc/hosts` or the config. Generated files land in
`sites.d/*.caddy` and are **all gitignored** — this repo is public, so no
personal topology is committed; recreate sites per host with `devproxy add`.
Chromium resolves `*.localhost` internally; `curl`/Node/containers need the
`/etc/hosts` entry `devproxy add` writes.

Streaming upstreams (SSE, long-poll) that feel buffered want `flush_interval -1`
in their `reverse_proxy` block. WebSockets (HMR) need nothing — Caddy passes
`Upgrade` through transparently.

## Verification

```sh
# Loopback only — want 127.0.0.1:8443, NOT 0.0.0.0:8443 or *:8443
lsof -nP -iTCP -sTCP:LISTEN | grep ':8443'
# Nothing answers off-box (run from another tailnet machine)
curl -sS --max-time 3 https://<lan-ip>:8443/ && echo "EXPOSED — fix bind" || echo "ok"
# Cert chain trusted / upstream independently reachable (swap in your own site)
curl -sS -o /dev/null -w '%{http_code}\n' https://<name>.localhost:8443/
curl -sS -o /dev/null -w '%{http_code}\n' http://localhost:<port>/   # use localhost, not 127.0.0.1
# Config sanity (validate BEFORE any reload — a bad reload 502s everything)
caddy validate --config ~/.config/caddy/Caddyfile
```

## CA rotation (if the key is ever suspected exposed)

```sh
caddy untrust
rm -rf "$HOME/Library/Application Support/Caddy/pki"
launchctl kickstart -k "gui/$(id -u)/com.caddyserver.caddy"
caddy trust
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| `connect: connection refused` on `:2019` | Proxy not running — `bootstrap` the agent before `caddy trust`; check `~/Library/Logs/caddy.err.log` |
| `launchctl load` → `Input/output error 5` | Agent already loaded — use `kickstart -k` to restart, not a second `load`/`bootstrap` |
| `bind: permission denied` on `:80` in the log | Missing `auto_https disable_redirects` — Caddy tried to open privileged :80 for redirects |
| `ERR_CERT_AUTHORITY_INVALID` | Re-run `caddy trust`, restart browser |
| Cert ok in Brave, fails in Firefox | `brew install nss`, re-run `caddy trust` |
| Works in Brave, `curl` can't resolve | Missing `/etc/hosts` entry — `devproxy add` writes it |
| `502 Bad Gateway` | Upstream down, port drifted, or IPv4/IPv6 mismatch — `lsof -nP -iTCP:PORT` (is it on `[::1]` not `127.0.0.1`?); the generated `localhost` upstream handles both |
| `400 Bad Request` on `http://host:8443` | Plain HTTP to a TLS port — use `https://` |
| App 400s its own POSTs / API calls behind the proxy | Upstream enforces an `Origin`/`Host` allowlist (anti-CSRF / DNS-rebinding). Rewrite the origin **only** for the trusted proxy origin — see below |

### Upstreams that enforce an Origin/Host allowlist

Some local servers (the DuckDB UI is one) reject POSTs whose `Origin`/`Host`
aren't `localhost`, as an anti-CSRF / anti-DNS-rebinding guard. Behind the proxy
the origin differs, so those requests 400 and the app breaks. Rewrite the origin
to what the upstream expects — but **conditionally**, matched on the incoming
`Origin` (which web content cannot forge), so a malicious page hitting your proxy
is passed through unrewritten and the upstream's own guard still rejects it. A
blanket rewrite would defeat that guard. Example (`sites.d/<name>.caddy`):

```caddyfile
name.localhost:8443 {
	import dev
	@fromui header Origin https://name.localhost:8443
	handle @fromui {
		reverse_proxy localhost:PORT {
			header_up Host localhost:PORT
			header_up Origin http://localhost:PORT
			header_up Referer http://localhost:PORT/
			flush_interval -1        # if it streams (SSE)
		}
	}
	handle {
		reverse_proxy localhost:PORT
	}
}
```
| Next HMR disconnects | Add the hostname to `allowedDevOrigins` |
| Everything 502s after an edit | Bad reload — `caddy validate` first, always |
