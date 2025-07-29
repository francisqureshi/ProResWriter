# ProResWriter - Quick Build Guide

## Build & Run Debug Version

### Method 1: Xcode (Easiest)
```bash
# Open in Xcode
open ProResWriter.xcodeproj

# Then press Cmd+B to build, Cmd+R to run
```

### Method 2: Command Line (Custom Build Directory)
```bash
# Build debug version with custom build directory
xcodebuild -project ProResWriter.xcodeproj -scheme ProResWriter -configuration Debug build -derivedDataPath ./build
# Release
xcodebuild -project ProResWriter.xcodeproj -scheme ProResWriter -configuration Release build -derivedDataPath ./build


xcodebuild -project ProResWriter.xcodeproj -scheme ProResWriter -configuration Release build -derivedDataPath ./build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# Run the built executable
./build/Build/Products/Debug/ProResWriter
```

### Method 3: Command Line (Default Location)
```bash
# Build debug version (default location)
xcodebuild -project ProResWriter.xcodeproj -scheme ProResWriter -configuration Debug build


# Run the built executable
./DerivedData/ProResWriter/Build/Products/Debug/ProResWriter
```

## Requirements
- macOS 15.0+
- Xcode 15.0+

## Troubleshooting

### "xcodebuild requires Xcode" Error
If you get this error but have Xcode installed:
```bash
# Fix xcode-select path
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

### Code Signing Issues
If build fails with signing certificate errors, use the command line method above with `CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO`

### Missing TimecodeKit?
Reset package caches in Xcode: File → Packages → Reset Package Caches 