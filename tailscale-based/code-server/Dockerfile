FROM codercom/code-server:latest

# Switch to root to perform system-level installs
USER root

# ── System dependencies ───────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    gnupg \
    ca-certificates \
    git \
    && rm -rf /var/lib/apt/lists/*

# ── Node.js 20 LTS via NodeSource ────────────────────────────────────────────
# codercom/code-server bundles its own node internally; we install a
# system-wide Node 20 so the AI CLIs use a proper, current version.
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# ── Global AI CLI tools ───────────────────────────────────────────────────────
# Installed as root → binaries land in /usr/local/bin, on PATH for all users.
# Rebuild the image to pick up new CLI versions: docker compose build --no-cache
RUN npm install --global --unsafe-perm \
    @anthropic-ai/claude-code \
    @openai/codex \
    @google/gemini-cli

# ── Verify binaries are available ────────────────────────────────────────────
# || true prevents build failure if a package has no --version flag yet
RUN claude --version || true
RUN codex  --version || true
RUN gemini --version || true

# ── Drop back to unprivileged runtime user ────────────────────────────────────
USER coder
WORKDIR /home/coder
