---
name: tua-orchestra
description: Conduct multiple agents in parallel. Activate when the user wants delegation, a swarm, a multi-agent workflow, or an orchestra of specialists.
metadata: { "openclaw": { "emoji": "🎼" } }
---

# Tua Orchestra

Use this skill when the task is too broad for one linear agent pass and should be split across workers.

## Primary Tools

- `sessions_spawn` to create workers
- `sessions_send` to assign focused tasks
- `sessions_list` to monitor progress
- `subagents` when a built-in subagent flow is enough

## Strategy

1. Decompose the job into independent workstreams.
2. Give each worker one narrow objective, a clear deliverable, and the right working directory.
3. Keep shared constraints identical across workers.
4. Poll results, merge the outputs, and resolve conflicts centrally.

## Good Worker Shapes

- One worker for UI
- One worker for backend/runtime
- One worker for tests/verification
- One worker for research or docs

## Routing Rules

- If the user wants reusable orchestration, activate the `prose` skill and express the workflow there.
- If a worker should run Codex, Claude Code, Pi, or OpenCode in a separate process, activate the `coding-agent` skill for that worker.
- Keep the conductor agent responsible for synthesis and final quality control.

## Operational Rules

- Do not send the same large context blob to every worker.
- Give each worker the minimum context needed.
- Prefer parallel workers only when their outputs are weakly coupled.
- Re-run a worker with a narrowed prompt if the first result is noisy.
