#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║          🤖 Tau Agent — One-Line Ultimate Installer          ║
# ║                                                              ║
# ║  Usage:                                                      ║
# ║    curl -fsSL https://raw.githubusercontent.com/             ║
# ║      shalevamin/Tau_agent/main/install.sh | bash             ║
# ║                                                              ║
# ║  Or locally:                                                 ║
# ║    bash install.sh                                           ║
# ╚══════════════════════════════════════════════════════════════╝
set -euo pipefail

# ── Colors ────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

banner() {
  echo ""
  echo -e "${MAGENTA}${BOLD}"
  echo "  ╔════════════════════════════════════════════════╗"
  echo "  ║                                                ║"
  echo "  ║        🤖  TAU AGENT  — Ultimate Setup         ║"
  echo "  ║        The AI Agent That Does Everything        ║"
  echo "  ║                                                ║"
  echo "  ╚════════════════════════════════════════════════╝"
  echo -e "${NC}"
}

step() {
  echo ""
  echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${CYAN}${BOLD}  ▸ $1${NC}"
  echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

success() {
  echo -e "${GREEN}  ✅ $1${NC}"
}

warn() {
  echo -e "${YELLOW}  ⚠️  $1${NC}"
}

fail() {
  echo -e "${RED}  ❌ $1${NC}"
}

info() {
  echo -e "${BLUE}  ℹ️  $1${NC}"
}

# ── Pre-flight checks ────────────────────────────────────────
banner

INSTALL_DIR="${TAU_INSTALL_DIR:-$HOME/Tau_agent}"
MANAGED_DIR="$HOME/.openclaw"
BIN_DIR="$MANAGED_DIR/bin"
SKILLS_DIR="$MANAGED_DIR/skills"

step "Step 1/9 — Checking system requirements"

# Check macOS
if [[ "$(uname)" != "Darwin" ]]; then
  fail "Tau Agent requires macOS. Detected: $(uname)"
  exit 1
fi
success "macOS detected ($(sw_vers -productVersion))"

# Check/install Homebrew
if ! command -v brew &>/dev/null; then
  info "Homebrew not found. Installing..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Add brew to PATH for this session
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -f /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
  success "Homebrew installed"
else
  success "Homebrew found ($(brew --version | head -1))"
fi

# Check/install Node.js
if ! command -v node &>/dev/null; then
  info "Node.js not found. Installing via Homebrew..."
  brew install node
  success "Node.js installed ($(node --version))"
else
  NODE_MAJOR=$(node --version | sed 's/v//' | cut -d. -f1)
  if [[ "$NODE_MAJOR" -lt 20 ]]; then
    warn "Node.js $(node --version) found but v20+ recommended. Upgrading..."
    brew upgrade node || brew install node
  fi
  success "Node.js found ($(node --version))"
fi

# Check/install pnpm
if ! command -v pnpm &>/dev/null; then
  info "pnpm not found. Installing..."
  npm install -g pnpm
  success "pnpm installed ($(pnpm --version))"
else
  success "pnpm found ($(pnpm --version))"
fi

# Check/install Python
PYTHON_CMD=""
for candidate in python3 /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3; do
  if command -v "$candidate" &>/dev/null; then
    PYTHON_CMD="$candidate"
    break
  fi
done
if [[ -z "$PYTHON_CMD" ]]; then
  info "Python 3 not found. Installing via Homebrew..."
  brew install python@3.12
  PYTHON_CMD="python3"
fi
success "Python found ($($PYTHON_CMD --version))"

# Check/install Git
if ! command -v git &>/dev/null; then
  info "Git not found. Installing via Homebrew..."
  brew install git
fi
success "Git found ($(git --version | head -1))"

# ── API Key ───────────────────────────────────────────────────
step "Step 2/9 — OpenAI API Key"

OPENAI_KEY="${OPENAI_API_KEY:-}"

if [[ -z "$OPENAI_KEY" ]]; then
  echo ""
  echo -e "${BOLD}  Tau Agent runs on OpenAI (GPT-5.4). You need an API key.${NC}"
  echo -e "  Get one at: ${BLUE}https://platform.openai.com/api-keys${NC}"
  echo ""
  read -rp "  🔑 Enter your OpenAI API Key (sk-...): " OPENAI_KEY
  echo ""
fi

if [[ -z "$OPENAI_KEY" ]]; then
  warn "No API key provided. You can set it later in ~/.zshrc"
  warn "  export OPENAI_API_KEY=\"sk-...\""
else
  success "API key received (${OPENAI_KEY:0:7}...)"
fi

# ── Clone Repository ──────────────────────────────────────────
step "Step 3/9 — Cloning Tau Agent"

if [[ -d "$INSTALL_DIR/openclaw-main" ]]; then
  info "Tau Agent already exists at $INSTALL_DIR. Pulling latest..."
  cd "$INSTALL_DIR"
  git pull --ff-only 2>/dev/null || true
  success "Updated to latest"
else
  info "Cloning to $INSTALL_DIR..."
  git clone https://github.com/shalevamin/Tau_agent.git "$INSTALL_DIR"
  success "Cloned to $INSTALL_DIR"
fi

cd "$INSTALL_DIR"

# ── Install Dependencies ─────────────────────────────────────
step "Step 4/9 — Installing Node.js dependencies"

cd "$INSTALL_DIR/openclaw-main"
pnpm install --no-frozen-lockfile 2>&1 | tail -5
success "Node.js dependencies installed"

# ── Install Toolchain ─────────────────────────────────────────
step "Step 5/9 — Installing Ultimate Toolchain (Codex, browser-use, OpenViking)"

mkdir -p "$BIN_DIR"
node scripts/install-ultimate-toolchain.mjs 2>&1 | tail -10
success "Toolchain installed to $MANAGED_DIR"

# ── Install Skills ────────────────────────────────────────────
step "Step 6/9 — Syncing 290+ Skills"

node scripts/install-ultimate-skills.mjs 2>&1 | tail -5
SKILL_COUNT=$(ls -d "$SKILLS_DIR"/*/ 2>/dev/null | wc -l | tr -d ' ')
success "$SKILL_COUNT skills installed to $SKILLS_DIR"

# ── Install Playwright ────────────────────────────────────────
step "Step 7/9 — Installing Playwright (browser automation)"

npx -y playwright install chromium 2>&1 | tail -3
success "Playwright Chromium installed"

# ── Environment Setup ─────────────────────────────────────────
step "Step 8/9 — Configuring environment"

SHELL_RC="$HOME/.zshrc"
if [[ -f "$HOME/.bashrc" ]] && [[ ! -f "$HOME/.zshrc" ]]; then
  SHELL_RC="$HOME/.bashrc"
fi

# Add PATH
if ! grep -q '\.openclaw/bin' "$SHELL_RC" 2>/dev/null; then
  echo '' >> "$SHELL_RC"
  echo '# Tau Agent — managed tools' >> "$SHELL_RC"
  echo 'export PATH="$HOME/.openclaw/bin:$PATH"' >> "$SHELL_RC"
  success "Added ~/.openclaw/bin to PATH in $SHELL_RC"
else
  success "PATH already configured"
fi

# Add API Key
if [[ -n "$OPENAI_KEY" ]]; then
  if ! grep -q 'OPENAI_API_KEY' "$SHELL_RC" 2>/dev/null; then
    echo "export OPENAI_API_KEY=\"$OPENAI_KEY\"" >> "$SHELL_RC"
    success "API key saved to $SHELL_RC"
  else
    # Update existing key
    sed -i '' "s|export OPENAI_API_KEY=.*|export OPENAI_API_KEY=\"$OPENAI_KEY\"|" "$SHELL_RC"
    success "API key updated in $SHELL_RC"
  fi
  export OPENAI_API_KEY="$OPENAI_KEY"
fi

# Source for current session
export PATH="$BIN_DIR:$PATH"

# ── macOS Permissions ─────────────────────────────────────────
step "Step 9/9 — macOS Permissions"

info "Tau Agent needs these permissions for full computer control:"
echo ""
echo -e "  ${BOLD}1. Accessibility${NC} — for mouse/keyboard control"
echo -e "  ${BOLD}2. Screen Recording${NC} — for screenshots"
echo ""
echo -e "  Opening System Settings → Privacy & Security..."
echo ""

# Try to open System Settings to the right pane
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" 2>/dev/null || \
  open "/System/Library/PreferencePanes/Security.prefPane" 2>/dev/null || \
  warn "Could not open System Settings automatically. Please grant permissions manually."

echo -e "  ${YELLOW}Please grant Accessibility and Screen Recording access to Terminal/iTerm.${NC}"
echo ""
read -rp "  Press Enter when permissions are granted (or skip)... " _

# ── Done! ─────────────────────────────────────────────────────
echo ""
echo ""
echo -e "${GREEN}${BOLD}"
echo "  ╔════════════════════════════════════════════════════════════╗"
echo "  ║                                                            ║"
echo "  ║      🎉  TAU AGENT IS READY!                               ║"
echo "  ║                                                            ║"
echo "  ╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo -e "  ${BOLD}What was installed:${NC}"
echo -e "    ✅ Tau Agent core         → $INSTALL_DIR"
echo -e "    ✅ Codex CLI              → $BIN_DIR/codex"
echo -e "    ✅ browser-use            → $BIN_DIR/browser-use"
echo -e "    ✅ $SKILL_COUNT skills              → $SKILLS_DIR"
echo -e "    ✅ Playwright (Chromium)  → managed by npx"
echo -e "    ✅ OpenAI API key         → saved in $SHELL_RC"
echo ""
echo -e "  ${BOLD}Quick Start:${NC}"
echo ""
echo -e "    ${CYAN}# Start the gateway${NC}"
echo -e "    cd $INSTALL_DIR/openclaw-main && pnpm dev"
echo ""
echo -e "    ${CYAN}# Or use Codex directly${NC}"
echo -e "    codex \"Build me something amazing\""
echo ""
echo -e "    ${CYAN}# Run a new terminal first to load PATH:${NC}"
echo -e "    source $SHELL_RC"
echo ""
echo -e "  ${BOLD}Documentation:${NC}"
echo -e "    ${BLUE}https://github.com/shalevamin/Tau_agent${NC}"
echo ""
echo -e "  ${MAGENTA}${BOLD}  Tau Agent — Because one agent should be able to do everything. 🤖${NC}"
echo ""
