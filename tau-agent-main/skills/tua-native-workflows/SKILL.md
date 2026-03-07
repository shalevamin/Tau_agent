---
name: tua-native-workflows
description: Route work through native apps, logged-in browser sessions, and real user workflows before requesting extra service-specific API setup. Activate for docs, spreadsheets, SaaS tasks, account-connected workflows, and productivity automation.
metadata: { "openclaw": { "emoji": "🧭" } }
---

# Tua Native Workflows

Use this skill when the user wants the agent to get real work done across browser apps, documents, and logged-in services with minimal manual setup.

## Core Policy

- Prefer existing machine state over fresh integrations.
- Prefer browser/native automation over adding a new API key.
- Prefer one OpenAI provider (`OPENAI_API_KEY`) and use browser sessions for the rest.

## Routing

### Docs / Specs / Proposals

Use this order:

1. `doc-coauthoring` to structure the content
2. `docx`, `xlsx`, `pptx`, or other installed document skills when they fit
3. Native browser workflows with this order: `browser-use` first, then `tua-computer-use`, then extension-backed browser relay only if the earlier paths are insufficient
4. Local apps (Word, browser tabs, Finder-managed files) via computer-use if the task needs the user's existing session

Do not stop at "here is markdown" unless the user explicitly asked for a file instead of an edited document.

### SaaS / Account-Connected Tasks

- If the machine is already logged into the target service in a browser, use that session.
- If a native integration is already configured, use it.
- If neither exists, install or stage the missing local tool when safe and approvals allow.

### Coding Tasks

- For non-trivial coding work, prefer `tua-orchestra` + `coding-agent`.
- Use `codex`, the local OpenAI operator stack (`tua-cua-runner`, `tua-cua-web`, `tua-cua-dev`), and subagents before compressing everything into a single-thread manual edit loop.

## Browser Guidance

- Use this browser order by default: `browser-use` -> `tua-computer-use` -> extension relay / BrowserMCP-style session takeover.
- Treat extension relay as a fallback when the job truly needs an already-open personal tab or a session that the first two layers cannot complete cleanly.
- If the task needs the user's existing browser identity, prefer browser/session-based workflows first and escalate to real-browser computer-use before asking for new credentials.
- Use screenshots and verify each step after mutating web state.

## Authentication Guidance

- Reuse authenticated sessions already present on the machine.
- Avoid requesting many separate vendor API keys when browser/native automation is enough.
- Only ask for new credentials when the task truly requires an API-only capability.
