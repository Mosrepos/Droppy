## Droppy beta v11.2.2

- Fixed drag-jiggle basket behavior: with 1 basket it now opens a second basket, and with 2+ baskets it opens Basket Switcher instead of re-summoning all hidden baskets.
- Fixed a multi-basket UI refresh issue where accent-colored handles could briefly disappear after jiggle/switcher actions; basket accents now update instantly and consistently.
- Fixed Menu Bar Manager hover auto-collapse so touching the upper menu bar strip no longer collapses it, while hover reveal still only triggers on actual menu bar icons.
- Fixed Menu Bar Manager auto-collapse so, after reveal, moving left within the menu bar no longer closes it; it now only auto-collapses after leaving the menu-bar strip.
- Fixed Menu Bar Manager icon detection for crowded menu bars by supporting shared status windows, cropping each icon from its real window region, and improving menu-bar window discovery so real icons no longer drop to fallback placeholders after rescans.
- Fixed Menu Bar Manager scanning/remap reliability for newly opened apps and shared status windows, removed stale ghost placeholder entries.
- Updated Floating Bar Liquid mode to use native macOS 26 liquid-glass styling for a consistent system-like appearance.
- Applied native macOS 26 Liquid Glass to the Floating Basket and Basket Quick Actions, with automatic older-macOS material behavior.
- Reworked Basket Switcher rendering to use a separate dimming window behind the glass panel, so native Liquid Glass now samples the real desktop/background like the Floating Basket and Floating Bar.
- Applied native macOS 26 Liquid Glass styling to Clipboard surfaces (main window, toast, and tag panels), with automatic fallback behavior on older macOS.
- Fixed a CPU drain where clipboard/switcher UI teardown could leave preview resources (including video playback) active after closing, and tightened overlay hosting cleanup to prevent lingering background work.
- Upgraded transparent UI surfaces (Screenshot Editor, Updater, onboarding) to native macOS 26 Liquid Glass.
