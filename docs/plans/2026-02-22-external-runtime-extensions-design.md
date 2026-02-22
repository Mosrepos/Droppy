# External Runtime Extensions Design

**Date:** 2026-02-22  
**Scope:** First migration pass for install-on-demand extension runtime delivery (Voice Transcribe first)

## Goal
Keep Droppy lean by moving heavy extension runtimes out of the base app bundle and installing them only when users explicitly install the extension.

## Approach
1. Keep extension metadata/UI in-app.
2. Deliver extension runtime artifacts via GitHub Releases.
3. Install runtime artifacts into `~/Library/Application Support/Droppy/Extensions/<extension-id>/<version>/`.
4. Verify SHA-256 and Team ID signature before activation.
5. Preserve offline use after install (runtime executes from local disk only).

## Runtime Contract (Voice Transcribe)
Manifest URL:
- `https://github.com/iordv/Droppy/releases/download/voice-runtime/voice-transcribe-runtime-manifest.txt`

Manifest fields:
- `id`, `version`, `protocolVersion`, `minAppVersion`, `executableName`
- `artifacts[]` with `arch`, `url`, `sha256`, `sizeBytes`, `teamID`

Architecture support:
- `arm64`
- `x86_64`

## Install Safety
Install flow is strict and atomic:
1. Fetch and decode manifest.
2. Select artifact by current architecture.
3. Download runtime archive.
4. Verify SHA-256 digest.
5. Extract archive.
6. Locate executable and verify code signature TeamIdentifier.
7. Atomically move staged runtime to the versioned Application Support location.
8. Persist installed version + executable path locally.

No runtime fallback path is used for this extension in this migration path.

## Update/Uninstall
- Updates are explicit: compare installed version with manifest version and present update action.
- Uninstall removes local runtime files and state keys.

## Rollout
- Step 1: Voice Transcribe runtime manager + UI controls.
- Step 2: Publish signed dual-arch runtime artifacts to GitHub Releases.
- Step 3: Validate with internal users.
- Step 4: Apply same runtime pattern extension-by-extension.
