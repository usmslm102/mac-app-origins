# AppOrigins

![AppOrigins icon](assets/apporigins-icon.svg)

Native macOS SwiftUI utility that scans installed apps and labels them as:

- `Homebrew`
- `App Store`
- `Manual / Unknown`

## Unsigned Build Warning

This app is currently unsigned and not notarized.

Use it at your own risk.

macOS may warn you the first time you open it because it is not signed by an identified developer. For personal use, you can usually launch it with `Right Click > Open`, or remove quarantine manually after copying it into `Applications`.

## Current v1 features

- Scans both `/Applications` and `~/Applications`
- Shows app icon, version, bundle ID, source, and path
- Search across app name, source, version, bundle ID, and path
- Filter by source
- Open app
- Reveal app in Finder
- Move app bundle to Trash with confirmation
- Export the current filtered list as CSV or JSON

## Detection

- `brew list --cask` is used to build the Homebrew app list
- `mas list` is used when `mas` is installed
- `mdls -raw -name kMDItemAppStoreHasReceipt` is used as a fallback to detect App Store receipts
- Homebrew matching is heuristic-based, similar to the original shell script

## Open in Xcode

1. Open Xcode.
2. Choose `File > Open...`.
3. Select [Package.swift](/Volumes/T7Shield/Developer/macos-apps/AppSourceScanner/Package.swift).
4. Run the `AppOrigins` scheme.

## Run from terminal

```bash
cd /Volumes/T7Shield/Developer/macos-apps/AppSourceScanner
swift run
```

## Package As DMG

Build the release binary:

```bash
cd /Volumes/T7Shield/Developer/macos-apps/AppSourceScanner
swift build -c release
```

Create the app bundle:

```bash
mkdir -p dist/AppOrigins.app/Contents/MacOS
mkdir -p dist/AppOrigins.app/Contents/Resources
cp .build/release/AppOrigins dist/AppOrigins.app/Contents/MacOS/AppOrigins
chmod +x dist/AppOrigins.app/Contents/MacOS/AppOrigins
cp assets/AppOrigins.icns dist/AppOrigins.app/Contents/Resources/AppOrigins.icns
```

Create `dist/AppOrigins.app/Contents/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>AppOrigins</string>
  <key>CFBundleIdentifier</key>
  <string>com.usamaansari.AppOrigins</string>
  <key>CFBundleName</key>
  <string>AppOrigins</string>
  <key>CFBundleDisplayName</key>
  <string>AppOrigins</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleIconFile</key>
  <string>AppOrigins</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
```

Create the DMG:

```bash
mkdir -p dmg
cp -R dist/AppOrigins.app dmg/
ln -s /Applications dmg/Applications
hdiutil create -volname "AppOrigins" -srcfolder dmg -ov -format UDZO AppOrigins.dmg
```

Install locally:

```bash
open AppOrigins.dmg
```

If Gatekeeper blocks the app after copying it into `Applications`, either use `Right Click > Open` or run:

```bash
xattr -dr com.apple.quarantine /Applications/AppOrigins.app
```

## Free GitHub Release Route

You do not need the Apple Developer Program if you only want to upload an unsigned DMG for personal use.

This repo now includes an unsigned release workflow at `.github/workflows/release-unsigned.yml`.

To trigger it:

```bash
git tag v0.1.0
git push origin v0.1.0
```

That workflow builds `AppOrigins.dmg`, creates a SHA256 checksum, and uploads both files to the GitHub release for that tag.

If you want to do it manually instead, you can still use:

```bash
./package-dmg.sh
```

After building `AppOrigins.dmg`, create a GitHub release and upload it:

```bash
gh release create v0.1.0 AppOrigins.dmg --title "v0.1.0" --notes "Unsigned self-use build."
```

Anyone downloading that release should expect the same unsigned-app warning on macOS.

## Notes

- `Move to Trash` only trashes the `.app` bundle. It does not remove support files from `~/Library`.
- If `brew` or `mas` are not installed, the app still works and falls back to receipt-based detection where possible.
- The repo icon lives at `assets/apporigins-icon.svg`, and the macOS app bundle icon lives at `assets/AppOrigins.icns`.
