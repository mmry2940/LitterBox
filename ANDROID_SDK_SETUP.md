# Android SDK and Emulator Setup for LitterBox

This document describes the Android SDK setup and emulator management functionality integrated into LitterBox.

## Overview

LitterBox now includes comprehensive Android SDK management and emulator functionality, allowing users to:

- Set up Android SDK command-line tools
- Install necessary SDK packages (platform-tools, emulator, build-tools, system images)
- Accept Android SDK licenses automatically
- Create and manage Android Virtual Devices (AVDs)
- Start and monitor emulators
- Integrate with existing ADB functionality

## Features

### 1. Android SDK Manager Service (`lib/services/android_sdk_manager.dart`)

A comprehensive service that handles:
- SDK installation detection and setup
- Automated package installation
- License acceptance
- AVD creation and management
- Emulator lifecycle management
- Real-time output streaming

### 2. SDK Management UI (`lib/screens/android_sdk_screen.dart`)

A dedicated screen with three tabs:
- **SDK Setup**: Status monitoring, installation controls, and setup guide
- **Emulators**: AVD creation and management interface
- **Output**: Real-time installation and operation logs

### 3. Integrated ADB Experience

The existing ADB screen now includes:
- SDK tab for quick access to SDK management
- Quick actions for common SDK operations
- Status monitoring integration
- Seamless navigation between ADB and SDK features

### 4. Automated Setup Script (`scripts/setup_android_sdk.sh`)

A bash script that automates the complete setup process:
- Downloads and installs Android command-line tools
- Installs required SDK packages
- Accepts all necessary licenses
- Creates a default AVD named `flutter_avd`
- Offers to start the emulator

## Usage

### Via LitterBox App

1. **From Home Screen**: Navigate to "Android SDK & Emulator" option
2. **From ADB Screen**: Switch to the "SDK" tab
3. **Setup Process**:
   - Check SDK status on the setup tab
   - Click "Setup Android SDK" to begin installation
   - Monitor progress in the output tab
   - Create AVDs in the emulators tab
   - Start emulators with one click

### Via Command Line

```bash
# Run the automated setup script
cd LitterBox/scripts
./setup_android_sdk.sh

# Test the setup
./test_android_setup.sh
```

### Manual Setup Steps

If you prefer manual setup or need to troubleshoot:

1. **Install Java JDK 17** (already done in most environments)
2. **Download Android Command Line Tools**:
   ```bash
   wget https://dl.google.com/android/repository/commandlinetools-linux-10406996_latest.zip
   ```
3. **Extract and Setup**:
   ```bash
   unzip commandlinetools-linux-*.zip -d $ANDROID_SDK_ROOT/cmdline-tools
   mv $ANDROID_SDK_ROOT/cmdline-tools/cmdline-tools $ANDROID_SDK_ROOT/cmdline-tools/latest
   ```
4. **Install SDK Packages**:
   ```bash
   sdkmanager --install "platform-tools" "emulator" "platforms;android-33" "build-tools;33.0.2" "system-images;android-33;google_apis;x86_64"
   ```
5. **Accept Licenses**:
   ```bash
   yes | sdkmanager --licenses
   ```
6. **Create AVD**:
   ```bash
   avdmanager create avd -n flutter_avd -k "system-images;android-33;google_apis;x86_64" -d "pixel" --force
   ```

## Configuration

### Environment Variables

The system respects standard Android environment variables:
- `ANDROID_SDK_ROOT`: Primary SDK location
- `ANDROID_HOME`: Alternative SDK location (legacy)

### Default Locations

- Linux: `$HOME/Android/Sdk`
- System installation: `/usr/local/lib/android/sdk`

### Customization

You can customize the setup by modifying these variables in the scripts:
- `AVD_NAME`: Name of the created AVD (default: "flutter_avd")
- `API_LEVEL`: Android API level (default: "33")
- `BUILD_TOOLS_VERSION`: Build tools version (default: "33.0.2")

## Integration with Flutter

Once set up, the Android SDK works seamlessly with Flutter:

```bash
# Check Flutter configuration
flutter doctor

# List available devices (including emulators)
flutter devices

# Run on emulator
flutter run
```

## Troubleshooting

### Common Issues

1. **Network Connectivity**: The setup requires internet access to download SDK components
2. **Disk Space**: Ensure at least 3GB of free space
3. **Permissions**: The user needs write access to the SDK installation directory
4. **Java Version**: Requires Java JDK 17 or later

### Error Resolution

- **SDK Not Found**: Use the "Setup Android SDK" button in the app
- **AVD Creation Failed**: Check that system images are installed
- **Emulator Won't Start**: Verify hardware acceleration and sufficient RAM
- **License Issues**: Run the license acceptance through the app interface

### Debugging

Enable verbose logging in the Android SDK Manager service for detailed troubleshooting information.

## Architecture

### Service Layer
- `AndroidSDKManager`: Core service handling all SDK operations
- Stream-based architecture for real-time updates
- Singleton pattern ensuring consistent state

### UI Layer
- `AndroidSDKScreen`: Dedicated management interface
- Integration into existing `AdbRefactoredScreen`
- Responsive design supporting mobile and desktop

### Script Layer
- Automated setup script for command-line users
- Test validation script
- Cross-platform compatibility (Linux focus)

## Future Enhancements

Potential improvements include:
- Support for multiple AVDs with different configurations
- Integration with Flutter project creation
- Automated system image management
- Performance monitoring for emulators
- Cloud-based emulator support

## Contributing

When contributing to the Android SDK functionality:

1. Test both UI and script-based workflows
2. Ensure compatibility with existing ADB features
3. Update documentation for any new features
4. Follow the existing code style and patterns
5. Test on different platforms when possible

## Support

For issues related to Android SDK setup:
1. Check the output tab in the app for detailed error messages
2. Run the test script to validate your environment
3. Consult the Flutter doctor output for system-level issues
4. Review Android developer documentation for SDK-specific problems