# Voice Runtime Externalization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Migrate Voice Transcribe to an external runtime install/update lifecycle using GitHub Releases and local Application Support storage.

**Architecture:** Add a runtime manager that handles manifest fetch, dual-arch artifact selection, checksum/signature verification, and atomic local install. Wire runtime status/actions into Voice Transcribe settings and gate feature usage on installed runtime.

**Tech Stack:** Swift, URLSession, CryptoKit (SHA-256), Process (`tar`/`codesign`), SwiftUI

---

### Task 1: Add runtime installer manager

**Files:**
- Modify: `/Users/jordyspruit/Desktop/Droppy/Droppy/Extensions/VoiceTranscribe/VoiceTranscribeManager.swift`

**Step 1: Define runtime state and manifest models**
- Add `VoiceRuntimeInstallState`.
- Add manifest structs with dual-arch artifacts.

**Step 2: Implement runtime manager**
- Add `VoiceTranscribeRuntimeManager` singleton.
- Add methods: `refresh`, `installOrUpdateRuntime`, `cancelInstall`, `uninstallRuntime`.

**Step 3: Implement verification and install internals**
- Manifest validation.
- SHA-256 verification.
- `codesign` TeamIdentifier validation.
- Atomic install into `~/Library/Application Support/Droppy/Extensions/voiceTranscribe/<version>/`.

**Step 4: Persist runtime install state**
- Save installed version and executable path in UserDefaults.

### Task 2: Wire runtime into extension UI

**Files:**
- Modify: `/Users/jordyspruit/Desktop/Droppy/Droppy/Extensions/VoiceTranscribe/VoiceTranscribeInfoView.swift`

**Step 1: Add runtime section UI**
- Show status and install/update/uninstall controls.
- Show install progress and cancel action.

**Step 2: Connect model install button flow**
- If runtime missing, show install-runtime action before model download.

### Task 3: Gate Voice Transcribe execution on runtime installation

**Files:**
- Modify: `/Users/jordyspruit/Desktop/Droppy/Droppy/Extensions/VoiceTranscribe/VoiceTranscribeManager.swift`
- Modify: `/Users/jordyspruit/Desktop/Droppy/Droppy/Extensions/ExtensionProtocol.swift`
- Modify: `/Users/jordyspruit/Desktop/Droppy/Droppy/ExtensionsShopView.swift`

**Step 1: Add runtime presence guards**
- Guard recording/transcription/model download actions when runtime is missing.

**Step 2: Align installed-state checks**
- Require runtime + model to consider Voice Transcribe installed.

**Step 3: Extend cleanup**
- Remove local runtime on extension cleanup.

### Task 4: Publish runtime release artifacts (manual follow-up)

**Files:**
- External release process (GitHub Releases)

**Step 1: Build and sign helper artifacts for `arm64` and `x86_64`**
**Step 2: Create release and upload assets**
**Step 3: Upload matching manifest JSON asset**
**Step 4: Verify install/update flow from a clean user account**
