# webai

VS Code in the browser with Claude, Codex, and Gemini CLIs — secured with HTTPS, password authentication, and Squid proxy network isolation.

## What it does

Runs [code-server](https://github.com/coder/code-server) (VS Code in the browser) inside Docker with three AI coding assistants available in the integrated terminal:

| Command  | CLI                      | API key needed       |
|----------|--------------------------|----------------------|
| `claude` | Anthropic Claude Code    | `ANTHROPIC_API_KEY`  |
| `codex`  | OpenAI Codex CLI         | `OPENAI_API_KEY`     |
| `gemini` | Google Gemini CLI        | `GEMINI_API_KEY`     |

## Architecture

```
Browser
  │  HTTPS :443
  ▼
nginx (TLS termination)
  │  HTTP :8080  [frontend network — internal]
  ▼
code-server (VS Code)
  │  HTTP_PROXY :3128  [isolated network — internal]
  ▼
squid (outbound filter)
  │  allowed domains only  [internet network]
  ▼
Internet
```

Three Docker networks enforce isolation at the kernel level:

| Network    | `internal` | Connected services         |
|------------|------------|----------------------------|
| `frontend` | yes        | nginx ↔ code-server        |
| `isolated` | yes        | code-server ↔ squid        |
| `internet` | no         | squid only                 |

**Only squid has a route to the internet.** All outbound traffic from the AI CLIs travels through `HTTP_PROXY=http://squid:3128`. Squid enforces a domain allowlist and blocks everything else.

## Requirements

- Docker Engine 24+
- Docker Compose v2 (`docker compose version`)
- `openssl` (for password generation in `setup.sh`)

## Quick start

```bash
git clone <this-repo> webai
cd webai
./setup.sh
```

`setup.sh` will:
1. Copy `.env.example` → `.env`
2. Generate a random 24-character password
3. Generate an argon2 password hash (if `npx` is on your PATH)
4. Prompt for API keys
5. Optionally mount `~/.claude` for Claude auth persistence
6. Build images and start the stack

Then open **`https://localhost`** in your browser. You will see a TLS warning for the self-signed certificate — click **Advanced → Proceed** to continue.

The password is printed once during setup and stored in `.env`.

## Usage

After `./setup.sh` completes, open **`https://localhost`** in your browser and log in with the generated password.

### Open a terminal

Inside the web VS Code, press `` Ctrl+` `` (backtick) or go to **Terminal → New Terminal**. The three AI CLIs are on the PATH and API keys are pre-loaded in the environment.

### Claude Code

```bash
claude
```

Starts an interactive session. Claude can read, write, and run code in your workspace. Type your task in natural language, e.g. `"add error handling to main.py"`.

```bash
claude "explain what this repo does"    # one-shot prompt
claude --help                           # all options
```

First run: if `ANTHROPIC_API_KEY` is set in `.env`, authentication is automatic. Otherwise run `claude auth login`.

### OpenAI Codex

```bash
codex
```

Interactive agentic coding session backed by OpenAI models. Reads your files and executes tasks.

```bash
codex "write unit tests for utils.js"   # one-shot prompt
codex --help
```

Requires `OPENAI_API_KEY` in `.env`.

### Google Gemini

```bash
gemini
```

Interactive session with Gemini. On first run it may prompt for Google account login — the OAuth flow opens a URL; paste it into your browser tab.

```bash
gemini "review this function for bugs"  # one-shot prompt
gemini --help
```

Requires `GEMINI_API_KEY` in `.env`, or use `gemini auth login` for Google account OAuth.

### Your workspace

Files are persisted in the `code_server_data` Docker volume at `/home/coder` inside the container. Open a folder with **File → Open Folder** and point it to `/home/coder/workspace` (or any subdirectory). Changes survive container restarts.

## Authentication

Each CLI supports two authentication modes.

| CLI | API key | OAuth login | Free tier via OAuth |
|-----|---------|-------------|---------------------|
| `claude` | `ANTHROPIC_API_KEY` | `claude auth login` | Yes (Claude.ai account) |
| `gemini` | `GEMINI_API_KEY` | `gemini auth login` | Yes (Google account) |
| `codex` | `OPENAI_API_KEY` | not supported | No |

### OAuth login (no API key needed)

Open a terminal in the web VS Code and run the login command. It prints a URL — open that URL in a new browser tab, authenticate, then return to the terminal.

**Claude:**
```bash
claude auth login
# Authenticate with your Claude.ai account
# Token saved to ~/.claude/
```

**Gemini:**
```bash
gemini auth login
# Authenticate with your Google account
# Token saved to ~/.config/gemini/
```

To use OAuth instead of an API key, leave the key blank in `.env`:

```bash
ANTHROPIC_API_KEY=   # leave empty, run claude auth login instead
GEMINI_API_KEY=      # leave empty, run gemini auth login instead
```

### Persist OAuth tokens across container restarts

Tokens are stored inside the container and lost when it is removed. Mount host directories to persist them.

For Claude, set `CLAUDE_CONFIG_DIR` in `.env`:

```bash
CLAUDE_CONFIG_DIR=~/.claude
```

For Gemini, add a volume to `docker-compose.yml` under the `code-server` service:

```yaml
volumes:
  - code_server_data:/home/coder
  - ${CLAUDE_CONFIG_DIR:-/dev/null}:/home/coder/.claude:rw
  - gemini_config:/home/coder/.config/gemini   # add this line
```

And declare the volume at the top level:

```yaml
volumes:
  gemini_config:
```

### Squid and OAuth flows

The OAuth redirect domains are already on the Squid allowlist:
- Claude OAuth → covered by `*.anthropic.com`
- Google OAuth → covered by `*.google.com` and `*.googleapis.com`

No changes to `squid/squid.conf` are needed.

## Configuration

Copy `.env.example` to `.env` and edit:

```bash
cp .env.example .env
$EDITOR .env
```

| Variable               | Description                                                  |
|------------------------|--------------------------------------------------------------|
| `CODE_SERVER_PASSWORD` | Plain-text password (auto-generated by `setup.sh`)           |
| `HASHED_PASSWORD`      | Argon2 hash — takes precedence over `CODE_SERVER_PASSWORD`   |
| `DOMAIN`               | Hostname/IP for the self-signed cert (`localhost` by default) |
| `ANTHROPIC_API_KEY`    | Claude Code API key                                          |
| `OPENAI_API_KEY`       | Codex API key                                                |
| `GEMINI_API_KEY`       | Gemini API key                                               |
| `CLAUDE_CONFIG_DIR`    | Optional: host path to mount as `~/.claude` (auth persistence)|

### Using a LAN IP or hostname

Set `DOMAIN` to your machine's LAN address so the cert is valid on other devices:

```bash
DOMAIN=192.168.1.100   # or: DOMAIN=mydev.local
```

Then regenerate the certificate:

```bash
docker volume rm webai_nginx_certs
docker compose up -d nginx
```

## Squid allowlist

Only the following domains are reachable from the code-server container:

| Domain                              | Used by                        |
|-------------------------------------|--------------------------------|
| `*.anthropic.com`                   | Claude Code CLI                |
| `*.openai.com`                      | Codex CLI                      |
| `*.googleapis.com`, `*.google.com`  | Gemini CLI + Google OAuth      |
| `registry.npmjs.org`, `*.npmjs.com` | npm installs, extensions       |
| `*.github.com`, `*.githubusercontent.com` | git, extension sources   |
| `*.sentry.io`, `*.statsigapi.net`   | CLI telemetry                  |

Edit `squid/squid.conf` to add more domains, then restart squid:

```bash
docker compose restart squid
```

## Building containers

Two images are built locally (nginx and code-server). Squid uses the `ubuntu/squid` image pulled from Docker Hub and is not built.

### Build all images

```bash
docker compose build
```

### Build a single image

```bash
docker compose build code-server
docker compose build nginx
```

### Build without cache

Use this after updating a CLI version or changing a `Dockerfile`:

```bash
docker compose build --no-cache
# or via the setup script:
./setup.sh --rebuild
```

### Build and start in one step

```bash
docker compose up -d --build
```

### What each build does

**`code-server`** (`code-server/Dockerfile`):
1. Starts from `codercom/code-server:latest`
2. Installs Node.js 20 LTS via NodeSource
3. Installs the three AI CLIs globally: `@anthropic-ai/claude-code`, `@openai/codex`, `@google/gemini-cli`

**`nginx`** (`nginx/Dockerfile`):
1. Starts from `nginx:alpine`
2. Adds `openssl` for self-signed certificate generation
3. Copies `nginx.conf` and `entrypoint.sh` into the image

The self-signed TLS certificate is **not** baked into the image — it is generated on the first container start and stored in the `nginx_certs` Docker volume so it survives rebuilds.

### Pull the squid image

Squid is not built locally. Pull it explicitly if you want to cache it before running:

```bash
docker compose pull squid
```

### Check image sizes after build

```bash
docker images | grep webai
```

## Operations

```bash
# View live logs from all services
docker compose logs -f

# View logs from one service
docker compose logs -f code-server
docker compose logs -f squid

# Stop the stack (data persists in volumes)
docker compose down

# Stop and remove all data
docker compose down -v

# Rebuild images after Dockerfile changes
./setup.sh --rebuild
# or:
docker compose build --no-cache && docker compose up -d

# Regenerate the TLS certificate
docker volume rm webai_nginx_certs && docker compose up -d nginx
```

## Verify network isolation

After the stack starts, confirm that code-server cannot reach the internet directly:

```bash
# Should FAIL — no direct internet route from code-server
docker exec webai-code-server curl --noproxy '*' -sf --max-time 5 https://example.com
echo "Exit code (expect non-zero): $?"

# Should SUCCEED — routed through squid (allowed domain)
docker exec webai-code-server curl -sf --max-time 10 https://api.anthropic.com
echo "Exit code (expect 0 or 401): $?"

# Should FAIL — squid blocks non-allowlisted domains
docker exec webai-code-server curl -sf --max-time 5 https://example.com
echo "Exit code (expect non-zero): $?"
```

## File structure

```
webai/
├── docker-compose.yml        # service definitions + 3-network topology
├── .env.example              # configuration template
├── .env                      # your secrets (never commit this)
├── .gitignore
├── setup.sh                  # first-run helper
├── code-server/
│   └── Dockerfile            # code-server + Node 20 + claude/codex/gemini
├── nginx/
│   ├── Dockerfile            # nginx:alpine + openssl
│   ├── nginx.conf            # HTTPS, WebSocket proxy, security headers
│   └── entrypoint.sh         # generates self-signed cert on first start
└── squid/
    └── squid.conf            # domain allowlist, cache disabled, logging
```

## Security notes

- **HTTPS only.** nginx redirects all HTTP traffic to HTTPS. The self-signed cert is generated with a SubjectAltName (required by Chrome 58+) and stored in a named Docker volume so it persists across restarts.
- **Password hashing.** When `npx` is available on the host, `setup.sh` generates an argon2 hash stored as `HASHED_PASSWORD`. code-server uses this in preference to the plain-text `PASSWORD`.
- **No direct internet from code-server.** The `frontend` and `isolated` Docker networks have `internal: true`, which removes the default gateway at the kernel level — not just a firewall rule. Outbound connections that bypass the proxy will fail at the network layer.
- **No caching in squid.** `cache deny all` is set so streaming API responses (Claude, Codex, Gemini) are never cached or replayed.
- **`.env` is gitignored.** API keys and the password never leave your machine via version control.
