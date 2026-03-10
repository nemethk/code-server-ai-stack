#!/usr/bin/env bash
# setup.sh — first-run helper for webai tailscale-based setup
# Configures Tailscale auth key, populates .env, builds images, and starts the stack.
#
# Usage:
#   ./setup.sh           — interactive first-run setup
#   ./setup.sh --reset   — recreate .env from scratch
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

check_deps() {
    local missing=()
    command -v docker &>/dev/null || missing+=("docker")
    docker compose version &>/dev/null || missing+=("docker compose (v2 plugin)")
    [ ${#missing[@]} -eq 0 ] || error "Missing required tools: ${missing[*]}"
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

prompt_api_key() {
    local key="$1" label="$2" val
    val=$(get_env "${key}")
    if [ -z "${val}" ]; then
        read -rp "  ${label} (Enter to skip): " val
        [ -n "${val}" ] && set_env "${key}" "${val}" && success "  ${key} saved"
    else
        info "  ${key} already set"
    fi
}

setup_tailscale() {
    local current_key
    current_key=$(get_env "TS_AUTHKEY")

    if [[ -n "${current_key}" && "${current_key}" == tskey-* ]]; then
        info "TS_AUTHKEY already set"
        return
    fi

    echo ""
    info "Tailscale auth key setup"
    echo ""
    echo "  Generate a reusable, non-ephemeral auth key at:"
    echo -e "  ${CYAN}https://login.tailscale.com/admin/settings/keys${NC}"
    echo ""
    echo "  Settings: Reusable ✓  Ephemeral ✗  (so the node persists on your Tailnet)"
    echo ""
    read -rp "  Paste your auth key (tskey-auth-...): " input_key

    if [[ -z "${input_key}" ]]; then
        error "TS_AUTHKEY is required. Generate one at https://login.tailscale.com/admin/settings/keys"
    fi
    if [[ "${input_key}" != tskey-* ]]; then
        warn "Key does not look like a Tailscale auth key (expected 'tskey-auth-...')"
        read -rp "  Continue anyway? [y/N]: " yn
        [[ "${yn}" =~ ^[Yy]$ ]] || error "Aborted."
    fi

    set_env "TS_AUTHKEY" "${input_key}"
    success "TS_AUTHKEY saved"
}

main() {
    local reset=false rebuild=false
    for arg in "$@"; do
        [[ "$arg" == "--reset"   ]] && reset=true
        [[ "$arg" == "--rebuild" ]] && rebuild=true
    done

    echo ""
    info "webai (Tailscale) — web VSCode + AI CLI setup"
    echo ""

    check_deps

    if [ ! -f "${ENV_FILE}" ] || [ "$reset" = true ]; then
        [ -f "${ENV_EXAMPLE}" ] || error ".env.example not found"
        cp "${ENV_EXAMPLE}" "${ENV_FILE}"
        success "Created .env from .env.example"
    else
        info ".env exists (use --reset to recreate)"
    fi

    # Tailscale auth key
    setup_tailscale

    # Hostname (optional)
    local current_hostname
    current_hostname=$(get_env "TS_HOSTNAME")
    if [ -z "${current_hostname}" ]; then
        read -rp "  Tailnet hostname [webai]: " input_hostname
        set_env "TS_HOSTNAME" "${input_hostname:-webai}"
    else
        info "TS_HOSTNAME: ${current_hostname}"
    fi

    # AI API keys
    echo ""
    info "AI API keys (press Enter to skip — you can authenticate interactively later):"
    prompt_api_key "ANTHROPIC_API_KEY" "Anthropic API key (Claude)"
    prompt_api_key "OPENAI_API_KEY"    "OpenAI API key (Codex)"
    prompt_api_key "GEMINI_API_KEY"    "Google API key (Gemini)"

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
        fi
    fi

    echo ""
    if [ "$rebuild" = true ]; then
        info "Rebuilding images (no cache)..."
        docker compose --env-file "${ENV_FILE}" -f "${SCRIPT_DIR}/docker-compose.yml" build --no-cache
    else
        info "Building images..."
        docker compose --env-file "${ENV_FILE}" -f "${SCRIPT_DIR}/docker-compose.yml" build
    fi

    info "Starting stack..."
    docker compose --env-file "${ENV_FILE}" -f "${SCRIPT_DIR}/docker-compose.yml" up -d

    local hostname
    hostname=$(get_env "TS_HOSTNAME"); hostname="${hostname:-webai}"

    echo ""
    success "Stack is up!"
    echo ""
    echo -e "  Waiting for Tailscale to join the Tailnet..."
    echo -e "  Once connected, open on any Tailnet device:"
    echo -e "  ${GREEN}https://${hostname}.<your-tailnet>.ts.net${NC}"
    echo ""
    echo -e "  Check Tailscale status:  ${CYAN}docker logs webai-tailscale${NC}"
    echo -e "  Logs:                    ${CYAN}docker compose logs -f${NC}"
    echo -e "  Stop:                    ${CYAN}docker compose down${NC}"
    echo -e "  Rebuild:                 ${CYAN}./setup.sh --rebuild${NC}"
    echo ""
}

main "$@"
