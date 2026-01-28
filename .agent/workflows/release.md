---
description: Release a new version of Droppy
---

# Release Workflow

// turbo-all

## 0. Versioning Decision (SemVer)

Before choosing a version number, use this guide:

| Change Type | Version Bump | Example |
|-------------|--------------|---------|
| Bug fix, polish, tweaks | **PATCH** (1.0.X) | "Fixed tooltip overlap" |
| New feature, improvement | **MINOR** (1.X.0) | "Added Smart Export" |
| Breaking change, milestone | **MAJOR** (X.0.0) | "Complete UI redesign" |

**Rule**: Multiple bug fixes = ONE patch release. Don't release v1.0.1, v1.0.2, v1.0.3 in the same day.

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

Write to `release_notes.txt` with this **EXACT** format:

```
📢 Important
- [Any critical announcements, timeline info, or important notices]

✨ New Features
- [Feature description in verb + description format]
- [Another feature]

🐛 Bug Fixes
- [Fix description in verb + description format]
- [Another fix]
```

**Formatting rules:**
- Section headers use emoji prefix (📢 ✨ 🐛)
- Bullet points for each item
- Verb + description format (e.g., "Added X", "Fixed Y", "Improved Z")
- Omit sections with no items (e.g., skip Important if nothing critical)
- Natural, human language - concise but specific

Also write to `github_release_notes.md` with this **EXACT** footer template:

```markdown
---

## Installation

<img src="https://raw.githubusercontent.com/iordv/Droppy/main/docs/assets/macos-disk-icon.png" height="24"> **Recommended: Direct Download** (signed & notarized)

Download `Droppy-[VERSION].dmg` below, open it, and drag Droppy to Applications. That's it!

> ✅ **Signed & Notarized by Apple** — No quarantine warnings, no terminal commands needed.

<img src="https://brew.sh/assets/img/homebrew.svg" height="24"> **Alternative: Install via Homebrew**
\`\`\`bash
brew install --cask iordv/tap/droppy
\`\`\`
```

**IMPORTANT:** Always use the signed/notarized template above. Never include quarantine removal instructions.

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
