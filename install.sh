#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║          🤖 Tau Agent — Ultimate Onboarding Installer        ║
# ║                                                              ║
# ║  Usage:                                                      ║
# ║    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent  ║
# ║      .com/shalevamin/Tau_agent/main/install.sh)"             ║
# ╚══════════════════════════════════════════════════════════════╝
set -eo pipefail

# ── TTY handling ──────────────────────────────────────────────
# When run via 'bash -c "$(curl ...)"' stdin is the terminal.
# When run via 'curl ... | bash' stdin is the pipe — we must
# open /dev/tty explicitly for interactive reads.
if [[ -t 0 ]]; then
  # stdin is a terminal — reads work normally
  TTY_FD=0
else
  # stdin is a pipe — open /dev/tty on fd 3
  exec 3</dev/tty
  TTY_FD=3
fi

# Wrapper that reads from the correct fd
prompt_read() {
  # Usage: prompt_read VARNAME "prompt text"
  local varname="$1"
  shift
  local prompt="$*"
  if [[ "$TTY_FD" -eq 0 ]]; then
    read -rp "$prompt" "$varname"
  else
    read -rp "$prompt" "$varname" <&3
  fi
}
# ── Colors & Formatting ──────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

INSTALL_DIR="${TAU_INSTALL_DIR:-$HOME/Tau_agent}"
MANAGED_DIR="$HOME/.openclaw"
BIN_DIR="$MANAGED_DIR/bin"
SKILLS_DIR="$MANAGED_DIR/skills"

banner() {
  clear
  echo ""
  echo -e "${MAGENTA}${BOLD}"
  echo "  ╔════════════════════════════════════════════════════════════╗"
  echo "  ║                                                            ║"
  echo "  ║            🤖  TAU AGENT  — Ultimate AI Agent              ║"
  echo "  ║                                                            ║"
  echo "  ║      Full Computer Control · Browser Automation            ║"
  echo "  ║      Agent Orchestration · 290+ Skills                     ║"
  echo "  ║                                                            ║"
  echo "  ╚════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
}

phase() {
  echo ""
  echo -e "${MAGENTA}${BOLD}  ╭──────────────────────────────────────────────────────────╮${NC}"
  echo -e "${MAGENTA}${BOLD}  │  $1${NC}"
  echo -e "${MAGENTA}${BOLD}  ╰──────────────────────────────────────────────────────────╯${NC}"
  echo ""
}

step() {
  echo -e "${CYAN}${BOLD}  ▸ $1${NC}"
}

ok() {
  echo -e "${GREEN}    ✅ $1${NC}"
}

skip() {
  echo -e "${BLUE}    ⏭️  $1${NC}"
}

warn() {
  echo -e "${YELLOW}    ⚠️  $1${NC}"
}

fail() {
  echo -e "${RED}    ❌ $1${NC}"
}

info() {
  echo -e "${DIM}    ℹ️  $1${NC}"
}

divider() {
  echo -e "${DIM}  ──────────────────────────────────────────────────────────${NC}"
}

press_enter() {
  echo ""
  prompt_read _ "  $(echo -e "${DIM}")Press Enter to continue...$(echo -e "${NC}") "
}

# ══════════════════════════════════════════════════════════════
# PHASE 0 — DANGER WARNING & CONSENT
# ══════════════════════════════════════════════════════════════

banner

echo -e "${RED}${BOLD}"
echo "  ╔════════════════════════════════════════════════════════════╗"
echo "  ║                                                            ║"
echo "  ║              ⚠️   IMPORTANT — PLEASE READ   ⚠️              ║"
echo "  ║                                                            ║"
echo "  ╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo -e "  ${BOLD}Tau Agent is a powerful AI tool that can:${NC}"
echo ""
echo -e "  ${RED}  🖱️  Control your mouse and keyboard${NC}"
echo -e "  ${RED}  📸  Take screenshots of your screen${NC}"
echo -e "  ${RED}  🌐  Automate your web browser${NC}"
echo -e "  ${RED}  💻  Execute commands on your computer${NC}"
echo -e "  ${RED}  📂  Read and write files on your system${NC}"
echo -e "  ${RED}  🤖  Spawn autonomous sub-agents${NC}"
echo ""
echo -e "  ${BOLD}${YELLOW}This means:${NC}"
echo -e "  ${YELLOW}  • It will request Accessibility & Screen Recording permissions${NC}"
echo -e "  ${YELLOW}  • It will install software (Node.js packages, Python packages)${NC}"
echo -e "  ${YELLOW}  • All actions require your explicit approval at runtime${NC}"
echo -e "  ${YELLOW}  • Default safety: ask = always, security = full${NC}"
echo ""
echo -e "  ${DIM}By continuing, you acknowledge that you understand these capabilities${NC}"
echo -e "  ${DIM}and accept responsibility for how the agent is used.${NC}"
echo ""
divider
echo ""
echo -e "  ${BOLD}Do you understand and wish to continue?${NC}"
echo ""
echo -e "    ${GREEN}[Y]${NC} Yes, I understand — proceed with installation"
echo -e "    ${RED}[N]${NC} No, cancel installation"
echo ""
prompt_read CONSENT "  Your choice (Y/N): "

if [[ ! "$CONSENT" =~ ^[Yy]$ ]]; then
  echo ""
  echo -e "  ${BLUE}Installation cancelled. No changes were made.${NC}"
  echo ""
  exit 0
fi

# ══════════════════════════════════════════════════════════════
# PHASE 1 — SYSTEM SCAN (check what's already installed)
# ══════════════════════════════════════════════════════════════

banner
phase "PHASE 1/6 — Scanning Your System"

FOUND_BREW=""
FOUND_NODE=""
FOUND_PNPM=""
FOUND_PYTHON=""
FOUND_GIT=""
FOUND_PLAYWRIGHT=""
FOUND_CODEX=""
FOUND_BROWSERUSE=""
FOUND_REPO=""

NEED_INSTALL=()

# macOS check
step "Checking operating system..."
if [[ "$(uname)" != "Darwin" ]]; then
  fail "Tau Agent requires macOS. Detected: $(uname)"
  exit 1
fi
ok "macOS $(sw_vers -productVersion) ($(uname -m))"

# Homebrew
step "Checking Homebrew..."
if command -v brew &>/dev/null; then
  FOUND_BREW="$(brew --version 2>/dev/null | head -1)"
  ok "Found: $FOUND_BREW"
else
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x "$candidate" ]]; then
      FOUND_BREW="$($candidate --version 2>/dev/null | head -1)"
      eval "$($candidate shellenv)"
      ok "Found: $FOUND_BREW"
      break
    fi
  done
  if [[ -z "$FOUND_BREW" ]]; then
    warn "Not found — will install"
    NEED_INSTALL+=("Homebrew")
  fi
fi

# Node.js
step "Checking Node.js..."
if command -v node &>/dev/null; then
  NODE_VER="$(node --version)"
  NODE_MAJOR="${NODE_VER#v}"
  NODE_MAJOR="${NODE_MAJOR%%.*}"
  if [[ "$NODE_MAJOR" -ge 20 ]]; then
    FOUND_NODE="$NODE_VER"
    ok "Found: Node.js $NODE_VER"
  else
    warn "Found Node.js $NODE_VER but v20+ required — will upgrade"
    NEED_INSTALL+=("Node.js (upgrade)")
  fi
else
  warn "Not found — will install"
  NEED_INSTALL+=("Node.js")
fi

# pnpm
step "Checking pnpm..."
if command -v pnpm &>/dev/null; then
  FOUND_PNPM="$(pnpm --version 2>/dev/null)"
  ok "Found: pnpm $FOUND_PNPM"
else
  warn "Not found — will install"
  NEED_INSTALL+=("pnpm")
fi

# Python 3
step "Checking Python 3..."
for candidate in python3 /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3; do
  if command -v "$candidate" &>/dev/null; then
    FOUND_PYTHON="$($candidate --version 2>/dev/null)"
    ok "Found: $FOUND_PYTHON ($candidate)"
    PYTHON_CMD="$candidate"
    break
  fi
done
if [[ -z "$FOUND_PYTHON" ]]; then
  warn "Not found — will install"
  NEED_INSTALL+=("Python 3")
  PYTHON_CMD=""
fi

# Git
step "Checking Git..."
if command -v git &>/dev/null; then
  FOUND_GIT="$(git --version 2>/dev/null)"
  ok "Found: $FOUND_GIT"
else
  warn "Not found — will install"
  NEED_INSTALL+=("Git")
fi

# Existing Tau Agent repo
step "Checking for existing Tau Agent installation..."
if [[ -d "$INSTALL_DIR/openclaw-main" ]]; then
  FOUND_REPO="yes"
  ok "Found existing installation at $INSTALL_DIR"
else
  info "No existing installation found — will clone fresh"
fi

# Codex CLI
step "Checking Codex CLI..."
if command -v codex &>/dev/null || [[ -x "$BIN_DIR/codex" ]]; then
  FOUND_CODEX="yes"
  ok "Found: codex"
else
  info "Not installed — will install"
fi

# browser-use
step "Checking browser-use..."
if command -v browser-use &>/dev/null || [[ -x "$BIN_DIR/browser-use" ]]; then
  FOUND_BROWSERUSE="yes"
  ok "Found: browser-use"
else
  info "Not installed — will install"
fi

# Playwright
step "Checking Playwright Chromium..."
if npx playwright --version &>/dev/null 2>&1; then
  FOUND_PLAYWRIGHT="yes"
  ok "Found: Playwright installed"
else
  info "Not installed — will install"
fi

# Summary
echo ""
divider
echo ""
if [[ ${#NEED_INSTALL[@]} -eq 0 ]]; then
  echo -e "  ${GREEN}${BOLD}All system prerequisites are installed! ✨${NC}"
else
  echo -e "  ${YELLOW}${BOLD}Will install/upgrade: ${NEED_INSTALL[*]}${NC}"
fi
echo ""

press_enter

# ══════════════════════════════════════════════════════════════
# PHASE 2 — macOS PERMISSIONS
# ══════════════════════════════════════════════════════════════

banner
phase "PHASE 2/6 — macOS Permissions"

echo -e "  ${BOLD}Tau Agent needs these permissions for full computer control.${NC}"
echo -e "  ${BOLD}Permission dialogs will appear on your screen.${NC}"
echo ""
echo -e "  ${WHITE}┌────────────────────┬────────────────────────────────────────┐${NC}"
echo -e "  ${WHITE}│ Permission         │ Purpose                                │${NC}"
echo -e "  ${WHITE}├────────────────────┼────────────────────────────────────────┤${NC}"
echo -e "  ${WHITE}│${NC} ${BOLD}Accessibility${NC}      ${WHITE}│${NC} Mouse/keyboard control                 ${WHITE}│${NC}"
echo -e "  ${WHITE}│${NC} ${BOLD}Screen Recording${NC}   ${WHITE}│${NC} Screenshots & screen capture            ${WHITE}│${NC}"
echo -e "  ${WHITE}│${NC} ${DIM}Camera (optional)${NC}  ${WHITE}│${NC} ${DIM}Camera snaps from paired nodes${NC}          ${WHITE}│${NC}"
echo -e "  ${WHITE}│${NC} ${DIM}Location (optional)${NC}${WHITE}│${NC} ${DIM}Location from paired nodes${NC}              ${WHITE}│${NC}"
echo -e "  ${WHITE}└────────────────────┴────────────────────────────────────────┘${NC}"
echo ""

# Request Accessibility
step "Requesting Accessibility permission..."
echo ""
echo -e "    ${YELLOW}A system dialog should appear. Please grant access to Terminal/iTerm.${NC}"
echo ""

# Trigger Accessibility check via AppleScript (this shows the macOS dialog)
osascript -e 'tell application "System Events" to key code 0' &>/dev/null 2>&1 || true

# Also open System Preferences to the right pane
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" &>/dev/null 2>&1 || true

echo -e "    ${DIM}Waiting for you to grant Accessibility access...${NC}"
prompt_read _ "    Press Enter once granted (or to skip)... "

# Check if we have Accessibility
if osascript -e 'tell application "System Events" to return name of first process' &>/dev/null 2>&1; then
  ok "Accessibility permission granted"
else
  warn "Accessibility may not be granted — some features will be limited"
fi

echo ""

# Request Screen Recording
step "Requesting Screen Recording permission..."
echo ""
echo -e "    ${YELLOW}A system dialog should appear for Screen Recording.${NC}"
echo ""

# Trigger screen recording check
osascript -e '
  tell application "System Events"
    try
      do shell script "screencapture -x /tmp/.tau-perm-test.png"
    end try
  end tell
' &>/dev/null 2>&1 || screencapture -x /tmp/.tau-perm-test.png &>/dev/null 2>&1 || true
rm -f /tmp/.tau-perm-test.png &>/dev/null 2>&1 || true

open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture" &>/dev/null 2>&1 || true

echo -e "    ${DIM}Waiting for you to grant Screen Recording access...${NC}"
prompt_read _ "    Press Enter once granted (or to skip)... "

if screencapture -x /tmp/.tau-perm-test2.png &>/dev/null 2>&1 && [[ -f /tmp/.tau-perm-test2.png ]]; then
  ok "Screen Recording permission granted"
  rm -f /tmp/.tau-perm-test2.png
else
  warn "Screen Recording may not be granted — screenshots will be limited"
fi

echo ""
ok "Permissions phase complete"

press_enter

# ══════════════════════════════════════════════════════════════
# PHASE 3 — API KEY & MODEL SELECTION
# ══════════════════════════════════════════════════════════════

banner
phase "PHASE 3/6 — API Key & Model Selection"

OPENAI_KEY="${OPENAI_API_KEY:-}"

echo -e "  ${BOLD}Tau Agent uses OpenAI's API for all AI features.${NC}"
echo -e "  ${DIM}Get a key at: https://platform.openai.com/api-keys${NC}"
echo ""

if [[ -n "$OPENAI_KEY" ]]; then
  echo -e "  ${GREEN}Found existing API key in environment: ${OPENAI_KEY:0:7}...${NC}"
  echo ""
  echo -e "  ${BOLD}Use this key?${NC}"
  echo -e "    ${GREEN}[Y]${NC} Yes, use existing key"
  echo -e "    ${BLUE}[N]${NC} No, enter a different key"
  echo ""
  prompt_read USE_EXISTING "  Your choice (Y/N): "
  if [[ "$USE_EXISTING" =~ ^[Nn]$ ]]; then
    OPENAI_KEY=""
  fi
fi

if [[ -z "$OPENAI_KEY" ]]; then
  echo ""
  prompt_read OPENAI_KEY "  🔑 Enter your OpenAI API Key (sk-...): "
fi

if [[ -z "$OPENAI_KEY" ]]; then
  warn "No API key provided. You'll need to set it later:"
  warn "  export OPENAI_API_KEY=\"sk-...\""
else
  ok "API key set: ${OPENAI_KEY:0:7}..."
fi

echo ""
divider
echo ""

# Model selection
echo -e "  ${BOLD}Select your default AI model:${NC}"
echo ""
echo -e "    ${GREEN}[1]${NC} ${BOLD}gpt-5.4${NC}        — Latest, best for CUA browser control ${GREEN}(recommended)${NC}"
echo -e "    ${BLUE}[2]${NC} ${BOLD}gpt-5.2${NC}        — Fast, reliable, lower cost"
echo -e "    ${BLUE}[3]${NC} ${BOLD}gpt-4.1${NC}        — Proven, cost-effective"
echo -e "    ${BLUE}[4]${NC} ${BOLD}o3${NC}             — Reasoning model, great for complex tasks"
echo -e "    ${DIM}[5]${NC} ${DIM}Custom${NC}         — Enter a custom model name"
echo ""
prompt_read MODEL_CHOICE "  Your choice (1-5) [1]: "

case "${MODEL_CHOICE:-1}" in
  1) SELECTED_MODEL="openai/gpt-5.4" ;;
  2) SELECTED_MODEL="openai/gpt-5.2" ;;
  3) SELECTED_MODEL="openai/gpt-4.1" ;;
  4) SELECTED_MODEL="openai/o3" ;;
  5)
    prompt_read CUSTOM_MODEL "  Enter model name (e.g. openai/gpt-5.4): "
    SELECTED_MODEL="${CUSTOM_MODEL:-openai/gpt-5.4}"
    ;;
  *) SELECTED_MODEL="openai/gpt-5.4" ;;
esac

ok "Selected model: $SELECTED_MODEL"

press_enter

# ══════════════════════════════════════════════════════════════
# PHASE 4 — INSTALLATION (with progress tracking)
# ══════════════════════════════════════════════════════════════

banner
phase "PHASE 4/6 — Installing Everything"

# ── Progress bar helpers ──────────────────────────────────────
TOTAL_STEPS=9
CURRENT_STEP=0

progress_bar() {
  CURRENT_STEP=$((CURRENT_STEP + 1))
  local pct=$((CURRENT_STEP * 100 / TOTAL_STEPS))
  local filled=$((pct / 2))
  local empty=$((50 - filled))
  local bar="${GREEN}"
  for ((i=0; i<filled; i++)); do bar+="█"; done
  bar+="${DIM}"
  for ((i=0; i<empty; i++)); do bar+="░"; done
  bar+="${NC}"
  echo -e "\r  ${BOLD}[${bar}${BOLD}] ${pct}%${NC}  "
}

# Spinner for long-running background tasks
spin_while() {
  local label="$1"
  shift
  local pid
  local spinchars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  local tmplog="/tmp/.tau-install-$$.log"

  # Run command in background, capture output
  "$@" > "$tmplog" 2>&1 &
  pid=$!

  local i=0
  local last_line=""
  while kill -0 "$pid" 2>/dev/null; do
    local c="${spinchars:i%${#spinchars}:1}"
    # Show last line of output for real-time feedback
    if [[ -f "$tmplog" ]]; then
      last_line=$(tail -1 "$tmplog" 2>/dev/null | cut -c1-60 || true)
    fi
    printf "\r    ${CYAN}${c}${NC}  %-62s" "${label}${last_line:+ — ${DIM}${last_line}${NC}}" >&2
    i=$((i + 1))
    sleep 0.15
  done

  # Clear spinner line
  printf "\r%-80s\r" "" >&2

  # Check exit code
  wait "$pid"
  local exit_code=$?
  rm -f "$tmplog"
  return $exit_code
}

# ── Step 1: Homebrew ──────────────────────────────────────────
if [[ -z "$FOUND_BREW" ]]; then
  step "[1/$TOTAL_STEPS] Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -f /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
  ok "Homebrew installed"
else
  step "[1/$TOTAL_STEPS] Homebrew"
  skip "Already installed"
fi
progress_bar

# ── Step 2: Node.js ───────────────────────────────────────────
if [[ -z "$FOUND_NODE" ]]; then
  step "[2/$TOTAL_STEPS] Installing Node.js..."
  brew install node
  ok "Node.js installed ($(node --version))"
else
  step "[2/$TOTAL_STEPS] Node.js"
  skip "Already installed ($FOUND_NODE)"
fi
progress_bar

# ── Step 3: pnpm ─────────────────────────────────────────────
if [[ -z "$FOUND_PNPM" ]]; then
  step "[3/$TOTAL_STEPS] Installing pnpm..."
  npm install -g pnpm 2>&1 | tail -2
  ok "pnpm installed ($(pnpm --version))"
else
  step "[3/$TOTAL_STEPS] pnpm"
  skip "Already installed ($FOUND_PNPM)"
fi
progress_bar

# ── Step 4: Python ────────────────────────────────────────────
if [[ -z "$FOUND_PYTHON" ]]; then
  step "[4/$TOTAL_STEPS] Installing Python 3..."
  brew install python@3.12
  PYTHON_CMD="python3"
  ok "Python installed ($($PYTHON_CMD --version))"
else
  step "[4/$TOTAL_STEPS] Python"
  skip "Already installed ($FOUND_PYTHON)"
fi
progress_bar

# ── Step 5: Git ───────────────────────────────────────────────
if [[ -z "$FOUND_GIT" ]]; then
  step "[5/$TOTAL_STEPS] Installing Git..."
  brew install git
  ok "Git installed"
else
  step "[5/$TOTAL_STEPS] Git"
  skip "Already installed"
fi
progress_bar

# ── Step 6: Clone / update repo ──────────────────────────────
if [[ -n "$FOUND_REPO" ]]; then
  step "[6/$TOTAL_STEPS] Updating Tau Agent..."
  cd "$INSTALL_DIR"
  git pull --ff-only 2>/dev/null || true
  ok "Updated to latest"
else
  step "[6/$TOTAL_STEPS] Cloning Tau Agent from GitHub..."
  git clone --depth 1 https://github.com/shalevamin/Tau_agent.git "$INSTALL_DIR"
  ok "Cloned to $INSTALL_DIR"
fi
progress_bar

cd "$INSTALL_DIR/openclaw-main"

# ── Step 7: Node dependencies (THE BIG ONE) ──────────────────
step "[7/$TOTAL_STEPS] Installing Node.js dependencies (this may take a few minutes)..."
echo ""
if spin_while "Installing packages" pnpm install --no-frozen-lockfile; then
  ok "Dependencies installed"
else
  warn "Some dependencies may have failed — continuing anyway"
fi
progress_bar

# ── Step 8: Toolchain ────────────────────────────────────────
step "[8/$TOTAL_STEPS] Installing Toolchain (Codex, browser-use, OpenViking)..."
echo ""
mkdir -p "$BIN_DIR"
if spin_while "Setting up toolchain" node scripts/install-ultimate-toolchain.mjs; then
  ok "Toolchain installed to $MANAGED_DIR"
else
  warn "Toolchain install had issues — some tools may not be available"
fi
progress_bar

# ── Step 9: Skills + Playwright ──────────────────────────────
step "[9/$TOTAL_STEPS] Syncing skills & installing Playwright..."
echo ""

# Skills
if spin_while "Syncing 290+ skills" node scripts/install-ultimate-skills.mjs; then
  SKILL_COUNT=$(find "$SKILLS_DIR" -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  SKILL_COUNT=$((SKILL_COUNT > 0 ? SKILL_COUNT - 1 : 0))
  ok "$SKILL_COUNT skills installed"
else
  SKILL_COUNT=0
  warn "Skills sync had issues"
fi

# Playwright
if [[ -n "$FOUND_PLAYWRIGHT" ]]; then
  skip "Playwright already installed"
else
  if spin_while "Installing Playwright Chromium" npx -y playwright install chromium; then
    ok "Playwright Chromium installed"
  else
    warn "Playwright install had issues — CUA browser features may not work"
  fi
fi
progress_bar

echo ""
echo -e "  ${GREEN}${BOLD}████████████████████████████████████████████████████${NC} ${GREEN}${BOLD}100%${NC}"
echo ""
echo -e "  ${GREEN}${BOLD}✨ All components installed!${NC}"

divider

# Save model selection to config
step "Writing configuration (model: $SELECTED_MODEL)..."
mkdir -p "$MANAGED_DIR"
CONFIG_FILE="$MANAGED_DIR/openclaw.json"
if [[ -f "$CONFIG_FILE" ]]; then
  # Update existing config — use node for safe JSON manipulation
  node -e "
    const fs = require('fs');
    const cfg = JSON.parse(fs.readFileSync('$CONFIG_FILE', 'utf8'));
    cfg.model = '$SELECTED_MODEL';
    if (!cfg.providers) cfg.providers = {};
    if (!cfg.providers.openai) cfg.providers.openai = {};
    fs.writeFileSync('$CONFIG_FILE', JSON.stringify(cfg, null, 2) + '\n');
  " 2>/dev/null || true
else
  cat > "$CONFIG_FILE" << JSONEOF
{
  "model": "$SELECTED_MODEL",
  "providers": {
    "openai": {}
  },
  "agents": {
    "defaults": {
      "maxSpawnDepth": 3,
      "maxChildrenPerAgent": 8
    }
  },
  "exec": {
    "ask": "always",
    "security": "full",
    "autoAllowSkills": true
  }
}
JSONEOF
fi
ok "Config written to $CONFIG_FILE"

# Environment
step "Configuring shell environment..."
SHELL_RC="$HOME/.zshrc"
if [[ -f "$HOME/.bashrc" ]] && [[ ! -f "$HOME/.zshrc" ]]; then
  SHELL_RC="$HOME/.bashrc"
fi

CHANGED_SHELL=false

if ! grep -q '\.openclaw/bin' "$SHELL_RC" 2>/dev/null; then
  echo '' >> "$SHELL_RC"
  echo '# Tau Agent — managed tools' >> "$SHELL_RC"
  echo 'export PATH="$HOME/.openclaw/bin:$PATH"' >> "$SHELL_RC"
  CHANGED_SHELL=true
fi

if [[ -n "$OPENAI_KEY" ]]; then
  if ! grep -q 'OPENAI_API_KEY' "$SHELL_RC" 2>/dev/null; then
    echo "export OPENAI_API_KEY=\"$OPENAI_KEY\"" >> "$SHELL_RC"
    CHANGED_SHELL=true
  else
    sed -i '' "s|export OPENAI_API_KEY=.*|export OPENAI_API_KEY=\"$OPENAI_KEY\"|" "$SHELL_RC"
  fi
  export OPENAI_API_KEY="$OPENAI_KEY"
fi

export PATH="$BIN_DIR:$PATH"

if [[ "$CHANGED_SHELL" == true ]]; then
  ok "Updated $SHELL_RC"
else
  skip "Shell already configured"
fi

ok "Installation complete!"

press_enter

# ══════════════════════════════════════════════════════════════
# PHASE 5 — VERIFICATION
# ══════════════════════════════════════════════════════════════

banner
phase "PHASE 5/6 — Verifying Installation"

TOTAL_CHECKS=0
PASSED_CHECKS=0

check_tool() {
  local name="$1"
  local check_cmd="$2"
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  if eval "$check_cmd" &>/dev/null 2>&1; then
    ok "$name"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
  else
    fail "$name"
  fi
}

check_tool "Node.js $(node --version 2>/dev/null || echo 'missing')"     "node --version"
check_tool "pnpm $(pnpm --version 2>/dev/null || echo 'missing')"       "pnpm --version"
check_tool "Python ($($PYTHON_CMD --version 2>/dev/null || echo 'missing'))" "$PYTHON_CMD --version"
check_tool "Git"                                                         "git --version"
check_tool "Codex CLI"                                                   "test -x $BIN_DIR/codex"
check_tool "browser-use"                                                 "test -x $BIN_DIR/browser-use"
check_tool "Tau Agent repo"                                              "test -d $INSTALL_DIR/openclaw-main"
check_tool "Skills ($SKILL_COUNT installed)"                             "test -d $SKILLS_DIR"
check_tool "Config file"                                                 "test -f $MANAGED_DIR/openclaw.json"

echo ""
divider
echo ""

if [[ "$PASSED_CHECKS" -eq "$TOTAL_CHECKS" ]]; then
  echo -e "  ${GREEN}${BOLD}All $TOTAL_CHECKS checks passed! ✨${NC}"
else
  echo -e "  ${YELLOW}${BOLD}$PASSED_CHECKS/$TOTAL_CHECKS checks passed${NC}"
fi

press_enter

# ══════════════════════════════════════════════════════════════
# PHASE 6 — LAUNCH DASHBOARD
# ══════════════════════════════════════════════════════════════

banner
phase "PHASE 6/6 — Ready to Launch!"

echo -e "${GREEN}${BOLD}"
echo "  ╔════════════════════════════════════════════════════════════╗"
echo "  ║                                                            ║"
echo "  ║        🎉  TAU AGENT IS READY!  🎉                         ║"
echo "  ║                                                            ║"
echo "  ╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo -e "  ${BOLD}Summary:${NC}"
echo -e "    📁 Installation     → $INSTALL_DIR"
echo -e "    🔧 Toolchain        → $MANAGED_DIR"
echo -e "    🧩 Skills ($SKILL_COUNT)     → $SKILLS_DIR"
echo -e "    🤖 Model            → $SELECTED_MODEL"
echo -e "    🔑 API Key          → ${OPENAI_KEY:+${OPENAI_KEY:0:7}...}${OPENAI_KEY:-not set}"
echo ""
divider
echo ""
echo -e "  ${BOLD}What would you like to do now?${NC}"
echo ""
echo -e "    ${GREEN}[1]${NC} 🚀 ${BOLD}Launch Dashboard${NC}         — Start the gateway & open the web UI"
echo -e "    ${BLUE}[2]${NC} 💬 ${BOLD}Connect WhatsApp${NC}         — Set up WhatsApp integration"
echo -e "    ${BLUE}[3]${NC} 📱 ${BOLD}Connect Telegram${NC}         — Set up Telegram bot"
echo -e "    ${BLUE}[4]${NC} 💬 ${BOLD}Connect Discord${NC}          — Set up Discord bot"
echo -e "    ${BLUE}[5]${NC} 💬 ${BOLD}Connect Slack${NC}            — Set up Slack integration"
echo -e "    ${BLUE}[6]${NC} 💻 ${BOLD}Use Codex CLI${NC}            — Start coding with Codex"
echo -e "    ${DIM}[7]${NC} ${DIM}Exit${NC}                       — ${DIM}Exit installer${NC}"
echo ""
prompt_read LAUNCH_CHOICE "  Your choice (1-7) [1]: "

case "${LAUNCH_CHOICE:-1}" in
  1)
    echo ""
    step "Starting Tau Agent gateway..."
    echo ""
    echo -e "  ${CYAN}The dashboard will open in your browser.${NC}"
    echo -e "  ${DIM}Press Ctrl+C to stop the gateway.${NC}"
    echo ""
    cd "$INSTALL_DIR/openclaw-main"
    pnpm dev
    ;;
  2)
    echo ""
    step "WhatsApp Integration"
    echo ""
    echo -e "  ${BOLD}To connect WhatsApp:${NC}"
    echo ""
    echo -e "  1. Start the gateway:  ${CYAN}cd $INSTALL_DIR/openclaw-main && pnpm dev${NC}"
    echo -e "  2. Open the Dashboard in your browser"
    echo -e "  3. Go to ${BOLD}Channels → WhatsApp${NC}"
    echo -e "  4. Scan the QR code with WhatsApp on your phone"
    echo ""
    echo -e "  ${DIM}Or start the gateway now?${NC}"
    prompt_read START_GW "  Start gateway? (Y/N) [Y]: "
    if [[ "${START_GW:-Y}" =~ ^[Yy]$ ]]; then
      cd "$INSTALL_DIR/openclaw-main"
      pnpm dev
    fi
    ;;
  3)
    echo ""
    step "Telegram Integration"
    echo ""
    echo -e "  ${BOLD}To connect Telegram:${NC}"
    echo ""
    echo -e "  1. Create a bot via ${CYAN}@BotFather${NC} on Telegram"
    echo -e "  2. Copy the bot token"
    echo -e "  3. Start the gateway:  ${CYAN}cd $INSTALL_DIR/openclaw-main && pnpm dev${NC}"
    echo -e "  4. Open Dashboard → ${BOLD}Channels → Telegram${NC}"
    echo -e "  5. Paste your bot token"
    echo ""
    echo -e "  ${DIM}Or start the gateway now?${NC}"
    prompt_read START_GW "  Start gateway? (Y/N) [Y]: "
    if [[ "${START_GW:-Y}" =~ ^[Yy]$ ]]; then
      cd "$INSTALL_DIR/openclaw-main"
      pnpm dev
    fi
    ;;
  4)
    echo ""
    step "Discord Integration"
    echo ""
    echo -e "  ${BOLD}To connect Discord:${NC}"
    echo ""
    echo -e "  1. Create a bot at ${CYAN}https://discord.com/developers/applications${NC}"
    echo -e "  2. Copy the bot token"
    echo -e "  3. Start the gateway:  ${CYAN}cd $INSTALL_DIR/openclaw-main && pnpm dev${NC}"
    echo -e "  4. Open Dashboard → ${BOLD}Channels → Discord${NC}"
    echo -e "  5. Paste your bot token and configure permissions"
    echo ""
    echo -e "  ${DIM}Or start the gateway now?${NC}"
    prompt_read START_GW "  Start gateway? (Y/N) [Y]: "
    if [[ "${START_GW:-Y}" =~ ^[Yy]$ ]]; then
      cd "$INSTALL_DIR/openclaw-main"
      pnpm dev
    fi
    ;;
  5)
    echo ""
    step "Slack Integration"
    echo ""
    echo -e "  ${BOLD}To connect Slack:${NC}"
    echo ""
    echo -e "  1. Create a Slack app at ${CYAN}https://api.slack.com/apps${NC}"
    echo -e "  2. Configure bot scopes and install to workspace"
    echo -e "  3. Start the gateway:  ${CYAN}cd $INSTALL_DIR/openclaw-main && pnpm dev${NC}"
    echo -e "  4. Open Dashboard → ${BOLD}Channels → Slack${NC}"
    echo -e "  5. Enter your Slack tokens"
    echo ""
    echo -e "  ${DIM}Or start the gateway now?${NC}"
    prompt_read START_GW "  Start gateway? (Y/N) [Y]: "
    if [[ "${START_GW:-Y}" =~ ^[Yy]$ ]]; then
      cd "$INSTALL_DIR/openclaw-main"
      pnpm dev
    fi
    ;;
  6)
    echo ""
    step "Starting Codex CLI..."
    echo ""
    echo -e "  ${DIM}Type your coding task and press Enter.${NC}"
    echo ""
    export PATH="$BIN_DIR:$PATH"
    "$BIN_DIR/codex" || codex || echo -e "  ${YELLOW}Codex not found. Run: source $SHELL_RC && codex${NC}"
    ;;
  7|*)
    echo ""
    echo -e "  ${BOLD}To launch later:${NC}"
    echo ""
    echo -e "    ${CYAN}cd $INSTALL_DIR/openclaw-main && pnpm dev${NC}"
    echo ""
    echo -e "  ${MAGENTA}${BOLD}  Tau Agent — Because one agent should be able to do everything. 🤖${NC}"
    echo ""
    ;;
esac
