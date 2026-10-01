#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null || { echo "Install XcodeGen with: brew install xcodegen" >&2; exit 1; }
xcodegen generate

DEVICE="${IOS_SIMULATOR_NAME:-iPhone 16 Pro}"
xcodebuild test \
  -project eForms.xcodeproj \
  -scheme eForms \
  -destination "platform=iOS Simulator,name=${DEVICE}" \
  -derivedDataPath build/DerivedData \
  -resultBundlePath build/eFormsTests.xcresult \
  CODE_SIGNING_ALLOWED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO

