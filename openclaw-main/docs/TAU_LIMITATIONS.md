# Tau Agent Known Limitations

## 1. `OPENAI_API_KEY` Is Still Required

Codex OAuth is not enough for every OpenAI-backed feature in this stack.

You still need `OPENAI_API_KEY` for:

- live OpenAI CUA runs
- semantic memory embeddings
- full OpenAI API usage outside Codex OAuth paths

Without it:

- memory search falls back to `fts-only`
- CUA installs but live OpenAI runs are not fully usable

## 2. Chrome Extension Fallback Is Manual

Tau does not need the extension for normal browser work.

But if you want the extension fallback layer, Chrome still requires:

1. open `chrome://extensions`
2. enable `Developer mode`
3. `Load unpacked`

That cannot be fully bypassed by a normal local app.

## 3. Current macOS Source Build Gap

In this source snapshot, `swift build` for the macOS app is still blocked by an external dependency issue in `swiftui-math`.

The failure observed is macro-plugin related:

- `SwiftUIMacros.EntryMacro` not found
- `PreviewsMacros.SwiftUIView` not found

This is currently external to the Tau changes in this repo.

## 4. Logged-In SaaS Sessions Still Depend On Real Login State

Tau can reuse existing browser sessions and native app state.

But it cannot legally or silently invent a valid login for:

- Google Docs
- Word/Microsoft 365
- other SaaS accounts

If the machine is already logged in, Tau can use that session.
If not, the user still has to log in for the first time.

## 5. Some Upstream Docs Still Reflect OpenClaw

This repo contains a large upstream documentation tree.

The Tau-specific entry points are:

- `README.md`
- `docs/TAU_INSTALL.md`
- `docs/TAU_USAGE.md`
- `docs/TAU_STACK.md`
- `docs/TAU_LIMITATIONS.md`

Treat those as the Tau-specific source of truth for now.
