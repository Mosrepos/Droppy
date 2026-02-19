## 🚀 Droppy v11.2.2
**New Features**
- Added automatic README latest-release syncing from GitHub Releases via a dedicated GitHub Actions workflow (`release: published/edited` + manual dispatch).
- Added a `scripts/sync_readme_latest_release.sh` updater that pulls the latest release body from GitHub API and refreshes the README changelog block between markers.
- Added dynamic website latest-release rendering on the Features page, so “Latest Release” now fetches and displays current GitHub release notes with local caching and graceful fallbacks.
**Bug Fixes**
- Removed manual README changelog mutation from `release_droppy.sh`, preventing stale/manual mismatch drift and making release-note propagation fully automated.
- Replaced hardcoded latest-release website bullets with live release data bindings, avoiding outdated “What’s New” content after new publishes.
