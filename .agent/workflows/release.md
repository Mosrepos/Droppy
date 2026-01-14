---
description: Release a new version of Droppy
---

# Release Workflow

// turbo-all

## 1. Get Version Number

Ask user for the version number (e.g., 7.8.0).

## 2. Pre-Release Checklist

Verify before proceeding:

### Entitlements (`Droppy.entitlements`)
- [ ] `com.apple.security.device.audio-input` - Microphone (VoiceTranscribe)
- [ ] `com.apple.security.device.bluetooth` - Bluetooth (AirPods HUD)

### Info.plist Usage Descriptions
- [ ] `NSMicrophoneUsageDescription`
- [ ] `NSBluetoothAlwaysUsageDescription`
- [ ] `NSAccessibilityUsageDescription`

### New Features Check
- [ ] Any new extension added to Supabase `extensions` table?
- [ ] Any new extension added to `docs/extensions.html`?
- [ ] Version number updated in `docs/index.html` footer?

## 3. Generate Release Notes

```bash
# Get last tag
git describe --tags --abbrev=0
```

```bash
# Get commits since last tag
git log $(git describe --tags --abbrev=0)..HEAD --pretty=format:"- %s"
```

Write to `release_notes.txt` with this format:

```
# Droppy vX.X.X

## ✨ New Features
- [Feature description]

## 🐛 Bug Fixes
- [Fix description]

## 🔧 Improvements
- [Improvement description]
```

**Writing style:**
- Natural, human language (not robotic)
- Specific about what changed
- User-focused (what they get, not technical details)
- Concise - respect reader's time

## 4. Run Release Script

```bash
cd /Users/jordyspruit/Desktop/Droppy && ./release_droppy.sh [VERSION] release_notes.txt -y
```

## 5. Post-Release Verification

### Install via Homebrew
```bash
brew upgrade iordv/tap/droppy
```

### Verify Entitlements
```bash
codesign -dv --entitlements - /Applications/Droppy.app 2>&1 | grep -E "(audio-input|bluetooth)"
```

### Smoke Test
- [ ] App launches without permission prompts
- [ ] Shelf works (drag file to notch)
- [ ] Basket works (drag file to screen edge)
- [ ] Clipboard shortcut works
- [ ] Any new features from this release

## 6. Update Marketing (if major release)

- [ ] Update `docs/index.html` version number
- [ ] Add new feature cards if applicable
- [ ] Update README if significant changes
- [ ] Consider social media post (`/social-post`)

## 7. Notify User

Confirm release complete with:
- Version number
- Homebrew updated
- Summary of changes
- Any manual steps needed (e.g., re-enable feature)
