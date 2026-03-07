# Tau Agent Stack Overview

## Core Direction

Tau is a single-provider operator stack centered on OpenAI.

The goal is:

- one key
- one primary reasoning stack
- native browser and desktop work
- orchestration when tasks get large

## Main Layers

### 1. OpenAI Model Layer

Tau keeps model defaults on OpenAI-family models only.

Primary defaults:

- `openai/gpt-5.4`
- `openai/gpt-5.2`
- `openai/gpt-5-mini`
- `openai-codex/gpt-5.4`
- `openai-codex/gpt-5.2-codex`

### 2. Coding Layer

Primary coding runtime:

- `codex`

This is the preferred coding CLI and should lead for non-trivial repo tasks.

### 3. Browser Layer

Default policy:

1. `browser-use`
2. computer-use on the Mac
3. extension relay fallback

This minimizes dependence on browser extensions and keeps normal automation native.

### 4. OpenAI CUA Layer

Bundled from:

- `https://github.com/openai/openai-cua-sample-app.git`

Installed locally into:

- `~/.openclaw/tools/openai-cua-sample-app`

Launcher commands:

- `tua-cua-dev`
- `tua-cua-runner`
- `tua-cua-web`

### 5. Skills Layer

Managed skill packs come from:

- OpenAI curated/system skills
- browser-use skills
- BrowserMCP repo content
- local Tau/OpenClaw skills

### 6. Memory Layer

Tau persists memory across sessions with:

- `MEMORY.md`
- daily notes under `memory/`
- session-memory hooks
- OpenAI memory search when `OPENAI_API_KEY` is available

### 7. Dashboard Layer

The dashboard exposes:

- Command Center
- Capability Mesh
- nodes/devices status
- skills inventory
- agent count
- OpenAI operator stack references

## Repo Areas To Know

- `apps/macos`
  macOS app and onboarding behavior
- `scripts/install-ultimate-toolchain.mjs`
  local toolchain install
- `scripts/install-ultimate-skills.mjs`
  managed skills sync/install
- `skills/tua-*`
  Tau-specific routing skills
- `ui/src/ui/views/overview.ts`
  dashboard overview copy
- `src/commands`
  onboarding and auth choice behavior

## Practical Meaning

When Tau gets a request, it should generally think like this:

1. Is this a coding task? Use `codex` or orchestration first.
2. Is this a browser task? Use `browser-use`.
3. Does it need the real visible UI? Escalate to computer-use.
4. Does it benefit from the OpenAI operator console and replay pipeline? Use `tua-cua-*`.
5. Only ask for more setup when the machine state really cannot do the job.
