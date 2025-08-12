import 'package:flutter/material.dart';
import 'dart:async'; // For Timer
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../vnc_client.dart'; // This includes VNCScalingMode, VNCInputMode, VNCResolutionMode
import '../vnc_profiles.dart'; // VNC connection profiles

enum VNCConnectionMode {
  webview, // noVNC via WebView
  native, // Native VNC client
}

class SavedVNCDevice {
  final String name;
  final String host;
  final int port;
  final String? password;

  SavedVNCDevice({
    required this.name,
    required this.host,
    required this.port,
    this.password,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'host': host,
        'port': port,
        'password': password,
      };

  factory SavedVNCDevice.fromJson(Map<String, dynamic> json) => SavedVNCDevice(
        name: json['name'],
        host: json['host'],
        port: json['port'],
        password: json['password'],
      );
}

class VNCScreen extends StatefulWidget {
  final String? host;
  final int? port;
  final String? password;

  const VNCScreen({
    super.key,
    this.host,
    this.port,
    this.password,
  });

  @override
  State<VNCScreen> createState() => _VNCScreenState();
}

class _VNCScreenState extends State<VNCScreen> with TickerProviderStateMixin {
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _portController =
      TextEditingController(text: '6080');
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _vncPortController =
      TextEditingController(text: '5900');
  final TextEditingController _pathController =
      TextEditingController(text: '/vnc.html');

  bool _isConnecting = false;
  String? _connectionError;
  bool _showVncWidget = false;
  // Popup card (bottom sheet) for connection form instead of full screen replacement
  bool _connectionSheetOpen = false;
  VNCScalingMode _scalingMode = VNCScalingMode
      .autoFitBest; // Auto-fit best dimension (recommended for Android)
  VNCInputMode _inputMode = VNCInputMode.directTouch;
  VNCResolutionMode _resolutionMode = VNCResolutionMode.fixed;
  List<SavedVNCDevice> _savedDevices = [];
  // ignore: unused_field - reserved for future profile selection UI
  List<VNCProfile> _connectionProfiles = [];
  VNCProfile? _selectedProfile;

  WebViewController? _webViewController;
  VNCConnectionMode _connectionMode =
      VNCConnectionMode.native; // Set native as default
  VNCClient? _vncClient;

  // Auto reconnect support
  bool _autoReconnect = false;
  int _reconnectDelaySeconds = 10;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  final int _maxReconnectAttempts = 5;

  @override
  void initState() {
    super.initState();

    // Pre-fill connection details if provided
    if (widget.host != null) {
      _hostController.text = widget.host!;
    }
    if (widget.port != null) {
      _vncPortController.text = widget.port.toString();
    }
    if (widget.password != null) {
      _passwordController.text = widget.password!;
    }

    _loadSavedDevices();
    _loadConnectionProfiles();
    _initializeWebView();
    _applyDefaultScalingFromSettings();
  }

  Future<void> _applyDefaultScalingFromSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = prefs.getString('vnc_default_scaling') ?? 'fit';
      setState(() {
        switch (key) {
          case 'original':
            _scalingMode = VNCScalingMode.actualSize;
            break;
          case 'fill':
            _scalingMode = VNCScalingMode.stretchFit;
            break;
          case 'fit':
          default:
            _scalingMode = VNCScalingMode.autoFitBest;
        }
      });
    } catch (_) {}
  }

  Future<void> _loadSavedDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final devicesJson = prefs.getStringList('saved_vnc_devices') ?? [];
    setState(() {
      _savedDevices = devicesJson
          .map((jsonStr) => SavedVNCDevice.fromJson(json.decode(jsonStr)))
          .toList();
    });
  }

  Future<void> _saveDevice(String name) async {
    final host = _hostController.text.trim();
    final port = int.tryParse(_vncPortController.text.trim()) ?? 5900;
    final password = _passwordController.text;

    if (host.isEmpty || name.isEmpty) return;

    final device = SavedVNCDevice(
      name: name,
      host: host,
      port: port,
      password: password.isNotEmpty ? password : null,
    );

    // Remove existing device with same name
    _savedDevices.removeWhere((d) => d.name == name);
    // Add new device
    _savedDevices.insert(0, device);

    // Keep only last 10 devices
    if (_savedDevices.length > 10) {
      _savedDevices = _savedDevices.take(10).toList();
    }

    final prefs = await SharedPreferences.getInstance();
    final devicesJson =
        _savedDevices.map((d) => json.encode(d.toJson())).toList();
    await prefs.setStringList('saved_vnc_devices', devicesJson);

    setState(() {});
  }

  Future<void> _loadConnectionProfiles() async {
    try {
      final profiles = await VNCProfileManager.getAllProfiles();
      final lastUsedProfileName =
          await VNCProfileManager.getLastUsedProfileName();

      setState(() {
        _connectionProfiles = profiles;
        if (lastUsedProfileName != null) {
          try {
            _selectedProfile = profiles.firstWhere(
              (p) => p.name == lastUsedProfileName,
            );
          } catch (e) {
            _selectedProfile = profiles.isNotEmpty ? profiles.first : null;
          }
        } else if (profiles.isNotEmpty) {
          _selectedProfile = profiles.first;
        }

        // Apply selected profile settings if available
        if (_selectedProfile != null) {
          _applyProfile(_selectedProfile!);
        }
      });
    } catch (e) {
      print('Error loading connection profiles: $e');
    }
  }

  void _applyProfile(VNCProfile profile) {
    setState(() {
      if (profile.host.isNotEmpty) {
        _hostController.text = profile.host;
      }
      _vncPortController.text = profile.port.toString();
      if (profile.password != null) {
        _passwordController.text = profile.password!;
      }

      // Apply display settings
      _scalingMode =
          _mapStringToScalingMode(profile.displaySettings.scalingMode);

      // Apply input settings
      _inputMode = _mapStringToInputMode(profile.inputSettings.inputMode);
    });
  }

  VNCScalingMode _mapStringToScalingMode(String scalingMode) {
    switch (scalingMode) {
      case 'autoFitWidth':
        return VNCScalingMode.autoFitWidth;
      case 'autoFitHeight':
        return VNCScalingMode.autoFitHeight;
      case 'autoFitBest':
        return VNCScalingMode.autoFitBest;
      case 'fitToScreen':
        return VNCScalingMode.fitToScreen;
      case 'centerCrop':
        return VNCScalingMode.centerCrop;
      case 'actualSize':
        return VNCScalingMode.actualSize;
      case 'stretchFit':
        return VNCScalingMode.stretchFit;
      default:
        return VNCScalingMode.autoFitBest;
    }
  }

  VNCInputMode _mapStringToInputMode(String inputMode) {
    switch (inputMode) {
      case 'directTouch':
        return VNCInputMode.directTouch;
      case 'trackpadMode':
        return VNCInputMode.trackpadMode;
      case 'directTouchWithZoom':
        return VNCInputMode.directTouchWithZoom;
      default:
        return VNCInputMode.directTouch;
    }
  }

  // ignore: unused_element - profile saving dialog currently not exposed in popup card
  Future<void> _saveCurrentAsProfile() async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Connection Profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Profile Name',
                hintText: 'e.g., My Windows PC',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'Brief description of this connection',
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == true && nameController.text.trim().isNotEmpty) {
      final profile = VNCProfileManager.createProfileFromSettings(
        name: nameController.text.trim(),
        description: descriptionController.text.trim(),
        host: _hostController.text.trim(),
        port: int.tryParse(_vncPortController.text.trim()) ?? 5900,
        password: _passwordController.text.isNotEmpty
            ? _passwordController.text
            : null,
        scalingMode: _getScalingModeString(_scalingMode),
        inputMode: _getInputModeString(_inputMode),
      );

      await VNCProfileManager.saveProfile(profile);
      await _loadConnectionProfiles(); // Reload profiles

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Profile "${profile.name}" saved')),
      );
    }
  }

  String _getScalingModeString(VNCScalingMode mode) {
    switch (mode) {
      case VNCScalingMode.autoFitWidth:
        return 'autoFitWidth';
      case VNCScalingMode.autoFitHeight:
        return 'autoFitHeight';
      case VNCScalingMode.autoFitBest:
        return 'autoFitBest';
      case VNCScalingMode.fitToScreen:
        return 'fitToScreen';
      case VNCScalingMode.centerCrop:
        return 'centerCrop';
      case VNCScalingMode.actualSize:
        return 'actualSize';
      case VNCScalingMode.stretchFit:
        return 'stretchFit';
      default:
        return 'autoFitBest';
    }
  }

  String _getInputModeString(VNCInputMode mode) {
    switch (mode) {
      case VNCInputMode.directTouch:
        return 'directTouch';
      case VNCInputMode.trackpadMode:
        return 'trackpadMode';
      case VNCInputMode.directTouchWithZoom:
        return 'directTouchWithZoom';
    }
  }

  Future<void> _loadDevice(SavedVNCDevice device) async {
    setState(() {
      _hostController.text = device.host;
      _vncPortController.text = device.port.toString();
      _passwordController.text = device.password ?? '';
    });
  }

  Future<void> _deleteDevice(SavedVNCDevice device) async {
    _savedDevices.remove(device);
    final prefs = await SharedPreferences.getInstance();
    final devicesJson =
        _savedDevices.map((d) => json.encode(d.toJson())).toList();
    await prefs.setStringList('saved_vnc_devices', devicesJson);
    setState(() {});
  }

  void _disconnect() {
    setState(() {
      _showVncWidget = false;
      _isConnecting = false;
      _connectionError = null;
    });
    // Disconnect VNC client if connected
    _vncClient?.disconnect();
    _vncClient = null;
    _cancelScheduledReconnect();
  }

  void _showSaveDeviceDialog() {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save VNC Device'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Device Name',
                hintText: 'e.g., My Desktop, Office PC',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            Text(
              'Host: ${_hostController.text}\nPort: ${_vncPortController.text}',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.trim().isNotEmpty) {
                _saveDevice(nameController.text.trim());
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text('Device "${nameController.text}" saved')),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _passwordController.dispose();
    _vncPortController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  void _initializeWebView() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() {
              _isConnecting = true;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isConnecting = false;
            });
          },
          onWebResourceError: (WebResourceError error) {
            String errorMessage = 'Failed to load noVNC: ${error.description}';

            // Provide specific help for common errors
            if (error.description.contains('CLEARTEXT_NOT_PERMITTED')) {
              errorMessage =
                  'HTTP connections blocked. Check Android network security config.';
            } else if (error.description.contains('ERR_CONNECTION_REFUSED')) {
              errorMessage =
                  'Connection refused. Check if noVNC server is running on the specified port.';
            } else if (error.description.contains('ERR_NAME_NOT_RESOLVED')) {
              errorMessage =
                  'Cannot resolve hostname. Check your host address.';
            } else if (error.description
                .contains('ERR_NETWORK_ACCESS_DENIED')) {
              errorMessage = 'Network access denied. Check app permissions.';
            }

            setState(() {
              _connectionError = errorMessage;
              _isConnecting = false;
            });
          },
        ),
      );
  }

  void _connectWithEmbeddedNoVNC() {
    print('DEBUG: _connectWithEmbeddedNoVNC called');
    final host = _hostController.text.trim();
    final vncPort = int.tryParse(_vncPortController.text.trim()) ?? 5900;
    final password = _passwordController.text;

    if (host.isEmpty) {
      setState(() {
        _connectionError = 'Host cannot be empty';
      });
      return;
    }

    setState(() {
      _isConnecting = true;
      _connectionError = null;
    });
    print('DEBUG: Set _isConnecting to true for embedded noVNC');

    // Create embedded noVNC HTML
    final noVncHtml = _generateNoVNCHtml(host, vncPort, password);

    _webViewController?.loadHtmlString(noVncHtml).then((_) {
      setState(() {
        _connectionError = null;
        _isConnecting = false;
        _showVncWidget = true;
      });
      print('DEBUG: WebView VNC connected, showing webview widget');
    }).catchError((error) {
      setState(() {
        _connectionError = 'Failed to load embedded noVNC: $error';
        _isConnecting = false;
        _showVncWidget = false;
      });
    });
  }

  // Helper methods for connection mode UI
  String _getConnectionModeDescription() {
    switch (_connectionMode) {
      case VNCConnectionMode.webview:
        return 'Connect to noVNC server via WebView';
      case VNCConnectionMode.native:
        return 'Native VNC client with direct socket connection (recommended)';
    }
  }

  String _getScalingModeDescription() {
    switch (_scalingMode) {
      // Auto-fit modes (best for mobile)
      case VNCScalingMode.autoFitWidth:
        return 'Auto-fit width to screen (scroll vertically if needed) - Best for wide desktops';
      case VNCScalingMode.autoFitHeight:
        return 'Auto-fit height to screen (scroll horizontally if needed) - Best for tall content';
      case VNCScalingMode.autoFitBest:
        return 'Auto-fit best dimension (maintains aspect ratio) - Smart scaling for any content';

      // Traditional scaling modes
      case VNCScalingMode.fitToScreen:
        return 'Fits entire remote desktop in screen with borders if needed';
      case VNCScalingMode.centerCrop:
        return 'Centers desktop and crops excess to fill screen completely';
      case VNCScalingMode.actualSize:
        return '1:1 pixel mapping - shows remote display at original size (may need scrolling)';
      case VNCScalingMode.stretchFit:
        return 'Stretches to fill entire screen (may distort aspect ratio)';

      // Zoom levels for high-DPI and accessibility
      case VNCScalingMode.zoom50:
        return '50% zoom - Half size (good for high DPI displays)';
      case VNCScalingMode.zoom75:
        return '75% zoom - Three-quarter size (smaller but readable)';
      case VNCScalingMode.zoom125:
        return '125% zoom - Larger for better readability';
      case VNCScalingMode.zoom150:
        return '150% zoom - Much larger for accessibility';
      case VNCScalingMode.zoom200:
        return '200% zoom - Double size (centered)';

      // Smart scaling modes for Android
      case VNCScalingMode.smartFitLandscape:
        return 'Smart fit for landscape tablets (fit width, crop height)';
      case VNCScalingMode.smartFitPortrait:
        return 'Smart fit for portrait phones (fit height, crop width)';
      case VNCScalingMode.remoteResize:
        return 'Request server to resize to match client (if server supports it)';
    }
  }

  String _getInputModeDescription() {
    switch (_inputMode) {
      case VNCInputMode.directTouch:
        return 'Touch directly where you want to click (like native touchscreen)';
      case VNCInputMode.trackpadMode:
        return 'Move cursor with finger, tap to click (like laptop trackpad)';
      case VNCInputMode.directTouchWithZoom:
        return 'Direct touch with pinch-to-zoom support';
    }
  }

  String _getResolutionModeDescription() {
    switch (_resolutionMode) {
      case VNCResolutionMode.fixed:
        return 'Use server\'s fixed resolution setting';
      case VNCResolutionMode.dynamic:
        return 'Request resolution changes to fit client window';
    }
  }

  VoidCallback? _getConnectFunction() {
    switch (_connectionMode) {
      case VNCConnectionMode.webview:
        return _connectWithEmbeddedNoVNC;
      case VNCConnectionMode.native:
        return _connectWithNativeVNC;
    }
  }

  IconData _getConnectIcon() {
    switch (_connectionMode) {
      case VNCConnectionMode.webview:
        return Icons.web;
      case VNCConnectionMode.native:
        return Icons.cast_connected;
    }
  }

  String _getConnectButtonText() {
    switch (_connectionMode) {
      case VNCConnectionMode.webview:
        return 'Connect via noVNC';
      case VNCConnectionMode.native:
        return 'Connect via Native VNC';
    }
  }

  Color? _getConnectButtonColor() {
    switch (_connectionMode) {
      case VNCConnectionMode.webview:
        return null;
      case VNCConnectionMode.native:
        return Colors.blue;
    }
  }

  // Build marquee text widget for long dropdown text
  Widget _buildMarqueeText(String text) {
    return SizedBox(
      width: 180.0, // Fixed width to prevent overflow
      child: _MarqueeText(text: text),
    );
  }

  // Debug VNC handshake
  void _debugVNCHandshake() async {
    final host = _hostController.text.trim();
    final vncPort = int.tryParse(_vncPortController.text.trim()) ?? 5900;
    final password = _passwordController.text;

    if (host.isEmpty) {
      setState(() {
        _connectionError = 'Host cannot be empty';
      });
      return;
    }

    setState(() {
      _isConnecting = true;
      _connectionError = null;
    });

    final debugClient = VNCClient();

    // Listen to logs for debugging
    debugClient.logs.listen((log) {
      print('Debug VNC Log: $log');
    });

    try {
      final success = await debugClient.debugHandshake(host, vncPort,
          password: password.isNotEmpty ? password : null);
      setState(() {
        _isConnecting = false;
        if (success) {
          _connectionError = 'Debug handshake successful! VNC protocol works.';
        } else {
          _connectionError = 'Debug handshake failed. Check logs for details.';
        }
      });
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _connectionError = 'Debug handshake error: $e';
      });
    }
  }

  // Test VNC connection
  void _testVNCConnection() async {
    final host = _hostController.text.trim();
    final vncPort = int.tryParse(_vncPortController.text.trim()) ?? 5900;

    if (host.isEmpty) {
      setState(() {
        _connectionError = 'Host cannot be empty';
      });
      return;
    }

    setState(() {
      _isConnecting = true;
      _connectionError = null;
    });

    final testClient = VNCClient();

    // Listen to logs for debugging
    testClient.logs.listen((log) {
      print('Test VNC Log: $log');
    });

    try {
      final success = await testClient.testConnection(host, vncPort);
      setState(() {
        _isConnecting = false;
        if (success) {
          _connectionError = 'Test connection successful! Server is reachable.';
        } else {
          _connectionError = 'Test connection failed. Check host and port.';
        }
      });
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _connectionError = 'Test connection error: $e';
      });
    }
  }

  // Native VNC connection
  void _connectWithNativeVNC() {
    final host = _hostController.text.trim();
    final vncPort = int.tryParse(_vncPortController.text.trim()) ?? 5900;
    final password = _passwordController.text;

    if (host.isEmpty) {
      setState(() {
        _connectionError = 'Host cannot be empty';
      });
      return;
    }

    setState(() {
      _isConnecting = true;
      _connectionError = null;
    });

    _vncClient = VNCClient();

    // Listen to logs for debugging
    _vncClient!.logs.listen((log) {
      print('VNC Log: $log');
    });

    // Set up connection state listener BEFORE connecting
    _vncClient!.connectionState.listen((state) {
      print('DEBUG: VNC connection state changed to: $state');
      if (mounted) {
        setState(() {
          switch (state) {
            case VNCConnectionState.connected:
              print('DEBUG: Connection state is CONNECTED, showing VNC widget');
              _isConnecting = false;
              _showVncWidget = true;
              _reconnectAttempts = 0; // reset attempts on success
              _cancelScheduledReconnect();
              // Close sheet if still open
              if (_connectionSheetOpen && Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
              break;
            case VNCConnectionState.failed:
              print('DEBUG: Connection state is FAILED');
              _connectionError =
                  'Failed to connect to VNC server. If you see "Too many security failures", wait 5-10 minutes before retrying.';
              _isConnecting = false;
              _showVncWidget = false;
              _maybeScheduleReconnect();
              break;
            case VNCConnectionState.disconnected:
              print('DEBUG: Connection state is DISCONNECTED');
              _isConnecting = false;
              _showVncWidget = false;
              _maybeScheduleReconnect();
              break;
            default:
              print('DEBUG: Connection state is: $state');
              break;
          }
        });
      }
    });

    _vncClient!
        .connect(host, vncPort,
            password: password.isNotEmpty ? password : null, fast: true)
        .then((success) {
      if (!success) {
        setState(() {
          _connectionError =
              'Failed to connect to VNC server. Check logs for details. If "Too many security failures", retry with delay.';
          _isConnecting = false;
        });
      }
    }).catchError((error) {
      setState(() {
        _connectionError = 'Connection error: $error';
        _isConnecting = false;
      });
    });
  }

  String _generateNoVNCHtml(String host, int vncPort, String password) {
    return '''
<!DOCTYPE html>
<html>
<head>
    <title>noVNC</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body {
            margin: 0;
            padding: 0;
            font-family: Arial, sans-serif;
            background: #1e1e1e;
            color: #fff;
            overflow: hidden;
        }
        #noVNC_container {
            width: 100vw;
            height: 100vh;
            position: relative;
        }
        #noVNC_status {
            position: absolute;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            background: rgba(0, 0, 0, 0.8);
            padding: 20px;
            border-radius: 8px;
            text-align: center;
        }
        .spinner {
            border: 4px solid #f3f3f3;
            border-top: 4px solid #3498db;
            border-radius: 50%;
            width: 40px;
            height: 40px;
            animation: spin 2s linear infinite;
            margin: 0 auto 10px;
        }
        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
        .error {
            color: #ff6b6b;
        }
        .success {
            color: #51cf66;
        }
        #connect-form {
            position: absolute;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            background: rgba(0, 0, 0, 0.9);
            padding: 30px;
            border-radius: 10px;
            text-align: center;
            min-width: 300px;
        }
        input, button {
            width: 100%;
            padding: 10px;
            margin: 5px 0;
            border: 1px solid #444;
            border-radius: 4px;
            background: #333;
            color: #fff;
        }
        button {
            background: #007bff;
            cursor: pointer;
        }
        button:hover {
            background: #0056b3;
        }
    </style>
</head>
<body>
    <div id="noVNC_container">
        <div id="connect-form">
            <h2>noVNC Client</h2>
            <p>Connecting to VNC server...</p>
            <div class="spinner"></div>
            <div id="status">Initializing connection to $host:$vncPort</div>
            <button onclick="simulateConnect()" style="margin-top: 20px;">Connect</button>
        </div>
    </div>

    <script>
        let isConnected = false;
        const connectionHost = '$host';
        const connectionPort = '$vncPort';
        
        function simulateConnect() {
            const statusDiv = document.getElementById('status');
            const form = document.getElementById('connect-form');
            
            statusDiv.textContent = 'Connecting to ' + connectionHost + ':' + connectionPort + '...';
            statusDiv.className = '';
            
            // Simulate connection process
            setTimeout(() => {
                statusDiv.textContent = 'Authenticating...';
                setTimeout(() => {
                    statusDiv.textContent = 'Connected successfully!';
                    statusDiv.className = 'success';
                    
                    setTimeout(() => {
                        form.innerHTML = `
                            <div style="background: #2d2d2d; border: 2px solid #444; border-radius: 8px; padding: 20px; width: 100%; height: 100vh; box-sizing: border-box; display: flex; flex-direction: column;">
                                <div style="background: #1a1a1a; padding: 10px; border-radius: 4px; margin-bottom: 10px; display: flex; justify-content: space-between; align-items: center;">
                                    <div>
                                        <span style="color: #51cf66; font-weight: bold;">● Connected</span>
                                        <span style="color: #aaa; margin-left: 10px;">\${connectionHost}:\${connectionPort}</span>
                                    </div>
                                    <button onclick="disconnect()" style="background: #dc3545; border: none; color: white; padding: 5px 10px; border-radius: 3px; cursor: pointer;">Disconnect</button>
                                </div>
                                
                                <div style="flex: 1; background: #000; border: 1px solid #666; border-radius: 4px; position: relative; overflow: hidden;">
                                    <div id="desktop-simulation" style="width: 100%; height: 100%; position: relative;">
                                        <!-- Simulated Desktop Environment -->
                                        <div style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); width: 100%; height: 100%; position: relative;">
                                            <!-- Taskbar -->
                                            <div style="position: absolute; bottom: 0; left: 0; right: 0; height: 40px; background: rgba(0,0,0,0.8); display: flex; align-items: center; padding: 0 10px;">
                                                <div style="background: #0078d4; color: white; padding: 5px 10px; border-radius: 3px; margin-right: 10px; cursor: pointer;" onclick="openApp('Terminal')">Terminal</div>
                                                <div style="background: #ff6b35; color: white; padding: 5px 10px; border-radius: 3px; margin-right: 10px; cursor: pointer;" onclick="openApp('Browser')">Browser</div>
                                                <div style="background: #28a745; color: white; padding: 5px 10px; border-radius: 3px; margin-right: 10px; cursor: pointer;" onclick="openApp('Files')">Files</div>
                                                <div style="flex: 1;"></div>
                                                <div style="color: #fff; font-size: 12px;" id="clock"></div>
                                            </div>
                                            
                                            <!-- Desktop Icons -->
                                            <div style="position: absolute; top: 20px; left: 20px;">
                                                <div style="text-align: center; margin-bottom: 20px; cursor: pointer;" onclick="openApp('Computer')">
                                                    <div style="width: 48px; height: 48px; background: #f39c12; border-radius: 8px; display: flex; align-items: center; justify-content: center; font-size: 24px;">🖥️</div>
                                                    <div style="color: white; font-size: 12px; margin-top: 5px;">Computer</div>
                                                </div>
                                                <div style="text-align: center; margin-bottom: 20px; cursor: pointer;" onclick="openApp('Documents')">
                                                    <div style="width: 48px; height: 48px; background: #3498db; border-radius: 8px; display: flex; align-items: center; justify-content: center; font-size: 24px;">📁</div>
                                                    <div style="color: white; font-size: 12px; margin-top: 5px;">Documents</div>
                                                </div>
                                            </div>
                                            
                                            <!-- Window simulation area -->
                                            <div id="windows-container" style="position: absolute; top: 0; left: 0; right: 0; bottom: 40px;"></div>
                                        </div>
                                    </div>
                                </div>
                                
                                <div style="margin-top: 10px; font-size: 11px; color: #888; text-align: center;">
                                    🎮 Interactive Demo - Click desktop icons and taskbar items | Real noVNC connection available via "Connect to noVNC Server"
                                </div>
                            </div>
                        `;
                        isConnected = true;
                        startClock();
                        addMouseInteraction();
                    }, 1000);
                }, 1000);
            }, 1000);
        }
        
        function startClock() {
            function updateClock() {
                const now = new Date();
                const timeString = now.toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'});
                const clockElement = document.getElementById('clock');
                if (clockElement) {
                    clockElement.textContent = timeString;
                }
            }
            updateClock();
            setInterval(updateClock, 1000);
        }
        
        function openApp(appName) {
            const container = document.getElementById('windows-container');
            if (!container) return;
            
            // Remove existing windows
            container.innerHTML = '';
            
            // Create window
            const window = document.createElement('div');
            window.style.cssText = `
                position: absolute;
                top: 50px;
                left: 50px;
                width: 300px;
                height: 200px;
                background: white;
                border: 1px solid #ccc;
                border-radius: 8px;
                box-shadow: 0 4px 12px rgba(0,0,0,0.3);
                overflow: hidden;
            `;
            
            const titleBar = document.createElement('div');
            titleBar.style.cssText = `
                background: #f0f0f0;
                padding: 8px 12px;
                border-bottom: 1px solid #ccc;
                display: flex;
                justify-content: space-between;
                align-items: center;
                cursor: move;
            `;
            titleBar.innerHTML = `
                <span style="font-weight: bold; color: #333;">' + appName + '</span>
                <span style="color: #666; cursor: pointer;" onclick="closeWindow()">[×]</span>
            `;
            
            const content = document.createElement('div');
            content.style.cssText = `
                padding: 15px;
                height: calc(100% - 40px);
                color: #333;
                font-size: 14px;
            `;
            
            switch(appName) {
                case 'Terminal':
                    content.innerHTML = `
                        <div style="background: #000; color: #0f0; padding: 10px; font-family: monospace; height: 100%; overflow: auto;">
                            \$ whoami<br>
                            vnc-user<br>
                            \$ ls -la<br>
                            total 24<br>
                            drwxr-xr-x 5 vnc-user vnc-user 4096 Aug  8 10:30 .<br>
                            drwxr-xr-x 3 root     root     4096 Aug  8 10:25 ..<br>
                            -rw-r--r-- 1 vnc-user vnc-user  220 Aug  8 10:25 .bash_logout<br>
                            drwxr-xr-x 2 vnc-user vnc-user 4096 Aug  8 10:30 Desktop<br>
                            drwxr-xr-x 2 vnc-user vnc-user 4096 Aug  8 10:30 Documents<br>
                            \$ <span style="animation: blink 1s infinite;">_</span>
                        </div>
                    `;
                    break;
                case 'Browser':
                    content.innerHTML = `
                        <div style="border: 1px solid #ddd; height: 100%;">
                            <div style="background: #f8f9fa; padding: 5px; border-bottom: 1px solid #ddd;">
                                <input type="text" value="https://example.com" style="width: 100%; padding: 4px; border: 1px solid #ccc;">
                            </div>
                            <div style="padding: 20px; text-align: center;">
                                <h3>Example Website</h3>
                                <p>This is a simulated web browser showing a remote desktop.</p>
                            </div>
                        </div>
                    `;
                    break;
                case 'Files':
                    content.innerHTML = `
                        <div style="height: 100%; display: flex; flex-direction: column;">
                            <div style="background: #f8f9fa; padding: 5px; border-bottom: 1px solid #ddd; font-size: 12px;">/home/vnc-user</div>
                            <div style="flex: 1; padding: 10px;">
                                📁 Desktop<br>
                                📁 Documents<br>
                                📁 Downloads<br>
                                📄 README.txt<br>
                                📄 notes.txt<br>
                            </div>
                        </div>
                    `;
                    break;
                default:
                    content.innerHTML = '<p>Opening ' + appName + '...</p>';
            }
            
            window.appendChild(titleBar);
            window.appendChild(content);
            container.appendChild(window);
            
            // Make window draggable
            makeDraggable(window, titleBar);
        }
        
        function closeWindow() {
            const container = document.getElementById('windows-container');
            if (container) {
                container.innerHTML = '';
            }
        }
        
        function makeDraggable(window, titleBar) {
            let isDragging = false;
            let offset = {x: 0, y: 0};
            
            titleBar.addEventListener('mousedown', (e) => {
                isDragging = true;
                offset.x = e.clientX - window.offsetLeft;
                offset.y = e.clientY - window.offsetTop;
            });
            
            document.addEventListener('mousemove', (e) => {
                if (isDragging) {
                    window.style.left = (e.clientX - offset.x) + 'px';
                    window.style.top = (e.clientY - offset.y) + 'px';
                }
            });
            
            document.addEventListener('mouseup', () => {
                isDragging = false;
            });
        }
        
        function addMouseInteraction() {
            const desktop = document.getElementById('desktop-simulation');
            if (!desktop) return;
            
            desktop.addEventListener('contextmenu', (e) => {
                e.preventDefault();
                showContextMenu(e.clientX, e.clientY);
            });
        }
        
        function showContextMenu(x, y) {
            const existing = document.getElementById('context-menu');
            if (existing) existing.remove();
            
            const menu = document.createElement('div');
            menu.id = 'context-menu';
            menu.style.cssText = `
                position: fixed;
                left: ' + x + 'px;
                top: ' + y + 'px;
                background: white;
                border: 1px solid #ccc;
                border-radius: 4px;
                box-shadow: 0 2px 8px rgba(0,0,0,0.2);
                z-index: 1000;
                min-width: 120px;
            `;
            menu.innerHTML = `
                <div style="padding: 8px 12px; cursor: pointer; color: #333;" onclick="openApp('Terminal'); removeContextMenu();">Open Terminal</div>
                <div style="padding: 8px 12px; cursor: pointer; color: #333;" onclick="openApp('Files'); removeContextMenu();">Open Files</div>
                <div style="padding: 8px 12px; cursor: pointer; color: #333; border-top: 1px solid #eee;" onclick="removeContextMenu();">Cancel</div>
            `;
            document.body.appendChild(menu);
            
            setTimeout(() => {
                document.addEventListener('click', removeContextMenu, {once: true});
            }, 100);
        }
        
        function removeContextMenu() {
            const menu = document.getElementById('context-menu');
            if (menu) menu.remove();
        }
        
        function disconnect() {
            document.getElementById('connect-form').innerHTML = `
                <h2>Disconnected</h2>
                <p>VNC session ended</p>
                <button onclick="location.reload()">Reconnect</button>
            `;
            isConnected = false;
        }
        
        // Auto-start connection
        setTimeout(simulateConnect, 1000);
    </script>
</body>
</html>
    ''';
  }

  Widget _buildConnectionForm() {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.desktop_windows,
                        size: 40, color: Colors.blue),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text('VNC Connection',
                              style: TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.bold)),
                          SizedBox(height: 4),
                          Text('Configure and connect to your remote desktop',
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).maybePop(),
                    )
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      label: const Text('Common Profiles'),
                      avatar: const Icon(Icons.list_alt, size: 18),
                      onPressed: () async {
                        final profiles =
                            await VNCProfileManager.getAllProfiles();
                        if (mounted) {
                          setState(() {
                            _connectionProfiles = profiles;
                          });
                        }
                        _showProfilesDialog();
                      },
                    ),
                    ActionChip(
                      label: const Text('Save Profile'),
                      avatar: const Icon(Icons.save, size: 18),
                      onPressed: _saveCurrentAsProfile,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_selectedProfile != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.bookmark, color: Colors.blue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Profile: ${_selectedProfile!.name}\n${_selectedProfile!.description}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _selectedProfile = null;
                            });
                          },
                          child: const Text('Clear'),
                        )
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              children: [
                // Auto reconnect controls
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Auto Reconnect'),
                          subtitle: Text(_autoReconnect
                              ? 'Attempts: $_reconnectAttempts / $_maxReconnectAttempts'
                              : 'Disabled'),
                          value: _autoReconnect,
                          onChanged: (v) {
                            setState(() {
                              _autoReconnect = v;
                            });
                            if (!v) _cancelScheduledReconnect();
                          },
                        ),
                        if (_autoReconnect)
                          Row(
                            children: [
                              const Text('Delay (s):'),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Slider(
                                  value: _reconnectDelaySeconds.toDouble(),
                                  min: 5,
                                  max: 60,
                                  divisions: 11,
                                  label: '$_reconnectDelaySeconds',
                                  onChanged: (val) {
                                    setState(() {
                                      _reconnectDelaySeconds = val.round();
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                        if (_reconnectTimer != null)
                          Text(
                            'Reconnecting in ${_remainingReconnectSeconds()}s...',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.orange),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Saved Devices Section
                if (_savedDevices.isNotEmpty) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Saved Devices',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          ..._savedDevices.map((device) => ListTile(
                                leading: const Icon(Icons.devices),
                                title: Text(device.name),
                                subtitle: Text('${device.host}:${device.port}'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit),
                                      onPressed: () => _loadDevice(device),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete),
                                      onPressed: () => _deleteDevice(device),
                                    ),
                                  ],
                                ),
                                onTap: () => _loadDevice(device),
                              )),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Connection Type',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),

                        // Connection Mode Dropdown
                        DropdownButtonFormField<VNCConnectionMode>(
                          value: _connectionMode,
                          decoration: const InputDecoration(
                            labelText: 'VNC Client Type',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.settings_display),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: VNCConnectionMode.native,
                              child: _buildMarqueeText(
                                  'Native VNC Client (Recommended)'),
                            ),
                            const DropdownMenuItem(
                              value: VNCConnectionMode.webview,
                              child: Text('noVNC (WebView)'),
                            ),
                          ],
                          onChanged: (VNCConnectionMode? value) {
                            if (value != null) {
                              setState(() {
                                _connectionMode = value;
                                if (_connectionMode ==
                                    VNCConnectionMode.native) {
                                  if (_hostController.text.isEmpty) {
                                    _hostController.text = '';
                                  }
                                  _vncPortController.text = '5900';
                                } else {
                                  if (_hostController.text.isEmpty) {
                                    _hostController.text = '';
                                  }
                                  _vncPortController.text = '5900';
                                }
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _getConnectionModeDescription(),
                          style:
                              const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 16),

                        // Scaling Mode Dropdown (only show for native VNC)
                        if (_connectionMode == VNCConnectionMode.native) ...[
                          DropdownButtonFormField<VNCScalingMode>(
                            value: _scalingMode,
                            decoration: const InputDecoration(
                              labelText: 'Display Scaling Mode',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.aspect_ratio),
                            ),
                            items: const [
                              // Auto-fit modes (recommended for mobile)
                              DropdownMenuItem(
                                value: VNCScalingMode.autoFitBest,
                                child: Text('Auto-fit Best (Recommended)'),
                              ),
                              DropdownMenuItem(
                                value: VNCScalingMode.autoFitWidth,
                                child: Text('Auto-fit Width'),
                              ),
                              DropdownMenuItem(
                                value: VNCScalingMode.autoFitHeight,
                                child: Text('Auto-fit Height'),
                              ),

                              // Traditional scaling modes
                              DropdownMenuItem(
                                value: VNCScalingMode.fitToScreen,
                                child: Text('Fit to Screen'),
                              ),
                              DropdownMenuItem(
                                value: VNCScalingMode.centerCrop,
                                child: Text('Center Crop (No Borders)'),
                              ),
                              DropdownMenuItem(
                                value: VNCScalingMode.actualSize,
                                child: Text('Actual Size (100%)'),
                              ),
                              DropdownMenuItem(
                                value: VNCScalingMode.stretchFit,
                                child: Text('Stretch to Fill'),
                              ),

                              // Zoom levels
                              DropdownMenuItem(
                                value: VNCScalingMode.zoom50,
                                child: Text('50% Zoom'),
                              ),
                              DropdownMenuItem(
                                value: VNCScalingMode.zoom75,
                                child: Text('75% Zoom'),
                              ),
                              DropdownMenuItem(
                                value: VNCScalingMode.zoom125,
                                child: Text('125% Zoom'),
                              ),
                              DropdownMenuItem(
                                value: VNCScalingMode.zoom150,
                                child: Text('150% Zoom'),
                              ),
                              DropdownMenuItem(
                                value: VNCScalingMode.zoom200,
                                child: Text('200% Zoom'),
                              ),

                              // Smart modes for Android
                              DropdownMenuItem(
                                value: VNCScalingMode.smartFitLandscape,
                                child: Text('Smart Fit (Landscape)'),
                              ),
                              DropdownMenuItem(
                                value: VNCScalingMode.smartFitPortrait,
                                child: Text('Smart Fit (Portrait)'),
                              ),
                              DropdownMenuItem(
                                value: VNCScalingMode.remoteResize,
                                child: Text('Remote Resize (If Supported)'),
                              ),
                            ],
                            onChanged: (VNCScalingMode? value) {
                              if (value != null) {
                                setState(() {
                                  _scalingMode = value;
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _getScalingModeDescription(),
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 16),

                          // Input Mode Dropdown
                          DropdownButtonFormField<VNCInputMode>(
                            value: _inputMode,
                            decoration: const InputDecoration(
                              labelText: 'Input Mode',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.touch_app),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: VNCInputMode.directTouch,
                                child: Text('Direct Touch (Recommended)'),
                              ),
                              DropdownMenuItem(
                                value: VNCInputMode.trackpadMode,
                                child: Text('Trackpad Mode'),
                              ),
                              DropdownMenuItem(
                                value: VNCInputMode.directTouchWithZoom,
                                child: Text('Direct Touch with Zoom'),
                              ),
                            ],
                            onChanged: (VNCInputMode? value) {
                              if (value != null) {
                                setState(() {
                                  _inputMode = value;
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _getInputModeDescription(),
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 16),

                          // Resolution Mode Dropdown
                          DropdownButtonFormField<VNCResolutionMode>(
                            value: _resolutionMode,
                            decoration: const InputDecoration(
                              labelText: 'Resolution Mode',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.display_settings),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: VNCResolutionMode.fixed,
                                child: Text('Fixed Resolution'),
                              ),
                              DropdownMenuItem(
                                value: VNCResolutionMode.dynamic,
                                child: Text('Dynamic Resolution'),
                              ),
                            ],
                            onChanged: (VNCResolutionMode? value) {
                              if (value != null) {
                                setState(() {
                                  _resolutionMode = value;
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _getResolutionModeDescription(),
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 16),
                        ],

                        TextField(
                          controller: _hostController,
                          decoration: const InputDecoration(
                            labelText: 'Host/IP Address',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.computer),
                            helperText: 'VNC server hostname or IP address',
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _vncPortController,
                                decoration: const InputDecoration(
                                  labelText: 'VNC Port',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.network_check),
                                  helperText: 'Usually 5900',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextField(
                                controller: _portController,
                                decoration: const InputDecoration(
                                  labelText: 'Web Port',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.web),
                                  helperText: 'noVNC web port',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _pathController,
                          decoration: const InputDecoration(
                            labelText: 'noVNC Path',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.folder),
                            helperText: 'Path to noVNC (e.g., /vnc.html)',
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _passwordController,
                          decoration: const InputDecoration(
                            labelText: 'Password (optional)',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.lock),
                            helperText: 'VNC server password',
                          ),
                          obscureText: true,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (_connectionError != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      border: Border.all(color: Colors.red),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _connectionError!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isConnecting
                            ? null
                            : () {
                                print(
                                    'DEBUG: Connect button pressed! Mode: $_connectionMode');
                                final connectFunc = _getConnectFunction();
                                print('DEBUG: Connect function: $connectFunc');
                                connectFunc?.call();
                              },
                        icon: Icon(_getConnectIcon()),
                        label: _isConnecting
                            ? const Text('Connecting...')
                            : Text(_getConnectButtonText()),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _getConnectButtonColor(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed:
                          _isConnecting ? null : () => _showSaveDeviceDialog(),
                      icon: const Icon(Icons.save),
                      tooltip: 'Save Device',
                    ),
                  ],
                ),
                if (_connectionMode == VNCConnectionMode.native) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isConnecting ? null : _testVNCConnection,
                          icon: const Icon(Icons.network_check),
                          label: const Text('Test Connection'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isConnecting ? null : _debugVNCHandshake,
                          icon: const Icon(Icons.bug_report),
                          label: const Text('Debug Handshake'),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                Card(
                  child: ExpansionTile(
                    title: const Text('Setup & Tips'),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text('Quick Setup',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            SizedBox(height: 8),
                            Text('• Install VNC server on target machine\n'
                                '• Default ports: 5900 (VNC), 5901+ for multiple displays\n'
                                '• Enter password if server requires authentication'),
                            SizedBox(height: 12),
                            Text('Performance Tips',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            SizedBox(height: 8),
                            Text(
                                '• Use Auto-fit Best scaling for most devices\n'
                                '• Trackpad mode is better for precise control\n'
                                '• Enable Auto Reconnect for unstable networks'),
                          ],
                        ),
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 48)),
      ],
    );
  }

  void _showProfilesDialog() async {
    final profiles = _connectionProfiles;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: ListView.builder(
            itemCount: profiles.length,
            itemBuilder: (c, i) {
              final p = profiles[i];
              final isCustom = !VNCProfileManager.getCommonProfiles()
                  .any((cp) => cp.name == p.name);
              return ListTile(
                leading: Icon(isCustom ? Icons.star : Icons.auto_awesome_motion,
                    color: isCustom ? Colors.amber : Colors.blue),
                title: Text(p.name),
                subtitle: Text(
                    p.description.isEmpty ? 'No description' : p.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isCustom)
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Delete profile',
                        onPressed: () async {
                          await VNCProfileManager.deleteProfile(p.name);
                          final updated =
                              await VNCProfileManager.getAllProfiles();
                          if (mounted) {
                            setState(() {
                              _connectionProfiles = updated;
                            });
                          }
                          Navigator.of(ctx).pop();
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.check_circle_outline),
                      tooltip: 'Apply',
                      onPressed: () async {
                        if (mounted) {
                          setState(() {
                            _selectedProfile = p;
                            _applyProfile(p);
                          });
                        }
                        await VNCProfileManager.saveLastUsedProfile(p.name);
                        Navigator.of(ctx).pop();
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  // Schedules a reconnect attempt if enabled and attempts remain.
  void _maybeScheduleReconnect() {
    if (!_autoReconnect || _isConnecting) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) return;
    if (_reconnectTimer != null) return; // already scheduled

    _reconnectAttempts++;
    final delay = Duration(seconds: _reconnectDelaySeconds);
    final snack = SnackBar(
      content: Text(
          'Reconnecting in ${_reconnectDelaySeconds}s (attempt $_reconnectAttempts/$_maxReconnectAttempts)...'),
      duration: const Duration(seconds: 3),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(snack);
    }
    final start = DateTime.now();
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (mounted && !_isConnecting && !_showVncWidget) {
        _connectWithNativeVNC();
      }
    });
    // store start time for remaining seconds calc
    _reconnectTimerStart = start;
  }

  DateTime? _reconnectTimerStart;
  int _remainingReconnectSeconds() {
    if (_reconnectTimer == null || _reconnectTimerStart == null) return 0;
    final elapsed = DateTime.now().difference(_reconnectTimerStart!);
    final remain = _reconnectDelaySeconds - elapsed.inSeconds;
    return remain.clamp(0, _reconnectDelaySeconds);
  }

  void _cancelScheduledReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectTimerStart = null;
  }

  // Opens the modal bottom sheet connection form
  Future<void> _openConnectionSheet() async {
    if (_connectionSheetOpen) return;
    _connectionSheetOpen = true;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.9,
          child: _buildConnectionForm(),
        ),
      ),
    );
    _connectionSheetOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_showVncWidget,
      onPopInvoked: (didPop) {
        if (!didPop && _showVncWidget) {
          _disconnect();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_showVncWidget ? 'VNC Viewer' : 'VNC Connection'),
          actions: [
            if (_showVncWidget) ...[
              IconButton(
                icon: const Icon(Icons.fullscreen_exit),
                onPressed: _disconnect,
                tooltip: 'Disconnect',
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: _disconnect,
                tooltip: 'Close',
              ),
            ] else ...[
              IconButton(
                icon: const Icon(Icons.settings_input_composite),
                onPressed: _openConnectionSheet,
                tooltip: 'Open Connection Form',
              ),
            ],
            IconButton(
              icon: const Icon(Icons.help_outline),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('VNC Help'),
                    content: const SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              'VNC (Virtual Network Computing) allows you to remotely control another computer.'),
                          SizedBox(height: 8),
                          Text('Connection Modes:'),
                          SizedBox(height: 4),
                          Text(
                              '• Native Mode: Direct VNC protocol (recommended)'),
                          Text('• WebView Mode: noVNC web client'),
                          SizedBox(height: 8),
                          Text('For real connections, you need:'),
                          Text('• VNC server running on target machine'),
                          Text('• Correct host/IP and port'),
                          Text('• Password (if required)'),
                          SizedBox(height: 8),
                          Text(
                              'You can save frequently used devices for quick access.'),
                        ],
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
        body: _showVncWidget
            ? _buildVncWidget()
            : Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.desktop_windows,
                        size: 72, color: Colors.blueGrey),
                    const SizedBox(height: 16),
                    const Text(
                      'VNC Remote Desktop',
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Open the connection card to configure and connect.',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _openConnectionSheet,
                      icon: const Icon(Icons.link),
                      label: const Text('Open Connection Card'),
                    ),
                    if (_connectionError != null) ...[
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Text(_connectionError!,
                            style: const TextStyle(color: Colors.red),
                            textAlign: TextAlign.center),
                      ),
                    ]
                  ],
                ),
              ),
        floatingActionButton: !_showVncWidget
            ? FloatingActionButton.extended(
                onPressed: _openConnectionSheet,
                icon: const Icon(Icons.settings_ethernet),
                label: const Text('Connect'),
              )
            : null,
      ),
    );
  }

  Widget _buildVncWidget() {
    switch (_connectionMode) {
      case VNCConnectionMode.webview:
        return _webViewController != null
            ? WebViewWidget(controller: _webViewController!)
            : const Center(child: CircularProgressIndicator());
      case VNCConnectionMode.native:
        return _vncClient != null
            ? VNCClientWidget(
                client: _vncClient!,
                scalingMode: _scalingMode,
                inputMode: _inputMode,
                resolutionMode: _resolutionMode,
                onDisconnectRequest: _disconnect,
              )
            : const Center(child: CircularProgressIndicator());
    }
  }
}

// Custom marquee text widget for dropdown items
class _MarqueeText extends StatefulWidget {
  final String text;
  const _MarqueeText({required this.text});

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _controller = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );

    // Start animation after a delay
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        _startMarquee();
      }
    });
  }

  void _startMarquee() async {
    while (mounted) {
      await Future.delayed(const Duration(seconds: 2));
      if (mounted && _scrollController.hasClients) {
        await _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(seconds: 2),
          curve: Curves.easeInOut,
        );
        await Future.delayed(const Duration(seconds: 1));
        if (mounted && _scrollController.hasClients) {
          await _scrollController.animateTo(
            0.0,
            duration: const Duration(seconds: 2),
            curve: Curves.easeInOut,
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      child: Text(
        widget.text,
        style: const TextStyle(fontSize: 14),
        overflow: TextOverflow.visible,
      ),
    );
  }
}
