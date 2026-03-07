# Tau Agent Usage Guide

## Operating Model

Tau is designed to behave like an OpenAI-only computer operator:

- `codex` for coding and repo work
- `browser-use` for browser automation
- computer-use for visible desktop workflows
- OpenAI CUA operator console for tracked browser runs
- durable memory written to workspace files

## Daily Commands

Run the gateway in dev mode:

```bash
pnpm gateway:watch
```

Open the operator console:

```bash
tua-cua-dev
```

Run a one-shot coding task with Codex:

```bash
codex exec "Audit this repo and fix the highest priority regression."
```

Inspect memory state:

```bash
openclaw memory status --json
openclaw memory index --force
```

## Browser Work Order

Tau should approach browser tasks in this order:

1. `browser-use`
2. real desktop computer-use
3. browser extension relay only if the first two are not enough

Use cases:

- filling forms
- navigating dashboards
- writing in Google Docs through an existing session
- working in SaaS tools that are already logged in on the machine

## Coding Workflow

For real coding tasks, Tau should prefer:

1. `codex`
2. orchestration / subagents
3. direct manual edits only when the task is small

This repo also seeds routing guidance so coding work is not collapsed into a single manual loop too early.

## Docs Workflow

When asked to create or edit docs:

1. structure content
2. prefer real document workflows
3. use browser/native editing when the user wants an actual document
4. avoid stopping at raw markdown if a real doc is expected

## Memory Workflow

Tau uses workspace memory files:

- `MEMORY.md`
- `memory/YYYY-MM-DD.md`

Rules:

- stable user facts go into `MEMORY.md`
- volatile session discoveries go into the daily note
- if the user says "remember this", Tau should persist it in the same turn

## Dashboard

The dashboard is adapted around Tau concepts:

- OpenAI operator stack
- browser stack policy
- skills mesh
- nodes and devices
- command center navigation

The overview copy explicitly points users to:

- `tua-cua-dev`
- `tua-cua-runner`
- `tua-cua-web`

## OpenAI CUA Console

The bundled OpenAI CUA stack lives here:

```bash
~/.openclaw/tools/openai-cua-sample-app
```

Use it when you want:

- screenshot timeline
- replay bundle
- event stream
- `native` computer-use runs
- `code` mode browser scripting runs

## Permissions And Approvals

Tau seeds aggressive command approval defaults:

- ask always
- security full

That means the agent is prepared for strong local execution, but still surfaces approvals instead of silently bypassing them.

## Updating Tau

Re-run these after pulling new changes:

```bash
node scripts/install-ultimate-toolchain.mjs
node scripts/install-ultimate-skills.mjs
openclaw memory index --force
```
