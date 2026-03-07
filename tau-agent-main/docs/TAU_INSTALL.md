# Tau Agent Installation Guide

## 1. Prerequisites

Install these first:

- macOS
- Node.js `22.x`
- `pnpm`
- Python 3
- Homebrew
- Google Chrome or Chromium if you want the optional extension fallback
- OpenAI API access

Recommended shell setup:

```bash
export PATH="$HOME/.openclaw/bin:$PATH"
export OPENAI_API_KEY="your_openai_key"
```

To make that persistent:

```bash
echo 'export PATH="$HOME/.openclaw/bin:$PATH"' >> ~/.zshrc
echo 'export OPENAI_API_KEY="your_openai_key"' >> ~/.zshrc
source ~/.zshrc
```

## 2. Clone The Repo

```bash
git clone https://github.com/shalevamin/Tau_agent.git
cd Tau_agent
```

## 3. Install JavaScript Dependencies

```bash
pnpm install
```

If you need the UI dependencies explicitly:

```bash
pnpm ui:install
```

## 4. Install Tau Toolchain

This installs the local operator binaries under `~/.openclaw/bin` and the OpenAI CUA sample stack under `~/.openclaw/tools/openai-cua-sample-app`.

```bash
node scripts/install-ultimate-toolchain.mjs
```

What it installs:

- `codex`
- `browser-use`
- `gog`
- `tua-cua-dev`
- `tua-cua-runner`
- `tua-cua-web`

## 5. Install Managed Skills

```bash
node scripts/install-ultimate-skills.mjs
```

Managed skills are copied into:

```bash
~/.openclaw/skills
```

## 6. Run Onboarding

Tau is configured to use OpenAI-only auth choices.

```bash
pnpm openclaw onboard --install-daemon
```

What this should set up:

- default workspace
- daemon install
- OpenAI-authenticated model defaults
- skills loading
- gateway config

## 7. macOS Permissions

Tau needs these macOS permissions for full operator behavior:

- Accessibility
  Required for keyboard and mouse control
- Screen Recording
  Required for screenshots and computer-use verification
- Notifications
  Useful for prompts and desktop feedback

If you use browser automation plus desktop control, grant both Accessibility and Screen Recording.

## 8. Browser Fallback Layer

Tau does not require the Chrome extension for normal operation.

Default browser order:

1. `browser-use`
2. computer-use on the real UI
3. extension relay fallback

If you want the extension fallback anyway:

1. run the Tau browser extension staging flow through the app or CLI
2. open `chrome://extensions`
3. enable `Developer mode`
4. choose `Load unpacked`
5. select the staged extension directory

This is a Chrome limitation, not a Tau limitation.

## 9. Start The Operator Stack

OpenAI operator console:

```bash
tua-cua-dev
```

Runner only:

```bash
tua-cua-runner
```

Web UI only:

```bash
tua-cua-web
```

## 10. Verify Installation

Check binaries:

```bash
which codex
which browser-use
which tua-cua-dev
```

Check managed skills:

```bash
ls ~/.openclaw/skills
```

Check memory status:

```bash
openclaw memory status --json
```

## 11. Optional Source Build Commands

General project build:

```bash
pnpm build
```

Control UI:

```bash
pnpm ui:build
```

macOS app source build:

```bash
cd apps/macos
swift build
```

At the moment, the macOS app build may still fail because of an external `swiftui-math` macro dependency issue. See [TAU_LIMITATIONS.md](TAU_LIMITATIONS.md).
