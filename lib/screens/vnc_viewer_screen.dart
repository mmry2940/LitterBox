import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../vnc_client.dart';

enum VNCViewerMode {
  demo,
  webview, // noVNC via WebView
  native, // Native VNC client
}

class VNCViewerScreen extends StatefulWidget {
  final String host;
  final int port;
  final String? password;
  final VNCViewerMode mode;
  final VNCClient? vncClient;
  final WebViewController? webViewController;

  const VNCViewerScreen({
    super.key,
    required this.host,
    required this.port,
    this.password,
    required this.mode,
    this.vncClient,
    this.webViewController,
  });

  @override
  State<VNCViewerScreen> createState() => _VNCViewerScreenState();
}

class _VNCViewerScreenState extends State<VNCViewerScreen> {
  bool _showControls = false;
  bool _isFullscreen = false;
  VNCScalingMode _scalingMode =
      VNCScalingMode.autoFitBest; // Use auto-fit best as default

  @override
  void initState() {
    super.initState();
    // Force landscape orientation for VNC viewer
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    // Restore all orientations when leaving VNC viewer
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // Note: We don't automatically disconnect here because the user might want
    // to keep the connection when navigating back. Disconnection is handled
    // explicitly in _disconnect() when the user chooses to disconnect.
    super.dispose();
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
    });
  }

  void _disconnect() {
    widget.vncClient?.disconnect();
    Navigator.of(context).pop();
  }

  void _showConnectionInfo() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Connection Info & Settings'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Connection Info Section
                const Text('Connection Details:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                Text('Host: ${widget.host}'),
                Text('Port: ${widget.port}'),
                Text('Mode: ${widget.mode.name}'),
                Text('Scaling: ${_scalingMode.name}'),

                if (widget.vncClient != null) ...[
                  const SizedBox(height: 10),
                  StreamBuilder<VNCConnectionState>(
                    stream: widget.vncClient!.connectionState,
                    builder: (context, snapshot) {
                      // Since we navigate here when connected, default to connected if no data yet
                      final state =
                          snapshot.data ?? VNCConnectionState.connected;
                      Color statusColor = Colors.grey;
                      if (state == VNCConnectionState.connected) {
                        statusColor = Colors.green;
                      }
                      if (state == VNCConnectionState.connecting) {
                        statusColor = Colors.orange;
                      }
                      if (state == VNCConnectionState.failed) {
                        statusColor = Colors.red;
                      }

                      return Text('Status: ${state.name}',
                          style: TextStyle(
                              color: statusColor, fontWeight: FontWeight.bold));
                    },
                  ),
                  if (widget.vncClient?.frameBuffer != null) ...[
                    Text(
                        'Resolution: ${widget.vncClient!.frameBuffer!.width}x${widget.vncClient!.frameBuffer!.height}'),
                    Text(
                        'Pixel Format: ${widget.vncClient!.frameBuffer!.pixelFormat.bitsPerPixel}bpp'),
                    Text(
                        'Server: ${widget.vncClient!.frameBuffer!.serverName}'),
                    if (widget.vncClient!.frameBuffer!.pixels != null)
                      Text(
                          'Frame Data: ${widget.vncClient!.frameBuffer!.pixels!.length} bytes'),
                  ],
                ],

                // Troubleshooting Section
                const SizedBox(height: 20),
                const Text('Quick Troubleshooting:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),

                // Scaling Mode Selection
                const Text('Scaling Mode:', style: TextStyle(fontSize: 14)),
                DropdownButton<VNCScalingMode>(
                  value: _scalingMode,
                  isExpanded: true,
                  items: [
                    // Most common Android-optimized modes
                    VNCScalingMode.autoFitBest,
                    VNCScalingMode.autoFitWidth,
                    VNCScalingMode.autoFitHeight,
                    VNCScalingMode.fitToScreen,
                    VNCScalingMode.centerCrop,
                    VNCScalingMode.actualSize,
                    VNCScalingMode.zoom200,
                    VNCScalingMode.zoom150,
                    VNCScalingMode.zoom125,
                    VNCScalingMode.zoom75,
                    VNCScalingMode.zoom50,
                  ].map((mode) {
                    String description;
                    switch (mode) {
                      case VNCScalingMode.autoFitBest:
                        description = 'Auto-fit Best (Recommended)';
                        break;
                      case VNCScalingMode.autoFitWidth:
                        description = 'Auto-fit Width';
                        break;
                      case VNCScalingMode.autoFitHeight:
                        description = 'Auto-fit Height';
                        break;
                      case VNCScalingMode.fitToScreen:
                        description = 'Fit to Screen';
                        break;
                      case VNCScalingMode.centerCrop:
                        description = 'Center Crop (No Borders)';
                        break;
                      case VNCScalingMode.actualSize:
                        description = 'Actual Size (1:1, scrollable)';
                        break;
                      case VNCScalingMode.zoom200:
                        description = '200% Zoom';
                        break;
                      case VNCScalingMode.zoom150:
                        description = '150% Zoom';
                        break;
                      case VNCScalingMode.zoom125:
                        description = '125% Zoom';
                        break;
                      case VNCScalingMode.zoom75:
                        description = '75% Zoom';
                        break;
                      case VNCScalingMode.zoom50:
                        description = '50% Zoom';
                        break;
                      default:
                        description = mode.name;
                        break;
                    }
                    return DropdownMenuItem(
                      value: mode,
                      child: Text('${mode.name} - $description',
                          style: const TextStyle(fontSize: 12)),
                    );
                  }).toList(),
                  onChanged: (VNCScalingMode? newMode) {
                    if (newMode != null) {
                      setState(() {
                        _scalingMode = newMode;
                      });
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Scaling changed to: ${newMode.name}'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),

                const SizedBox(height: 15),
                const Text('Common Issues:',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 5),

                _buildTroubleshootingTip('Multiple screens visible',
                    'Try "Center Crop" or "Fit to Screen" scaling mode'),
                _buildTroubleshootingTip('Display too small/large',
                    'Use scaling dropdown above to adjust'),
                _buildTroubleshootingTip('Connection drops',
                    'Check network stability and server status'),
                _buildTroubleshootingTip('Blurry display',
                    'Check server pixel format and network speed'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTroubleshootingTip(String issue, String solution) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• $issue:',
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          Text('  $solution',
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }

  void _cycleScalingMode() {
    setState(() {
      switch (_scalingMode) {
        case VNCScalingMode.autoFitBest:
          _scalingMode = VNCScalingMode.autoFitWidth;
          break;
        case VNCScalingMode.autoFitWidth:
          _scalingMode = VNCScalingMode.autoFitHeight;
          break;
        case VNCScalingMode.autoFitHeight:
          _scalingMode = VNCScalingMode.fitToScreen;
          break;
        case VNCScalingMode.fitToScreen:
          _scalingMode = VNCScalingMode.centerCrop;
          break;
        case VNCScalingMode.centerCrop:
          _scalingMode = VNCScalingMode.actualSize;
          break;
        case VNCScalingMode.actualSize:
          _scalingMode = VNCScalingMode.zoom200;
          break;
        case VNCScalingMode.zoom200:
          _scalingMode = VNCScalingMode.autoFitBest;
          break;
        default:
          _scalingMode = VNCScalingMode.autoFitBest;
          break;
      }
    });

    // Show feedback to user
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Scaling: ${_scalingMode.name}'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Widget _buildControlBar() {
    return Container(
      height: 60,
      color: Colors.black87,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: _disconnect,
            tooltip: 'Disconnect',
          ),
          IconButton(
            icon: Icon(
              _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
              color: Colors.white,
            ),
            onPressed: _toggleFullscreen,
            tooltip: _isFullscreen ? 'Exit Fullscreen' : 'Fullscreen',
          ),
          IconButton(
            icon: const Icon(Icons.aspect_ratio, color: Colors.white),
            onPressed: _cycleScalingMode,
            tooltip: 'Scaling: ${_scalingMode.name}',
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: _showConnectionInfo,
            tooltip: 'Settings & Info',
          ),
          const Spacer(),
          Text(
            '${widget.host}:${widget.port}',
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }

  Widget _buildVNCContent() {
    switch (widget.mode) {
      case VNCViewerMode.demo:
        return _buildDemoContent();
      case VNCViewerMode.webview:
        return _buildWebViewContent();
      case VNCViewerMode.native:
        return _buildNativeContent();
    }
  }

  Widget _buildDemoContent() {
    return Container(
      color: Colors.blue[900],
      child: Stack(
        children: [
          // Simulated desktop background
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.blue[800]!, Colors.blue[900]!],
              ),
            ),
          ),
          // Simulated desktop icons
          Positioned(
            top: 20,
            left: 20,
            child: Column(
              children: [
                _buildDesktopIcon(Icons.folder, 'Documents'),
                const SizedBox(height: 20),
                _buildDesktopIcon(Icons.image, 'Pictures'),
                const SizedBox(height: 20),
                _buildDesktopIcon(Icons.settings, 'Settings'),
              ],
            ),
          ),
          // Simulated taskbar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 40,
              color: Colors.grey[800],
              child: Row(
                children: [
                  const SizedBox(width: 10),
                  Icon(Icons.computer, color: Colors.blue[300]),
                  const SizedBox(width: 10),
                  const Text(
                    'Demo Desktop - Connected',
                    style: TextStyle(color: Colors.white),
                  ),
                  const Spacer(),
                  Text(
                    DateTime.now().toString().substring(11, 16),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopIcon(IconData icon, String label) {
    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Demo: Opened $label'),
            duration: const Duration(seconds: 1),
          ),
        );
      },
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.blue[700],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.white, size: 30),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildWebViewContent() {
    if (widget.webViewController == null) {
      return const Center(
        child: Text(
          'WebView not initialized',
          style: TextStyle(color: Colors.red),
        ),
      );
    }

    return WebViewWidget(controller: widget.webViewController!);
  }

  Widget _buildNativeContent() {
    if (widget.vncClient == null) {
      return const Center(
        child: Text(
          'VNC Client not initialized',
          style: TextStyle(color: Colors.red),
        ),
      );
    }

    // Since we only navigate here when connected, always show VNC content
    // Only monitor for disconnections that happen after navigation
    return StreamBuilder<VNCConnectionState>(
      stream: widget.vncClient!.connectionState,
      builder: (context, snapshot) {
        // Always render the VNC client widget since we know we're connected when we get here
        return Stack(
          children: [
            // VNC content is always rendered with a unique key to prevent multiple instances
            // Let VNCClientWidget handle its own sizing and scaling - no FittedBox wrapper
            Container(
              width: double.infinity,
              height: double.infinity,
              color: Colors.black,
              child: VNCClientWidget(
                key: const ValueKey('vnc_viewer_client'),
                client: widget.vncClient!,
                scalingMode: _scalingMode,
              ),
            ),

            // Only show overlay if we have received a disconnected/failed state via the stream
            // (not on initial build or if no snapshot data yet)
            if (snapshot.hasData &&
                (snapshot.data == VNCConnectionState.disconnected ||
                    snapshot.data == VNCConnectionState.failed))
              Container(
                color: Colors.black.withValues(alpha: 0.8),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        snapshot.data == VNCConnectionState.failed
                            ? Icons.error
                            : Icons.link_off,
                        color: snapshot.data == VNCConnectionState.failed
                            ? Colors.red
                            : Colors.grey,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        snapshot.data == VNCConnectionState.failed
                            ? 'Connection failed'
                            : 'Disconnected from VNC server',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 16),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Host: ${widget.host}:${widget.port}',
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Back to Connection'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: 2.0, // 200% UI scaling
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: GestureDetector(
            onTap: _toggleControls,
            child: Stack(
              children: [
                // Main VNC content
                Positioned.fill(
                  top: _isFullscreen ? 0 : (_showControls ? 60 : 0),
                  child: _buildVNCContent(),
                ),
                // Control bar (only shown when not in fullscreen or when controls are visible)
                if (!_isFullscreen || _showControls)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: AnimatedOpacity(
                      opacity: _showControls || !_isFullscreen ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      child: _buildControlBar(),
                    ),
                  ),
                // Instructions overlay
                if (_showControls && _isFullscreen)
                  Positioned(
                    bottom: 20,
                    left: 20,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Tap screen to toggle controls • Back button to disconnect',
                        style: TextStyle(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
