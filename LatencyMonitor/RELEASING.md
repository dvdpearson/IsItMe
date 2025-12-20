# How to Release

## Building for Distribution

```bash
xcodebuild -project LatencyMonitor.xcodeproj -scheme LatencyMonitor -configuration Release clean build

# Find the built app
cd /Users/dpearson/Library/Developer/Xcode/DerivedData/LatencyMonitor-*/Build/Products/Release/

# Copy and package
cp -R LatencyMonitor.app ~/Desktop/IsItMe.app
cd ~/Desktop
ditto -c -k --sequesterRsrc --keepParent IsItMe.app IsItMe.zip
```

## Publishing a Release on GitHub

1. Tag the version:
```bash
git tag -a v1.0 -m "Release 1.0"
git push origin v1.0
```

2. Go to GitHub → Releases → Create new release
3. Select the tag (v1.0)
4. Upload `IsItMe.zip`
5. Add release notes
6. Publish

Users download the .zip from GitHub Releases, not from the repo.
