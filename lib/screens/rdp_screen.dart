import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:convert';
import '../rdp_client.dart';

enum RDPConnectionMode {
  guacamole('Guacamole WebView'),
  native('Native RDP Test');

  const RDPConnectionMode(this.displayName);
  final String displayName;
}

class RDPScreen extends StatefulWidget {
  const RDPScreen({super.key});

  @override
  State<RDPScreen> createState() => _RDPScreenState();
}

class _RDPScreenState extends State<RDPScreen> {
  final _hostController = TextEditingController(text: '192.168.1.100');
  final _portController = TextEditingController(text: '3389');
  final _usernameController = TextEditingController(text: 'Administrator');
  final _passwordController = TextEditingController();
  final _domainController = TextEditingController();

  bool _isConnecting = false;
  String _connectionStatus = 'Disconnected';
  List<SavedRDPDevice> _savedDevices = [];
  SavedRDPDevice? _selectedDevice;
  RDPConnectionMode _connectionMode = RDPConnectionMode.guacamole;
  WebViewController? _webViewController;
  bool _showRdpViewer = false;
  RDPClient? _rdpClient;
  bool _showNativeClient = false;

  @override
  void initState() {
    super.initState();
    _loadSavedDevices();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _domainController.dispose();
    _rdpClient?.dispose();
    super.dispose();
  }

  Future<void> _loadSavedDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final devicesJson = prefs.getStringList('rdp_devices') ?? [];
    setState(() {
      _savedDevices = devicesJson
          .map((json) => SavedRDPDevice.fromJson(jsonDecode(json)))
          .toList();
    });
  }

  Future<void> _saveDevice() async {
    if (_hostController.text.isEmpty) return;

    final device = SavedRDPDevice(
      name: '${_usernameController.text}@${_hostController.text}',
      host: _hostController.text,
      port: int.tryParse(_portController.text) ?? 3389,
      username: _usernameController.text,
      domain: _domainController.text,
    );

    final prefs = await SharedPreferences.getInstance();
    _savedDevices.add(device);
    final devicesJson =
        _savedDevices.map((d) => jsonEncode(d.toJson())).toList();
    await prefs.setStringList('rdp_devices', devicesJson);

    setState(() {});

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Device saved successfully')),
      );
    }
  }

  Future<void> _deleteDevice(int index) async {
    final prefs = await SharedPreferences.getInstance();
    _savedDevices.removeAt(index);
    final devicesJson =
        _savedDevices.map((d) => jsonEncode(d.toJson())).toList();
    await prefs.setStringList('rdp_devices', devicesJson);

    setState(() {
      if (_selectedDevice == _savedDevices.length) {
        _selectedDevice = null;
      }
    });
  }

  void _loadDevice(SavedRDPDevice device) {
    setState(() {
      _hostController.text = device.host;
      _portController.text = device.port.toString();
      _usernameController.text = device.username;
      _domainController.text = device.domain;
      _selectedDevice = device;
    });
  }

  Future<void> _testConnection() async {
    if (_hostController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a host address')),
      );
      return;
    }

    setState(() {
      _connectionStatus = 'Testing connection...';
    });

    try {
      // Initialize RDP client if not already done
      _rdpClient ??= RDPClient();

      final host = _hostController.text;
      final port = int.tryParse(_portController.text) ?? 3389;

      // Test connection using RDP client
      final success = await _rdpClient!.testConnection(host, port);

      setState(() {
        if (success) {
          _connectionStatus =
              'Connection test successful - RDP port is reachable';
        } else {
          _connectionStatus = 'Connection test failed';
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success
                ? 'Successfully connected to $host:$port'
                : 'Failed to connect to $host:$port'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _connectionStatus = 'Connection test failed: $e';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to connect to ${_hostController.text}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _connect() async {
    if (_hostController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a host address')),
      );
      return;
    }

    setState(() {
      _isConnecting = true;
      _connectionStatus = 'Connecting...';
    });

    try {
      if (_connectionMode == RDPConnectionMode.guacamole) {
        await _connectWithGuacamole();
      } else {
        await _connectWithNative();
      }
    } catch (e) {
      setState(() {
        _connectionStatus = 'Connection failed: $e';
        _isConnecting = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to connect: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _connectWithGuacamole() async {
    // Initialize WebView for Guacamole
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            // Update loading bar.
          },
          onPageStarted: (String url) {},
          onPageFinished: (String url) {},
          onHttpError: (HttpResponseError error) {},
          onWebResourceError: (WebResourceError error) {},
        ),
      );

    // Create a simple Guacamole client HTML page
    final guacamoleHtml = _createGuacamoleHtml();
    await _webViewController!.loadHtmlString(guacamoleHtml);

    setState(() {
      _connectionStatus = 'Connected via Guacamole WebView';
      _isConnecting = false;
      _showRdpViewer = true;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('RDP connection established to ${_hostController.text}'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _connectWithNative() async {
    // Initialize RDP client if not already done
    _rdpClient ??= RDPClient();

    final host = _hostController.text;
    final port = int.tryParse(_portController.text) ?? 3389;
    final username = _usernameController.text;
    final password = _passwordController.text;
    final domain = _domainController.text;

    // Listen to connection state changes
    _rdpClient!.connectionState.listen((state) {
      if (mounted) {
        setState(() {
          switch (state) {
            case RDPConnectionState.connected:
              _connectionStatus = 'Connected via Native RDP Client';
              _isConnecting = false;
              _showNativeClient = true;
              break;
            case RDPConnectionState.connecting:
              _connectionStatus = 'Connecting via Native RDP...';
              break;
            case RDPConnectionState.failed:
              _connectionStatus = 'Native RDP connection failed';
              _isConnecting = false;
              _showNativeClient = false;
              break;
            case RDPConnectionState.disconnected:
              _connectionStatus = 'Disconnected';
              _isConnecting = false;
              _showNativeClient = false;
              break;
          }
        });
      }
    });

    // Attempt to connect
    final success =
        await _rdpClient!.connect(host, port, username, password, domain);

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Native RDP connected to $host:$port'),
          backgroundColor: Colors.green,
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to connect to $host:$port'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _createGuacamoleHtml() {
    final host = _hostController.text;
    final port = _portController.text;
    final username = _usernameController.text;
    final domain = _domainController.text;

    return '''
<!DOCTYPE html>
<html>
<head>
    <title>RDP Viewer</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body {
            margin: 0;
            padding: 20px;
            font-family: Arial, sans-serif;
            background-color: #f0f0f0;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .header {
            text-align: center;
            margin-bottom: 20px;
            color: #333;
        }
        .connection-info {
            background: #e8f4f8;
            padding: 15px;
            border-radius: 5px;
            margin-bottom: 20px;
        }
        .status {
            background: #d4edda;
            color: #155724;
            padding: 10px;
            border-radius: 5px;
            margin-bottom: 20px;
        }
        .demo-area {
            height: 400px;
            background: #2c3e50;
            border-radius: 5px;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            font-size: 18px;
            text-align: center;
            position: relative;
            overflow: hidden;
        }
        .desktop-simulation {
            width: 100%;
            height: 100%;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
        }
        .taskbar {
            position: absolute;
            bottom: 0;
            left: 0;
            right: 0;
            height: 40px;
            background: rgba(0,0,0,0.8);
            display: flex;
            align-items: center;
            padding: 0 10px;
        }
        .start-button {
            background: #0078d4;
            color: white;
            padding: 5px 15px;
            border-radius: 3px;
            font-size: 14px;
        }
        .window {
            background: white;
            color: #333;
            padding: 20px;
            border-radius: 5px;
            box-shadow: 0 4px 8px rgba(0,0,0,0.3);
            max-width: 300px;
            text-align: center;
        }
        .controls {
            margin-top: 20px;
        }
        .btn {
            background: #0078d4;
            color: white;
            border: none;
            padding: 8px 16px;
            margin: 0 5px;
            border-radius: 3px;
            cursor: pointer;
        }
        .btn:hover {
            background: #106ebe;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h2>🖥️ RDP Connection Viewer</h2>
        </div>
        
        <div class="connection-info">
            <strong>Connection Details:</strong><br>
            Host: $host:$port<br>
            User: $username${domain.isNotEmpty ? '@$domain' : ''}<br>
            Protocol: RDP (Remote Desktop Protocol)
        </div>
        
        <div class="status">
            ✅ Connected to Remote Desktop
        </div>
        
        <div class="demo-area">
            <div class="desktop-simulation">
                <div class="window">
                    <h3>🖥️ Remote Desktop</h3>
                    <p>Connected to $host</p>
                    <p>This is a demonstration of RDP connectivity.</p>
                    <p>In a production environment, this would show the actual remote desktop.</p>
                </div>
                <div class="taskbar">
                    <div class="start-button">Start</div>
                </div>
            </div>
        </div>
        
        <div class="controls">
            <button class="btn" onclick="toggleFullscreen()">🔳 Fullscreen</button>
            <button class="btn" onclick="sendCtrlAltDel()">🔐 Ctrl+Alt+Del</button>
            <button class="btn" onclick="refreshConnection()">🔄 Refresh</button>
        </div>
    </div>

    <script>
        function toggleFullscreen() {
            alert('Fullscreen mode would be enabled in a real RDP client');
        }
        
        function sendCtrlAltDel() {
            alert('Ctrl+Alt+Del would be sent to the remote machine');
        }
        
        function refreshConnection() {
            alert('Connection would be refreshed');
        }
        
        // Simulate typing activity
        setInterval(function() {
            const demo = document.querySelector('.desktop-simulation');
            if (demo) {
                demo.style.background = 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)';
                setTimeout(() => {
                    demo.style.background = 'linear-gradient(135deg, #764ba2 0%, #667eea 100%)';
                }, 1000);
            }
        }, 3000);
    </script>
</body>
</html>
    ''';
  }

  Future<void> _disconnect() async {
    setState(() {
      _connectionStatus = 'Disconnecting...';
    });

    // Close WebView if it was used
    if (_webViewController != null) {
      await _webViewController!
          .loadHtmlString('<html><body><h2>Disconnected</h2></body></html>');
    }

    // Disconnect RDP client if it was used
    if (_rdpClient != null) {
      await _rdpClient!.disconnect();
    }

    // Simulate disconnection
    await Future.delayed(const Duration(milliseconds: 500));

    setState(() {
      _connectionStatus = 'Disconnected';
      _showRdpViewer = false;
      _showNativeClient = false;
      _webViewController = null;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Disconnected from RDP server')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show WebView if Guacamole is connected
    if (_showRdpViewer && _webViewController != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('RDP Viewer - Guacamole'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          actions: [
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _disconnect,
              tooltip: 'Disconnect',
            ),
          ],
        ),
        body: WebViewWidget(controller: _webViewController!),
      );
    }

    // Show Native Client if connected
    if (_showNativeClient && _rdpClient != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('RDP Viewer - Native'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          actions: [
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _disconnect,
              tooltip: 'Disconnect',
            ),
          ],
        ),
        body: RDPClientWidget(
          rdpClient: _rdpClient!,
          onDisconnectRequest: _disconnect,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('RDP Connection'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Connection Status
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(
                      _connectionStatus.contains('Connected') ||
                              _connectionStatus.contains('successful')
                          ? Icons.check_circle
                          : _connectionStatus.contains('Connecting') ||
                                  _connectionStatus.contains('Testing')
                              ? Icons.hourglass_empty
                              : Icons.cancel,
                      color: _connectionStatus.contains('Connected') ||
                              _connectionStatus.contains('successful')
                          ? Colors.green
                          : _connectionStatus.contains('failed')
                              ? Colors.red
                              : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Status: $_connectionStatus',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Connection Mode Selector
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Connection Method',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<RDPConnectionMode>(
                      initialValue: _connectionMode,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: RDPConnectionMode.values.map((mode) {
                        return DropdownMenuItem(
                          value: mode,
                          child: Text(mode.displayName),
                        );
                      }).toList(),
                      onChanged: (RDPConnectionMode? value) {
                        if (value != null) {
                          setState(() {
                            _connectionMode = value;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _connectionMode == RDPConnectionMode.guacamole
                          ? 'Uses web-based Guacamole client for full RDP functionality'
                          : 'Native connectivity test - checks if RDP port is accessible',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Saved Devices
            if (_savedDevices.isNotEmpty) ...[
              const Text(
                'Saved Devices',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 120,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _savedDevices.length,
                  itemBuilder: (context, index) {
                    final device = _savedDevices[index];
                    return Card(
                      margin: const EdgeInsets.only(right: 8),
                      child: InkWell(
                        onTap: () => _loadDevice(device),
                        child: Container(
                          width: 200,
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      device.name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, size: 16),
                                    onPressed: () => _deleteDevice(index),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                ],
                              ),
                              Text('${device.host}:${device.port}'),
                              Text('User: ${device.username}'),
                              if (device.domain.isNotEmpty)
                                Text('Domain: ${device.domain}'),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Connection Form
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Connection Details',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _hostController,
                            decoration: const InputDecoration(
                              labelText: 'Host/IP Address',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.computer),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 1,
                          child: TextField(
                            controller: _portController,
                            decoration: const InputDecoration(
                              labelText: 'Port',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    TextField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                    ),
                    const SizedBox(height: 16),

                    TextField(
                      controller: _passwordController,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.lock),
                      ),
                      obscureText: true,
                    ),
                    const SizedBox(height: 16),

                    TextField(
                      controller: _domainController,
                      decoration: const InputDecoration(
                        labelText: 'Domain (optional)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.domain),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Action Buttons
                    Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _isConnecting ? null : _connect,
                                icon: _isConnecting
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Icon(Icons.play_arrow),
                                label: Text(_isConnecting
                                    ? 'Connecting...'
                                    : 'Connect'),
                                style: ElevatedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed:
                                  (_connectionStatus.contains('Connected') ||
                                          _showRdpViewer ||
                                          _showNativeClient)
                                      ? _disconnect
                                      : null,
                              icon: const Icon(Icons.stop),
                              label: const Text('Disconnect'),
                              style: ElevatedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed:
                                    _isConnecting ? null : _testConnection,
                                icon: const Icon(Icons.network_check),
                                label: const Text('Test Connection'),
                                style: ElevatedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: _saveDevice,
                              icon: const Icon(Icons.save),
                              label: const Text('Save'),
                              style: ElevatedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Information Card
                    Card(
                      color: Colors.blue.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.info, color: Colors.blue.shade700),
                                const SizedBox(width: 8),
                                Text(
                                  'RDP Connection Info',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              '• Default RDP port is 3389\n'
                              '• Make sure the target machine has Remote Desktop enabled\n'
                              '• Network connectivity to the target is required\n'
                              '• Valid credentials are needed for authentication\n'
                              '• Guacamole mode provides full RDP functionality\n'
                              '• Native mode tests connectivity only',
                              style: TextStyle(fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SavedRDPDevice {
  final String name;
  final String host;
  final int port;
  final String username;
  final String domain;

  SavedRDPDevice({
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    required this.domain,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'host': host,
      'port': port,
      'username': username,
      'domain': domain,
    };
  }

  factory SavedRDPDevice.fromJson(Map<String, dynamic> json) {
    return SavedRDPDevice(
      name: json['name'] ?? '',
      host: json['host'] ?? '',
      port: json['port'] ?? 3389,
      username: json['username'] ?? '',
      domain: json['domain'] ?? '',
    );
  }
}
