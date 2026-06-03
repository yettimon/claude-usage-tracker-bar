#!/bin/bash
# Wrapper around xcodegen that patches the generated project for Xcode 15.4 compatibility.
# Run this script instead of `xcodegen generate` after adding new Swift files.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PBXPROJ="$SCRIPT_DIR/ClaudeUsageTrackerBar.xcodeproj/project.pbxproj"

echo "Running xcodegen..."
xcodegen generate --project "$SCRIPT_DIR" --spec "$SCRIPT_DIR/project.yml"

echo "Patching project for Xcode 15.4 compatibility..."
# Xcode 15.4 only supports up to objectVersion 55; xcodegen 2.45+ generates 77.
sed -i '' 's/objectVersion = 77;/objectVersion = 55;/' "$PBXPROJ"
sed -i '' '/preferredProjectObjectVersion = [0-9]*;/d' "$PBXPROJ"

echo "Done. Project ready for Xcode 15.4."
