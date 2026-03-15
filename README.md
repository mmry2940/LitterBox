# LitterBox 🧰

[![Flutter](https://img.shields.io/badge/Flutter-3.24.0-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.5.0-0175C2?logo=dart)](https://dart.dev)
[![Android](https://img.shields.io/badge/Android-5.0+-3DDC84?logo=android)](https://developer.android.com)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Release](https://img.shields.io/badge/Release-v2.0.0-blue)](https://github.com/mmry2940/LitterBox/releases)

> **A powerful remote access toolkit for Android developers, system administrators, and IoT engineers**

LitterBox is a comprehensive Android application that brings together essential remote access and device management tools in one convenient package. Whether you're managing servers via SSH, debugging Android devices with ADB, accessing remote desktops through VNC, managing ESP32 microcontrollers, or monitoring connection quality — LitterBox provides the tools you need with a modern, secure, and intuitive interface.

> **🆕 Version 2.0.0** — Major update adding ESP32 support, in-app security, background sync, connection pooling, app management, and more. See [RELEASE_NOTES_v2.0.0.md](RELEASE_NOTES_v2.0.0.md) for the full changelog.

## ✨ Features Overview

### 🔧 **Core Functionality**
- **SSH Terminal** - Full-featured terminal with persistent connections
- **Android ADB Manager** - Comprehensive ADB interface for device management  
- **VNC Client** - Native VNC remote desktop viewer
- **ESP32 Manager** - Connect and control ESP32 microcontrollers via Bluetooth or LAN
- **Network Scanner** - Discover and sort devices on your local network
- **Device Manager** - Centralized connection management with connection pooling
- **App Manager** - Browse, search, and manage installed apps on connected Android devices

### 🔐 **Security**
- **Encrypted credential storage** - Connection passwords stored with device-specific encryption
- **Security health reports** - Real-time overview of stored credentials and security posture
- **Security settings screen** - Manage policies, view stats, and audit saved connections

### 🎨 **User Experience**
- **Material 3 Design** - Modern, responsive UI following Google's design principles
- **Dark/Light Themes** - Automatic theme switching and manual toggle
- **Responsive Layout** - Optimized for phones and tablets
- **Device sorting & filtering** - Sort SSH hosts by name, host, or status
- **Connection quality indicator** - Visual signal-strength widget for active connections
- **Background sync** - Automatic data synchronization for saved devices

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

### 🔌 **ESP32 Manager** ✅ **New in 2.0.0**

<details>
<summary>Click to expand ESP32 features</summary>

**Connection Methods:**
- ✅ **Bluetooth** - Scan and connect to nearby ESP32 devices via Bluetooth
- ✅ **LAN / Wi-Fi** - Connect over IP to ESP32 devices on the local network
- ✅ **Saved devices** - Persist ESP32 device configurations across sessions

**Device Control:**
- ✅ **REPL console** - Interactive MicroPython/Lua REPL with command history
- ✅ **GPIO monitoring** - View and toggle GPIO pin states in real time
- ✅ **Sensor data** - Read temperature, humidity, and other sensor values
- ✅ **File system** - Browse and manage files on the device
- ✅ **Firmware info** - Chip model, MAC address, CPU frequency, free memory

**Technical Stack:**
- HTTP API communication for LAN-connected devices
- Bluetooth service integration via platform channels
- `esp32_scan_test_dialog` for scan/test workflow

</details>

### 📱 **App Manager** ✅ **New in 2.0.0**

<details>
<summary>Click to expand App Manager features</summary>

**App Operations:**
- ✅ **Installed apps list** - View all user and system apps on connected ADB device
- ✅ **Search & filter** - Filter by All / User / System / Enabled / Disabled
- ✅ **Batch operations** - Select multiple apps and uninstall or perform actions in bulk
- ✅ **Favorites** - Mark frequently used packages for quick access
- ✅ **APK installation** - Install APKs via file picker

**Technical Stack:**
- Shared ADB connection via `SharedADBManager`
- `AppInfo` model for structured package metadata

</details>

### 🔐 **Security Settings** ✅ **New in 2.0.0**

<details>
<summary>Click to expand Security features</summary>

**Credential Security:**
- ✅ **Encrypted storage** - All passwords encrypted with device-specific key derivation
- ✅ **Secure ADB devices** - Saved ADB configurations protected by `SecureADBDeviceManager`
- ✅ **Secure VNC devices** - VNC profiles stored via `SecureVNCDeviceManager`

**Security Health:**
- ✅ **Health report** - `SecurityConfigService.performSecurityCheck()` produces a detailed `SecurityHealthReport`
- ✅ **Connection stats** - View counts of saved ADB and VNC connections
- ✅ **Configurable policies** - Password expiration, max saved devices, session timeout, max failed attempts, lockout duration

**Settings Screen Integration:**
- ✅ **Session management** - Configure authentication timeout
- ✅ **Security settings screen** - Dedicated screen accessible from the Settings drawer

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

**File Operations:**
- ✅ **Remote file browser** - Navigate remote filesystem via SSH
- ✅ **File transfer** - Upload/download files between devices
- ✅ **Directory navigation** - Intuitive folder browsing
- ✅ **File selection** - Multi-select for batch operations

**ADB File Operations:**
- ✅ **Push files** - Transfer files to Android devices
- ✅ **Pull files** - Download files from Android devices
- ✅ **APK installation** - Install applications via file picker
- ✅ **Path management** - Recent paths and quick access

**File Picker Integration:**
- Uses `file_picker` package (downgraded to 8.0.3 for compatibility)
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
- `shared_preferences: ^2.2.2` - Local data persistence
- `file_picker: ^10.3.3` - File system integration

#### **Network & Discovery**
- `network_tools: ^6.0.2` - Network scanning utilities
- `network_info_plus: ^7.0.0` - Network information
- `multicast_dns: ^0.3.2` - mDNS service discovery
- `connectivity_plus: ^7.0.0` - Network connectivity monitoring

#### **Security & Encryption**
- `crypto: ^3.0.3` - Cryptographic operations
- `pointycastle: ^3.9.1` - Dart cryptography library

#### **Platform Integration**
- `webview_flutter: ^4.4.2` - WebView for noVNC
- `path_provider: ^2.1.4` - Platform directories
- `http: ^1.2.0` - HTTP client for ESP32 and WebADB
- `web_socket_channel: ^3.0.1` - WebSocket support

### 🏛️ **Application Structure**

```
lib/
├── main.dart                         # Application entry point
├── screens/                          # Main UI screens
│   ├── home_screen.dart              # Device dashboard with sort/filter
│   ├── device_screen.dart            # Device detail tabs
│   ├── device_terminal_screen.dart   # SSH terminal
│   ├── device_info_screen.dart       # System information
│   ├── device_details_screen.dart    # Enhanced device details
│   ├── device_files_screen.dart      # Remote file browser
│   ├── device_logs_screen.dart       # Logcat / log viewer
│   ├── device_packages_screen.dart   # Package listing
│   ├── device_processes_screen.dart  # Process monitoring
│   ├── device_misc_screen.dart       # Miscellaneous device tools
│   ├── adb_screen_refactored.dart    # ADB management
│   ├── adb_cards_preview_screen.dart # ADB card previews
│   ├── apps_screen.dart              # App Manager (NEW)
│   ├── esp32_screen.dart             # ESP32 Manager (NEW)
│   ├── vnc_screen.dart               # VNC connection list
│   ├── vnc_viewer_screen.dart        # VNC remote desktop viewer
│   ├── security_settings_screen.dart # Security settings (NEW)
│   └── settings_screen.dart          # App settings
├── models/                           # Data models
│   ├── device_status.dart            # Device connection status
│   ├── saved_adb_device.dart         # Saved ADB configurations
│   ├── saved_vnc_device.dart         # Saved VNC configurations
│   ├── secure_adb_device.dart        # Encrypted ADB device storage (NEW)
│   ├── secure_vnc_device.dart        # Encrypted VNC device storage (NEW)
│   └── app_info.dart                 # App package metadata (NEW)
├── services/                         # Background services
│   ├── device_status_monitor.dart    # Connection monitoring
│   ├── background_sync_service.dart  # Background data sync (NEW)
│   ├── connection_pool_manager.dart  # Connection pooling with health checks (NEW)
│   ├── shared_adb_manager.dart       # Shared ADB connection manager (NEW)
│   ├── secure_storage_service.dart   # Encrypted credential storage (NEW)
│   ├── security_config_service.dart  # Security policies & health checks (NEW)
│   ├── adb_connection_manager.dart   # ADB connection lifecycle
│   └── esp32_service.dart            # ESP32 device service (NEW)
├── widgets/                          # Reusable UI components
│   ├── enhanced_device_card.dart     # Device cards
│   ├── adb_connection_wizard.dart    # ADB setup wizard
│   ├── connection_management_panel.dart  # Connection hub panel (NEW)
│   ├── connection_quality_indicator.dart # Signal-strength widget (NEW)
│   ├── device_summary_card.dart      # Compact device summary (NEW)
│   ├── enhanced_adb_dashboard.dart   # Improved ADB dashboard (NEW)
│   ├── enhanced_adb_device_card.dart # ADB device card (NEW)
│   ├── enhanced_misc_card.dart       # Misc tools card (NEW)
│   └── esp32_scan_test_dialog.dart   # ESP32 scan dialog (NEW)
├── adb/                              # ADB implementation
│   ├── flutter_adb_client.dart       # Flutter-native ADB
│   ├── adb_mdns_discovery.dart       # mDNS device discovery
│   ├── embedded_adb_manager.dart     # Embedded ADB manager
│   ├── enhanced_adb_manager.dart     # Enhanced ADB operations
│   └── usb_bridge.dart               # USB device integration
└── controllers/                      # State management
    └── webadb_controller.dart        # WebADB server control
```

### 🔄 **State Management**
- **Provider pattern** for global state
- **Singleton services** for connection management
- **Stream controllers** for real-time updates
- **SharedPreferences** for data persistence

### 🔐 **Security Features**
- **Local-only data storage** - No cloud data transmission
- **Encrypted connections** - SSH and VNC use standard encryption
- **Secure credential storage** - Passwords encrypted with device-specific keys (new in 2.0.0)
- **Permission management** - Minimal required permissions

---

## 🚧 **Development Status**

### ✅ **Completed Features**
- [x] SSH terminal with persistent connections
- [x] Android ADB management (Wi-Fi, USB, pairing)
- [x] VNC remote desktop client
- [x] Network device discovery with sorting and filtering
- [x] Device information and monitoring
- [x] File transfer and management
- [x] Material 3 UI implementation
- [x] Background service integration
- [x] Connection state management
- [x] Settings and preferences
- [x] **ESP32 management** (Bluetooth & LAN) *(new in 2.0.0)*
- [x] **App Manager** (batch ops, favorites, filter) *(new in 2.0.0)*
- [x] **Security settings** (encrypted storage, health reports) *(new in 2.0.0)*
- [x] **Background sync service** *(new in 2.0.0)*
- [x] **Connection pool manager** with health checks *(new in 2.0.0)*
- [x] **Connection quality indicator widget** *(new in 2.0.0)*
- [x] **Device sorting & filtering** in home screen *(new in 2.0.0)*

### ⚠️ **Partially Implemented**
- [x] WebADB server (functional but could use more features)

### ❌ **Removed in 2.0.0**
- ~~RDP client~~ — The dedicated RDP screen has been removed. RDP port is still configurable in settings for future use.

### 🔮 **Future Enhancements**
- [ ] Native RDP protocol implementation
- [ ] SFTP file transfer integration
- [ ] Custom SSH key management
- [ ] Advanced network monitoring
- [ ] Plugin system for additional protocols
- [ ] Tablet-optimized layouts
- [ ] Desktop companion app

### 🐛 **Known Issues**
- Kotlin compilation warnings during build (cosmetic only)
- VNC security lockout requires server restart after multiple failures
- Large file transfers may timeout on slow connections

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
- **Email:** [Contact maintainer](mailto:your-email@domain.com)

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
