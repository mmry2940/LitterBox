# LitterBox v1.0.0 - Initial Release 🚀

## 📱 **What is LitterBox?**

LitterBox is a powerful remote access toolkit designed for developers and system administrators. Connect to your servers, manage Android devices, and access remote desktops from anywhere on your Android device.

## 🔑 **Key Features**

### **SSH Terminal & Remote Access**
- ✅ **Persistent SSH connections** - Stay connected even when switching apps
- ✅ **Enhanced terminal** with font size controls and hotkeys
- ✅ **Smart cursor tracking** and improved text selection
- ✅ **Quick commands menu** for common operations

### **Android ADB Management**
- ✅ **Wireless ADB over Wi-Fi** - Connect to Android devices remotely
- ✅ **USB ADB support** - Direct USB debugging connection
- ✅ **Device discovery** via mDNS scanning
- ✅ **Complete ADB command interface** with interactive shell
- ✅ **File transfer** - Push/pull files between devices
- ✅ **Package management** - Install/uninstall APKs
- ✅ **Logcat viewer** with real-time filtering

### **VNC Remote Desktop**
- ✅ **Native VNC client** with RFB protocol support
- ✅ **Multiple scaling modes** optimized for mobile
- ✅ **VNC Authentication** with DES encryption
- ✅ **Connection profiles** for quick access
- ✅ **Clipboard synchronization** between devices

### **RDP Remote Desktop** 
- ✅ **RDP protocol support** for Windows Remote Desktop
- ✅ **Guacamole WebView integration** for full functionality
- ✅ **Connection testing** and validation
- ✅ **Saved connection profiles**

### **Network & Device Management**
- ✅ **Network scanning** with isolate-based subnet discovery
- ✅ **Device information** with enhanced system monitoring
- ✅ **Process management** and monitoring
- ✅ **File browser** for remote file operations
- ✅ **Package listing** and management tools

### **Enhanced User Experience**
- ✅ **Material 3 Design** with modern, responsive UI
- ✅ **Dark/Light theme** support
- ✅ **Device status monitoring** with real-time updates
- ✅ **Connection state management** with auto-reconnect
- ✅ **Favorite devices** for quick access
- ✅ **Search and filtering** across all interfaces

## 🛠 **Technical Specifications**

- **Target SDK**: Android 34 (Android 14)
- **Minimum SDK**: Android 21 (Android 5.0)
- **Framework**: Flutter 3.24.0
- **Architecture**: ARM64, ARMv7, x86_64
- **File Size**: ~70MB (Release APK), ~165MB (Debug APK)
- **Permissions**: Internet, Network State, Foreground Service

## 📦 **Download Options**

### **For Regular Users**
- **app-release.apk** (69.9MB) - Optimized production build, recommended for most users

### **For Developers & Testers**  
- **app-debug.apk** (165MB) - Debug build with additional logging and development features
- **app-release.aab** (55MB) - Android App Bundle for Google Play Store

### **For Developers & Contributors**
- **LitterBox-Source-v1.0.0.zip** (11.5MB) - Complete source code with all project files

## 🔐 **Security & Privacy**

- ✅ **No data collection** - All connections are direct between your device and target servers
- ✅ **Local storage only** - Connection settings stored securely on your device
- ✅ **Encrypted connections** - SSH, VNC, and RDP use industry-standard encryption
- ✅ **Open source** - Full source code available for transparency

## 🎯 **Perfect For**

- **Software developers** managing remote Linux/Windows servers
- **Android developers** testing and debugging devices over Wi-Fi
- **System administrators** monitoring infrastructure remotely  
- **DevOps engineers** accessing production environments
- **IT professionals** providing remote support

## 📋 **Installation Instructions**

### **APK Installation** (Recommended)
1. Download `app-release.apk`
2. Enable "Install from Unknown Sources" in Android Settings
3. Open the APK file and follow installation prompts
4. Launch LitterBox and start connecting to your devices

### **Requirements**
- Android 5.0+ (API level 21 or higher)
- Internet connection for remote access
- SSH server on target devices for terminal access
- VNC/RDP server for remote desktop functionality

## 🚀 **Getting Started**

1. **SSH Connections**: Add your server details (host, port, username, password/key)
2. **ADB Devices**: Enable wireless debugging on Android devices and scan for connections
3. **VNC/RDP**: Configure your remote desktop server and connect
4. **Network Scanning**: Discover devices on your local network automatically

## 🔧 **Build Information**

- **Build Date**: October 12, 2025
- **Flutter Version**: 3.24.0
- **Dart Version**: 3.5.0
- **Gradle Version**: 8.3
- **Target Platforms**: Android (ARM64, ARMv7, x86_64)

## 📝 **Known Issues**

- Some Kotlin compilation warnings during build (do not affect functionality)
- VNC "security failures" may require server restart if too many failed attempts
- RDP native mode is primarily for connection testing (use Guacamole mode for full functionality)

## 🤝 **Contributing**

This is an open-source project. Feel free to:
- Report bugs and issues
- Suggest new features
- Submit pull requests
- Improve documentation

## 📄 **License**

This project is released under the MIT License. See LICENSE file for details.

---

**Made with ❤️ for the developer community**

*LitterBox - Your portable toolkit for remote access and device management*