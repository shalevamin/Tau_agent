# Tau Agent

Tau Agent is an OpenAI-first personal operator stack built on top of OpenClaw, `browser-use`, and the OpenAI GPT-5.4 computer-use sample app.

This repo is tuned for one-provider operation:

- OpenAI-family models only
- native browser work first
- desktop computer-use second
- extension relay fallback last
- aggressive memory persistence
- managed skills and toolchain installation on first setup

## What Tau Adds

- OpenAI-only onboarding and auth flows
- `Tau Command Center` dashboard copy and operator routing
- bundled OpenAI CUA operator stack via `tua-cua-dev`, `tua-cua-runner`, `tua-cua-web`
- browser stack policy: `browser-use` -> computer-use -> extension relay
- durable memory scaffold (`MEMORY.md` + daily notes)
- preinstalled managed skills focused on OpenAI, browser automation, docs, orchestration, and local workflows

## Quick Start

Prerequisites:

- macOS
- Node.js 22+
- `pnpm`
- Python 3
- Homebrew
- an OpenAI API key in `OPENAI_API_KEY`

Setup:

```bash
git clone https://github.com/shalevamin/Tau_agent.git
cd Tau_agent

pnpm install
export PATH="$HOME/.openclaw/bin:$PATH"
export OPENAI_API_KEY="your_openai_key"

node scripts/install-ultimate-toolchain.mjs
node scripts/install-ultimate-skills.mjs

pnpm openclaw onboard --install-daemon
```

Start the OpenAI operator console:

```bash
tua-cua-dev
```

## Documentation

- [Installation Guide](docs/TAU_INSTALL.md)
- [Usage Guide](docs/TAU_USAGE.md)
- [Stack Overview](docs/TAU_STACK.md)
- [Known Limitations](docs/TAU_LIMITATIONS.md)

## Default Runtime Policy

- Coding and orchestration should prefer `codex` and the local OpenAI operator stack.
- Browser tasks should prefer `browser-use`.
- Real UI work should escalate to computer-use on the Mac.
- Extension relay exists, but only as fallback.
- Logged-in browser sessions are preferred over asking for more API keys.
- Semantic memory uses OpenAI embeddings when `OPENAI_API_KEY` is present.

## Installed Operator Commands

After `node scripts/install-ultimate-toolchain.mjs`, Tau installs:

- `codex`
- `browser-use`
- `gog`
- `tua-cua-dev`
- `tua-cua-runner`
- `tua-cua-web`

These are installed under `~/.openclaw/bin`.

## Managed Skills

Tau syncs and installs managed skills from:

- `openai/skills`
- `browser-use/browser-use`
- `BrowserMCP/mcp`
- local Tau/OpenClaw skills in this repo

## Current Source Note

The OpenAI-only product configuration, toolchain install, managed skills install, memory defaults, and dashboard changes are in this repo now.

The macOS app source build is still blocked by an external dependency issue in `swiftui-math` macro plugins. See [Known Limitations](docs/TAU_LIMITATIONS.md).
