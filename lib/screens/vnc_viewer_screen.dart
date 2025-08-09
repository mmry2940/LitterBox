import 'package:flutter/material.dart';
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

  @override
  void dispose() {
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
          title: const Text('Connection Info'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Host: ${widget.host}'),
              Text('Port: ${widget.port}'),
              Text('Mode: ${widget.mode.name}'),
              if (widget.vncClient?.currentState ==
                  VNCConnectionState.connected) ...[
                const SizedBox(height: 10),
                const Text('Status: Connected',
                    style: TextStyle(color: Colors.green)),
                if (widget.vncClient?.frameBuffer != null) ...[
                  Text(
                      'Resolution: ${widget.vncClient!.frameBuffer!.width}x${widget.vncClient!.frameBuffer!.height}'),
                  Text(
                      'Pixel Format: ${widget.vncClient!.frameBuffer!.pixelFormat.bitsPerPixel}bpp'),
                ],
              ],
            ],
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
            icon: const Icon(Icons.info, color: Colors.white),
            onPressed: _showConnectionInfo,
            tooltip: 'Connection Info',
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

    return VNCClientWidget(client: widget.vncClient!);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
    );
  }
}
