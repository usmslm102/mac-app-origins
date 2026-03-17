# AppSourceScanner

Native macOS SwiftUI utility that scans installed apps and labels them as:

- `Homebrew`
- `App Store`
- `Manual / Unknown`

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
4. Run the `AppSourceScanner` scheme.

## Run from terminal

```bash
cd /Volumes/T7Shield/Developer/macos-apps/AppSourceScanner
swift run
```

## Notes

- `Move to Trash` only trashes the `.app` bundle. It does not remove support files from `~/Library`.
- If `brew` or `mas` are not installed, the app still works and falls back to receipt-based detection where possible.
