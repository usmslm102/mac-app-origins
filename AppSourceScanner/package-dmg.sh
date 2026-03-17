rm -rf dist dmg AppSourceScanner.dmg
swift build -c release
mkdir -p dist/AppSourceScanner.app/Contents/MacOS
mkdir -p dist/AppSourceScanner.app/Contents/Resources
cp .build/release/AppSourceScanner dist/AppSourceScanner.app/Contents/MacOS/AppSourceScanner
chmod +x dist/AppSourceScanner.app/Contents/MacOS/AppSourceScanner
mkdir -p dmg
cp -R dist/AppSourceScanner.app dmg/
ln -s /Applications dmg/Applications
hdiutil create -volname "AppSourceScanner" -srcfolder dmg -ov -format UDZO AppSourceScanner.dmg
