# webai — Tailscale variant

VS Code in the browser with Claude, Codex, and Gemini CLIs. Authentication and secure access via [Tailscale](https://tailscale.com) — no passwords, no exposed ports, works from any device including Android tablets.

## How it works

Tailscale runs as a container alongside code-server. It joins your Tailnet and serves code-server over HTTPS using a valid Tailscale-issued certificate. Any device with the Tailscale app installed and connected to the same Tailnet can open the URL and reach VS Code directly — no VPN setup, no port forwarding on your router.

```
Android/browser (Tailscale app)
  │  WireGuard (encrypted)
  ▼
tailscale container  ──────────────────────────  Tailscale coordination servers
  │  HTTPS reverse proxy  [frontend — internal]
  ▼
code-server (VS Code, --auth none)
  │  HTTP_PROXY  [isolated — internal]
  ▼
squid (outbound filter)
  │  allowed domains only  [internet]
  ▼
AI APIs (Anthropic, OpenAI, Google)
```

## Architecture

Three Docker networks enforce isolation:

| Network    | `internal` | Connected services              |
|------------|------------|---------------------------------|
| `frontend` | yes        | tailscale ↔ code-server         |
| `isolated` | yes        | code-server ↔ squid             |
| `internet` | no         | tailscale + squid               |

Tailscale has internet access (to reach coordination servers). code-server has no direct internet — all AI API calls go through squid's domain allowlist.

## Requirements

- Docker Engine 24+ with Docker Compose v2
- A [Tailscale account](https://tailscale.com) (free tier is sufficient)
- Tailscale installed on the devices you want to access from (Android, iOS, desktop)

## Quick start

### 1. Generate a Tailscale auth key

Go to **[tailscale.com/admin/settings/keys](https://login.tailscale.com/admin/settings/keys)** and create a key with these settings:

- **Reusable**: yes
- **Ephemeral**: no (so the node stays on your Tailnet permanently)
- **Tags**: optional

Copy the key — it starts with `tskey-auth-`.

### 2. Run setup

```bash
git clone <this-repo> webai
cd webai/tailscale-based
./setup.sh
```

`setup.sh` will:
1. Prompt for your Tailscale auth key
2. Set a Tailnet hostname (default: `webai`)
3. Prompt for AI API keys
4. Build images and start the stack

### 3. Connect

Once the stack is running, check the Tailscale logs to confirm the node has joined:

```bash
docker logs webai-tailscale
```

Then open from **any device on your Tailnet**:

```
https://webai.<your-tailnet>.ts.net
```

The certificate is issued by Tailscale — no browser warning. No password prompt.

### Connecting from Android tablet

1. Install [Tailscale for Android](https://play.google.com/store/apps/details?id=com.tailscale.ipn.android)
2. Log in with the same account used when creating the auth key
3. Tap the toggle to connect
4. Open the browser and navigate to `https://webai.<your-tailnet>.ts.net`

## Usage

After opening the URL, VS Code loads immediately — no login screen. Press `` Ctrl+` `` to open a terminal.

### Claude Code

```bash
claude                                 # interactive session
claude "explain what this repo does"   # one-shot
```

Auto-authenticated if `ANTHROPIC_API_KEY` is set. Otherwise: `claude auth login`.

### OpenAI Codex

```bash
codex                                  # interactive session
codex "write tests for main.py"        # one-shot
```

Requires `OPENAI_API_KEY` in `.env`.

### Google Gemini

```bash
gemini                                 # interactive session
gemini "review this function"          # one-shot
```

Auto-authenticated if `GEMINI_API_KEY` is set. Otherwise: `gemini auth login`.

## Configuration

| Variable            | Description                                                        |
|---------------------|--------------------------------------------------------------------|
| `TS_AUTHKEY`        | Tailscale auth key (`tskey-auth-...`)                              |
| `TS_HOSTNAME`       | Node hostname on Tailnet — access via `https://<hostname>.ts.net`  |
| `ANTHROPIC_API_KEY` | Claude API key — leave blank to use `claude auth login`            |
| `OPENAI_API_KEY`    | OpenAI API key                                                     |
| `GEMINI_API_KEY`    | Gemini API key — leave blank to use `gemini auth login`            |
| `CLAUDE_CONFIG_DIR` | Host path mounted as `~/.claude` for Claude auth persistence        |

## Squid allowlist

Only these domains are reachable from code-server:

| Domain                                    | Used by                   |
|-------------------------------------------|---------------------------|
| `*.anthropic.com`                         | Claude Code CLI           |
| `*.openai.com`                            | Codex CLI                 |
| `*.googleapis.com`, `*.google.com`        | Gemini CLI + Google OAuth |
| `registry.npmjs.org`, `*.npmjs.com`       | npm, extensions           |
| `*.github.com`, `*.githubusercontent.com` | git, extensions           |
| `*.sentry.io`, `*.statsigapi.net`         | CLI telemetry             |

Tailscale's own traffic (to coordination servers) bypasses squid — Tailscale is on the `internet` network directly.

To add a domain, edit `squid/squid.conf` then:

```bash
docker compose restart squid
```

## Building containers

```bash
docker compose build              # build code-server and pull tailscale/squid images
docker compose build --no-cache   # force full rebuild
./setup.sh --rebuild              # rebuild + restart in one step
```

Two images are built locally (`code-server`). `tailscale` and `squid` use pre-built images from Docker Hub.

## Operations

```bash
docker compose logs -f                  # tail all logs
docker compose logs -f tailscale        # check Tailscale connection status
docker compose logs -f squid            # check which domains are being accessed
docker compose down                     # stop (data persists in volumes)
docker compose down -v                  # stop and delete all data
docker compose up -d                    # start
```

## Revoking access

To permanently remove access from a device or rotate the auth key:

1. Go to [tailscale.com/admin/machines](https://login.tailscale.com/admin/machines)
2. Remove the `webai` node
3. Generate a new auth key and update `.env`
4. Restart: `docker compose down && docker compose up -d`

## File structure

```
tailscale-based/
├── docker-compose.yml        # 3 services + 3-network topology
├── .env.example              # configuration template
├── .env                      # your secrets (never commit this)
├── .gitignore
├── setup.sh                  # first-run helper
├── code-server/
│   └── Dockerfile            # code-server + Node 20 + claude/codex/gemini
├── tailscale/
│   └── serve.json            # Tailscale serve: HTTPS → code-server:8080
└── squid/
    └── squid.conf            # domain allowlist
```

## Security notes

- **No exposed ports.** The only inbound path is through the Tailscale WireGuard tunnel. There is nothing listening on the host's public IP.
- **Valid TLS certificate.** Tailscale issues a certificate for `<hostname>.ts.net` from its own CA. No self-signed cert warnings.
- **Access control via Tailnet.** Only devices logged in to your Tailscale account can reach the node. Revoke access instantly from the Tailscale admin console.
- **`--auth none` on code-server.** Intentional — authentication is fully delegated to Tailscale. If you share your Tailnet with others and want an extra layer, add `PASSWORD` back to the code-server environment in `docker-compose.yml`.
- **Squid network isolation.** code-server cannot reach the internet directly; all outbound traffic is filtered by Squid's domain allowlist.
