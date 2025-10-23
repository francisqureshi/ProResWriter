#!/bin/bash

# SourcePrint Release Script
# Automates packaging, signing, GitHub release, and appcast update

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Paths
APP_PATH="SourcePrint/build/Build/Products/Release/SourcePrint.app"
SIGN_UPDATE_TOOL="SourcePrint/build/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
APPCAST_PATH="appcast.xml"

echo -e "${BLUE}🚀 SourcePrint Release Automation${NC}"
echo ""

# Check if app exists
if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}❌ App not found at $APP_PATH${NC}"
    echo "Please run ./build-sourceprint.sh first"
    exit 1
fi

# Extract version and build number
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_PATH/Contents/Info.plist")

echo -e "${GREEN}📦 Found: SourcePrint v$VERSION (Build $BUILD)${NC}"
echo ""

# Ask for release notes
echo -e "${YELLOW}📝 Enter release notes (press Ctrl+D when done):${NC}"
NOTES=$(cat)

if [ -z "$NOTES" ]; then
    NOTES="SourcePrint v$VERSION - Build $BUILD"
fi

# Package the app
echo ""
echo -e "${BLUE}📦 Packaging app...${NC}"
ZIP_NAME="SourcePrint-$VERSION.zip"
ZIP_PATH="SourcePrint/build/Build/Products/Release/$ZIP_NAME"

cd SourcePrint/build/Build/Products/Release
rm -f "$ZIP_NAME"
ditto -c -k --sequesterRsrc --keepParent SourcePrint.app "$ZIP_NAME"
cd - > /dev/null

echo -e "${GREEN}✅ Created $ZIP_NAME${NC}"

# Sign with Sparkle
echo ""
echo -e "${BLUE}🔐 Signing with Sparkle EdDSA...${NC}"
SIGNATURE_OUTPUT=$("$SIGN_UPDATE_TOOL" "$ZIP_PATH")
ED_SIGNATURE=$(echo "$SIGNATURE_OUTPUT" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)
LENGTH=$(echo "$SIGNATURE_OUTPUT" | grep -o 'length="[^"]*"' | cut -d'"' -f2)

echo -e "${GREEN}✅ Signature: $ED_SIGNATURE${NC}"
echo -e "${GREEN}✅ Length: $LENGTH bytes${NC}"

# Copy to Desktop for GitHub release
cp "$ZIP_PATH" ~/Desktop/

# Create GitHub release
echo ""
echo -e "${BLUE}🌐 Creating GitHub release v$VERSION...${NC}"

RELEASE_NOTES="## SourcePrint v$VERSION

$NOTES

**Build:** $BUILD
**Release Date:** $(date '+%Y-%m-%d')

---

gh release create "v$VERSION" ~/Desktop/"$ZIP_NAME" \
    --title "SourcePrint v$VERSION" \
    --notes "$RELEASE_NOTES" || {
    echo -e "${YELLOW}⚠️  Release already exists, uploading asset...${NC}"
    gh release upload "v$VERSION" ~/Desktop/"$ZIP_NAME" --clobber
}

echo -e "${GREEN}✅ GitHub release created/updated${NC}"

# Update appcast.xml
echo ""
echo -e "${BLUE}📡 Updating appcast.xml...${NC}"

PUBDATE=$(date -u '+%a, %d %b %Y %H:%M:%S +0000')
NEW_ITEM="        <item>
            <title>Version $VERSION</title>
            <description><![CDATA[
                <h2>SourcePrint v$VERSION</h2>
                <ul>
                    <li>$NOTES</li>
                </ul>
            ]]></description>
            <pubDate>$PUBDATE</pubDate>
            <sparkle:version>$BUILD</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
            <enclosure
                url=\"https://github.com/francisqureshi/ProResWriter/releases/download/v$VERSION/SourcePrint-$VERSION.zip\"
                sparkle:edSignature=\"$ED_SIGNATURE\"
                length=\"$LENGTH\"
                type=\"application/octet-stream\"
            />
        </item>

"

# Check if version already exists in appcast
if grep -q "<sparkle:version>$BUILD</sparkle:version>" "$APPCAST_PATH"; then
    echo -e "${YELLOW}⚠️  Version $VERSION (Build $BUILD) already exists in appcast${NC}"
    read -p "Update existing entry? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Remove existing entry and add new one
        # This is a simple approach - in production you'd want more robust XML editing
        echo -e "${YELLOW}⚠️  Manual appcast update required - entry already exists${NC}"
        echo "Please update appcast.xml manually or delete the existing entry first"
        exit 1
    else
        echo -e "${BLUE}Skipping appcast update${NC}"
        exit 0
    fi
else
    # Insert new item after the public key comment using Perl
    perl -i -0pe "s|(<!-- Sparkle Public Key.*?\n\n)|\$1$NEW_ITEM|s" "$APPCAST_PATH"

    echo -e "${GREEN}✅ Appcast updated${NC}"
fi

# Commit and push
echo ""
echo -e "${BLUE}📤 Committing and pushing to GitHub...${NC}"

git add "$APPCAST_PATH"
git commit -m "Release v$VERSION (Build $BUILD)

$NOTES

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
git push

echo ""
echo -e "${GREEN}✅✅✅ Release complete! ✅✅✅${NC}"
echo ""
echo -e "${BLUE}Summary:${NC}"
echo -e "  Version: ${GREEN}$VERSION${NC}"
echo -e "  Build: ${GREEN}$BUILD${NC}"
echo -e "  GitHub: ${GREEN}https://github.com/francisqureshi/ProResWriter/releases/tag/v$VERSION${NC}"
echo ""
echo -e "${YELLOW}⏳ Wait ~2 minutes for GitHub CDN to refresh appcast, then users can update!${NC}"
