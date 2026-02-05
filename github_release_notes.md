## ✨ New Features
- **Modal Reorder Sheet**: Dedicated reorder panel for shelf and basket items
  - Compact 2-column grid with horizontal rows for more items visible at once
  - Resizable panel with drag handles
  - Modal sovereignty: basket hides when reordering for clear focus
- **Quickshare is now removable**: Disable it like any other extension to hide from menus and quick actions
- **Area Capture mode**: Click-drag-snap selection for capturing any screen region
- **Configurable Editor Shortcuts**: Customize screenshot editor keybindings with Window Snap-style UI
- **Enhanced drag previews** showing actual thumbnails and correct folder icons

## 🔧 Improvements
- **Screenshot Editor** now properly resizable with edge drag handles
- **Screenshot Editor** now respects transparent mode preference
- Simplified floating basket peek animation (removed unnecessary 3D transforms)
- Basket now preserves position when auto-hiding to edge (no more vertical centering jumps)
- Folder drag previews now use custom folder icon with correct pinned state
- Removed experimental "Notch Height" adjustment feature

## ⚡ Performance
- Context menus now use cached sharing services and app lists for faster rendering
- Bulk operations (clear all, remove selected, move to shelf) now skip animations for instant feedback
- Drag preview stack limited to 5 visible items for snappier multi-select drags

## 🐛 Bug Fixes
- Fixed floating basket revealing too early when cursor approaches edge (now requires actual sliver contact)
- Fixed Quick Actions bar collapsing prematurely when drag ends near the bar
- Fixed reorder drag position jumping when items swap positions
- Fixed Quick Actions bar being clipped when dragging files over multi-row shelf
- Fixed Dock folder drags not triggering shelf actions
- Fixed shortcut registration not persisting after restart
- Added cask URL verification to prevent Homebrew version mismatch bugs
- Fixed NotificationHUD crashes from concurrent database access (#152, #156)

---

## Installation

<img src="https://raw.githubusercontent.com/iordv/Droppy/main/docs/assets/macos-disk-icon.png" height="24"> **Recommended: Direct Download** (signed & notarized)

Download `Droppy-10.2.5.dmg` below, open it, and drag Droppy to Applications. That's it!

> ✅ **Signed & Notarized by Apple** — No quarantine warnings, no terminal commands needed.

<img src="https://brew.sh/assets/img/homebrew.svg" height="24"> **Alternative: Install via Homebrew**
```bash
brew install --cask iordv/tap/droppy
```
