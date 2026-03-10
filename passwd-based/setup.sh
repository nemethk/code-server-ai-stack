#!/usr/bin/env bash
# setup.sh — first-run helper for webai (web VSCode + AI CLIs)
# Generates a random password, populates .env, builds images, and starts the stack.
#
# Usage:
#   ./setup.sh           — interactive first-run setup
#   ./setup.sh --reset   — recreate .env from scratch (keeps existing containers)
#   ./setup.sh --rebuild — rebuild Docker images without cache, then start

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
ENV_EXAMPLE="${SCRIPT_DIR}/.env.example"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[setup]${NC} $*"; }
success() { echo -e "${GREEN}[setup]${NC} $*"; }
warn()    { echo -e "${YELLOW}[setup]${NC} $*"; }
error()   { echo -e "${RED}[setup]${NC} $*" >&2; exit 1; }

# ── Dependency check ─────────────────────────────────────────────────────────
check_deps() {
    local missing=()
    command -v docker  &>/dev/null || missing+=("docker")
    command -v openssl &>/dev/null || missing+=("openssl")
    docker compose version &>/dev/null || missing+=("docker compose (v2 plugin)")
    [ ${#missing[@]} -eq 0 ] || error "Missing required tools: ${missing[*]}"
}

# ── Helpers ───────────────────────────────────────────────────────────────────
generate_password() {
    openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 24
}

set_env() {
    local key="$1" val="$2"
    if grep -q "^${key}=" "${ENV_FILE}" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${val}|" "${ENV_FILE}"
    else
        echo "${key}=${val}" >> "${ENV_FILE}"
    fi
}

get_env() {
    grep -E "^${1}=" "${ENV_FILE}" 2>/dev/null | cut -d= -f2- || true
}

prompt_key() {
    local key="$1" label="$2" val
    val=$(get_env "${key}")
    if [ -z "${val}" ]; then
        read -rp "  ${label} (Enter to skip): " val
        if [ -n "${val}" ]; then set_env "${key}" "${val}" && success "  ${key} saved"; fi
    else
        info "  ${key} already set"
    fi
}

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
    local reset=false rebuild=false
    for arg in "$@"; do
        [[ "$arg" == "--reset"   ]] && reset=true
        [[ "$arg" == "--rebuild" ]] && rebuild=true
    done

    echo ""
    info "webai — web VSCode + AI CLI setup"
    echo ""

    check_deps

    # Create .env from example if missing or --reset
    if [ ! -f "${ENV_FILE}" ] || [ "$reset" = true ]; then
        [ -f "${ENV_EXAMPLE}" ] || error ".env.example not found"
        cp "${ENV_EXAMPLE}" "${ENV_FILE}"
        success "Created .env from .env.example"
    else
        info ".env exists (use --reset to recreate)"
    fi

    # Generate password if not set
    local pass
    pass=$(get_env "CODE_SERVER_PASSWORD")
    if [ -z "${pass}" ]; then
        pass=$(generate_password)
        set_env "CODE_SERVER_PASSWORD" "${pass}"
        echo ""
        success "Generated CODE_SERVER_PASSWORD: ${pass}"
        warn "Save this password — it is stored in .env"
        echo ""

        # Try argon2 hash (optional, requires node on host)
        if command -v npx &>/dev/null; then
            info "Generating argon2 HASHED_PASSWORD..."
            local hash
            hash=$(echo -n "${pass}" | npx --yes argon2-cli -e 2>/dev/null || true)
            if [ -n "${hash}" ]; then
                # Escape $ for docker-compose
                set_env "HASHED_PASSWORD" "${hash//\$/\$\$}"
                success "HASHED_PASSWORD set (argon2, takes precedence over plain-text)"
            else
                warn "argon2-cli not available — using plain-text PASSWORD"
            fi
        else
            warn "npx not found — using plain-text PASSWORD (install node on host for argon2 hashing)"
        fi
    fi

    # Prompt for API keys
    echo ""
    info "API keys (press Enter to skip and set manually in .env later):"
    prompt_key "ANTHROPIC_API_KEY" "Anthropic API key (Claude)"
    prompt_key "OPENAI_API_KEY"    "OpenAI API key (Codex)"
    prompt_key "GEMINI_API_KEY"    "Google API key (Gemini)"

    # Optional: Claude config mount
    echo ""
    local claude_dir
    claude_dir=$(get_env "CLAUDE_CONFIG_DIR")
    if [ -z "${claude_dir}" ]; then
        read -rp "Mount ~/.claude for Claude auth persistence? [y/N]: " yn
        if [[ "${yn}" =~ ^[Yy]$ ]]; then
            set_env "CLAUDE_CONFIG_DIR" "${HOME}/.claude"
            mkdir -p "${HOME}/.claude"
            success "CLAUDE_CONFIG_DIR set to ${HOME}/.claude"
            # Uncomment the volume mount in compose
            sed -i 's|# - \${CLAUDE_CONFIG_DIR.*|- ${CLAUDE_CONFIG_DIR}:/home/coder/.claude:rw|' \
                "${SCRIPT_DIR}/docker-compose.yml" 2>/dev/null || true
        fi
    fi

    # Optional: Gemini config mount
    echo ""
    local gemini_dir
    gemini_dir=$(get_env "GEMINI_CONFIG_DIR")
    if [ -z "${gemini_dir}" ]; then
        read -rp "Mount ~/.gemini for Gemini auth persistence? [y/N]: " yn
        if [[ "${yn}" =~ ^[Yy]$ ]]; then
            set_env "GEMINI_CONFIG_DIR" "${HOME}/.gemini"
            mkdir -p "${HOME}/.gemini"
            success "GEMINI_CONFIG_DIR set to ${HOME}/.gemini"
            # Uncomment the volume mount in compose
            sed -i 's|# - \${GEMINI_CONFIG_DIR.*|- ${GEMINI_CONFIG_DIR}:/home/coder/.gemini:rw|' \
                "${SCRIPT_DIR}/docker-compose.yml" 2>/dev/null || true
        fi
    fi

    # Optional: Codex config mount
    echo ""
    local codex_dir
    codex_dir=$(get_env "CODEX_CONFIG_DIR")
    if [ -z "${codex_dir}" ]; then
        read -rp "Mount ~/.codex for Codex auth persistence? [y/N]: " yn
        if [[ "${yn}" =~ ^[Yy]$ ]]; then
            set_env "CODEX_CONFIG_DIR" "${HOME}/.codex"
            mkdir -p "${HOME}/.codex"
            success "CODEX_CONFIG_DIR set to ${HOME}/.codex"
            info "  Inside the container, run: codex login --device-auth"
            # Uncomment the volume mount in compose
            sed -i 's|# - \${CODEX_CONFIG_DIR.*|- ${CODEX_CONFIG_DIR}:/home/coder/.codex:rw|' \
                "${SCRIPT_DIR}/docker-compose.yml" 2>/dev/null || true
        fi
    fi

    echo ""
    # Build
    if [ "$rebuild" = true ]; then
        info "Rebuilding images (no cache)..."
        docker compose --env-file "${ENV_FILE}" -f "${SCRIPT_DIR}/docker-compose.yml" build --no-cache
    else
        info "Building images..."
        docker compose --env-file "${ENV_FILE}" -f "${SCRIPT_DIR}/docker-compose.yml" build
    fi

    # Start
    info "Starting stack..."
    docker compose --env-file "${ENV_FILE}" -f "${SCRIPT_DIR}/docker-compose.yml" up -d

    echo ""
    local domain
    domain=$(get_env "DOMAIN"); domain="${domain:-localhost}"

    success "Stack is up!"
    echo ""
    echo -e "  URL:       ${GREEN}https://${domain}${NC}"
    echo -e "  Password:  stored in .env as CODE_SERVER_PASSWORD"
    echo ""
    echo -e "  Browser will show a TLS warning for the self-signed cert."
    echo -e "  Click 'Advanced' → 'Proceed to ${domain}' to continue."
    echo ""
    echo -e "  Logs:      ${CYAN}docker compose logs -f${NC}"
    echo -e "  Stop:      ${CYAN}docker compose down${NC}"
    echo -e "  Rebuild:   ${CYAN}./setup.sh --rebuild${NC}"
    echo ""
}

main "$@"
