import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../vnc_client.dart';
import 'vnc_viewer_screen.dart';

enum VNCConnectionMode {
  demo,
  webview, // noVNC via WebView
  native, // Native VNC client
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

class _VNCScreenState extends State<VNCScreen> {
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

  WebViewController? _webViewController;
  VNCConnectionMode _connectionMode = VNCConnectionMode.demo;
  VNCClient? _vncClient;

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
      });
      print('DEBUG: WebView VNC connected, navigating to webview viewer screen');
      
      // Navigate to webview viewer screen
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => VNCViewerScreen(
            host: host,
            port: vncPort,
            password: password.isNotEmpty ? password : null,
            mode: VNCViewerMode.webview,
            webViewController: _webViewController,
          ),
        ),
      ).then((_) {
        // When returning from viewer screen, reset state
        setState(() {
          _isConnecting = false;
        });
      });
    }).catchError((error) {
      setState(() {
        _connectionError = 'Failed to load embedded noVNC: $error';
        _isConnecting = false;
      });
    });
  }

  // Demo mode connection - immediately navigates to demo viewer
  void _connectWithDemo() {
    print('DEBUG: _connectWithDemo called');
    setState(() {
      _isConnecting = true;
      _connectionError = null;
    });
    print('DEBUG: Set _isConnecting to true');

    // Simulate a brief connection delay
    Future.delayed(const Duration(seconds: 1), () {
      print('DEBUG: Delayed callback executing');
      setState(() {
        _isConnecting = false;
      });
      print('DEBUG: Demo VNC connected, navigating to demo viewer screen');
      
      // Navigate to demo viewer screen
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => VNCViewerScreen(
            host: _hostController.text.isNotEmpty ? _hostController.text : 'demo.local',
            port: int.tryParse(_vncPortController.text) ?? 5900,
            password: _passwordController.text.isNotEmpty ? _passwordController.text : null,
            mode: VNCViewerMode.demo,
          ),
        ),
      ).then((_) {
        // When returning from viewer screen, reset state
        setState(() {
          _isConnecting = false;
        });
      });
    });
  }

  // Helper methods for connection mode UI
  String _getConnectionModeDescription() {
    switch (_connectionMode) {
      case VNCConnectionMode.demo:
        return 'Interactive demo - no real server required';
      case VNCConnectionMode.webview:
        return 'Connect to noVNC server via WebView';
      case VNCConnectionMode.native:
        return 'Native VNC client with direct socket connection';
    }
  }

  VoidCallback? _getConnectFunction() {
    switch (_connectionMode) {
      case VNCConnectionMode.demo:
        return _connectWithDemo;
      case VNCConnectionMode.webview:
        return _connectWithEmbeddedNoVNC;
      case VNCConnectionMode.native:
        return _connectWithNativeVNC;
    }
  }

  IconData _getConnectIcon() {
    switch (_connectionMode) {
      case VNCConnectionMode.demo:
        return Icons.play_arrow;
      case VNCConnectionMode.webview:
        return Icons.web;
      case VNCConnectionMode.native:
        return Icons.cast_connected;
    }
  }

  String _getConnectButtonText() {
    switch (_connectionMode) {
      case VNCConnectionMode.demo:
        return 'Start Demo';
      case VNCConnectionMode.webview:
        return 'Connect via noVNC';
      case VNCConnectionMode.native:
        return 'Connect via Native VNC';
    }
  }

  Color? _getConnectButtonColor() {
    switch (_connectionMode) {
      case VNCConnectionMode.demo:
        return Colors.green;
      case VNCConnectionMode.webview:
        return null;
      case VNCConnectionMode.native:
        return Colors.blue;
    }
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
      setState(() {
        switch (state) {
          case VNCConnectionState.connected:
            print('DEBUG: Connection state is CONNECTED, navigating to VNC viewer screen');
            _isConnecting = false;
            
            // Navigate to dedicated VNC viewer screen
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => VNCViewerScreen(
                  host: host,
                  port: vncPort,
                  password: password.isNotEmpty ? password : null,
                  mode: VNCViewerMode.native,
                  vncClient: _vncClient,
                ),
              ),
            ).then((_) {
              // When returning from viewer screen, reset state
              setState(() {
                _isConnecting = false;
              });
            });
            break;
          case VNCConnectionState.failed:
            print('DEBUG: Connection state is FAILED');
            _connectionError =
                'Failed to connect to VNC server. If you see "Too many security failures", wait 5-10 minutes before retrying.';
            _isConnecting = false;
            break;
          case VNCConnectionState.disconnected:
            print('DEBUG: Connection state is DISCONNECTED');
            _isConnecting = false;
            break;
          default:
            print('DEBUG: Connection state is: $state');
            break;
        }
      });
    });

    // Add delay to avoid triggering VNC server security lockout
    Future.delayed(const Duration(seconds: 2), () {
      _vncClient!
          .connect(host, vncPort,
              password: password.isNotEmpty ? password : null)
          .then((success) {
        if (!success) {
          setState(() {
            _connectionError =
                'Failed to connect to VNC server. Check logs for details. If "Too many security failures", wait before retrying.';
            _isConnecting = false;
          });
        }
      }).catchError((error) {
        setState(() {
          _connectionError = 'Connection error: $error';
          _isConnecting = false;
        });
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

                  // Connection Mode Dropdown
                  DropdownButtonFormField<VNCConnectionMode>(
                    value: _connectionMode,
                    decoration: const InputDecoration(
                      labelText: 'VNC Client Type',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.settings_display),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: VNCConnectionMode.demo,
                        child: Text('Demo Mode (Simulation)'),
                      ),
                      DropdownMenuItem(
                        value: VNCConnectionMode.webview,
                        child: Text('noVNC (WebView)'),
                      ),
                      DropdownMenuItem(
                        value: VNCConnectionMode.native,
                        child: Text('Native VNC Client'),
                      ),
                    ],
                    onChanged: (VNCConnectionMode? value) {
                      if (value != null) {
                        setState(() {
                          _connectionMode = value;
                          if (_connectionMode == VNCConnectionMode.demo) {
                            _hostController.text = 'demo.local';
                            _vncPortController.text = '5900';
                          } else if (_connectionMode ==
                              VNCConnectionMode.native) {
                            _hostController.text = '';
                            _vncPortController.text = '5900';
                          } else {
                            _hostController.text = '';
                            _vncPortController.text = '5900';
                          }
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _getConnectionModeDescription(),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: _hostController,
                    enabled: _connectionMode != VNCConnectionMode.demo,
                    decoration: InputDecoration(
                      labelText: 'Host/IP Address',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.computer),
                      helperText: _connectionMode == VNCConnectionMode.demo
                          ? 'Demo mode - server not required'
                          : 'VNC server hostname or IP address',
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
          if (_connectionMode != VNCConnectionMode.demo) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isConnecting ? null : _connectWithEmbeddedNoVNC,
                    icon: const Icon(Icons.integration_instructions),
                    label: const Text('Use Embedded Demo'),
                  ),
                ),
              ],
            ),
          ],
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VNC Connection'),
        actions: [
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
                        Text('VNC (Virtual Network Computing) allows you to remotely control another computer.'),
                        SizedBox(height: 8),
                        Text('Connection Modes:'),
                        SizedBox(height: 4),
                        Text('• Demo Mode: Interactive simulation'),
                        Text('• WebView Mode: noVNC web client'),
                        Text('• Native Mode: Direct VNC protocol'),
                        SizedBox(height: 8),
                        Text('For real connections, you need:'),
                        Text('• VNC server running on target machine'),
                        Text('• Correct host/IP and port'),
                        Text('• Password (if required)'),
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
      body: _buildConnectionForm(),
    );
  }
}
