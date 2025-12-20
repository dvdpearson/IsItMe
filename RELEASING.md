# Release Process

## Building for Distribution

1. Build the release version:
```bash
xcodebuild -project IsItMe.xcodeproj -scheme IsItMe -configuration Release clean build
```

2. Locate the built app:
```bash
cd ~/Library/Developer/Xcode/DerivedData/IsItMe-*/Build/Products/Release/
```

3. Create distribution package:
```bash
ditto -c -k --sequesterRsrc --keepParent IsItMe.app ~/Desktop/IsItMe.zip
```

## Publishing a GitHub Release

1. Tag the version:
```bash
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0
```

2. Create the release on GitHub:
   - Go to Releases → Create new release
   - Select the tag (e.g., v1.0.0)
   - Upload `IsItMe.zip`
   - Write release notes
   - Publish

Users download the .zip from GitHub Releases.
