#!/bin/zsh
# Builds the Mac version of Bloom and zips it: the same Release build that
# goes on an iPhone (no dev tools), in a fixed iPhone 16 window (393 × 852).
#
# Usage: scripts/build-mac.sh [output-dir]   (default: ./dist)
# For the judge's version with made-up friends, use build-judge-mac.sh.
set -euo pipefail

root="${0:A:h:h}"
out="${1:-$root/dist}"
derived="$root/build/mac"

xcodebuild \
  -project "$root/SVSD.xcodeproj" \
  -scheme SVSD \
  -configuration Release \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath "$derived" \
  PRODUCT_BUNDLE_IDENTIFIER=com.amberzeng.bloom.demo \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" \
  -quiet build

mkdir -p "$out"
rm -rf "$out/Bloom.app" "$out/Bloom-mac.zip"
ditto "$derived/Build/Products/Release-maccatalyst/SVSD.app" "$out/Bloom.app"
(cd "$out" && ditto -c -k --keepParent Bloom.app Bloom-mac.zip)
echo "Built $out/Bloom-mac.zip"
