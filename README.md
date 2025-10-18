# LitterBox 🧰

[![Flutter](https://img.shields.io/badge/Flutter-3.24.0-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.5.0-0175C2?logo=dart)](https://dart.dev)
[![Android](https://img.shields.io/badge/Android-5.0+-3DDC84?logo=android)](https://developer.android.com)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/mmry2940/LitterBox)](https://github.com/mmry2940/LitterBox/releases)

> **A powerful remote access toolkit for Android developers and system administrators**

LitterBox is a comprehensive Android application that brings together essential remote access tools in one convenient package. Whether you're managing servers via SSH, debugging Android devices with ADB, or accessing remote desktops through VNC/RDP, LitterBox provides the tools you need with a modern, intuitive interface.

![LitterBox Screenshots](https://via.placeholder.com/800x400/2196F3/FFFFFF?text=LitterBox+Screenshots)

## 🚀 Quick Start

1. **Download** the latest release APK from [Releases](https://github.com/mmry2940/LitterBox/releases/latest)
2. **Install** on your Android device (Android 5.0+)
3. **Connect** to your servers/devices:
   - **SSH:** Enter host, port, username, and password
   - **ADB:** Enable wireless debugging and scan network
   - **VNC/RDP:** Configure remote desktop settings
4. **Manage** your devices from anywhere!

## ✨ Features Overview

### 🔧 **Core Functionality**
- **SSH Terminal** - Full-featured terminal with persistent connections
- **Android ADB Manager** - Comprehensive ADB interface for device management  
- **VNC Client** - Native VNC remote desktop viewer
- **RDP Client** - Remote Desktop Protocol support
- **Network Scanner** - Discover devices on your local network
- **Device Manager** - Centralized connection management

### 🎨 **User Experience**
- **Material 3 Design** - Modern, responsive UI following Google's design principles
- **Dark/Light Themes** - Automatic theme switching and manual toggle
- **Responsive Layout** - Optimized for phones and tablets
- **Intuitive Navigation** - Easy-to-use interface for complex operations

---

## 🚀 Getting Started

### 📱 **Installation**

#### **Option 1: Download APK (Recommended)**
1. Go to [Releases](https://github.com/mmry2940/LitterBox/releases/latest)
2. Download `app-release.apk` (production build)
3. Enable "Install from Unknown Sources" in Android Settings
4. Install and launch the app

#### **Option 2: Build from Source**
```bash
# Clone the repository
git clone https://github.com/mmry2940/LitterBox.git
cd LitterBox

# Install dependencies
flutter pub get

# Build for Android
flutter build apk --release
```

### 📋 **Requirements**
- **Android 5.0+** (API level 21 or higher)
- **Internet connection** for remote access
- **Storage permission** for file operations
- **Network access** for device discovery

---

## 🔥 **Features in Detail**

### 🖥️ **SSH Terminal** ✅ **Fully Implemented**

<details>
<summary>Click to expand SSH features</summary>

**Core Features:**
- ✅ **Persistent connections** - Stay connected even when switching apps
- ✅ **Multiple sessions** - Connect to multiple servers simultaneously  
- ✅ **Authentication support** - Password and key-based authentication
- ✅ **Font size controls** - Adjustable terminal font with persistence
- ✅ **Hotkeys bar** - Quick access to common terminal shortcuts
- ✅ **Session management** - Save and restore connection settings
- ✅ **Smart cursor tracking** - Improved text selection and cursor positioning
- ✅ **Auto-reconnect** - Automatic reconnection on network interruption
- ✅ **Background operation** - Foreground service keeps connections alive

**Technical Implementation:**
- Uses `dartssh2` for SSH protocol implementation
- `xterm` package for terminal emulation
- `flutter_foreground_task` for background persistence
- Custom session management with lifecycle awareness

**Quick Commands Menu:**
- File operations (`ls`, `pwd`, `cat`, `nano`)
- System monitoring (`top`, `htop`, `ps`, `df`)
- Network utilities (`ping`, `netstat`, `ss`)
- Package management (`apt`, `yum`, `pacman`)

</details>

### 📱 **Android ADB Manager** ✅ **Fully Implemented**

<details>
<summary>Click to expand ADB features</summary>

**Connection Methods:**
- ✅ **Wi-Fi ADB** - Wireless debugging over TCP/IP
- ✅ **USB ADB** - Direct USB connection support
- ✅ **Device pairing** - Android 11+ wireless pairing with QR codes
- ✅ **mDNS discovery** - Automatic device discovery on local network
- ✅ **Custom connections** - Manual IP/port configuration

**Device Management:**
- ✅ **Interactive shell** - Full ADB shell with command history
- ✅ **File operations** - Push/pull files between devices
- ✅ **Package management** - Install/uninstall APKs
- ✅ **Logcat viewer** - Real-time log viewing with filtering
- ✅ **Device information** - Hardware specs, system properties
- ✅ **Process monitoring** - Running processes and resource usage

**Advanced Features:**
- ✅ **Multiple backend support** - Flutter ADB, System ADB, Internal ADB
- ✅ **WebADB server** - HTTP API for remote ADB operations
- ✅ **Saved connections** - Quick access to favorite devices
- ✅ **Connection wizard** - Step-by-step setup for new devices

**Technical Stack:**
- Custom ADB protocol implementation
- USB device integration via platform channels
- mDNS service discovery
- HTTP server for WebADB functionality

</details>

### 🖥️ **VNC Remote Desktop** ✅ **Fully Implemented**

<details>
<summary>Click to expand VNC features</summary>

**Core VNC Features:**
- ✅ **Native VNC client** - Custom RFB protocol implementation
- ✅ **Multiple RFB versions** - Support for RFB 3.3, 3.8, and 5.0+
- ✅ **VNC authentication** - DES-encrypted password authentication
- ✅ **Connection profiles** - Save frequently used VNC servers
- ✅ **Multiple scaling modes** - Optimized for mobile displays

**Display Options:**
- ✅ **Auto-fit modes** - Automatic width/height fitting
- ✅ **Manual scaling** - 50%, 75%, 125%, 150%, 200% zoom levels
- ✅ **Smart scaling** - Landscape/portrait optimizations
- ✅ **Full-screen support** - Immersive remote desktop experience

**Input Methods:**
- ✅ **Direct touch** - Touch directly where you want to click
- ✅ **Trackpad mode** - Laptop-style cursor control
- ✅ **Touch with zoom** - Pinch-to-zoom support

**Advanced Features:**
- ✅ **Clipboard sync** - Bidirectional clipboard sharing
- ✅ **Connection testing** - Verify connectivity before connecting
- ✅ **Auto-reconnect** - Configurable reconnection on disconnect
- ✅ **Debug logging** - Detailed logs for troubleshooting

**Technical Implementation:**
- Custom RFB protocol parser
- DES encryption for VNC auth
- Efficient frame buffer management
- WebView fallback with noVNC integration

</details>

### 💻 **RDP Remote Desktop** ⚠️ **Partially Implemented**

<details>
<summary>Click to expand RDP features</summary>

**Working Features:**
- ✅ **Connection testing** - TCP connectivity verification
- ✅ **Guacamole integration** - WebView-based RDP via Guacamole
- ✅ **Connection profiles** - Save RDP server configurations
- ✅ **Basic authentication** - Username/password/domain support

**Limitations:**
- ⚠️ **Native RDP client** - Protocol implementation incomplete
- ⚠️ **Direct RDP connection** - Currently requires Guacamole server
- ⚠️ **Advanced features** - No file transfer, audio, or clipboard sync

**Current Status:**
The RDP implementation focuses on connection management and testing. For full RDP functionality, users should:
1. Set up a Guacamole server
2. Use the Guacamole WebView mode
3. Native RDP mode is for testing connectivity only

**Future Improvements:**
- [ ] Complete native RDP protocol implementation
- [ ] Direct RDP connections without Guacamole
- [ ] File transfer support
- [ ] Audio redirection
- [ ] Enhanced security options

</details>

### 🌐 **Network Scanner** ✅ **Fully Implemented**

<details>
<summary>Click to expand Network features</summary>

**Discovery Features:**
- ✅ **Subnet scanning** - Fast network host discovery
- ✅ **Isolate-based scanning** - Non-blocking background scanning
- ✅ **Port detection** - Check common service ports (SSH, HTTP, HTTPS)
- ✅ **Progress tracking** - Real-time scan progress updates
- ✅ **Result caching** - Cache scan results for faster repeated access

**Network Tools:**
- ✅ **mDNS discovery** - Find ADB devices and other services
- ✅ **Network information** - Current network details
- ✅ **IP configuration** - Automatic subnet detection
- ✅ **Connectivity testing** - Network connectivity validation

**Technical Features:**
- Custom isolate implementation for parallel scanning
- Lightweight TCP connection testing
- Efficient result aggregation and caching
- Integration with device management system

</details>

### 📊 **Device Information** ✅ **Fully Implemented**

<details>
<summary>Click to expand Device Info features</summary>

**System Information:**
- ✅ **Hardware details** - CPU, memory, storage information
- ✅ **Operating system** - OS version, kernel information
- ✅ **Network configuration** - IP addresses, network interfaces
- ✅ **Performance metrics** - Real-time system resource usage

**Visualization:**
- ✅ **Interactive gauges** - Memory and CPU usage with Syncfusion charts
- ✅ **Progress indicators** - Visual representation of resource consumption
- ✅ **Copy-to-clipboard** - Easy sharing of system information
- ✅ **Auto-refresh** - Configurable automatic data updates

**Data Sources:**
- SSH command execution for remote systems
- System property queries for Android devices
- Network interface inspection
- Real-time performance monitoring

</details>

### 📁 **File Management** ✅ **Fully Implemented**

<details>
<summary>Click to expand File features</summary>

**SSH File Operations:**
- ✅ **Remote file browser** - Navigate remote filesystem via SSH
- ✅ **Copy/Cut/Paste** - Full clipboard support for files and folders
- ✅ **Delete files/folders** - Remove items with confirmation
- ✅ **Rename files/folders** - In-place renaming
- ✅ **Create folders** - New directory creation
- ✅ **Archive operations** - Create and extract tar.gz archives
- ✅ **Multi-select** - Batch operations on multiple items
- ✅ **Search and filter** - Find files quickly
- ✅ **Hidden files toggle** - Show/hide hidden files
- ✅ **File type icons** - Visual file type identification
- ✅ **Permissions display** - View file permissions and metadata

**ADB File Operations:**
- ✅ **Push files** - Transfer files to Android devices
- ✅ **Pull files** - Download files from Android devices
- ✅ **APK installation** - Install applications via file picker
- ✅ **Path management** - Recent paths and quick access

**File Picker Integration:**
- Uses `file_picker` package (version 8.0.3 for compatibility)
- Local file system access
- Integration with ADB file operations

</details>

---

## ⚙️ **Technical Architecture**

### 🏗️ **Core Technologies**
- **Flutter 3.24.0** - Cross-platform UI framework
- **Dart 3.5.0** - Programming language
- **Material 3** - Google's latest design system
- **Target SDK 34** - Android 14 compatibility

### 📦 **Key Dependencies**

#### **SSH & Terminal**
- `dartssh2: ^2.13.0` - SSH protocol implementation
- `xterm: ^4.0.0` - Terminal emulation
- `flutter_foreground_task: ^9.1.0` - Background service management

#### **UI & Visualization**
- `syncfusion_flutter_gauges: ^31.1.19` - Charts and progress indicators
- `shared_preferences: ^2.4.12` - Local data persistence
- `file_picker: ^8.0.3` - File system integration

#### **Network & Discovery**
- `network_tools: ^6.0.2` - Network scanning utilities
- `network_info_plus: ^7.0.0` - Network information
- `multicast_dns: ^0.3.2` - mDNS service discovery

#### **Security & Encryption**
- `crypto: ^3.0.3` - Cryptographic operations
- `pointycastle: ^3.7.3` - Dart cryptography library

#### **Platform Integration**
- `webview_flutter: ^4.4.2` - WebView for RDP/noVNC
- `path_provider: ^2.1.4` - Platform directories

### 🏛️ **Application Structure**

```
lib/
├── main.dart                    # Application entry point
├── screens/                     # Main UI screens
│   ├── home_screen.dart         # Device dashboard
│   ├── device_screen.dart       # Device detail tabs
│   ├── device_terminal_screen.dart  # SSH terminal
│   ├── device_info_screen.dart     # System information
│   ├── adb_screen_refactored.dart  # ADB management
│   ├── vnc_screen.dart          # VNC remote desktop
│   └── rdp_screen.dart          # RDP remote desktop
├── models/                      # Data models
│   ├── device_status.dart       # Device connection status
│   └── saved_adb_device.dart    # Saved ADB configurations
├── services/                    # Background services
│   └── device_status_monitor.dart  # Connection monitoring
├── widgets/                     # Reusable UI components
│   ├── enhanced_device_card.dart   # Device cards
│   └── adb_connection_wizard.dart  # ADB setup wizard
├── adb/                        # ADB implementation
│   ├── flutter_adb_client.dart    # Flutter-native ADB
│   ├── adb_mdns_discovery.dart    # mDNS device discovery
│   └── usb_bridge.dart            # USB device integration
└── controllers/                # State management
    └── webadb_controller.dart      # WebADB server control
```

### 🔄 **State Management**
- **Provider pattern** for global state
- **Singleton services** for connection management
- **Stream controllers** for real-time updates
- **SharedPreferences** for data persistence

### 🔐 **Security Features**
- **Local-only data storage** - No cloud data transmission
- **Encrypted connections** - SSH, VNC, RDP use standard encryption
- **Secure credential storage** - Passwords stored locally only
- **Permission management** - Minimal required permissions

---

## 🚧 **Development Status**

### 📊 **Feature Status Summary**

| Feature Category | Status | Notes |
|-----------------|--------|-------|
| **SSH Terminal** | ✅ Fully Working | Persistent connections, hotkeys, session management |
| **File Management** | ✅ Fully Working | Copy/paste/delete/rename/archive all functional |
| **ADB Manager** | ✅ Fully Working | Wi-Fi, USB, pairing, file ops, package management |
| **VNC Client** | ✅ Fully Working | Multiple auth types, scaling modes, clipboard sync |
| **RDP Client** | ⚠️ Partial | Connection testing works, use Guacamole for full features |
| **Network Scanner** | ✅ Fully Working | Subnet scanning, mDNS discovery, port detection |
| **Device Info** | ✅ Fully Working | System monitoring, hardware details, performance metrics |
| **Process Manager** | ✅ Fully Working | Process listing, monitoring, resource usage |
| **Package Manager** | ✅ Fully Working | Package listing, install/uninstall operations |
| **WebADB Server** | ✅ Fully Working | HTTP API for ADB operations |

### ✅ **Completed Features**
- [x] SSH terminal with persistent connections across screen changes
- [x] Android ADB management (Wi-Fi, USB, pairing)
- [x] VNC remote desktop client with native protocol
- [x] Network device discovery and scanning
- [x] Device information and real-time monitoring
- [x] File transfer and management (SSH and ADB)
- [x] Complete file operations (copy, cut, paste, delete, rename, archive)
- [x] Material 3 UI implementation with dark/light themes
- [x] Background service for persistent connections
- [x] Connection state management with auto-reconnect
- [x] Settings and preferences with data persistence
- [x] Multi-session terminal support
- [x] Terminal font size controls with persistence
- [x] Quick commands menu for common operations

### ⚠️ **Partially Implemented**
- [x] RDP client (connection testing works, requires Guacamole for full desktop functionality)
- [x] WebADB server (functional HTTP API, can be extended with more endpoints)

### 🔮 **Future Enhancements**
- [ ] Native RDP protocol implementation (currently requires Guacamole)
- [ ] SFTP file transfer integration (currently uses SSH commands)
- [ ] SSH key-based authentication (currently password-based)
- [ ] Custom SSH key management interface
- [ ] Enhanced connection encryption options
- [ ] Advanced network monitoring dashboard
- [ ] Plugin system for additional protocols
- [ ] Tablet-optimized split-screen layouts
- [ ] Desktop companion app (Windows/Mac/Linux)
- [ ] File editor integration for remote file editing
- [ ] Scripting/automation features

### 🐛 **Known Issues**

**Build & Compilation:**
- Kotlin compilation warnings during build (cosmetic only, does not affect functionality)
- Some deprecation warnings in dependencies (scheduled for future updates)

**SSH & Terminal:**
- Terminal session persistence works across screen changes and app backgrounding
- Font size adjustments persist across sessions
- Cursor tracking automatically ensures visibility

**File Management:**
- SSH file operations (copy, cut, paste, delete) fully functional
- File operations execute commands via SSH shell
- Large file transfers may timeout on slow connections (consider using compression)

**VNC & RDP:**
- VNC security lockout requires server restart after multiple failed authentication attempts
- RDP native mode limited to connection testing (use Guacamole mode for full functionality)
- WebView-based implementations require stable network connection

**Network & Discovery:**
- Network scanning speed depends on subnet size and network conditions
- Some firewalls may block discovery protocols (mDNS)

**General:**
- First-time connection may take longer as SSH keys are exchanged
- Background service notification required for persistent terminal sessions

---

## 🔧 **Troubleshooting**

### **SSH Connection Issues**
- **Problem:** Cannot connect to SSH server
  - Verify host, port, username, and password are correct
  - Ensure SSH server is running on target device
  - Check firewall rules allow SSH connections (port 22 by default)
  - Try connecting from another SSH client to verify server availability

- **Problem:** Terminal session disconnects
  - Check network stability
  - Increase SSH timeout settings on server
  - Ensure foreground service notification is active

### **File Management Issues**
- **Problem:** File operations fail
  - Verify SSH connection is active
  - Check file permissions on target system
  - Ensure sufficient storage space
  - Use absolute paths when possible

- **Problem:** Copy/Paste not working
  - Verify files are selected before copying
  - Check that clipboard contains valid items
  - Ensure target directory has write permissions
  - Try with smaller files first to verify functionality

### **ADB Connection Issues**
- **Problem:** Cannot discover ADB devices
  - Enable Developer Options on Android device
  - Enable Wireless Debugging in Developer Options
  - Ensure both devices are on same network
  - Check if device IP/port are correct

- **Problem:** ADB connection refused
  - Pair device first (Android 11+)
  - Verify wireless debugging is enabled
  - Restart ADB server on device
  - Check if another ADB client is connected

### **VNC/RDP Issues**
- **Problem:** Cannot connect to VNC server
  - Verify VNC server is running on target
  - Check firewall allows VNC port (usually 5900+)
  - Verify VNC password is correct
  - Try with authentication disabled first (if safe to do so)

- **Problem:** RDP connection fails
  - For full RDP, set up Guacamole server
  - Native RDP mode is for connection testing only
  - Verify RDP is enabled on Windows target
  - Check network policies allow RDP connections

### **Performance Issues**
- **Problem:** Slow terminal response
  - Reduce terminal font size
  - Disable terminal decorations
  - Check network latency
  - Close unused sessions

- **Problem:** File browsing slow
  - Reduce number of files in directory
  - Use search to find specific files
  - Disable hidden files view if not needed
  - Consider using terminal commands for bulk operations

---

## 🤝 **Contributing**

We welcome contributions from the community! Whether you're fixing bugs, adding features, or improving documentation, your help is appreciated.

### **How to Contribute**

1. **Fork the repository**
2. **Create a feature branch:** `git checkout -b feature/amazing-feature`
3. **Make your changes** and test thoroughly
4. **Commit your changes:** `git commit -m 'Add amazing feature'`
5. **Push to the branch:** `git push origin feature/amazing-feature`
6. **Open a Pull Request**

### **Development Guidelines**

- Follow Dart/Flutter style guidelines
- Add tests for new functionality
- Update documentation for new features
- Ensure builds pass on all target platforms
- Test on multiple Android versions when possible

### **Reporting Issues**

Found a bug or have a feature request? Please check existing issues first, then create a new issue with:
- Clear description of the problem
- Steps to reproduce
- Expected vs actual behavior
- Device/Android version information
- Logs or screenshots if applicable

---

## 📄 **License**

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

### **MIT License Summary**
- ✅ Commercial use allowed
- ✅ Modification allowed  
- ✅ Distribution allowed
- ✅ Private use allowed
- ❗ No warranty provided
- ❗ Author not liable for damages

---

## 🙏 **Acknowledgments**

### **Open Source Libraries**
- **Flutter Team** - Amazing cross-platform framework
- **dartssh2** - Robust SSH implementation
- **xterm** - Excellent terminal emulation
- **Syncfusion** - Beautiful charts and gauges
- **Community contributors** - Various Flutter packages

### **Inspiration**
- **ConnectBot** - Android SSH client inspiration
- **Termux** - Terminal emulator concepts
- **VNC Viewer** - Remote desktop UX patterns
- **ADB Wireless** - ADB management ideas

---

## 📞 **Contact & Support**

- **GitHub Issues:** [Report bugs and request features](https://github.com/mmry2940/LitterBox/issues)
- **Discussions:** [Community discussions and Q&A](https://github.com/mmry2940/LitterBox/discussions)
- **Repository:** [View source code](https://github.com/mmry2940/LitterBox)

### **Support the Project**
If you find LitterBox helpful, consider:
- ⭐ **Starring the repository**
- 🐛 **Reporting bugs** you encounter
- 💡 **Suggesting new features**
- 🔧 **Contributing code** improvements
- 📚 **Improving documentation**
- 💬 **Helping other users** in discussions

---

**Made with ❤️ for the developer community**

*LitterBox - Your portable toolkit for remote access and device management*
