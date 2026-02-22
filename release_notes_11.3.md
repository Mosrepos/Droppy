## 🚀 Droppy v11.3

This is our biggest Droppy update yet.
`v11.3` brings a brand-new Pomodoro extension, a completely redesigned Extensions Store, deep Floating Bar and Menu Bar Manager reliability improvements, and app-wide Liquid Glass design support across core surfaces and extension windows.

Under the hood, this release also focuses heavily on smoothness and stability: major memory cleanup work, faster opening/closing flows, improved media behavior, and faster Voice + AI runtime handling.

## ✨ New Features

- Added a brand-new **Pomodoro extension** with a notch-first workflow, compact hover timer HUD (High Alert style), and quick focus/break presets.
- Created an all-new **Extensions Store** with a more professional, polished browsing experience.
- Rolled out full **Liquid Glass** styling across major app surfaces: Floating Bar, Floating Basket, Basket Quick Actions, Clipboard surfaces, Settings, Screenshot Editor, Updater, onboarding, and extension windows.
- Reworked **Settings** into a dedicated Liquid Glass window with custom title bar, custom close button, right-side Updates action, and interactive capsule controls.
- Upgraded **Settings search** to a smarter native-style experience with keyword/synonym matching, grouped contextual results, and instant navigation.
- Refined the Settings sidebar to feel closer to macOS with consistent squircle icon badges, unified sizing, and immediate tab selection feedback.
- Added a new **Donate** action in the Settings title bar and a native Donate panel with a “Donate Now” flow.
- Added **alpha** Beats Studio battery integration in the AirPods/Headphones HUD (**not stable yet**).
- Expanded **alpha** Beats compatibility across Solo, Studio, Powerbeats, Fit, BeatsX, and urBeats with improved single-cell and left/right battery handling (**not stable yet**).
- Added AI **Remove Background** directly to Clipboard image context menus, including alerts and automatic insertion of processed results into Clipboard history.
- Added optional **Open editor instantly** for Element Capture, so screenshots can go straight into Screenshot Editor.
- Added in-section drag reordering for Menu Bar Manager icon lanes (Visible/Hidden/Always Hidden/Floating Bar), with persistent Floating Bar order across launches.
- Added real screenshot preview assets for Menu Bar Manager and Pomodoro in the Extensions UI and updated web extension metadata.
- Migrated Voice Transcribe to **Droppy Voice Runtime** (external runtime-helper IPC), removing in-app WhisperKit linkage.
- Moved AI Background Removal to an **on-demand external runtime** via GitHub Releases, reducing bundled app weight.
- Removed extension ratings/reviews across app + website and simplified extension stats to installs-only.
- Renamed **Transparency Mode** to **Liquid Mode** across terminology and release notes.

## 🐞 Bug Fixes

- Fixed drag-jiggle basket behavior: with 1 basket it now opens a second basket, and with 2+ baskets it opens Basket Switcher instead of re-summoning hidden baskets.
- Fixed multi-basket accent refresh issues where handles could briefly lose color after jiggle/switcher actions.
- Fixed Menu Bar Manager hover auto-collapse so touching the upper menu-bar strip no longer collapses it.
- Fixed Menu Bar Manager auto-collapse so moving left within the menu bar after reveal no longer closes it.
- Fixed crowded menu-bar icon detection by supporting shared status windows, real window-region cropping, and improved window discovery.
- Fixed Menu Bar Manager scanning/remap reliability for newly opened apps and shared status windows, removing stale ghost placeholders.
- Hardened Menu Bar Manager persistence with wake/startup recovery guards so transient restarts no longer wipe saved floating/always-hidden selections.
- Improved Menu Bar Manager floating bar reliability (Beta 2): wake self-heal, stronger rescans, better Always Hidden remapping, and removed dashed placeholders in favor of real icon continuity.
- Fixed fullscreen Floating Bar visibility so it only stays shown when the menu bar is actually revealed.
- Reworked Basket Switcher compositing to use a separate dimming window so native Liquid Glass samples real desktop/background correctly.
- Fixed basket photo thumbnails that could appear horizontally compressed after reopen.
- Redesigned Clipboard rendering for better Liquid Glass consistency, speed, reliability, and smoothness.
- Fixed Tag Manager presentation by replacing system sheets with an in-window liquid-glass modal, removing clipped border artifacts and blocking background shortcuts while open.
- Fixed Clipboard preview pane layout so image/video/file previews fill available space (instead of small centered rendering).
- Fixed Clipboard preview corner-radius inconsistencies by standardizing media/document corner behavior.
- Unified extension/settings/clipboard zoom sheet hosting with native liquid-glass chrome and fixed clipped/double top-border artifacts.
- Fixed expanded media visualizer initialization so paused tracks reopen with low/inactive bars instead of full-height bars.
- Reworked album hover behavior to morph into a full source view and removed the older expanded-media parallax hover effect.
- Fixed browser tab-close edge cases that could re-trigger mini/expanded media HUD surfaces after playback ended.
- Fixed stale browser media sessions where closed tabs could still appear as playing.
- Replaced media controls with native SF Symbols-style transitions: smooth play/pause morphing and directional chevron animation for next/previous.
- Fixed lock/unlock HUD on notchless MacBooks by correcting lock-screen HUD window sizing when physical notch height is zero.
- Unified the Lock/Unlock Animation onboarding card styling with the main HUD card style.
- Unified shelf/notch/media/notification/reminders/TermiNotch motion into one consistent animation system.
- Unified app-wide window open/close behavior with warm reopen and faster deferred teardown.
- Reduced hidden-window memory retention window from 20s to 8s and improved transient window cleanup (capture/editor/voice/onboarding/quickshare).
- Fixed clipboard open jank/pop-in by keeping the window warm, reducing list pop-in, and moving hard reclaim to delayed idle cleanup.
- Fixed Clipboard memory retention by tearing down window/view trees on hide and removing eager startup thumbnail warmup.
- Fixed additional memory retention hotspots by bounding metadata/image caches, improving icon cache accounting, and adding stronger reclaim hooks.
- Improved app-wide memory stability by tightening observer/timer lifecycles and reducing background task churn.
- Optimized audio memory pressure with safer runtime pooling.
- Improved Task/Calendar opening smoothness by batching sync updates, reducing recompute/resizing churn, coalescing timeline recomputes, and removing heavy first-open animations.
- Improved Extensions performance by removing full-view rebuilds, lazy-loading rows more efficiently, and reusing cached images to reduce flicker.
- Improved Extensions tab scroll smoothness by reducing hover-triggered redraw churn and stabilizing stack rendering.
- Fixed AI Background Removal reliability by enforcing deterministic install/validation, normalizing problematic inputs (including HEIC), and adding robust timeout/output draining safeguards.
- Fixed AI background runtime install failures by switching to a live checkpoint URL and improving explicit 404 error handling.
- Improved AI Background Removal progress UX in Clipboard so progress appears immediately, advances smoothly, and completes cleanly.
- Improved High Alert readability in light mode with higher-contrast orange for timer/icon/status.
- Unified Screenshot Editor header alignment with Settings/Clipboard while keeping close button behavior intact.
- Standardized Droppy accent blue to match Clipboard selected-row highlight.
- Improved onboarding HUD toggle layout so long labels (for example “Droppy Updates”) no longer clip.
- Renamed Settings sidebar label from “About & Updates” to “About” for cleaner navigation.
- Refined license card design with cleaner hierarchy, polished status badges, and consistent layout.
- Refined Extracted Text window chrome to updater-style custom liquid header by removing native titlebar controls/toolbar strip.
- Improved Voice Transcribe throughput significantly (much faster end-to-end result delivery).
