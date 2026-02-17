# Thaw vs Droppy Floating Bar Audit (Deep Dive)

Date: 2026-02-16
Scope: Full Thaw repo inventory (169 files, 116 Swift), with file/function-level focus on floating/menu bar implementation and direct Droppy deltas.

## Coverage Proof
- Total Thaw files inspected: 169
- Swift files inspected: 116
- Swift files with menu/floating-bar-relevant references: 79
- Full file inventory: `docs/thaw-audit/thaw_full_inventory.tsv`
- Full function/symbol dump: `docs/thaw-audit/thaw_symbols_full.txt`
- Relevance matrix: `docs/thaw-audit/thaw_file_matrix.txt`

## High-Impact Differences (What Thaw does better)

1. Event pipeline reliability for moves/clicks is significantly stronger in Thaw.
- Thaw move/click path uses barriered event confirmation with event taps, adaptive timeout learning, and verified retries:
  - `Thaw/MenuBar/MenuBarItems/MenuBarItemManager.swift:966`
  - `Thaw/MenuBar/MenuBarItems/MenuBarItemManager.swift:1091`
  - `Thaw/MenuBar/MenuBarItems/MenuBarItemManager.swift:1390`
  - `Thaw/MenuBar/MenuBarItems/MenuBarItemManager.swift:1487`
- Droppy uses fixed-step command-drag with sleeps and geometric verification:
  - `Droppy/Extensions/MenuBarManager/MenuBarFloatingBarManager.swift:1639`
  - `Droppy/Extensions/MenuBarManager/MenuBarFloatingBarManager.swift:1727`

Impact:
- Explains “they drag faster / ours misses or jitters under load”.

2. Icon capture correctness is structurally stronger in Thaw.
- Thaw captures exact menu-item windows by window ID, supports composite+individual fallback, validates transparency, and suppresses stale capture during move/reset windows:
  - `Thaw/MenuBar/MenuBarItems/MenuBarItemImageCache.swift:278`
  - `Thaw/MenuBar/MenuBarItems/MenuBarItemImageCache.swift:399`
  - `Thaw/MenuBar/MenuBarItems/MenuBarItemImageCache.swift:439`
  - `Thaw/MenuBar/MenuBarItems/MenuBarItemImageCache.swift:857`
- Droppy captures icon rectangles from display pixels and then heuristically strips menu-bar background:
  - `Droppy/Extensions/MenuBarManager/MenuBarFloatingScanner.swift:342`
  - `Droppy/Extensions/MenuBarManager/MenuBarFloatingScanner.swift:417`

Impact:
- Explains black stripe/background bleed and inconsistent icon fidelity in Droppy.

3. Active-display anchoring is stricter in Thaw; Droppy mixes heuristics and main-screen assumptions.
- Thaw consistently anchors to active menu bar display:
  - `Shared/Bridging/Bridging.swift:149`
  - `Thaw/Utilities/Extensions.swift:514`
  - `Thaw/Events/HIDEventManager.swift:599`
  - `Thaw/MenuBar/MenuBarSection.swift:88`
- Droppy hover and interaction checks use `NSScreen.main` in critical paths:
  - `Droppy/Extensions/MenuBarManager/MenuBarManagerManager.swift:1227`
  - `Droppy/Extensions/MenuBarManager/MenuBarFloatingBarManager.swift:915`
- Droppy panel placement uses `bestScreen(...) ?? NSScreen.main` and pointer bias:
  - `Droppy/Extensions/MenuBarManager/MenuBarFloatingWindows.swift:270`
  - `Droppy/Extensions/MenuBarManager/MenuBarFloatingWindows.swift:298`

Impact:
- Explains floating bar position jumping between displays.

4. Control-item order fix path exists in Droppy but is currently dead code.
- Function defined but no callsites:
  - `Droppy/Extensions/MenuBarManager/MenuBarFloatingBarManager.swift:565`

Impact:
- Explains repeated separator/order drift when always-hidden mode is active.

5. Scanner scope/perf tradeoff is heavier in Droppy.
- Droppy scans owner bundle IDs from all running apps when owner hints are absent:
  - `Droppy/Extensions/MenuBarManager/MenuBarFloatingScanner.swift:220`
  - `Droppy/Extensions/MenuBarManager/MenuBarFloatingScanner.swift:239`
- Thaw starts from process menu bar window list and resolves source PID through dedicated service/caching:
  - `Shared/Bridging/Bridging.swift:382`
  - `Thaw/MenuBar/MenuBarItems/MenuBarItem.swift:221`
  - `MenuBarItemService/SourcePIDCache.swift:227`

Impact:
- Explains slower rescan cycles in certain app-heavy sessions.

## Concrete Upgrade Plan for Droppy

Priority 0 (stability)
- Wire `attemptControlItemOrderFixIfNeeded()` into the runtime flow (likely in `applyPanel()` and post-relocation success path).
- Replace `NSScreen.main` usage in hover/menu-interaction checks with an active-menu-bar-display resolver.

Priority 1 (drag reliability/speed)
- Introduce a barrier-confirmed event posting utility (Thaw-style) for cmd-drag/click operations.
- Keep existing command-drag as fallback only.

Priority 2 (icon fidelity)
- Prefer window-ID captures when possible (or include a second pass using window list + ID mapping) before display-rect stripping.
- Keep current background-removal heuristic only as a fallback.

Priority 3 (scanner performance)
- Keep owner-hinted scans by default.
- Restrict full running-app sweep to explicit refresh/settings-inspection mode.
- Add per-owner warm caches to avoid full AX traversal each cycle.

## Why this upgrades Droppy’s Menu Bar Manager
- Less relocation drift and fewer failed/partial moves.
- Cleaner icons without stripe/bleed artifacts.
- Stable floating bar placement on multi-display setups.
- Lower scan overhead under normal runtime.

## Full-file note
- Every file in Thaw was enumerated and included in the inventory. Non-swift/resource files are included in `thaw_full_inventory.tsv`; Swift files additionally include symbol and relevance counts.
