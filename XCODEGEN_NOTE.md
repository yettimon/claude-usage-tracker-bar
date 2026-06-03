# xcodegen Usage Note

Run `./xcodegen.sh` from this directory after adding new Swift files to register them in the Xcode project.

Do **not** run `xcodegen generate` directly — the wrapper script patches the generated `.pbxproj` for Xcode 15.4 compatibility (xcodegen 2.45+ emits `objectVersion = 77` which Xcode 15.4 cannot read; the script downgrades it to `55`).

## Quick reference

```bash
# After adding new Swift files:
cd /Users/dima/Work/claude-usage-tracker/ClaudeUsageTrackerBar
./xcodegen.sh

# Build
xcodebuild build \
  -project ClaudeUsageTrackerBar.xcodeproj \
  -scheme ClaudeUsageTrackerBar \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```
