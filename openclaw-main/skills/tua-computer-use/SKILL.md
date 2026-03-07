---
name: tua-computer-use
description: Use the paired Mac like a real computer operator. Activate when the task requires screenshots, mouse control, keyboard input, app navigation, or step-by-step desktop automation.
metadata: { "openclaw": { "emoji": "🖱️" } }
---

# Tua Computer Use

Use this skill when the user wants the agent to operate the Mac directly instead of only reading or writing files.

Default browser-stack position:

- Prefer `browser-use` before this skill when pure browser automation is enough.
- Use `tua-computer-use` as the next layer when the task needs the real visible UI, desktop apps, or a logged-in browser session that browser-only automation cannot complete reliably.
- Treat browser extension relay as a later fallback, not the first browser path.

## Tools

Use the `nodes` tool with these actions:

- `computer_screenshot`
- `computer_mouse`
- `computer_type`
- `computer_keypress`

## Operating Loop

Follow a tight observe -> act -> verify loop:

1. Start with `computer_screenshot`.
2. Inspect the current UI state before deciding.
3. Take one small action at a time.
4. Capture another screenshot after every meaningful action.
5. Stop once the requested state is visibly achieved.

This follows the same host-exec loop used by modern computer-use systems: the model chooses an action, the host executes it, then the model verifies the result from a fresh screenshot.

## Coordinate Rules

- `computer_screenshot` returns:
  - `width` / `height`: the actual image dimensions returned to the model
  - `coordinateWidth` / `coordinateHeight`: the coordinate space to click in
  - `screenIndex`: which screen was captured
  - `inputOrigin`: the coordinate origin to use (`topLeft`)
- When clicking from screenshot coordinates, pass `imageWidth` and `imageHeight` back into `computer_mouse`. The node will rescale them to the real screen coordinates.

## Mouse Patterns

- Move without clicking: `computer_mouse` with `mouseAction: "move"`
- Single click: `mouseAction: "click"`
- Double click: `mouseAction: "doubleClick"`
- Scroll: `mouseAction: "scroll"` with `deltaY`
- Use `button: "right"` for context menus

Prefer clicking the center of a visible target, not the edge.

## Keyboard Patterns

- Free text entry: `computer_type`
- Shortcuts and navigation: `computer_keypress`
- Common shortcut examples:
  - `command + c`
  - `command + v`
  - `command + l`
  - `enter`
  - `tab`
  - arrow keys

Prefer keyboard shortcuts when they are more deterministic than mouse travel.

## Safety + Recovery

- If screenshots fail, tell the user Screen Recording permission is missing.
- If mouse/keyboard actions fail, tell the user Accessibility permission is missing.
- If the UI changes unexpectedly, take another screenshot instead of guessing.
- If an action could be destructive, confirm intent before executing it.
