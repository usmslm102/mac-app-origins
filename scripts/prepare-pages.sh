#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Package only the public site. The app, build output, and repository stay out.
rm -rf .pages-dist
mkdir -p .pages-dist/assets
cp site/index.html site/styles.css site/script.js .pages-dist/
cp site/assets/icon.svg site/assets/screenshot.png .pages-dist/assets/
cp demo/demo.gif .pages-dist/assets/demo.gif
touch .pages-dist/.nojekyll
echo "Static site ready in .pages-dist/"
