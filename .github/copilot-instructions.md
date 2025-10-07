# LitterBox - AI Coding Agent Instructions

## Project Overview
LitterBox is a Flutter-based mobile app that provides remote connection tools and Android development utilities. It's a "toolbox" app for developers containing ADB management, VNC/RDP clients, SSH connections, and device management features.

## Core Architecture

### Multi-Backend ADB System
- **Hybrid Backend**: Uses both native Flutter ADB (`flutter_adb`) and external system ADB
- **Backend Types**: `AdbBackendType` enum with `external`, `internal`, `native`, `hybrid` modes
- **Primary Classes**: `ADBClientManager`, `EnhancedAdbManager`, `ADBBackend` interface
- **Singleton Pattern**: `SharedADBManager` ensures single ADB connection across screens
- **File Locations**: `lib/adb_client.dart`, `lib/adb_backend.dart`, `lib/adb/enhanced_adb_manager.dart`

### Connection Management Pattern
- **State Streams**: All clients use `StreamController<ConnectionState>` for real-time status
- **Connection States**: `disconnected`, `connecting`, `connected`, `failed` enum pattern
- **Shared Output**: Unified console output streams across all connection types
- **Persistence**: Device configurations saved via `SharedPreferences` JSON serialization

### Navigation & State Architecture
- **Home Screen Hub**: `lib/screens/home_screen.dart` - main device list and dashboard
- **Modal Screens**: Each tool (ADB, VNC, RDP) has dedicated full screens
- **Settings Integration**: Theme, text scale, startup page via global `ValueNotifier`s
- **Responsive Design**: Uses `flutter_breakpoints` for adaptive layouts

## Key Development Patterns

### Device Connection Workflow
```dart
// Standard pattern for all connection types
1. Test connection (optional) - basic TCP connectivity
2. Connect with credentials - full protocol handshake  
3. Stream state updates - real-time status via StreamController
4. Handle failures - detailed error messages with troubleshooting
5. Cleanup on disconnect - proper resource disposal
```

### Stream Management Convention
- Always use `.broadcast()` controllers for multiple listeners
- Dispose controllers in widget `dispose()` methods
- Use `StreamSubscription` variables for manual cleanup
- Handle both connection state and output streams separately

### Settings & Persistence
- **SharedPreferences Keys**: Use descriptive prefixes (`adb_devices`, `vnc_profiles`, `favorite_devices`)
- **JSON Serialization**: Store complex objects as JSON strings
- **Global Notifiers**: `themeModeNotifier`, `colorSeedNotifier`, `textScaleNotifier` in `main.dart`
- **Favorites System**: Set-based storage for starred connections

## Network & Protocol Implementation

### VNC Client Features
- **Full RFB Protocol**: Supports versions 3.3, 3.8, 5.0+ with proper version negotiation
- **Authentication Types**: None, VNC (DES), RA2, RA2ne, ATEN, VeNCrypt with AES
- **DES Encryption**: VNC-specific bit-reversed password encryption in `_encryptChallenge()`
- **Connection Modes**: Demo, WebView (noVNC), Native client options
- **File Location**: `lib/vnc_client.dart` (~3800 lines of protocol implementation)

### Network Discovery
- **Subnet Scanning**: Isolate-based ping scanning with progress reporting
- **mDNS Discovery**: `AdbMdnsDiscovery` for automatic device detection  
- **Caching**: Scan results cached by subnet with timestamp validation
- **Background Processing**: Heavy network operations run in isolates

### ADB Protocol Details
- **Multiple Backends**: External adb binary, internal mock, Flutter native ADB
- **Protocol Client**: Low-level ADB protocol implementation in `ADBProtocolClient`
- **Shell Management**: Interactive shell sessions with persistent processes
- **File Transfer**: Push/pull with progress streaming support
- **Port Forwarding**: Local port to device service tunneling

## UI/UX Patterns

### Error Handling Strategy
- **User-Friendly Messages**: Convert technical errors to actionable guidance
- **Troubleshooting Hints**: Include specific steps for common failures
- **Debug Information**: Detailed logs available but hidden by default
- **Status Indicators**: Color-coded connection states with clear icons

### Responsive Design Approach
- **Wide Screen Detection**: `constraints.maxWidth >= 800` for tablet layouts
- **Adaptive Grids**: Dynamic column counts based on screen size
- **Drawer Navigation**: Consistent sidebar with theme controls and quick actions
- **Multi-Select Operations**: Batch device management with checkbox selection

### Theming & Accessibility
- **Material 3**: Full Material Design 3 theming with dynamic color
- **Semantic Labels**: Comprehensive screen reader support with `Semantics` widgets
- **Text Scaling**: Configurable text scale from 0.8x to 1.6x
- **Dark Mode**: Automatic theme switching with user preference persistence

## Development Workflows

### Adding New Connection Types
1. Create enum value in appropriate `ConnectionState` enum
2. Implement client class following existing patterns (`VNCClient`, `RDPClient`)
3. Add UI screen in `lib/screens/` with standard form layout
4. Integrate with `SharedPreferences` for persistence
5. Add drawer navigation entry and route handling

### Backend Integration
- **External Dependencies**: Handle missing system tools gracefully with fallbacks
- **Platform Channels**: Use for native Android features when needed
- **Embedded Binaries**: Store in `assets/` with platform-specific paths
- **Error Recovery**: Always provide fallback options when external tools fail

### Testing Connection Flows
- **Test Methods**: Implement `testConnection()` for basic connectivity checks
- **Debug Modes**: Provide detailed handshake debugging for protocol development
- **Mock Backends**: Internal backends for offline development and testing
- **Logging Strategy**: Verbose logging with performance-conscious buffering

## Performance Considerations

### Stream Optimization
- **Buffer Management**: Limit console output buffer sizes (default 500 lines)
- **Throttled Updates**: Use timers to batch UI updates (e.g., 250ms intervals)
- **Memory Cleanup**: Proper disposal of StreamControllers and subscriptions
- **Background Processing**: CPU-intensive tasks run in isolates

### Network Efficiency
- **Connection Pooling**: Reuse ADB connections across operations
- **Incremental Updates**: VNC frame updates use incremental mode after initial frame
- **Request Throttling**: Limit frame update frequency based on connection speed
- **Compression**: Support for compressed VNC encodings when available

## Common Gotchas

### ADB Backend Switching
- **State Consistency**: Always check current backend before operations
- **Client Selection**: `_getActiveClient()` pattern for choosing appropriate backend
- **Cleanup Timing**: Dispose old backends before initializing new ones
- **Connection Inheritance**: Some operations may need specific backend types

### Stream Listener Management  
- **Single Listeners**: Avoid "already listened to stream" errors with `.broadcast()`
- **Subscription Tracking**: Store `StreamSubscription` references for cleanup
- **Widget Lifecycle**: Cancel subscriptions in `dispose()` methods
- **Error Propagation**: Handle stream errors gracefully without crashing

### Network Security
- **Cleartext Traffic**: Android 9+ requires network security config for local connections
- **Certificate Validation**: Handle self-signed certificates for internal servers
- **Permission Requirements**: INTERNET and ACCESS_NETWORK_STATE permissions
- **Timeout Handling**: Generous timeouts for slow network environments

This architecture prioritizes modularity, error recovery, and user experience while maintaining clean separation between UI and protocol implementation layers.