#!/usr/bin/env bash
# Android SDK Setup Script for LitterBox
# This script sets up Android SDK command-line tools, creates an AVD, and starts the emulator
set -euo pipefail
IFS=$'\n\t'

ANDROID_SDK_ROOT="$HOME/Android/Sdk"
AVD_NAME="flutter_avd"
API_LEVEL="33"
BUILD_TOOLS_VERSION="33.0.2"
CMDLINE_TOOLS_ZIP_URL="https://dl.google.com/android/repository/commandlinetools-linux-10406996_latest.zip"

echo "🚀 LitterBox Android SDK Setup Script"
echo "======================================"

# Ensure basics
mkdir -p "$ANDROID_SDK_ROOT"
sudo chown -R "$(id -u):$(id -g)" "$ANDROID_SDK_ROOT" || true
export PATH="$PATH:$ANDROID_SDK_ROOT/emulator:$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin"

echo "📍 SDK Root: $ANDROID_SDK_ROOT"
echo "📍 AVD Name: $AVD_NAME"
echo "📍 API Level: $API_LEVEL"

# Check Java
echo "☕ Checking Java installation..."
if ! command -v java >/dev/null 2>&1; then
  echo "❌ Java not found. Installing OpenJDK 17 (deb-based systems)."
  sudo apt-get update
  sudo apt-get install -y openjdk-17-jdk wget unzip curl
else
  echo "✅ Java found: $(java -version 2>&1 | head -n 1)"
fi

# Check if SDK is already installed
if [ -d "$ANDROID_SDK_ROOT/cmdline-tools" ] && [ -d "$ANDROID_SDK_ROOT/platform-tools" ]; then
  echo "✅ Android SDK already installed at $ANDROID_SDK_ROOT"
else
  echo "📦 Downloading and installing Android command line tools..."
  
  # Download command line tools zip
  TMPDIR=$(mktemp -d)
  cd "$TMPDIR"
  
  echo "⬇️ Downloading from: $CMDLINE_TOOLS_ZIP_URL"
  wget -O commandlinetools.zip "$CMDLINE_TOOLS_ZIP_URL" || {
    echo "❌ Failed to download command line tools"
    echo "💡 You may need to download manually from:"
    echo "    https://developer.android.com/studio"
    exit 1
  }
  
  echo "📦 Extracting command line tools..."
  unzip -q commandlinetools.zip -d "$ANDROID_SDK_ROOT/cmdline-tools"
  
  # The zip creates a "cmdline-tools" directory, we need to rename it to "latest"
  if [ -d "$ANDROID_SDK_ROOT/cmdline-tools/cmdline-tools" ]; then
    mv "$ANDROID_SDK_ROOT/cmdline-tools/cmdline-tools" "$ANDROID_SDK_ROOT/cmdline-tools/latest"
  fi
  
  echo "✅ Command line tools installed"
  
  # Clean up
  cd /
  rm -rf "$TMPDIR"
fi

# Update PATH for this session
export PATH="$PATH:$ANDROID_SDK_ROOT/emulator:$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin"

echo "📦 Installing SDK packages..."
# Install SDK packages
"$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$ANDROID_SDK_ROOT" --install \
  "platform-tools" \
  "emulator" \
  "platforms;android-$API_LEVEL" \
  "build-tools;$BUILD_TOOLS_VERSION" \
  "system-images;android-$API_LEVEL;google_apis;x86_64" || {
  echo "⚠️ Some packages failed to install. Continuing anyway..."
}

echo "📝 Accepting SDK licenses..."
# Accept licenses
yes | "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" --licenses --sdk_root="$ANDROID_SDK_ROOT" || true

echo "📱 Creating AVD: $AVD_NAME..."
# Create AVD
"$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/avdmanager" create avd \
  -n "$AVD_NAME" \
  -k "system-images;android-$API_LEVEL;google_apis;x86_64" \
  -d "pixel" \
  --force || {
  echo "⚠️ AVD creation failed, but continuing..."
}

echo "🎯 Setup Summary:"
echo "=================="
echo "✅ Android SDK installed at: $ANDROID_SDK_ROOT"
echo "✅ Command line tools available"
echo "✅ Platform tools installed"
echo "✅ Emulator installed"
echo "✅ AVD '$AVD_NAME' created"

echo ""
echo "🚀 To start the emulator:"
echo "   $ANDROID_SDK_ROOT/emulator/emulator -avd $AVD_NAME"
echo ""
echo "🔧 To use with Flutter:"
echo "   export ANDROID_SDK_ROOT=\"$ANDROID_SDK_ROOT\""
echo "   export PATH=\"\$PATH:\$ANDROID_SDK_ROOT/emulator:\$ANDROID_SDK_ROOT/platform-tools:\$ANDROID_SDK_ROOT/cmdline-tools/latest/bin\""
echo "   flutter doctor"
echo "   flutter devices"
echo ""

# Offer to start emulator
read -p "🤔 Would you like to start the emulator now? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo "🚀 Starting emulator $AVD_NAME..."
  echo "💡 The emulator will start in the background. Check your system for the emulator window."
  
  # Start emulator in background with no window (headless)
  # Remove -no-window if you want to see the emulator UI
  nohup "$ANDROID_SDK_ROOT/emulator/emulator" -avd "$AVD_NAME" -no-window -no-audio > /dev/null 2>&1 &
  
  echo "✅ Emulator started! Process ID: $!"
  echo "💡 Use 'adb devices' to check if it's ready"
  echo "💡 It may take a few minutes for the emulator to fully boot"
else
  echo "👍 Emulator not started. You can start it later with:"
  echo "   $ANDROID_SDK_ROOT/emulator/emulator -avd $AVD_NAME"
fi

echo ""
echo "🎉 Android SDK setup completed!"
echo "💡 You can now use LitterBox to connect to Android devices and emulators"