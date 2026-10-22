#!/bin/zsh
# Builds the judge's Mac version of Bloom and zips it.
#
# It's the Release app with JUDGE_DEMO on: two made-up friends (Nora and Leo)
# instead of real people, and a note on first launch about what's simulated.
# It has its own bundle ID, so it never mixes with the everyday build.
#
# Usage: scripts/build-judge-mac.sh [output-dir]   (default: ./dist)
set -euo pipefail

root="${0:A:h:h}"
out="${1:-$root/dist}"
derived="$root/build/judge-mac"

xcodebuild \
  -project "$root/SVSD.xcodeproj" \
  -scheme SVSD \
  -configuration Release \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath "$derived" \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS="JUDGE_DEMO" \
  PRODUCT_BUNDLE_IDENTIFIER=com.amberzeng.bloom.judge \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" \
  -quiet build

# What the judge unzips: the app, the instructions for getting past
# Gatekeeper, and the screenshots those refer to. An unsigned app is blocked
# on first launch, so the way through ships beside it rather than in a message
# that can get separated from the download.
mkdir -p "$out"
rm -rf "$out/Bloom" "$out/Bloom-demo.zip"
mkdir -p "$out/Bloom"
ditto "$derived/Build/Products/Release-maccatalyst/SVSD.app" "$out/Bloom/Bloom.app"
ditto "$root/judge-package" "$out/Bloom"
find "$out/Bloom" -name .DS_Store -delete
(cd "$out" && ditto -c -k --sequesterRsrc --keepParent Bloom Bloom-demo.zip)
# Bloom-for-Mac.zip is the name the judge build gets shared under. Keep it in
# step here, or it silently goes stale while the other zips are rebuilt.
cp "$out/Bloom-demo.zip" "$out/Bloom-for-Mac.zip"
echo "Built $out/Bloom-demo.zip"
