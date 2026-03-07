<p align="center">
  <img src="https://img.shields.io/badge/Tau%20Agent-Ultimate%20AI%20Operator-blueviolet?style=for-the-badge&logo=openai&logoColor=white" alt="Tau Agent Badge" />
</p>

<h1 align="center">🤖 Tau Agent</h1>

<p align="center">
  <strong>The Ultimate AI Agent — Full Computer Control, Browser Automation, Agent Orchestration</strong>
</p>

<p align="center">
  <a href="#-features">Features</a> •
  <a href="#-architecture">Architecture</a> •
  <a href="#%EF%B8%8F-prerequisites">Prerequisites</a> •
  <a href="#-installation">Installation</a> •
  <a href="#-quick-start">Quick Start</a> •
  <a href="#-usage-guide">Usage Guide</a> •
  <a href="#-skills">Skills</a> •
  <a href="#-contributors--credits">Contributors</a>
</p>

---

## ⚡ One-Line Install

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/shalevamin/Tau_agent/main/install.sh)"
```

> This single command installs **everything**: Homebrew, Node.js, pnpm, Python, Git, Codex CLI, browser-use, Playwright, 290+ skills — then asks for your OpenAI API key and requests macOS permissions. Done. ✨

Or clone and run locally:

```bash
git clone https://github.com/shalevamin/Tau_agent.git && cd Tau_agent && bash install.sh
```

---

## ✨ Features

| Feature                          | Description                                                                                                               |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| 🖱️ **Full Computer Control**     | Mouse movement, clicking, typing, key presses, scrolling — via macOS Accessibility APIs                                   |
| 🌐 **Native Browser Automation** | GPT-5.4 CUA (Computer Use Agent) Responses API with Playwright — click, type, scroll, drag, screenshot inside any website |
| 🎭 **Dual CUA Modes**            | **Native mode**: raw mouse/keyboard actions on live browser. **Code mode**: persistent JavaScript REPL over Playwright    |
| 🧠 **Agent Orchestration**       | Spawn and manage sub-agents (up to 3 levels deep, 8 children per agent) for parallel workflows                            |
| 📸 **Screen & Camera**           | Take screenshots, record screen, capture camera snaps/clips from paired nodes                                             |
| 💾 **Persistent Memory**         | Long-term memory (`MEMORY.md`), daily notes (`memory/YYYY-MM-DD.md`), auto-flush on compaction                            |
| 🔧 **290+ Pre-installed Skills** | Coding, browser control, computer use, orchestration, dev workflows and more                                              |
| 🛡️ **Safety-First Execution**    | All commands require explicit user approval (`ask = always`, `security = full`)                                           |
| 🔑 **Single API Key**            | Runs entirely on OpenAI (`OPENAI_API_KEY`) — no multi-provider complexity                                                 |
| 📱 **Node Pairing**              | Pair with iOS/macOS companion apps for remote camera, notifications, location, and device control                         |

---

## 🏗 Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Tau Agent (macOS App)                  │
│                                                          │
│  ┌──────────┐  ┌──────────┐  ┌───────────────────────┐  │
│  │Onboarding│  │ Dashboard │  │   Agent Runtime (TS)  │  │
│  │  (Swift) │  │   (Web)   │  │                       │  │
│  │          │  │           │  │  ┌─────────────────┐  │  │
│  │• Setup   │  │• Overview │  │  │  nodes-tool.ts  │  │  │
│  │• Perms   │  │• Skills   │  │  │  • computer_*   │  │  │
│  │• API Key │  │• Agents   │  │  │  • camera_*     │  │  │
│  │• Install │  │• CUA      │  │  │  • cua_run ←NEW │  │  │
│  └──────────┘  └──────────┘  │  │  • run / invoke  │  │  │
│                              │  └────────┬──────────┘  │  │
│                              │           │             │  │
│                              │  ┌────────▼──────────┐  │  │
│                              │  │ cua-responses-loop │  │  │
│                              │  │  GPT-5.4 + Playwright│ │
│                              │  │  Native & Code modes │ │
│                              │  └─────────────────────┘│  │
│                              └─────────────────────────┘  │
│                                                          │
│  ┌──────────────────────────────────────────────────┐    │
│  │             Gateway (Node.js Server)              │    │
│  │  • Agent sessions  • Skill loading  • Node IPC   │    │
│  │  • Memory search   • Exec approvals • WebSocket  │    │
│  └──────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
              │                         │
    ┌─────────▼──────────┐   ┌──────────▼──────────┐
    │  Paired Nodes       │   │  External Services   │
    │  (iOS/macOS apps)   │   │  • OpenAI API        │
    │  • Camera           │   │  • browser-use       │
    │  • Location         │   │  • Playwright        │
    │  • Notifications    │   │  • Codex CLI         │
    └────────────────────┘   └─────────────────────┘
```

### Key Directories

```
Tau_agent/
├── openclaw-main/                   # Core agent framework (modified)
│   ├── apps/macos/                  # macOS Swift app (onboarding, UI)
│   │   └── Sources/OpenClaw/
│   │       ├── Onboarding.swift               # Onboarding flow
│   │       ├── OnboardingView+UltimateSetup.swift  # Auto-setup: toolchain, skills, perms
│   │       ├── AgentWorkspace.swift           # Workspace templates (AGENTS.md, MEMORY.md)
│   │       └── Constants.swift                # Version keys
│   ├── src/agents/tools/
│   │   ├── nodes-tool.ts            # Main tool: 25+ actions including cua_run
│   │   └── cua-responses-loop.ts    # GPT-5.4 CUA Responses API integration
│   ├── ui/src/ui/
│   │   ├── app-render.ts            # Dashboard shell ("TUA AGENT" branding)
│   │   └── views/overview.ts        # Command Center + Capability Mesh
│   ├── scripts/
│   │   ├── install-ultimate-toolchain.mjs  # Installs Codex, browser-use, OpenViking
│   │   └── install-ultimate-skills.mjs     # Syncs 290+ skills from GitHub repos
│   └── skills/
│       ├── tua-computer-use/        # Computer control skill
│       ├── tua-orchestra/           # Agent orchestration skill
│       └── tua-native-workflows/    # Native app workflows skill
│
├── openai-cua-sample-app/           # Reference: OpenAI CUA sample app
│   └── packages/
│       ├── runner-core/             # Responses API loop (reference implementation)
│       └── browser-runtime/         # Playwright browser session management
│
└── README.md                        # This file
```

---

## ⚙️ Prerequisites

### System Requirements

| Requirement | Details                                               |
| ----------- | ----------------------------------------------------- |
| **OS**      | macOS 14+ (Sonoma) or macOS 15+ (Sequoia) recommended |
| **Node.js** | v20+ (`brew install node`)                            |
| **pnpm**    | v9+ (`npm install -g pnpm`)                           |
| **Python**  | 3.11+ (`brew install python@3.12`)                    |
| **Xcode**   | 15+ (for building the macOS app)                      |
| **Git**     | Latest (`brew install git`)                           |

### API Key

You need **one API key**:

```bash
export OPENAI_API_KEY="sk-..."
```

> 💡 This single key powers the agent runtime, CUA browser automation (GPT-5.4), Codex CLI, and memory embeddings.

### macOS Permissions

The setup will request these permissions interactively:

| Permission              | Purpose                                                                   |
| ----------------------- | ------------------------------------------------------------------------- |
| **Accessibility**       | Mouse/keyboard control (`system.mouse`, `system.type`, `system.keypress`) |
| **Screen Recording**    | Screenshots (`system.screenshot`, `screen.record`)                        |
| **Camera** (optional)   | Camera snaps/clips from paired nodes                                      |
| **Location** (optional) | Location services from paired nodes                                       |

---

## 📦 Installation

### Step 1: Clone the Repository

```bash
git clone https://github.com/shalevamin/Tau_agent.git
cd Tau_agent
```

### Step 2: Install Core Dependencies

```bash
cd openclaw-main
pnpm install
```

### Step 3: Install the Ultimate Toolchain

This installs Codex CLI, browser-use (Python), and OpenViking into `~/.openclaw/`:

```bash
node scripts/install-ultimate-toolchain.mjs
```

**What gets installed:**

| Tool          | Type         | Purpose                           |
| ------------- | ------------ | --------------------------------- |
| `codex`       | npm (global) | OpenAI Codex CLI for coding tasks |
| `browser-use` | Python venv  | Browser automation via Playwright |
| `openviking`  | Python venv  | OpenViking AI toolkit             |

After installation, add the managed bin to your PATH:

```bash
export PATH="$HOME/.openclaw/bin:$PATH"
```

### Step 4: Install Skills (290+ Skills)

```bash
node scripts/install-ultimate-skills.mjs
```

This will:

1. Clone/update skill repositories from GitHub
2. Scan for `SKILL.md` files
3. Install all skills into `~/.openclaw/skills/`
4. Generate a manifest at `~/.openclaw/skills/.tua-installed-skills.json`

### Step 5: Install Playwright Browsers

```bash
npx playwright install chromium
```

### Step 6: Build the macOS App (Optional)

```bash
cd apps/macos
swift build
```

> ⚠️ The macOS app build requires Xcode 15+ and may need additional Swift package resolution. The first build can take several minutes.

### Step 7: Set Your API Key

Add to your shell profile (`~/.zshrc` or `~/.bashrc`):

```bash
echo 'export OPENAI_API_KEY="sk-your-key-here"' >> ~/.zshrc
echo 'export PATH="$HOME/.openclaw/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

---

## 🚀 Quick Start

### 1. Launch the Gateway

```bash
cd openclaw-main
pnpm dev
```

### 2. Open the macOS App

If built via Step 6, launch the app. The onboarding wizard will:

- ✅ Configure defaults (model: `gpt-5.4`, single OpenAI provider)
- ✅ Create workspace with `AGENTS.md`, `MEMORY.md`, `IDENTITY.md`, `USER.md`
- ✅ Install toolchain and skills automatically
- ✅ Request macOS permissions
- ✅ Seed safe execution policies

### 3. Or Use the CLI

```bash
# Use Codex directly
codex "Build me a React dashboard"

# Or start the gateway and interact via the web UI
pnpm dev
# Navigate to the local URL shown in terminal
```

---

## 📖 Usage Guide

### Computer Control (Mouse & Keyboard)

Tau Agent can control your computer through the paired macOS node:

```
Action: computer_screenshot
→ Takes a screenshot and returns it with coordinate metadata

Action: computer_mouse
→ mouseAction: click | doubleClick | move | scroll | down | up
→ x, y: coordinates on screen
→ button: left | right | center

Action: computer_type
→ text: "Hello World" → types the text at current cursor

Action: computer_keypress
→ key: "a" | "Enter" | "Tab" etc.
→ modifiers: ["command", "shift", "option", "control", "fn"]
```

### CUA Browser Automation (GPT-5.4)

The `cua_run` action launches a full CUA Responses API session:

```
Action: cua_run
Parameters:
  cuaPrompt: "Go to github.com and star the Tau_agent repo"
  cuaMode: "native"          # or "code" for JS REPL mode
  cuaStartUrl: "https://github.com"
  cuaMaxTurns: 24             # max interaction cycles
  cuaHeadless: true           # false to see the browser

Returns:
  finalMessage: "Done! I starred the repo."
  screenshots: ["/tmp/tua-cua-xxx/001-native-turn-1.png", ...]
  usage: { inputTokens: 1234, outputTokens: 567, reasoningTokens: 89 }
```

#### Native Mode vs Code Mode

| Mode       | How It Works                                                 | Best For                                                    |
| ---------- | ------------------------------------------------------------ | ----------------------------------------------------------- |
| **Native** | GPT-5.4 sees screenshots and sends click/type/scroll actions | Interacting with any website as a human would               |
| **Code**   | GPT-5.4 writes and executes JavaScript via Playwright        | Scraping data, filling forms, complex multi-step automation |

### Agent Orchestration

Tau Agent can spawn and manage sub-agents:

- **Max Spawn Depth**: 3 levels
- **Max Children Per Agent**: 8
- Sub-agents inherit skills and memory context
- Each agent has its own session and can run tasks independently

### Memory System

```
Workspace/
├── AGENTS.md          # Agent instructions & routing rules
├── IDENTITY.md        # Agent persona (name, creature, vibe, emoji)
├── USER.md            # User profile
├── MEMORY.md          # Long-term facts (preferences, accounts, devices)
├── SOUL.md            # Persona & boundaries
└── memory/
    ├── 2026-03-07.md  # Today's notes (auto-created)
    └── 2026-03-06.md  # Yesterday's notes
```

**Memory defaults:**

- Memory flush before compaction
- Memory search on sessions
- Daily notes auto-created
- User facts persisted immediately

### Browser Routing Priority

Tau Agent uses this priority order for web tasks:

1. **`browser-use`** — Native Playwright automation via Python
2. **`cua_run`** — GPT-5.4 CUA Responses API (native or code mode)
3. **Computer Use** — `computer_screenshot` → `computer_mouse` → `computer_type` (raw screen interaction)
4. **Chrome Extension Relay** — Fallback via `~/.openclaw/browser/chrome-extension`

### Screen Recording

```
Action: screen_record
Parameters:
  node: "macbook"
  durationMs: 10000    # max 300000 (5 minutes)
  fps: 10
  screenIndex: 0
  includeAudio: true
```

### Device Control

```
Action: device_status     → Battery, storage, network
Action: device_info       → Model, OS version, capabilities
Action: device_permissions → Current permission states
Action: device_health     → System health metrics
Action: location_get      → Current GPS location
Action: notifications_list → Pending notifications
```

---

## 🧩 Skills

Skills are modular capabilities stored in `~/.openclaw/skills/`. Each skill has a `SKILL.md` file with instructions.

### Built-in Tua Skills

| Skill                  | Description                                              |
| ---------------------- | -------------------------------------------------------- |
| `tua-computer-use`     | Full computer control (screenshot, mouse, keyboard, CUA) |
| `tua-orchestra`        | Agent orchestration and sub-agent management             |
| `tua-native-workflows` | Native app integration (Google Docs, Word, etc.)         |

### Skill Sources (Synced Automatically)

| Repository                                                            | Skills                    |
| --------------------------------------------------------------------- | ------------------------- |
| [openai/skills](https://github.com/openai/skills)                     | Official OpenAI skills    |
| [browser-use/browser-use](https://github.com/browser-use/browser-use) | Browser automation skills |
| [BrowserMCP/mcp](https://github.com/BrowserMCP/mcp)                   | Browser MCP integration   |
| [volcengine/OpenViking](https://github.com/volcengine/OpenViking)     | OpenViking AI skills      |
| [steipete/gogcli](https://github.com/steipete/gogcli)                 | Go CLI tools              |
| [superset-sh/superset](https://github.com/superset-sh/superset)       | Superset AI toolkit       |

### Adding Custom Skills

Create a folder under `~/.openclaw/skills/my-skill/` with a `SKILL.md`:

```markdown
---
name: my-custom-skill
description: Does something amazing
---

# My Custom Skill

Instructions for using this skill...
```

---

## 🔧 Configuration

### Default Model

The default model is `openai/gpt-5.4`. This is set during the Ultimate Setup and can be changed in the config:

```json
{
  "model": "openai/gpt-5.4",
  "providers": {
    "openai": { "apiKey": "sk-..." }
  }
}
```

### Execution Safety

All commands require explicit user approval by default:

```
security = full
ask = always
autoAllowSkills = true
```

### Environment Variables

| Variable                      | Required | Description                          |
| ----------------------------- | -------- | ------------------------------------ |
| `OPENAI_API_KEY`              | ✅       | Powers all AI features               |
| `TUA_SKILLS_SOURCE_ROOT`      | ❌       | Override skills source directory     |
| `OPENCLAW_MANAGED_SKILLS_DIR` | ❌       | Override skills install directory    |
| `CUA_RESPONSES_MODE`          | ❌       | CUA mode: `auto`, `fallback`, `live` |

---

## 🛡️ Safety & Security

> ⚠️ **Important**: Tau Agent can control your mouse, keyboard, and browser. Use responsibly.

- **All commands require explicit approval** — nothing runs without your consent
- **Safety checks on CUA actions** — GPT-5.4 safety filters are enforced; any pending safety check will abort the action
- **Sandboxed execution** — CUA code mode runs in a VM context, not directly on your system
- **No data exfiltration** — default rules prohibit sending secrets or private data externally
- **Screen recording consent** — macOS permission required before any screen access

---

## 🏗️ Development

### Project Structure

```
openclaw-main/
├── apps/macos/          # macOS Swift app
├── src/                 # Core TypeScript runtime
│   ├── agents/          # Agent framework
│   │   └── tools/       # All agent tools (nodes-tool, etc.)
│   ├── cli/             # CLI commands
│   ├── config/          # Configuration
│   └── infra/           # Infrastructure utilities
├── ui/                  # Web dashboard
├── scripts/             # Installation scripts
├── skills/              # Built-in skills
└── docs/                # Documentation & templates
```

### Running Tests

```bash
cd openclaw-main
pnpm test
```

### Running Specific Test Files

```bash
pnpm vitest run src/agents/tools/nodes-tool.test.ts
```

### Building

```bash
# TypeScript
pnpm build

# macOS app
cd apps/macos && swift build
```

---

## 👥 Contributors & Credits

Tau Agent stands on the shoulders of these amazing open-source projects. Huge thanks to all contributors:

### Core Framework

| Project                                           | Author/Org                                                      | License | Contribution                                                         |
| ------------------------------------------------- | --------------------------------------------------------------- | ------- | -------------------------------------------------------------------- |
| [OpenClaw](https://github.com/nichochar/openclaw) | [@nichochar](https://github.com/nichochar) (Nicholas Charriere) | MIT     | Core agent framework, gateway, macOS app, skill system, node pairing |

### AI & Automation

| Project                                                                  | Author/Org                                    | License    | Contribution                                                             |
| ------------------------------------------------------------------------ | --------------------------------------------- | ---------- | ------------------------------------------------------------------------ |
| [OpenAI CUA Sample App](https://github.com/openai/openai-cua-sample-app) | [OpenAI](https://github.com/openai)           | MIT        | GPT-5.4 Responses API loop, computer-use actions, Playwright integration |
| [OpenAI Skills](https://github.com/openai/skills)                        | [OpenAI](https://github.com/openai)           | MIT        | Official OpenAI skill definitions                                        |
| [browser-use](https://github.com/browser-use/browser-use)                | [browser-use](https://github.com/browser-use) | MIT        | Python browser automation framework                                      |
| [OpenViking](https://github.com/volcengine/OpenViking)                   | [Volcengine](https://github.com/volcengine)   | Apache-2.0 | AI toolkit and agent capabilities                                        |

### Browser & Tools

| Project                                             | Author/Org                                                   | License | Contribution                   |
| --------------------------------------------------- | ------------------------------------------------------------ | ------- | ------------------------------ |
| [BrowserMCP](https://github.com/BrowserMCP/mcp)     | [BrowserMCP](https://github.com/BrowserMCP)                  | MIT     | Browser MCP server integration |
| [gogcli](https://github.com/steipete/gogcli)        | [@steipete](https://github.com/steipete) (Peter Steinberger) | MIT     | Go CLI toolkit                 |
| [Superset](https://github.com/superset-sh/superset) | [superset-sh](https://github.com/superset-sh)                | MIT     | AI superset toolkit            |

### Skill Repositories

| Project                                                     | Author/Org                                 | License | Contribution                         |
| ----------------------------------------------------------- | ------------------------------------------ | ------- | ------------------------------------ |
| [Anthropic Skills](https://github.com/anthropics/skills)    | [Anthropic](https://github.com/anthropics) | MIT     | Claude skill patterns (referenced)   |
| [Claude Skills](https://github.com/Jeffallan/claude-skills) | [@Jeffallan](https://github.com/Jeffallan) | MIT     | Community Claude skills (referenced) |
| [Agency Agents](https://github.com/agency-agents)           | Community                                  | Various | Agent orchestration patterns         |
| [Awesome OpenClaw Skills](https://github.com/community)     | Community                                  | Various | Community skill collection           |
| [Awesome OpenClaw Usecases](https://github.com/community)   | Community                                  | Various | Community use cases                  |
| [Naruto Skills](https://github.com/community)               | Community                                  | Various | Creative agent skills                |
| [PM Skills](https://github.com/community)                   | Community                                  | Various | Project management skills            |
| [Paperclip](https://github.com/community)                   | Community                                  | Various | Automation patterns                  |

### Key Technologies

| Technology                                     | Purpose                       |
| ---------------------------------------------- | ----------------------------- |
| [Playwright](https://playwright.dev/)          | Browser automation engine     |
| [OpenAI API](https://platform.openai.com/)     | GPT-5.4, Responses API, Codex |
| [SwiftUI](https://developer.apple.com/xiftui/) | macOS native UI               |
| [Node.js](https://nodejs.org/)                 | Runtime engine                |
| [TypeScript](https://www.typescriptlang.org/)  | Type-safe agent logic         |
| [pnpm](https://pnpm.io/)                       | Package management            |

---

## 📄 License

This project integrates multiple open-source components, each with their own licenses. See individual project repositories for specific license terms.

The Tau Agent integration layer is provided as-is for educational and development purposes.

---

## 🗺️ Roadmap

- [ ] Semantic memory search (requires embeddings API)
- [ ] Multi-window CUA support
- [ ] iOS companion app integration
- [ ] Plugin marketplace for skills
- [ ] Voice-activated commands
- [ ] Real-time collaboration between agents

---

<p align="center">
  Built with ❤️ by <a href="https://github.com/shalevamin">@shalevamin</a>
</p>
<p align="center">
  <em>Tau Agent — Because one agent should be able to do everything.</em>
</p>
