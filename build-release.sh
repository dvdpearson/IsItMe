#!/bin/bash

# IsItMe Release Build Script
# This script builds, signs, and notarizes the app for distribution

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}IsItMe Release Builder${NC}"
echo "======================================"

# Configuration
APP_NAME="IsItMe"
SCHEME="IsItMe"
CONFIGURATION="Release"
PROJECT="IsItMe.xcodeproj"

# Check for required tools
if ! command -v xcodebuild &> /dev/null; then
    echo -e "${RED}Error: xcodebuild not found. Please install Xcode.${NC}"
    exit 1
fi

# Get version from Info.plist
VERSION=$(defaults read "$(pwd)/IsItMe/Info.plist" CFBundleShortVersionString)
echo -e "Building version: ${GREEN}${VERSION}${NC}"
echo ""

# Check if we have a developer identity for signing
IDENTITY_LINE=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1)
IDENTITY=$(echo "$IDENTITY_LINE" | awk -F'"' '{print $2}')
TEAM_ID=$(echo "$IDENTITY_LINE" | grep -o '([A-Z0-9]\{10\})' | tr -d '()')

if [ -z "$IDENTITY" ]; then
    echo -e "${YELLOW}Warning: No 'Developer ID Application' certificate found.${NC}"
    echo "You need an Apple Developer account and certificate to avoid security warnings."
    echo ""
    echo "Options:"
    echo "1. Get an Apple Developer account at https://developer.apple.com"
    echo "2. Build unsigned (users will see security warnings)"
    echo ""
    read -p "Continue with unsigned build? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
    SIGN_APP=false
else
    echo -e "Found signing identity: ${GREEN}${IDENTITY}${NC}"
    echo -e "Team ID: ${GREEN}${TEAM_ID}${NC}"
    SIGN_APP=true
fi

echo ""
echo "Step 1: Building..."

# Clean and build
if [ "$SIGN_APP" = true ]; then
    xcodebuild -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        clean build \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGN_IDENTITY="$IDENTITY" \
        DEVELOPMENT_TEAM="$TEAM_ID" \
        CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
        OTHER_CODE_SIGN_FLAGS="--timestamp" \
        | xcpretty || xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" clean build CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO OTHER_CODE_SIGN_FLAGS="--timestamp"
else
    xcodebuild -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        clean build \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_REQUIRED=NO \
        | xcpretty || xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" clean build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO
fi

# Find the built app
BUILD_DIR=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" -showBuildSettings | grep " BUILD_DIR = " | awk '{print $3}')
APP_PATH="${BUILD_DIR}/${CONFIGURATION}/${APP_NAME}.app"

if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}Error: Built app not found at ${APP_PATH}${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Build successful${NC}"
echo ""

# Create output directory
OUTPUT_DIR="$(pwd)/release"
mkdir -p "$OUTPUT_DIR"

ZIP_NAME="${APP_NAME}-${VERSION}.zip"
ZIP_PATH="${OUTPUT_DIR}/${ZIP_NAME}"

echo "Step 2: Creating archive..."

# Create zip using ditto (preserves code signature)
cd "${BUILD_DIR}/${CONFIGURATION}"
ditto -c -k --sequesterRsrc --keepParent "${APP_NAME}.app" "$ZIP_PATH"

echo -e "${GREEN}✓ Archive created: ${ZIP_PATH}${NC}"
echo ""

# Notarization (only if signed)
if [ "$SIGN_APP" = true ]; then
    echo "Step 3: Notarization..."
    echo ""
    echo "To notarize (required to avoid security warnings):"
    echo "1. Create an app-specific password at https://appleid.apple.com"
    echo "2. Run:"
    echo ""
    echo -e "   ${YELLOW}xcrun notarytool submit \"${ZIP_PATH}\" \\${NC}"
    echo -e "   ${YELLOW}     --apple-id YOUR_APPLE_ID \\${NC}"
    echo -e "   ${YELLOW}     --team-id YOUR_TEAM_ID \\${NC}"
    echo -e "   ${YELLOW}     --password YOUR_APP_SPECIFIC_PASSWORD \\${NC}"
    echo -e "   ${YELLOW}     --wait${NC}"
    echo ""
    echo "3. After notarization succeeds, staple the ticket:"
    echo ""
    echo -e "   ${YELLOW}xcrun stapler staple \"${APP_PATH}\"${NC}"
    echo -e "   ${YELLOW}ditto -c -k --sequesterRsrc --keepParent \"${APP_PATH}\" \"${ZIP_PATH}\"${NC}"
    echo ""

    read -p "Do you want to notarize now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        read -p "Apple ID: " APPLE_ID
        read -p "Team ID: " TEAM_ID
        read -sp "App-specific password: " APP_PASSWORD
        echo ""

        echo "Submitting for notarization..."
        NOTARY_OUTPUT=$(xcrun notarytool submit "$ZIP_PATH" \
            --apple-id "$APPLE_ID" \
            --team-id "$TEAM_ID" \
            --password "$APP_PASSWORD" \
            --wait 2>&1)

        echo "$NOTARY_OUTPUT"

        # Check if notarization was actually accepted (not just that the command succeeded)
        if echo "$NOTARY_OUTPUT" | grep -q "status: Accepted"; then
            echo -e "${GREEN}✓ Notarization successful${NC}"
            echo "Stapling ticket..."
            xcrun stapler staple "$APP_PATH"

            if [ $? -eq 0 ]; then
                # Recreate zip with stapled app
                rm "$ZIP_PATH"
                ditto -c -k --sequesterRsrc --keepParent "${APP_NAME}.app" "$ZIP_PATH"
                echo -e "${GREEN}✓ Ticket stapled and archive recreated${NC}"
            else
                echo -e "${YELLOW}Warning: Stapling failed, but notarization succeeded.${NC}"
                echo "The notarized (but not stapled) zip is available at: ${ZIP_PATH}"
            fi
        else
            echo -e "${RED}Notarization failed.${NC}"
            if echo "$NOTARY_OUTPUT" | grep -q "id:"; then
                SUBMISSION_ID=$(echo "$NOTARY_OUTPUT" | grep "  id:" | head -1 | awk '{print $2}')
                echo "To see detailed error log, run:"
                echo -e "  ${YELLOW}xcrun notarytool log $SUBMISSION_ID --apple-id $APPLE_ID --team-id $TEAM_ID --password YOUR_PASSWORD${NC}"
            fi
            echo "The zip is still available at: ${ZIP_PATH}"
        fi
    fi
else
    echo "Step 3: Notarization skipped (no signing identity)"
    echo ""
    echo -e "${YELLOW}Warning: Users will see security warnings when opening this app.${NC}"
    echo "To fix this, you need:"
    echo "  1. Apple Developer account (\$99/year)"
    echo "  2. Developer ID Application certificate"
    echo "  3. Notarization with Apple"
fi

echo ""
echo "======================================"
echo -e "${GREEN}Build complete!${NC}"
echo ""
echo "Output: ${ZIP_PATH}"
echo ""
echo "Next steps:"
echo "  1. Test the app: unzip and run it"
echo "  2. Create GitHub release with tag v${VERSION}"
echo "  3. Upload ${ZIP_NAME} to the release"
echo ""
