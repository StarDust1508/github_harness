---
name: ai-engineer-coach-install
description: "Установка Microsoft AI Engineer Coach локально на macOS, включая частую ошибку: это расширение VS Code, а не отдельное приложение. Используй, когда просят поставить AI Engineer Coach на Mac."
version: 1.0.0
author: Hermes Agent
license: MIT
---

# AI Engineer Coach install

## When to use

Use when the user wants Microsoft's AI Engineer Coach installed locally on Mac.

## What it actually is

AI Engineer Coach is **not** a standalone macOS app. It is a **VS Code extension** (`.vsix`).

Repo:
- `https://github.com/microsoft/AI-Engineering-Coach`

## Prerequisites

- `git`
- `node`
- `npm`
- A supported editor installed locally:
  - `Visual Studio Code` 1.118+
  - or a compatible environment if the extension explicitly supports it
- Prefer `code` CLI available in PATH for automated install

## Workflow

1. Clone the repo exactly:
   ```bash
   git clone https://github.com/microsoft/AI-Engineering-Coach.git
   ```
2. Read `README.md` and `package.json` first to confirm install mode and engine requirements.
3. Check editor compatibility before doing extra work:
   - Cursor may be installed but still unusable because its embedded VS Code engine is too old.
   - Compare the extension requirement (currently `vscode ^1.118.0`) against the actual editor engine version.
4. Install deps:
   ```bash
   npm install
   ```
5. Package the extension:
   ```bash
   npm run package
   ```
6. Confirm the generated VSIX exists, e.g.:
   - `ai-engineer-coach-0.1.0.vsix`
7. If `code` exists, install via:
   ```bash
   code --install-extension /absolute/path/to/ai-engineer-coach-*.vsix
   ```
   If `code` is not in PATH but VS Code is installed, use the app-bundle CLI directly:
   ```bash
   '/Users/$USER/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code' --install-extension /absolute/path/to/ai-engineer-coach-*.vsix
   ```
8. Then in VS Code run:
   - `AI Engineer Coach: Open Dashboard`

## macOS checks

Before promising a full install, verify both:

```bash
command -v code
```

and whether the app exists under typical paths:
- `/Applications/Visual Studio Code.app`
- `~/Applications/Visual Studio Code.app`
- if relevant, `Cursor.app`

Also verify the actual editor version/engine, not just app presence:
- Cursor can be present but incompatible even when the extension builds fine.
- On this workflow, Cursor 3.5.17 exposed VS Code engine 1.105.1, which is too old for `^1.118.0`.
- A separately installed VS Code 1.121.0 worked for extension installation.

If VS Code must be installed manually from a ZIP on macOS and normal shell unzip/extract behaves badly, Python zip extraction that preserves symlinks/permissions is a viable fallback. User-local install under `~/Applications/Visual Studio Code.app` is acceptable.

## Key pitfalls

- User may think this is a downloadable Mac app. Correct that early: it is a VS Code extension.
- Repo name is case-sensitive in docs and uses `AI-Engineering-Coach`.
- Build can succeed even when install cannot proceed because `code` CLI or VS Code itself is missing.
- Cursor may look like a VS Code-compatible editor but still fail on `engines.vscode` mismatch; check the embedded engine version explicitly.
- If VS Code is manually installed under `~/Applications`, the working CLI may be only inside the app bundle rather than in PATH.
- First-launch VS Code screens like Release Notes can interfere with UI automation; successful install should be verified from CLI (`--list-extensions --show-versions`) before assuming the dashboard command failed because install failed.
- If destructive cleanup like `rm -rf AI-Engineering-Coach` is needed before reclone, Hermes terminal hooks may require explicit user approval.
- Successful packaging alone does **not** mean the tool is usable; editor presence must be verified.
- The dashboard will only be useful if the user's AI coding activity actually leaves compatible local logs; otherwise results will be partial.

## Verification

Minimum success criteria:

1. `npm run package` completes successfully.
2. A `.vsix` file is present.
3. `code --install-extension ...` succeeds.
4. `code --list-extensions --show-versions` shows `ai-engineer-coach.ai-engineer-coach@...`.
5. The command palette shows `AI Engineer Coach: Open Dashboard`.

If install succeeds but UI automation does not surface the dashboard, separate the problem into:
- extension install/registration
- VS Code window focus / command-palette interaction
- actual dashboard data availability

If step 1-2 pass but 3-5 fail due to missing editor, report that installation is blocked by environment, not by the extension build.

## Translation / i18n

See [`references/translation-pitfalls.md`](references/translation-pitfalls.md) for lessons on translating the extension's Preact/htm UI strings — escaping, bundle structure, esbuild quirks, and VS Code reload flow.
