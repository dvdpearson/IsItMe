# Release Process

## Prerequisites

To create a release without security warnings, you need:

1. **Apple Developer Account** ($99/year)
   - Sign up at https://developer.apple.com

2. **Developer ID Application Certificate**
   - In Xcode: Settings → Accounts → Manage Certificates
   - Click "+" → Select "Developer ID Application"
   - This downloads and installs your certificate

3. **App-Specific Password** (for notarization)
   - Go to https://appleid.apple.com
   - Sign in → App-Specific Passwords → Generate
   - Save this password securely

4. **Team ID**
   - Find it at https://developer.apple.com/account
   - Or run: `xcrun altool --list-providers -u YOUR_APPLE_ID -p YOUR_APP_PASSWORD`

## Quick Release (Automated)

The easiest way to build a signed and notarized release:

```bash
./build-release.sh
```

This script will:
1. Build the app in Release configuration
2. Code sign with your Developer ID
3. Create a .zip archive
4. Guide you through notarization
5. Staple the notarization ticket

Follow the on-screen prompts for notarization.

## Manual Release Process

If you prefer manual control or the script doesn't work:

### 1. Update Version

Edit `IsItMe/Info.plist` and update `CFBundleShortVersionString` (e.g., "1.2.0").

### 2. Build and Sign

```bash
# Set your team ID
TEAM_ID="YOUR_TEAM_ID"

# Build with signing
xcodebuild -project IsItMe.xcodeproj \
  -scheme IsItMe \
  -configuration Release \
  -derivedDataPath ./build \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  clean build
```

### 3. Create Archive

```bash
cd build/Build/Products/Release
ditto -c -k --sequesterRsrc --keepParent IsItMe.app ~/Desktop/IsItMe.zip
```

### 4. Notarize

```bash
# Submit for notarization
xcrun notarytool submit ~/Desktop/IsItMe.zip \
  --apple-id YOUR_APPLE_ID \
  --team-id YOUR_TEAM_ID \
  --password YOUR_APP_SPECIFIC_PASSWORD \
  --wait

# If successful, staple the ticket to the app
xcrun stapler staple build/Build/Products/Release/IsItMe.app

# Recreate the zip with stapled app
cd build/Build/Products/Release
ditto -c -k --sequesterRsrc --keepParent IsItMe.app ~/Desktop/IsItMe.zip
```

### 5. Verify

```bash
# Check code signature
codesign -vvv --deep --strict ~/Desktop/IsItMe.app

# Check notarization
spctl -a -vvv -t install ~/Desktop/IsItMe.app
```

## Publishing a GitHub Release

1. **Commit and tag the version:**
   ```bash
   git add .
   git commit -m "Bump version to 1.2.0"
   git tag -a v1.2.0 -m "Release v1.2.0"
   git push origin main
   git push origin v1.2.0
   ```

2. **Create the release on GitHub:**
   - Go to https://github.com/dvdpearson/IsItMe/releases
   - Click "Create a new release"
   - Select tag: v1.2.0
   - Release title: v1.2.0
   - Upload `IsItMe.zip` (the notarized version)
   - Write release notes describing changes
   - Click "Publish release"

3. **Test the download:**
   - Download the .zip from GitHub
   - Unzip and open the app
   - Should open without security warnings

## Troubleshooting

### "No identity found" error

You need to install a Developer ID Application certificate in Xcode:
- Xcode → Settings → Accounts → Select your account
- Click "Manage Certificates" → "+" → "Developer ID Application"

### Notarization fails

Check the detailed log:
```bash
xcrun notarytool log SUBMISSION_ID \
  --apple-id YOUR_APPLE_ID \
  --team-id YOUR_TEAM_ID \
  --password YOUR_APP_SPECIFIC_PASSWORD
```

Common issues:
- Missing hardened runtime (should be enabled in Xcode project)
- Missing entitlements (should be set in project)
- Unsigned binaries or frameworks

### Users still see security warnings

Make sure you:
1. Signed with Developer ID Application (not development certificate)
2. Successfully notarized with Apple
3. Stapled the notarization ticket
4. Users downloaded the stapled version

### Building without an Apple Developer account

You can build unsigned, but users will see security warnings:

```bash
xcodebuild -project IsItMe.xcodeproj \
  -scheme IsItMe \
  -configuration Release \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  clean build
```

Users will need to right-click → Open to bypass Gatekeeper.
