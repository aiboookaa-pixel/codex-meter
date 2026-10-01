#!/bin/bash
set -euo pipefail

task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
xcodebuild -project CodexMeter.xcodeproj -scheme CodexMeter \
  -configuration Release -derivedDataPath build \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build CODE_SIGNING_ALLOWED=NO

task_app="$task_root/build/Build/Products/Release/CodexMeter.app"
codesign --force --deep --sign - "$task_app"
codesign --verify --deep --strict "$task_app"
mkdir -p dist
task_distribution="$task_root/dist/CodexMeter"
mkdir -p "$task_distribution"
ditto "$task_app" "$task_distribution/CodexMeter.app"
ditto LICENSE "$task_distribution/LICENSE"
ditto README.md "$task_distribution/README.md"
ditto Scriptable "$task_distribution/Scriptable"
ditto docs "$task_distribution/docs"
ditto CONTRIBUTING.md "$task_distribution/CONTRIBUTING.md"
ditto SECURITY.md "$task_distribution/SECURITY.md"
ditto CHANGELOG.md "$task_distribution/CHANGELOG.md"
ditto -c -k --norsrc --keepParent "$task_distribution" dist/CodexMeter-macOS.zip
printf '%s\n' "Built dist/CodexMeter-macOS.zip (ad-hoc signed, not notarized)."
