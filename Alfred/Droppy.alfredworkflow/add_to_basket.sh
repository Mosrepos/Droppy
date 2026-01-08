#!/bin/bash

# Add selected files to Droppy Basket via URL scheme
# This script is called by Alfred with file paths as arguments

# Build the URL with all file paths
url="droppy://add?target=basket"

for file in "$@"; do
    # URL-encode the path (basic encoding for spaces and special chars)
    encoded_path=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$file', safe=''))")
    url="${url}&path=${encoded_path}"
done

# Open the URL to trigger Droppy
open "$url"
