#!/usr/bin/env bash
# Test script for Android SDK setup functionality
# This script validates that the setup script works correctly

echo "🧪 Testing Android SDK Setup for LitterBox"
echo "==========================================="

# Test 1: Check if the setup script exists and is executable
echo "📋 Test 1: Checking setup script..."
SCRIPT_PATH="$(dirname "$0")/setup_android_sdk.sh"

if [ -f "$SCRIPT_PATH" ]; then
  echo "✅ Setup script exists: $SCRIPT_PATH"
else
  echo "❌ Setup script not found: $SCRIPT_PATH"
  exit 1
fi

if [ -x "$SCRIPT_PATH" ]; then
  echo "✅ Setup script is executable"
else
  echo "❌ Setup script is not executable"
  exit 1
fi

# Test 2: Check Java installation
echo ""
echo "📋 Test 2: Checking Java installation..."
if command -v java >/dev/null 2>&1; then
  JAVA_VERSION=$(java -version 2>&1 | head -n 1)
  echo "✅ Java found: $JAVA_VERSION"
else
  echo "❌ Java not found - required for Android SDK"
  exit 1
fi

# Test 3: Check if Android SDK is already available
echo ""
echo "📋 Test 3: Checking existing Android SDK..."
if [ -n "${ANDROID_SDK_ROOT:-}" ] && [ -d "$ANDROID_SDK_ROOT" ]; then
  echo "✅ Android SDK found at: $ANDROID_SDK_ROOT"
  
  # Check for key components
  if [ -d "$ANDROID_SDK_ROOT/platform-tools" ]; then
    echo "✅ Platform tools available"
  else
    echo "⚠️ Platform tools not found"
  fi
  
  if [ -d "$ANDROID_SDK_ROOT/cmdline-tools" ]; then
    echo "✅ Command line tools available"
  else
    echo "⚠️ Command line tools not found"
  fi
  
else
  echo "⚠️ Android SDK not found in standard locations"
  echo "💡 The setup script will install it"
fi

# Test 4: Check network connectivity for downloads
echo ""
echo "📋 Test 4: Checking network connectivity..."
if curl -s --head https://dl.google.com >/dev/null 2>&1; then
  echo "✅ Network connectivity to Google servers available"
else
  echo "⚠️ Cannot reach Google servers - setup may fail"
  echo "💡 You may need to download SDK components manually"
fi

# Test 5: Check available disk space
echo ""
echo "📋 Test 5: Checking disk space..."
SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}"
PARENT_DIR=$(dirname "$SDK_ROOT")
AVAILABLE_MB=$(df -m "$PARENT_DIR" | awk 'NR==2 {print $4}')

if [ "$AVAILABLE_MB" -gt 3000 ]; then
  echo "✅ Sufficient disk space available: ${AVAILABLE_MB}MB"
else
  echo "⚠️ Limited disk space: ${AVAILABLE_MB}MB (recommend 3GB+)"
fi

# Test 6: Validate script syntax
echo ""
echo "📋 Test 6: Validating script syntax..."
if bash -n "$SCRIPT_PATH"; then
  echo "✅ Script syntax is valid"
else
  echo "❌ Script has syntax errors"
  exit 1
fi

echo ""
echo "🎯 Test Summary:"
echo "================"
echo "✅ Setup script found and executable"
echo "✅ Java installation verified"
echo "✅ Disk space checked"
echo "✅ Script syntax validated"

if [ -n "${ANDROID_SDK_ROOT:-}" ] && [ -d "$ANDROID_SDK_ROOT" ]; then
  echo "ℹ️ Android SDK already available"
else
  echo "💡 Android SDK will be installed by setup script"
fi

echo ""
echo "🚀 Ready to run Android SDK setup!"
echo "💡 Run the setup script with: $SCRIPT_PATH"
echo ""
echo "🔧 For LitterBox integration:"
echo "1. The Flutter app includes an AndroidSDKManager service"
echo "2. The app provides UI for SDK management and AVD creation"
echo "3. Access via Home Screen → 'Android SDK & Emulator'"
echo "4. Or via ADB Screen → SDK tab"