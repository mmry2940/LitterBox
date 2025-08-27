#!/usr/bin/env bash
# Quick Flutter Emulator Setup for LitterBox
# This script creates a Flutter-optimized AVD and starts it

set -euo pipefail

ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}"
AVD_NAME="${AVD_NAME:-flutter_avd}"
API_LEVEL="${API_LEVEL:-33}"

echo "🚀 Flutter Emulator Quick Setup"
echo "==============================="
echo "📍 SDK Root: $ANDROID_SDK_ROOT"
echo "📱 AVD Name: $AVD_NAME"
echo "🔧 API Level: $API_LEVEL"
echo ""

# Check if SDK is available
if [ ! -d "$ANDROID_SDK_ROOT" ]; then
    echo "❌ Android SDK not found at $ANDROID_SDK_ROOT"
    echo "💡 Run the main setup script first: ./setup_android_sdk.sh"
    exit 1
fi

# Update PATH
export PATH="$PATH:$ANDROID_SDK_ROOT/emulator:$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin"

# Check if AVD already exists
echo "🔍 Checking if AVD '$AVD_NAME' exists..."
if avdmanager list avd | grep -q "Name: $AVD_NAME"; then
    echo "✅ AVD '$AVD_NAME' already exists"
else
    echo "📱 Creating AVD '$AVD_NAME'..."
    
    # Create AVD with Flutter-optimized settings
    avdmanager create avd \
        -n "$AVD_NAME" \
        -k "system-images;android-$API_LEVEL;google_apis;x86_64" \
        -d "pixel" \
        --force
    
    if [ $? -eq 0 ]; then
        echo "✅ AVD '$AVD_NAME' created successfully"
    else
        echo "❌ Failed to create AVD"
        exit 1
    fi
fi

# Configure AVD for better performance
AVD_CONFIG="$HOME/.android/avd/${AVD_NAME}.avd/config.ini"
if [ -f "$AVD_CONFIG" ]; then
    echo "⚙️ Optimizing AVD configuration..."
    
    # Add or update performance settings
    grep -q "hw.gpu.enabled" "$AVD_CONFIG" || echo "hw.gpu.enabled=yes" >> "$AVD_CONFIG"
    grep -q "hw.gpu.mode" "$AVD_CONFIG" || echo "hw.gpu.mode=auto" >> "$AVD_CONFIG"
    sed -i 's/hw.gpu.enabled=no/hw.gpu.enabled=yes/' "$AVD_CONFIG" 2>/dev/null || true
    sed -i 's/hw.gpu.mode=off/hw.gpu.mode=auto/' "$AVD_CONFIG" 2>/dev/null || true
    
    echo "✅ AVD configuration optimized"
fi

# Function to check if emulator is running
check_emulator_running() {
    adb devices | grep -q "emulator-" || return 1
}

# Start emulator if not already running
echo "🔍 Checking if emulator is already running..."
if check_emulator_running; then
    echo "✅ Emulator already running"
    adb devices
else
    echo "🚀 Starting emulator '$AVD_NAME'..."
    
    # Start emulator in background
    echo "💡 Starting emulator in background (this may take a few minutes)..."
    nohup "$ANDROID_SDK_ROOT/emulator/emulator" -avd "$AVD_NAME" -no-snapshot-save > /tmp/emulator.log 2>&1 &
    EMULATOR_PID=$!
    
    echo "✅ Emulator started with PID: $EMULATOR_PID"
    echo "📋 Log file: /tmp/emulator.log"
    
    # Wait for emulator to be ready
    echo "⏳ Waiting for emulator to be ready..."
    TIMEOUT=300  # 5 minutes timeout
    ELAPSED=0
    
    while [ $ELAPSED -lt $TIMEOUT ]; do
        if check_emulator_running; then
            echo "✅ Emulator is ready!"
            break
        fi
        
        echo "⏳ Still waiting... (${ELAPSED}s/${TIMEOUT}s)"
        sleep 10
        ELAPSED=$((ELAPSED + 10))
    done
    
    if [ $ELAPSED -ge $TIMEOUT ]; then
        echo "⚠️ Emulator startup timeout. Check /tmp/emulator.log for details"
        echo "💡 The emulator may still be starting in the background"
    fi
fi

# Show current status
echo ""
echo "📱 Current Android devices:"
adb devices

echo ""
echo "🎯 Flutter Integration:"
echo "======================"
echo "✅ AVD '$AVD_NAME' is ready"
echo "✅ Android SDK configured"
echo ""
echo "🚀 Next steps for Flutter development:"
echo "1. flutter doctor          # Check Flutter configuration"
echo "2. flutter devices         # List available devices"
echo "3. flutter create my_app   # Create a new Flutter project"
echo "4. cd my_app && flutter run # Run on the emulator"
echo ""
echo "💡 To stop the emulator:"
echo "   adb -s emulator-5554 emu kill"
echo ""
echo "🎉 Flutter emulator setup completed!"