---
name: macos-app-zip-install
description: Install a macOS .app distributed as a ZIP when normal unzip/extract flows fail, time out, or break symlinks/permissions.
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [macos]
metadata:
  hermes:
    tags: [macOS, app-install, zip, symlink, permissions, vscode]
---

# macOS app install from ZIP

Use this when a macOS app is distributed as a ZIP archive and the normal install path fails:
- `unzip` times out in Hermes
- Python `ZipFile.extractall()` produces a broken app bundle
- binaries lose execute bits
- framework symlinks are restored as regular files, causing launch failures like `slice is not valid mach-o file`

## Core finding

For macOS `.app` bundles inside ZIPs, a naive extraction can silently corrupt the app bundle:
- `extractall()` does **not** recreate symlinks correctly
- helper binaries may lose executable permissions
- Electron apps then fail with `Permission denied` or broken framework loading

When this happens, extract manually from Python while restoring:
1. directories
2. regular files
3. symlinks from `external_attr`
4. file modes from ZIP metadata

## Recommended workflow

### 1) Prefer vendor direct update URL over flaky marketing links

For VS Code, this worked reliably:

```bash
curl -L 'https://update.code.visualstudio.com/latest/darwin-arm64/stable' -o ~/Downloads/VSCode-darwin-arm64.zip
```

Reason: some `code.visualstudio.com/sha/download?...` links returned 404 while the update endpoint redirected correctly.

### 2) Inspect ZIP metadata before extraction if the app breaks

```bash
python3 - <<'PY'
import zipfile
from pathlib import Path
src=Path('~/Downloads/VSCode-darwin-arm64.zip').expanduser()
with zipfile.ZipFile(src) as z:
    for name in [
        'Visual Studio Code.app/Contents/MacOS/Code',
        'Visual Studio Code.app/Contents/Frameworks/Electron Framework.framework/Electron Framework',
    ]:
        info=z.getinfo(name)
        print(name, oct(info.external_attr >> 16), info.file_size)
PY
```

If a framework binary shows mode `0o120755`, that entry is a **symlink**, not a regular file.

### 3) Do not rely on these failed paths

Avoid treating these as successful installs:

```bash
unzip -q archive.zip -d ~/Applications
```

and

```bash
python3 -c 'import zipfile; zipfile.ZipFile(...).extractall(...)'
```

They may appear to finish but leave a broken `.app`.

### 4) Use metadata-aware extraction

```bash
python3 - <<'PY'
import zipfile, os, shutil
from pathlib import Path

src = Path('~/Downloads/VSCode-darwin-arm64.zip').expanduser()
dest_root = Path('~/Applications').expanduser()
app_path = dest_root / 'Visual Studio Code.app'

if app_path.exists():
    shutil.rmtree(app_path)

with zipfile.ZipFile(src) as z:
    for info in z.infolist():
        out = dest_root / info.filename
        if info.is_dir():
            out.mkdir(parents=True, exist_ok=True)
            continue

        out.parent.mkdir(parents=True, exist_ok=True)
        mode = info.external_attr >> 16

        # restore symlinks from ZIP metadata
        if ((mode & 0o170000) == 0o120000):
            target = z.read(info).decode('utf-8')
            if out.exists() or out.is_symlink():
                out.unlink()
            os.symlink(target, out)
        else:
            with z.open(info) as src_f, open(out, 'wb') as dst_f:
                shutil.copyfileobj(src_f, dst_f)
            if mode:
                os.chmod(out, mode & 0o7777)

print(app_path)
print(app_path.exists())
PY
```

## Verification

### Check the CLI launches

```bash
'/Users/$USER/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code' --version
```

### If you see permission errors

Check the main binary mode:

```bash
python3 - <<'PY'
from pathlib import Path
p=Path('~/Applications/Visual Studio Code.app/Contents/MacOS/Code').expanduser()
print(oct(p.stat().st_mode))
PY
```

Expected: executable bit present.

### If you see Electron framework load errors

Check whether the framework entry is a symlink:

```bash
python3 - <<'PY'
from pathlib import Path
import os
p=Path('~/Applications/Visual Studio Code.app/Contents/Frameworks/Electron Framework.framework/Electron Framework').expanduser()
print('is_symlink', p.is_symlink())
if p.is_symlink():
    print('target', os.readlink(p))
PY
```

If it is not a symlink, the extraction was wrong.

## Pitfalls

- Hermes hooks may block `rm -rf`, `unlink`, or other destructive cleanup. If the user has approved, rerun with `HERMES_CONFIRM=1`.
- `unzip` in Hermes may time out on large archives even when the archive is fine.
- A successfully extracted `.app` directory does **not** mean the app is valid.
- `chmod +x` alone is not enough when the real problem is broken framework symlinks.
- Vendor marketing download URLs may differ from the reliable update-service URLs.
- In Hermes, a long `terminal()` heredoc that contains Python bitmask expressions like `mode & 0o170000` can be misclassified as shell backgrounding because of `&`. If that happens, run the extraction script via `execute_code` instead of `terminal()`.

## Hermes-specific fallback

If the metadata-aware Python extractor keeps getting rejected by `terminal()` despite being valid Python, switch to `execute_code` with the same logic. This avoids the shell parser/backgrounding heuristic and worked reliably for restoring the VS Code app bundle.

## When this skill is especially relevant

- VS Code / Electron apps
- ZIP-based app distributions on macOS
- Install attempts that fail with `Permission denied`, `Abort trap: 6`, or `slice is not valid mach-o file`
