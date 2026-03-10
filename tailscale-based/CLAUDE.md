# CLAUDE.md — tailscale-based

Project context and development guidelines for AI-assisted work on this variant.

## What this is

Browser-based VS Code (code-server) with Claude, Codex, and Gemini CLIs. Authentication and network access via Tailscale — no passwords, no exposed ports. Works from Android tablets and any other device with the Tailscale app.

## Architecture

```
Browser/Android (Tailscale app)
  │  WireGuard encrypted tunnel
  ▼
tailscale container ──── Tailscale coordination servers (internet network)
  │  HTTPS reverse proxy  [frontend — internal:true]
  ▼
code-server (--auth none, port 8080)
  │  HTTP_PROXY=http://squid:3128  [isolated — internal:true]
  ▼
squid → AI APIs only  [internet network]
```

## File map

```
docker-compose.yml          — 3 services, 3 networks, volumes
.env.example                — copy to .env before running
setup.sh                    — first-run: auth key, API keys, build + start
code-server/Dockerfile      — codercom/code-server + Node 20 + claude/codex/gemini CLIs
tailscale/serve.json        — Tailscale serve config: HTTPS :443 → code-server:8080
squid/squid.conf            — domain allowlist
```

## Services

| Service       | Image                          | Internet access          |
|---------------|--------------------------------|--------------------------|
| `tailscale`   | `tailscale/tailscale:latest`   | yes (coordination + WireGuard) |
| `code-server` | built from `code-server/`      | via squid only           |
| `squid`       | `ubuntu/squid:latest`          | yes (AI APIs only)       |

## Docker networks

| Network    | `internal` | Purpose                        |
|------------|------------|--------------------------------|
| `frontend` | true       | tailscale ↔ code-server        |
| `isolated` | true       | code-server ↔ squid            |
| `internet` | false      | tailscale + squid              |

## Environment variables

| Variable            | Required | Notes                                               |
|---------------------|----------|-----------------------------------------------------|
| `TS_AUTHKEY`        | yes      | From tailscale.com/admin/settings/keys              |
| `TS_HOSTNAME`       | no       | Tailnet node name; default `webai`                  |
| `ANTHROPIC_API_KEY` | no       | Leave blank → `claude auth login` inside terminal   |
| `OPENAI_API_KEY`    | no       | No OAuth alternative for Codex                      |
| `GEMINI_API_KEY`    | no       | Leave blank → `gemini auth login` inside terminal   |
| `CLAUDE_CONFIG_DIR` | no       | Host path → `/home/coder/.claude:rw` volume mount   |

## Tailscale serve config (`tailscale/serve.json`)

```json
{
  "TCP": { "443": { "HTTPS": true } },
  "Web": {
    "${TS_CERT_DOMAIN}:443": {
      "Handlers": { "/": { "Proxy": "http://code-server:8080" } }
    }
  }
}
```

`${TS_CERT_DOMAIN}` is resolved by the Tailscale container to the node's FQDN (e.g. `webai.tail12345.ts.net`). Do not replace it with a literal hostname.

## Tailscale container requirements

- `/dev/net/tun` device mount — required for kernel-mode WireGuard
- `NET_ADMIN` capability — required to manage the WireGuard interface
- `SYS_MODULE` capability — required to load kernel modules (remove if unavailable in your environment)
- `tailscale_state` volume — persists node identity so the Tailscale node doesn't re-authenticate on restart

## code-server runs with `--auth none`

Authentication is fully delegated to Tailscale. Only devices on your Tailnet can reach code-server. If you share a Tailnet with others and need an extra layer, add `PASSWORD` back to the code-server environment in `docker-compose.yml`.

## AI CLI packages

| Binary   | npm package                 | Auth options                               |
|----------|-----------------------------|--------------------------------------------|
| `claude` | `@anthropic-ai/claude-code` | `ANTHROPIC_API_KEY` or `claude auth login` |
| `codex`  | `@openai/codex`             | `OPENAI_API_KEY` only                      |
| `gemini` | `@google/gemini-cli`        | `GEMINI_API_KEY` or `gemini auth login`    |

## Squid allowlist domains

`.anthropic.com`, `.openai.com`, `.googleapis.com`, `.google.com`, `registry.npmjs.org`, `.npmjs.com`, `.github.com`, `.githubusercontent.com`, `.sentry.io`, `.statsigapi.net`

After editing `squid/squid.conf`: `docker compose restart squid`

**Squid ACL rule:** never add both `.foo.com` and `api.foo.com` — Squid refuses to start.

## Common commands

```bash
./setup.sh                              # first-run setup
./setup.sh --rebuild                    # rebuild images + restart
docker compose up -d                    # start
docker compose down                     # stop
docker compose logs -f tailscale        # check Tailscale join status
docker compose logs -f                  # all logs
docker compose restart squid            # reload squid config
```

## Revoking access

Remove the node from tailscale.com/admin/machines, generate a new auth key, update `.env`, then `docker compose down && docker compose up -d`.

## What NOT to change without understanding the impact

- `internal: true` on `frontend` and `isolated` — removing this bypasses network isolation
- `NO_PROXY=squid,tailscale,...` — removing this causes proxy loops
- `cache deny all` in squid — enabling caching breaks streaming AI responses
- `${TS_CERT_DOMAIN}` in serve.json — do not hardcode a hostname here
- `tailscale_state` volume — deleting this forces Tailscale re-authentication
