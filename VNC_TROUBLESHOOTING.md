# VNC Viewer Troubleshooting Guide

## 1. VNC Viewer Settings Overview

### Current Settings Configuration
- **Default Connection Mode**: Native VNC Client
- **Default Scaling Mode**: Center Crop (scaleToFitWidth)
- **Default Orientation**: Landscape (forced)
- **Default Resolution**: Auto-detected from server

## 2. Scaling Mode Issues

### Problem: Display shows multiple screens or incorrect scaling

**Steps to fix:**
1. **Tap the aspect ratio button** (□) in the control bar to cycle through scaling modes:
   - `scaleToFitWidth` (centerCrop) - Recommended for mobile
   - `scaleToFit` (fitToScreen) - Shows entire desktop
   - `scaleToFitHeight` - Fits height
   - `actualSize` - 1:1 mapping (may be very large)

2. **If scaling is still incorrect:**
   ```dart
   // Check current scaling mode in connection info
   // Tap the info button (i) to see current settings
   ```

3. **Best practices for mobile:**
   - Use `scaleToFitWidth` for most cases
   - Use `scaleToFit` if you need to see the entire desktop
   - Avoid `actualSize` unless you need pixel-perfect accuracy

### Problem: Remote desktop appears too small/large

**Solution:**
1. Press the aspect ratio button to change scaling mode
2. For better visibility, use `scaleToFitWidth` or `scaleToFit`
3. Check server resolution in connection info dialog

## 3. Connection Issues

### Problem: "VNC Client not initialized" error

**Steps to fix:**
1. Ensure you're using native VNC mode
2. Check connection parameters:
   - Host IP address is correct
   - Port 5900 (or custom port) is accessible
   - Password is correct (if required)
3. Try test connection first before full connect

### Problem: "Disconnected from VNC server" overlay appears

**Steps to fix:**
1. Check network connectivity
2. Verify VNC server is running
3. Check firewall settings on both client and server
4. Ensure VNC server accepts the connection type (password/no auth)

### Problem: Connection fails immediately

**Diagnostic steps:**
1. Use "Test Connection" button first
2. Check terminal output for detailed error messages
3. Verify server supports RFB protocol version 3.3 or 3.8
4. Check if server requires specific security types

## 4. Display Quality Issues

### Problem: Blurry or pixelated display

**Solutions:**
1. Check server pixel format in connection info:
   - Should show 32bpp or 16bpp
   - Higher is better for quality
2. Ensure stable network connection
3. Try different scaling modes

### Problem: Display appears in wrong colors

**Troubleshooting:**
1. Check pixel format conversion in logs
2. Server may be using different color depth
3. Try reconnecting to refresh pixel format

### Problem: Display updates are slow

**Optimization steps:**
1. Check network latency
2. Ensure VNC server isn't overloaded
3. Consider using `actualSize` for less processing
4. Check frame buffer update frequency in logs

## 5. Control and Navigation Issues

### Problem: Can't see control bar

**Solutions:**
1. **Tap anywhere on screen** to toggle controls
2. If in fullscreen mode, tap to show controls temporarily
3. Use back gesture or hardware back button to disconnect

### Problem: Touch input not working

**Current status:**
- Touch input is mapped to VNC coordinates
- Scaling is considered for accurate positioning
- Works in landscape mode

### Problem: Can't exit viewer

**Steps:**
1. Tap screen to show controls
2. Press back arrow (←) button to disconnect and return
3. Or use device back button/gesture

## 6. Performance Optimization

### For better performance:
1. **Use Native VNC mode** (default) instead of WebView
2. **Choose appropriate scaling mode**:
   - `centerCrop` for best mobile experience
   - `fitToScreen` for complete desktop view
3. **Ensure good network connection**
4. **Close unnecessary apps** to free memory

### Monitor connection status:
1. Press info button (i) to see:
   - Connection state
   - Server resolution
   - Pixel format
   - Frame data size

## 7. Settings Access

### In VNC Viewer Screen:
- **Scaling Mode**: Tap aspect ratio button (□)
- **Fullscreen**: Tap fullscreen button
- **Connection Info**: Tap info button (i)
- **Disconnect**: Tap back arrow (←)

### In Main VNC Screen:
- **Connection Mode**: Dropdown (Native/WebView)
- **Scaling Mode**: Dropdown with descriptions
- **Save Device**: Save button after entering details
- **Load Device**: Select from saved devices list

## 8. Debug Information

### To get debug info:
1. Check Flutter console/logs for VNC messages
2. Use "Test Connection" for network diagnostics
3. Check connection info dialog for server details
4. Monitor frame buffer updates in logs

### Common log messages:
- `VNCClient: Connected successfully` - Good connection
- `VNCClient: Processing X bytes of pixel data` - Receiving updates
- `VNCClient: Unknown message type` - Protocol sync issue
- `VNCClient: Server pixel format: Xbpp` - Format info

## 9. Known Limitations

1. **Security Types**: Supports No Auth (1) and VNC Auth (2)
2. **Encodings**: Currently supports Raw encoding (0)
3. **Orientation**: Forced landscape in viewer
4. **Resolution**: Auto-detected, not manually configurable
5. **Color Depth**: Depends on server settings

## 10. Advanced Settings

Currently, advanced settings need code modification:

### To change default scaling mode:
```dart
// In vnc_viewer_screen.dart
VNCScalingMode _scalingMode = VNCScalingMode.scaleToFitWidth; // Change this
```

### To change default connection mode:
```dart
// In vnc_screen.dart  
VNCConnectionMode _connectionMode = VNCConnectionMode.native; // Already set
```

### To modify orientation:
```dart
// In vnc_viewer_screen.dart initState()
SystemChrome.setPreferredOrientations([
  DeviceOrientation.landscapeLeft,
  DeviceOrientation.landscapeRight,
  // Add portrait orientations if needed
]);
```
