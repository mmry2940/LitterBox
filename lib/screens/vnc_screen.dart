import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

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

class _VNCScreenState extends State<VNCScreen> {
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _portController =
      TextEditingController(text: '6080');
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _vncPortController =
      TextEditingController(text: '5900');
  final TextEditingController _pathController =
      TextEditingController(text: '/vnc.html');

  bool _showConnectionForm = true;
  String? _connectionError;
  bool _isConnected = false;
  bool _isConnecting = false;

  WebViewController? _webViewController;
  bool _showControls = false;

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

    _initializeWebView();
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
            setState(() {
              _connectionError = 'Failed to load noVNC: ${error.description}';
              _isConnecting = false;
              _isConnected = false;
              _showConnectionForm = true;
            });
          },
        ),
      );
  }

  void _connect() {
    final host = _hostController.text.trim();
    final webPort = int.tryParse(_portController.text.trim()) ?? 6080;
    final vncPort = int.tryParse(_vncPortController.text.trim()) ?? 5900;
    final path = _pathController.text.trim().isEmpty
        ? '/vnc.html'
        : _pathController.text.trim();
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

    // Build noVNC URL with connection parameters
    final params = <String, String>{
      'host': host,
      'port': vncPort.toString(),
      'autoconnect': 'true',
      'resize': 'scale',
    };

    if (password.isNotEmpty) {
      params['password'] = password;
    }

    final queryString = params.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');

    final noVncUrl = 'http://$host:$webPort$path?$queryString';

    _webViewController?.loadRequest(Uri.parse(noVncUrl)).then((_) {
      setState(() {
        _showConnectionForm = false;
        _isConnected = true;
        _connectionError = null;
      });
    }).catchError((error) {
      setState(() {
        _connectionError = 'Failed to connect: $error';
        _isConnecting = false;
      });
    });
  }

  void _connectWithEmbeddedNoVNC() {
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

    // Create embedded noVNC HTML
    final noVncHtml = _generateNoVNCHtml(host, vncPort, password);

    _webViewController?.loadHtmlString(noVncHtml).then((_) {
      setState(() {
        _showConnectionForm = false;
        _isConnected = true;
        _connectionError = null;
      });
    }).catchError((error) {
      setState(() {
        _connectionError = 'Failed to load embedded noVNC: $error';
        _isConnecting = false;
      });
    });
  }

  void _disconnect() {
    setState(() {
      _isConnected = false;
      _showConnectionForm = true;
      _isConnecting = false;
    });
    _webViewController
        ?.loadHtmlString('<html><body><h1>Disconnected</h1></body></html>');
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
        
        function simulateConnect() {
            const statusDiv = document.getElementById('status');
            const form = document.getElementById('connect-form');
            
            statusDiv.textContent = 'Connecting to $host:$vncPort...';
            statusDiv.className = '';
            
            // Simulate connection process
            setTimeout(() => {
                statusDiv.textContent = 'Authenticating...';
                setTimeout(() => {
                    statusDiv.textContent = 'Connected successfully!';
                    statusDiv.className = 'success';
                    
                    setTimeout(() => {
                        form.innerHTML = `
                            <div style="background: #2d2d2d; border: 2px solid #444; border-radius: 8px; padding: 20px;">
                                <h3 style="color: #51cf66; margin-top: 0;">VNC Connected</h3>
                                <p>Host: $host</p>
                                <p>Port: $vncPort</p>
                                <p style="font-size: 12px; color: #aaa; margin-top: 15px;">
                                    This is a demo noVNC interface. In a real implementation, 
                                    you would see the remote desktop here.
                                </p>
                                <div style="background: #000; height: 200px; margin: 15px 0; border: 1px solid #666; display: flex; align-items: center; justify-content: center;">
                                    <span style="color: #666;">Remote Desktop Display Area</span>
                                </div>
                                <button onclick="disconnect()" style="background: #dc3545;">Disconnect</button>
                            </div>
                        `;
                        isConnected = true;
                    }, 1000);
                }, 1000);
            }, 1000);
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.desktop_windows, size: 64, color: Colors.blue),
          const SizedBox(height: 24),
          const Text(
            'noVNC Remote Desktop',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Connect to a VNC server using noVNC web client',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 32),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Connection Type',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
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
          const SizedBox(height: 24),
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
                  onPressed: _isConnecting ? null : _connect,
                  icon: const Icon(Icons.web),
                  label: _isConnecting
                      ? const Text('Connecting...')
                      : const Text('Connect to noVNC Server'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isConnecting ? null : _connectWithEmbeddedNoVNC,
                  icon: const Icon(Icons.integration_instructions),
                  label: _isConnecting
                      ? const Text('Connecting...')
                      : const Text('Use Embedded noVNC'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          ExpansionTile(
            title: const Text('Setup Instructions'),
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Option 1: External noVNC Server',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Text(
                      '• Install noVNC on your server\n'
                      '• Run: websockify --web /path/to/noVNC 6080 localhost:5900\n'
                      '• Use server IP and port 6080',
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Option 2: Embedded noVNC (Recommended)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Text(
                      '• Uses built-in noVNC simulation\n'
                      '• No external server required\n'
                      '• Good for testing and development',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVNCDisplay() {
    return Stack(
      children: [
        // WebView displaying noVNC
        Positioned.fill(
          child: _webViewController != null
              ? WebViewWidget(controller: _webViewController!)
              : const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Initializing noVNC...'),
                    ],
                  ),
                ),
        ),

        // Control Panel (overlay)
        if (_showControls)
          Positioned(
            top: 16,
            right: 16,
            child: Card(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () {
                      _webViewController?.reload();
                    },
                    tooltip: 'Refresh',
                  ),
                  IconButton(
                    icon: const Icon(Icons.fullscreen),
                    onPressed: () {
                      // Toggle fullscreen in WebView
                      _webViewController?.runJavaScript('''
                        if (document.fullscreenElement) {
                          document.exitFullscreen();
                        } else {
                          document.documentElement.requestFullscreen();
                        }
                      ''');
                    },
                    tooltip: 'Toggle Fullscreen',
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _disconnect,
                    tooltip: 'Disconnect',
                  ),
                ],
              ),
            ),
          ),

        // Toggle controls button
        Positioned(
          top: 16,
          left: 16,
          child: FloatingActionButton.small(
            onPressed: () {
              setState(() {
                _showControls = !_showControls;
              });
            },
            child:
                Icon(_showControls ? Icons.visibility_off : Icons.visibility),
          ),
        ),

        // Connection indicator
        if (_isConnecting)
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.5),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      'Connecting to VNC...',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isConnected
            ? 'noVNC - ${_hostController.text}'
            : 'noVNC Connection'),
        backgroundColor: _isConnected ? Colors.green : null,
        actions: [
          if (_isConnected)
            IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Connection Info'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Host: ${_hostController.text}'),
                        Text('VNC Port: ${_vncPortController.text}'),
                        Text('Web Port: ${_portController.text}'),
                        Text('Path: ${_pathController.text}'),
                        const SizedBox(height: 8),
                        const Text('noVNC Features:'),
                        const Text('• Web-based VNC client'),
                        const Text('• Cross-platform compatibility'),
                        const Text('• Touch-friendly interface'),
                        const Text('• No plugins required'),
                      ],
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
          if (!_isConnected)
            IconButton(
              icon: const Icon(Icons.help_outline),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('noVNC Help'),
                    content: const SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              'noVNC is a web-based VNC client that runs in browsers.'),
                          SizedBox(height: 8),
                          Text('Setup Options:'),
                          SizedBox(height: 4),
                          Text('1. External noVNC Server:'),
                          Text('   • Requires noVNC + websockify on server'),
                          Text('   • Full VNC functionality'),
                          SizedBox(height: 8),
                          Text('2. Embedded noVNC (Demo):'),
                          Text('   • Built-in simulation'),
                          Text('   • No server setup required'),
                          Text('   • Good for testing'),
                          SizedBox(height: 8),
                          Text('Installation:'),
                          Text('git clone https://github.com/novnc/noVNC.git'),
                          Text(
                              'git clone https://github.com/novnc/websockify.git'),
                          Text(
                              './websockify/run --web noVNC/ 6080 localhost:5900'),
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
      body: _showConnectionForm ? _buildConnectionForm() : _buildVNCDisplay(),
    );
  }
}
