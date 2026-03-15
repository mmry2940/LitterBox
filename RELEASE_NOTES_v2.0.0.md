# LitterBox v2.0.0 - Major Release 🚀

## 📱 **What's New in 2.0.0?**

Version 2.0.0 is a major update that significantly expands LitterBox beyond SSH, ADB, and VNC. It adds ESP32 microcontroller management, a dedicated App Manager, in-app security with encrypted credential storage, background synchronization, connection pooling, device sorting, and a suite of new UI widgets and service improvements.

---

## ✅ **What Was Added**

### 🔌 ESP32 Manager *(new screen)*
- Connect to ESP32 microcontrollers via **Bluetooth** or **LAN / Wi-Fi**
- **Interactive REPL** console with command history (MicroPython / Lua)
- **GPIO monitoring** — view and toggle pin states in real time
- **Sensor data** — temperature, humidity, and custom sensor readings
- **File system browser** for on-device file management
- **Firmware info** — chip model, MAC address, CPU frequency, free memory
- Save and restore ESP32 device configurations
- Detailed scan results with progress tracking

### 📱 App Manager *(new screen)*
- Browse **installed apps** on the connected ADB device (user & system)
- **Search and filter** by name, and filter by category: All / User / System / Enabled / Disabled
- **Batch operations** — select multiple apps and uninstall or act in bulk
- **Favorites** — star frequently used packages for quick access
- Uses the shared ADB connection (`SharedADBManager`) for seamless integration

### 🔐 Security Settings & Encrypted Storage *(new screen + services)*
- **Encrypted credential storage** — all saved passwords encrypted with device-specific key derivation (`SecureStorageService`)
- **Secure ADB device manager** (`SecureADBDeviceManager`) for protected ADB connection storage
- **Secure VNC device manager** (`SecureVNCDeviceManager`) for protected VNC profile storage
- **Security health reports** — `SecurityConfigService.performSecurityCheck()` evaluates password expiration, cleanup status, and security policy compliance
- **Security config screen** — view ADB and VNC connection stats, run security checks, manage policies
- Configurable security policies: session timeout, max failed attempts, lockout duration, password expiration, max saved devices

### 🔄 Background Sync Service *(new service)*
- Automatic background data synchronization for saved devices (`BackgroundSyncService`)
- Caches system info (CPU, memory, disk) for offline viewing
- Heartbeat monitoring to detect device availability changes
- Per-device sync toggle with configurable intervals
- Event stream for sync activity reporting

### 🔗 Connection Pool Manager *(new service)*
- `ConnectionPoolManager` manages pooled SSH/network connections with health monitoring
- **Circuit breaker** pattern — automatically pauses failing connections
- **Connection quality tracking** — latency, packet loss, bandwidth estimation
- **Adaptive timeouts** — adjusts based on measured connection quality
- **Keep-alive** mechanisms and periodic health checks
- Network state awareness (`NetworkState`) for optimizing reconnection strategy

### 🤝 Shared ADB Manager *(new service)*
- `SharedADBManager` singleton provides a single shared ADB client across screens
- Eliminates duplicate ADB connections when navigating between App Manager, ADB screen, and device screens

### 📊 New Widgets
- **`ConnectionManagementPanel`** — bottom-sheet hub for managing all active connections (accessible from drawer)
- **`ConnectionQualityIndicator`** — visual signal-strength bar widget showing live connection health
- **`DeviceSummaryCard`** — compact card summarising device type, host, and status
- **`EnhancedADBDashboard`** — improved ADB overview dashboard
- **`EnhancedADBDeviceCard`** — richer ADB device card with status indicators
- **`EnhancedMiscCard`** — additional miscellaneous tools card
- **`ESP32ScanTestDialog`** — guided scan-and-test dialog for ESP32 devices

### 🗂️ New Models
- `AppInfo` — structured package metadata for the App Manager
- `SecureADBDevice` — ADB device model with encrypted credential fields
- `SecureVNCDevice` — VNC device model with encrypted credential fields

### 🏠 Home Screen Improvements
- **`DeviceSortMode` enum** — sort SSH hosts by **Name**, **Host**, or **Status**
- **Filtering and sorting controls** in the home screen host list
- **Connection refused = alive** — network scanner now correctly marks hosts that refuse TCP connections as reachable

### 🛠️ Code Quality Improvements
- Replaced `print()` calls with `debugPrint()` throughout the codebase for proper log management
- Refactored `_showPairingDialog` (ADB screen) for better readability and consistency
- Periodic stats refresh added to `ConnectionManagementPanel`
- Cleaned up unused variables across multiple screens
- Improved overall UI responsiveness

---

## ❌ **What Was Removed**

### 💻 RDP Screen
- The dedicated **RDP remote desktop screen** (`rdp_screen.dart`) has been **removed**.
- The RDP implementation in v1.0.0 was limited to connection testing via Guacamole WebView and provided no meaningful native RDP functionality.
- The default **RDP port (3389)** setting is still available in Settings for future use when a proper RDP implementation is added.

---

## 🔧 **What Was Fixed**

| Area | Fix |
|------|-----|
| Network Scanner | `_probeHost` now treats TCP "connection refused" as a valid alive signal, reducing false negatives |
| ADB | `_showPairingDialog` refactored for cleaner state management and error handling |
| ESP32 | `_ESP32ScreenState` tracks progress dialog state to prevent duplicate dialogs and provides richer scan feedback |
| Logging | All `print()` statements replaced with `debugPrint()` to respect debug/release build modes |
| Connection Panel | `ConnectionManagementPanel` now auto-refreshes stats periodically |
| Code Quality | Unused variables removed; improved readability across all major screens |

---

## 🛠 **Technical Specifications**

| Property | Value |
|----------|-------|
| **Version** | 2.0.0+2 |
| **Target SDK** | Android 34 (Android 14) |
| **Minimum SDK** | Android 21 (Android 5.0) |
| **Framework** | Flutter 3.24.0 |
| **Dart** | 3.5.0+ |
| **Architecture** | ARM64, ARMv7, x86_64 |
| **Build Date** | March 2026 |

---

## 📦 **Download Options**

### **For Regular Users**
- **app-release.apk** — Optimized production build, recommended for most users

### **For Developers & Testers**
- **app-debug.apk** — Debug build with additional logging and development features
- **app-release.aab** — Android App Bundle for Google Play Store

---

## 🔐 **Security & Privacy**

- ✅ **No data collection** — All connections are direct between your device and target servers
- ✅ **Encrypted local storage** — Connection passwords encrypted with device-specific key derivation (new in 2.0.0)
- ✅ **Encrypted connections** — SSH and VNC use industry-standard encryption
- ✅ **Open source** — Full source code available for transparency

---

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
- VNC server for remote desktop functionality
- ESP32 device with MicroPython/HTTP support for ESP32 features

---

## 🚀 **Getting Started**

1. **SSH Connections**: Add your server details (host, port, username, password/key) from the home screen
2. **ADB Devices**: Enable wireless debugging on Android and use the ADB screen to connect
3. **VNC**: Configure your VNC server and connect from the VNC screen
4. **ESP32**: Add your ESP32 device (Bluetooth or IP) from the new ESP32 screen
5. **App Manager**: Connect via ADB first, then open App Manager to browse installed apps
6. **Network Scanning**: Discover and sort devices on your local network automatically

---

## 📝 **Known Issues**

- Some Kotlin compilation warnings during build (do not affect functionality)
- VNC "security failures" may require server restart if too many failed attempts occur
- Large file transfers may timeout on slow network connections

---

## 🤝 **Contributing**

This is an open-source project. Feel free to:
- Report bugs and issues
- Suggest new features
- Submit pull requests
- Improve documentation

## 📄 **License**

This project is released under the MIT License. See [LICENSE](LICENSE) for details.

---

**Made with ❤️ for the developer community**

*LitterBox — Your portable toolkit for remote access, device management, and IoT control*
