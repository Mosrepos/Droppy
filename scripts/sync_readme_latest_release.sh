#!/bin/bash

set -euo pipefail

REPO_OWNER="iordv"
REPO_NAME="Droppy"
README_PATH="README.md"
START_MARKER="<!-- CHANGELOG_START -->"
END_MARKER="<!-- CHANGELOG_END -->"

if [ ! -f "$README_PATH" ]; then
  echo "README.md not found"
  exit 1
fi

api_url="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"
raw_release_body="$(curl -fsSL "$api_url" | jq -r '.body // empty')"

# Keep only the update notes section; drop installation/license footer blocks
# that are appended to GitHub release descriptions.
release_body="$(printf '%s\n' "$raw_release_body" | awk '
  /^## Installation$/ {exit}
  /^## License$/ {exit}
  {print}
')"

# Remove trailing separator line if it is left right before removed footer.
release_body="$(printf '%s\n' "$release_body" | sed '${/^[[:space:]]*---[[:space:]]*$/d;}')"

if [ -z "$release_body" ]; then
  echo "Latest release body is empty; aborting sync."
  exit 1
fi

start_line="$(grep -n "^${START_MARKER}$" "$README_PATH" | cut -d: -f1 | head -n1 || true)"
end_line="$(grep -n "^${END_MARKER}$" "$README_PATH" | cut -d: -f1 | head -n1 || true)"

if [ -z "$start_line" ] || [ -z "$end_line" ] || [ "$start_line" -ge "$end_line" ]; then
  echo "Could not find valid changelog markers in README.md"
  exit 1
fi

tmp_file="$(mktemp)"

{
  head -n "$start_line" "$README_PATH"
  echo "$release_body"
  tail -n +"$end_line" "$README_PATH"
} > "$tmp_file"

mv "$tmp_file" "$README_PATH"
echo "README latest-release section synced from GitHub release notes."
