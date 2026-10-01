#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to the Apple Developer Team ID used for this release}"
command -v xcodegen >/dev/null || { echo "Install XcodeGen with: brew install xcodegen" >&2; exit 1; }
test -f eForms/GoogleService-Info.plist || {
  echo "eForms/GoogleService-Info.plist is required so release Crashlytics is active." >&2
  exit 1
}

xcodegen generate
xcodebuild archive \
  -project eForms.xcodeproj \
  -scheme eForms \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/eForms.xcarchive \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"

xcodebuild -exportArchive \
  -archivePath build/eForms.xcarchive \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath build/export \
  -allowProvisioningUpdates

echo "Export completed in ios/build/export"
