#!/usr/bin/env bash
set -euo pipefail

task_repo_root="$(cd "$(dirname "$0")/.." && pwd)"
task_output="$(mktemp -d)"
task_archive="$task_output/BoltLauncher.xcarchive"

cd "$task_repo_root"

plutil -lint \
  MacAppLauncher/Info.plist \
  MacAppLauncher/MacAppLauncher.entitlements \
  MacAppLauncher/PrivacyInfo.xcprivacy

xcodebuild \
  -project MacAppLauncher.xcodeproj \
  -scheme MacAppLauncher \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$task_output/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  test

xcodebuild \
  -project MacAppLauncher.xcodeproj \
  -scheme MacAppLauncher \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$task_archive" \
  CODE_SIGNING_ALLOWED=NO \
  archive

task_app="$task_archive/Products/Applications/BoltLauncher.app"
task_info="$task_app/Contents/Info.plist"
task_privacy="$task_app/Contents/Resources/PrivacyInfo.xcprivacy"
task_icon="$task_app/Contents/Resources/AppIcon.icns"

test -f "$task_info"
test -f "$task_privacy"
test -f "$task_icon"

test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$task_info")" = \
  'io.github.chengzi0103.boltlauncher'
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$task_info")" = \
  '1.0.0'
test "$(/usr/libexec/PlistBuddy -c 'Print :LSApplicationCategoryType' "$task_info")" = \
  'public.app-category.utilities'
test "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' MacAppLauncher/MacAppLauncher.entitlements)" = \
  'true'

printf 'Unsigned App Store archive validated: %s\n' "$task_archive"
