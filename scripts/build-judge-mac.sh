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

mkdir -p "$out"
rm -rf "$out/Bloom.app" "$out/Bloom-demo.zip"
ditto "$derived/Build/Products/Release-maccatalyst/SVSD.app" "$out/Bloom.app"
(cd "$out" && ditto -c -k --keepParent Bloom.app Bloom-demo.zip)
echo "Built $out/Bloom-demo.zip"
