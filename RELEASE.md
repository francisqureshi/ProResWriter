# SourcePrint Release Process

## Quick Start

### 1. Build the App
```bash
./build-sourceprint.sh
```

### 2. Release to GitHub + Sparkle
```bash
./release-sourceprint.sh
```

The script will prompt you for release notes, then automatically:
- ✅ Package the app as a signed zip
- ✅ Create GitHub release
- ✅ Update appcast.xml with Sparkle signature
- ✅ Commit and push to GitHub

Wait ~2 minutes for GitHub CDN to refresh, then users can update!

---

## Version Management

Version numbers are managed in Xcode:
- **Marketing Version** (`CFBundleShortVersionString`): e.g., `0.1.4`
- **Build Number** (`CFBundleVersion`): Auto-increments on each build (e.g., `45`)

To update the marketing version:
```bash
# Edit in Xcode project settings, or:
vim SourcePrint/SourcePrint.xcodeproj/project.pbxproj
# Find: MARKETING_VERSION = 0.1.4;
# Change to your new version
```

---

## Manual Release (if needed)

If you need to manually release:

### 1. Package & Sign
```bash
cd SourcePrint/build/Build/Products/Release
ditto -c -k --sequesterRsrc --keepParent SourcePrint.app SourcePrint-VERSION.zip
```

### 2. Get Sparkle Signature
```bash
SourcePrint/build/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update SourcePrint-VERSION.zip
# Copy the edSignature and length values
```

### 3. Create GitHub Release
```bash
gh release create vVERSION SourcePrint-VERSION.zip --title "..." --notes "..."
```

### 4. Update appcast.xml
Add the new version entry with:
- `sparkle:version` = Build number (CFBundleVersion)
- `sparkle:shortVersionString` = Marketing version
- `sparkle:edSignature` = From step 2
- `length` = From step 2

### 5. Commit & Push
```bash
git add appcast.xml
git commit -m "Release vVERSION"
git push
```

---

## Sparkle Configuration

### Public Key (in Info.plist)
```
SUPublicEDKey: 7Gzr9LEfP3ZrSaHS6XqWPjU6x/GtNWzwAUTFfEAr5wI=
```

### Private Key (in macOS Keychain)
Account: `ed25519`
Service: Sparkle EdDSA signing key

### Feed URL
```
https://raw.githubusercontent.com/francisqureshi/ProResWriter/main/appcast.xml
```

---

## Code Signing Notes

SourcePrint uses **adhoc signing** with the following entitlement:

```xml
<key>com.apple.security.cs.disable-library-validation</key>
<true/>
```

This allows the app to load FFmpeg libraries from Homebrew without full Apple Developer signing.

Build settings:
```bash
CODE_SIGN_IDENTITY="-"
ENABLE_HARDENED_RUNTIME=YES
```

---

## Testing Updates

1. Install an older version of SourcePrint
2. Run `./release-sourceprint.sh` to create a new version
3. Wait ~2 minutes for GitHub CDN
4. In the app: **SourcePrint → Check for Updates...**
5. Verify the update downloads and installs correctly

---

## Troubleshooting

### "App is damaged" error
```bash
xattr -cr /Applications/SourcePrint.app
```

### FFmpeg library not loading
Check that the entitlement is present:
```bash
codesign -d --entitlements :- /Applications/SourcePrint.app
```

Should show: `com.apple.security.cs.disable-library-validation`

### Update not detected
- Check appcast.xml is committed and pushed
- Wait 2-5 minutes for GitHub CDN refresh
- Verify build number in appcast > installed build number
- Check Console.app for Sparkle logs

---

## Release Checklist

- [ ] Update version in Xcode if needed
- [ ] Run `./build-sourceprint.sh`
- [ ] Test the built app launches successfully
- [ ] Run `./release-sourceprint.sh`
- [ ] Enter meaningful release notes
- [ ] Verify GitHub release created
- [ ] Wait ~2 minutes for CDN refresh
- [ ] Test update from previous version
- [ ] Announce release!
