---
name: tua-openai-operator
description: Run Tau's local OpenAI operator console and GPT-5.4 computer-use stack. Activate when a task needs the OpenAI CUA sample app, browser lab automation, or a dedicated operator console instead of ad-hoc browser steps.
metadata: { "openclaw": { "emoji": "🧠" } }
---

# Tua OpenAI Operator

Use this skill when the job is best handled through Tau's bundled OpenAI operator stack instead of a one-off browser loop.

## Local Stack

- Repo path: `~/.openclaw/tools/openai-cua-sample-app`
- Launcher commands:
  - `tua-cua-dev`
  - `tua-cua-runner`
  - `tua-cua-web`

## Default Model Policy

- Use OpenAI-family models only.
- Prefer `gpt-5.4` for native computer-use runs.
- Keep `OPENAI_API_KEY` as the single required key when possible.

## When To Use It

- The task needs a dedicated operator console with screenshots, replay, and event streaming.
- You want OpenAI Responses computer-use (`native`) or a browser REPL (`code`) against a controlled web workspace.
- The user wants a browser task validated step-by-step instead of a blind automation run.

## Execution Notes

1. Start the runner or combined dev stack if it is not already running.
2. Use `native` mode for direct computer-use actions.
3. Use `code` mode when Playwright scripting is more deterministic than raw clicks.
4. Review screenshots, activity, and replay artifacts before declaring the task done.

## Interaction With Tau Browser Policy

- Tau still prefers `browser-use` for ordinary browser work.
- Escalate to this skill when the task benefits from the dedicated OpenAI operator console and replay pipeline.
- If the user needs an already-open personal browser session, escalate to `tua-computer-use` before extension relay.
