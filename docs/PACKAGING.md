# Packaging & Signing Notes — IndexPilot

## Development Build

```bash
# Resolve dependencies and build
swift build --arch arm64

# Run tests
swift test --arch arm64

# Open in Xcode (generate Xcode project from Package.swift)
open Package.swift
# Or: xed .
```

## Creating a .app Bundle

SwiftUI apps built with SPM need a minimal Xcode project wrapper for proper app bundle structure,
entitlements, and notarization. Two approaches:

### Option A: Add an Xcode project

1. Run `xed .` to open the package in Xcode.
2. Xcode will offer to generate an Xcode project — accept.
3. Set Bundle Identifier: `com.yourcompany.IndexPilot`
4. Set Deployment Target: macOS 14.0
5. Under Signing & Capabilities:
   - Enable Automatic Signing with your Apple Developer account
   - Add entitlement: `com.apple.security.network.client` (for URLSession)
   - Add entitlement: `com.apple.security.app-sandbox` (for Mac App Store distribution)
   - Add entitlement: `com.apple.security.files.user-selected.read-write` (for CSV export)
6. Product → Archive → Distribute

### Option B: DIY .app with custom Info.plist (direct distribution)

Create `IndexPilot.app/Contents/`:
```
MacOS/IndexPilot          (the binary)
Info.plist
Resources/
  IndexPilot.icns
_CodeSignature/
```

Minimal `Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.yourcompany.IndexPilot</string>
  <key>CFBundleName</key><string>IndexPilot</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleExecutable</key><string>IndexPilot</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
</dict>
</plist>
```

## Code Signing

```bash
# Sign with Developer ID (for direct distribution outside App Store)
codesign --force --deep \
    --sign "Developer ID Application: Your Name (TEAMID)" \
    --entitlements IndexPilot.entitlements \
    --options runtime \
    IndexPilot.app

# Verify
codesign --verify --verbose=2 IndexPilot.app
spctl --assess --type execute -v IndexPilot.app
```

## Notarization (required for Gatekeeper on macOS 10.15+)

```bash
# Zip for notarization
ditto -c -k --keepParent IndexPilot.app IndexPilot.zip

# Submit to Apple notarization service
xcrun notarytool submit IndexPilot.zip \
    --apple-id your@email.com \
    --team-id YOURTEAMID \
    --password @keychain:AC_PASSWORD \
    --wait

# Staple the notarization ticket
xcrun stapler staple IndexPilot.app
```

## Distribution

For direct distribution (no App Store):
1. Archive → Export → Developer ID
2. Set the export method to "Direct Distribution"
3. Distribute the signed, notarized .app in a DMG or zip

### Create a DMG (optional)

```bash
# Using create-dmg (brew install create-dmg)
create-dmg \
  --volname "IndexPilot" \
  --window-size 600 400 \
  --background "scripts/dmg-background.png" \
  --icon "IndexPilot.app" 150 200 \
  --app-drop-link 450 200 \
  "IndexPilot-0.1.0.dmg" \
  "IndexPilot.app"
```

## Entitlements File

`IndexPilot.entitlements`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
  <!-- Network access for crawling -->
  <key>com.apple.security.network.client</key><true/>
  <!-- Sandbox -->
  <key>com.apple.security.app-sandbox</key><true/>
  <!-- File access for exports -->
  <key>com.apple.security.files.user-selected.read-write</key><true/>
  <!-- Keychain for stored credentials -->
  <key>keychain-access-groups</key>
  <array><string>$(AppIdentifierPrefix)com.yourcompany.IndexPilot</string></array>
</dict>
</plist>
```

## Apple Silicon Performance Notes

- Set `NSQualityOfService = .userInitiated` for the crawl engine task group.
- `URLSession` uses the Network framework automatically on Apple Silicon — uses the Efficiency cores for I/O when the crawl is background-priority.
- SQLite WAL mode (set by GRDB) works well on Apple Silicon's unified memory — no page fault penalty for database reads concurrent with crawl writes.
- The `arm64` architecture target eliminates Rosetta overhead.
- Memory pressure relief: `URLSession` stream downloads (not yet implemented) would reduce peak memory vs buffering the full response body.
