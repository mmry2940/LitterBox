import 'package:flutter/material.dart';
import 'package:dartssh2/dartssh2.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:xterm/xterm.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Singleton service to manage persistent terminal sessions
class TerminalSessionManager {
  static final TerminalSessionManager _instance =
      TerminalSessionManager._internal();
  factory TerminalSessionManager() => _instance;
  TerminalSessionManager._internal();

  final Map<String, TerminalSession> _sessions = {};

  TerminalSession? getSession(String sessionId) => _sessions[sessionId];

  Future<TerminalSession> createOrGetSession(
      String sessionId, SSHClient sshClient) async {
    if (_sessions.containsKey(sessionId)) {
      return _sessions[sessionId]!;
    }

    final session = TerminalSession(sessionId, sshClient);
    await session.initialize();
    _sessions[sessionId] = session;
    return session;
  }

  void removeSession(String sessionId) {
    final session = _sessions[sessionId];
    session?.dispose();
    _sessions.remove(sessionId);
  }

  void disposeAll() {
    for (final session in _sessions.values) {
      session.dispose();
    }
    _sessions.clear();
  }
}

class TerminalSession {
  final String sessionId;
  final SSHClient sshClient;
  late Terminal terminal;
  SSHSession? shellSession;
  bool _isConnected = false;
  String _connectionStatus = 'Connecting...';
  final List<void Function()> _statusListeners = [];
  final List<void Function()> _dataListeners = [];
  Timer? _keepAliveTimer;

  TerminalSession(this.sessionId, this.sshClient);

  bool get isConnected => _isConnected;
  String get connectionStatus => _connectionStatus;

  void addStatusListener(void Function() listener) {
    _statusListeners.add(listener);
  }

  void removeStatusListener(void Function() listener) {
    _statusListeners.remove(listener);
  }

  void addDataListener(void Function() listener) {
    _dataListeners.add(listener);
  }

  void removeDataListener(void Function() listener) {
    _dataListeners.remove(listener);
  }

  void _notifyStatusChange() {
    for (final listener in _statusListeners) {
      listener();
    }
  }

  void _notifyDataReceived() {
    for (final listener in _dataListeners) {
      listener();
    }
  }

  Future<void> initialize() async {
    terminal = Terminal(maxLines: 10000);

    try {
      _updateStatus('Establishing shell session...');
      final session = await sshClient.shell();
      shellSession = session;

      _updateStatus('Connected', true);

      // Write welcome message
      terminal.write(
          '\x1b[32m=== SSH Terminal Connected (Persistent) ===\x1b[0m\r\n');
      terminal.write(
          '\x1b[90mPersistent terminal session established\x1b[0m\r\n\r\n');

      // Set up data streams
      session.stdout.listen((data) {
        terminal.write(String.fromCharCodes(data));
        _notifyDataReceived();
      });

      session.stderr.listen((data) {
        terminal.write(String.fromCharCodes(data));
        _notifyDataReceived();
      });

      terminal.onOutput = (output) {
        session.write(utf8.encode(output));
      };

      // Handle session closure
      session.done.then((_) {
        _updateStatus('Disconnected', false);
        terminal.write('\r\n\x1b[31m=== SSH Session Closed ===\x1b[0m\r\n');
      });

      // Start keep-alive timer to prevent timeout
      _startKeepAlive();
    } catch (e) {
      _updateStatus('Connection failed', false);
      terminal.write('\x1b[31mShell error: $e\x1b[0m\r\n');
    }
  }

  void _updateStatus(String status, [bool? connected]) {
    _connectionStatus = status;
    if (connected != null) _isConnected = connected;
    _notifyStatusChange();
  }

  void _startKeepAlive() {
    _keepAliveTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (_isConnected && shellSession != null) {
        // Send a null byte to keep connection alive
        shellSession!.write(Uint8List.fromList([0]));
      }
    });
  }

  void sendSpecialKey(String key) {
    if (shellSession == null || !_isConnected) return;

    switch (key) {
      case 'CTRL_C':
        shellSession!.write(Uint8List.fromList([3]));
        break;
      case 'CTRL_Z':
        shellSession!.write(Uint8List.fromList([26]));
        break;
      case 'CTRL_D':
        shellSession!.write(Uint8List.fromList([4]));
        break;
      case 'ESC':
        shellSession!.write(Uint8List.fromList([27]));
        break;
      case 'TAB':
        shellSession!.write(Uint8List.fromList([9]));
        break;
      case 'UP':
        shellSession!.write(utf8.encode('\x1b[A'));
        break;
      case 'DOWN':
        shellSession!.write(utf8.encode('\x1b[B'));
        break;
      case 'LEFT':
        shellSession!.write(utf8.encode('\x1b[D'));
        break;
      case 'RIGHT':
        shellSession!.write(utf8.encode('\x1b[C'));
        break;
    }
  }

  void sendText(String text) {
    if (shellSession != null && _isConnected) {
      shellSession!.write(utf8.encode(text));
    }
  }

  void sendCommand(String command) {
    if (shellSession != null && _isConnected) {
      shellSession!.write(utf8.encode('$command\n'));
    }
  }

  void clearTerminal() {
    terminal.buffer.clear();
    terminal.write('\x1b[2J\x1b[H');
  }

  void dispose() {
    _keepAliveTimer?.cancel();
    shellSession?.close();
    _statusListeners.clear();
  }
}

class DeviceTerminalScreen extends StatefulWidget {
  final SSHClient? sshClient;
  final String? error;
  final bool loading;

  const DeviceTerminalScreen({
    super.key,
    this.sshClient,
    this.error,
    this.loading = false,
  });

  @override
  State<DeviceTerminalScreen> createState() => _DeviceTerminalScreenState();
}

class _DeviceTerminalScreenState extends State<DeviceTerminalScreen>
    with WidgetsBindingObserver {
  late TerminalController _controller;
  final ScrollController _scrollController = ScrollController();
  Timer? _cursorTrackingTimer;
  bool _showHotkeys = true;
  TerminalSession? _session;
  String _sessionId = '';
  double _fontSize = 14.0; // Default font size

  Future<void> _loadFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _fontSize = prefs.getDouble('terminal_font_size') ?? 14.0;
    });
  }

  Future<void> _saveFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('terminal_font_size', _fontSize);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = TerminalController();

    // Load saved font size
    _loadFontSize();

    // Generate session ID based on SSH client
    if (widget.sshClient != null) {
      _sessionId = 'terminal_${widget.sshClient.hashCode}';
      _initializeSession();
    }

    // Start periodic cursor tracking to ensure visibility
    _cursorTrackingTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _ensureCursorVisible(),
    );

    _startForegroundService();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Keep session alive even when app goes to background
    if (state == AppLifecycleState.paused) {
      // App is backgrounded but session stays alive
      debugPrint('Terminal: App backgrounded, keeping session alive');
    } else if (state == AppLifecycleState.resumed) {
      // App is brought back to foreground, ensure session is still connected
      debugPrint('Terminal: App resumed, checking session');
      _ensureSessionConnected();
    } else if (state == AppLifecycleState.detached) {
      // App is being closed, clean up sessions
      debugPrint('Terminal: App detached, cleaning up sessions');
      TerminalSessionManager().disposeAll();
    }
  }

  Future<void> _initializeSession() async {
    if (widget.sshClient == null) return;

    try {
      _session = await TerminalSessionManager()
          .createOrGetSession(_sessionId, widget.sshClient!);
      _session!.addStatusListener(() {
        if (mounted) {
          setState(() {}); // Trigger UI update when status changes
        }
      });

      _session!.addDataListener(() {
        if (mounted) {
          _scrollToBottom(); // Auto-scroll when new data is received
        }
      });

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Failed to initialize session: $e');
    }
  }

  void _ensureSessionConnected() {
    if (_session != null && !_session!.isConnected) {
      // Try to reconnect if session was lost
      _initializeSession();
    }
  }

  void _ensureCursorVisible() {
    if (!mounted || _session?.isConnected != true) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final position = _scrollController.position;
        final maxExtent = position.maxScrollExtent;
        final currentExtent = position.pixels;

        // If we're not near the bottom, scroll to keep cursor visible
        if (maxExtent - currentExtent > 50) {
          _scrollController.animateTo(
            maxExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cursorTrackingTimer?.cancel();
    // Remove listeners but don't close session - it should persist
    if (_session != null) {
      _session!.removeStatusListener(() {});
      _session!.removeDataListener(() {});
    }
    _scrollController.dispose();
    // Only stop foreground service if no other terminal screens are active
    FlutterForegroundTask.stopService();
    super.dispose();
  }

  void _startForegroundService() async {
    await FlutterForegroundTask.startService(
      notificationTitle: 'SSH Terminal Active',
      notificationText: 'Your SSH session is running.',
      callback: () {}, // No background callback needed for now
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 50),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendSpecialKey(String key) {
    _session?.sendSpecialKey(key);
  }

  void _sendText(String text) {
    _session?.sendText(text);
  }

  void _clearTerminal() {
    _session?.clearTerminal();
  }

  void _sendCommand(String command) {
    _session?.sendCommand(command);
    _scrollToBottom();
  }

  void _increaseFontSize() {
    setState(() {
      _fontSize = (_fontSize + 2).clamp(8.0, 24.0);
    });
    _saveFontSize();
  }

  void _decreaseFontSize() {
    setState(() {
      _fontSize = (_fontSize - 2).clamp(8.0, 24.0);
    });
    _saveFontSize();
  }

  void _resetFontSize() {
    setState(() {
      _fontSize = 14.0;
    });
    _saveFontSize();
  }

  Widget _buildHotkeyButton({
    required String label,
    required VoidCallback onPressed,
    required IconData icon,
    Color? backgroundColor,
    Color? textColor,
    String? tooltip,
  }) {
    return Tooltip(
      message: tooltip ?? label,
      child: ElevatedButton.icon(
        onPressed: (_session?.isConnected == true) ? onPressed : null,
        icon: Icon(
          icon,
          size: 14, // Smaller icon for compact design
          color: textColor ?? Colors.white,
        ),
        label: Text(
          label,
          style: TextStyle(
            fontSize: 10, // Smaller text for compact design
            fontWeight: FontWeight.bold,
            color: textColor ?? Colors.white,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor ?? Colors.grey[800],
          foregroundColor: textColor ?? Colors.white,
          padding: const EdgeInsets.symmetric(
              horizontal: 6, vertical: 3), // More compact
          minimumSize: const Size(50, 30), // Smaller minimum size
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4), // Smaller radius
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Connecting to terminal...'),
            ],
          ),
        ),
      );
    }

    if (widget.error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red,
              ),
              SizedBox(height: 16),
              Text(
                'SSH Error',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              SizedBox(height: 8),
              Text(
                widget.error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red[700]),
              ),
            ],
          ),
        ),
      );
    }

    if (widget.sshClient == null) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Waiting for SSH connection...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Terminal'),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        actions: [
          // Connection status indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color:
                  (_session?.isConnected == true) ? Colors.green : Colors.red,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  (_session?.isConnected == true) ? Icons.wifi : Icons.wifi_off,
                  size: 16,
                  color: Colors.white,
                ),
                const SizedBox(width: 4),
                Text(
                  _session?.connectionStatus ?? 'No session',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // Clear terminal button
          IconButton(
            onPressed: _clearTerminal,
            icon: const Icon(Icons.clear_all),
            tooltip: 'Clear Terminal',
          ),
          // Toggle hotkeys button
          IconButton(
            onPressed: () => setState(() => _showHotkeys = !_showHotkeys),
            icon: Icon(_showHotkeys ? Icons.keyboard_hide : Icons.keyboard),
            tooltip: _showHotkeys ? 'Hide Hotkeys' : 'Show Hotkeys',
          ),
          // Font size controls
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'increase':
                  _increaseFontSize();
                  break;
                case 'decrease':
                  _decreaseFontSize();
                  break;
                case 'reset':
                  _resetFontSize();
                  break;
              }
            },
            icon: const Icon(Icons.text_fields),
            tooltip: 'Font Size',
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'increase',
                child: ListTile(
                  leading: const Icon(Icons.add, size: 20),
                  title: Text('Increase Font (${_fontSize.toInt()}px)'),
                  dense: true,
                ),
              ),
              PopupMenuItem(
                value: 'decrease',
                child: ListTile(
                  leading: const Icon(Icons.remove, size: 20),
                  title: const Text('Decrease Font'),
                  dense: true,
                ),
              ),
              PopupMenuItem(
                value: 'reset',
                child: ListTile(
                  leading: const Icon(Icons.refresh, size: 20),
                  title: const Text('Reset Font (14px)'),
                  dense: true,
                ),
              ),
            ],
          ),
          // Quick commands menu
          PopupMenuButton<String>(
            onSelected: _sendCommand,
            icon: const Icon(Icons.terminal),
            tooltip: 'Quick Commands',
            itemBuilder: (context) => [
              // File operations
              const PopupMenuItem(
                value: 'ls -la',
                child: ListTile(
                  leading: Icon(Icons.folder, size: 20),
                  title: Text('List files (ls -la)'),
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: 'pwd',
                child: ListTile(
                  leading: Icon(Icons.location_on, size: 20),
                  title: Text('Current directory (pwd)'),
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: 'du -h',
                child: ListTile(
                  leading: Icon(Icons.folder_open, size: 20),
                  title: Text('Directory size (du -h)'),
                  dense: true,
                ),
              ),
              const PopupMenuDivider(),
              // System monitoring
              const PopupMenuItem(
                value: 'top',
                child: ListTile(
                  leading: Icon(Icons.memory, size: 20),
                  title: Text('System monitor (top)'),
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: 'htop',
                child: ListTile(
                  leading: Icon(Icons.speed, size: 20),
                  title: Text('Enhanced monitor (htop)'),
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: 'df -h',
                child: ListTile(
                  leading: Icon(Icons.storage, size: 20),
                  title: Text('Disk usage (df -h)'),
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: 'free -h',
                child: ListTile(
                  leading: Icon(Icons.memory, size: 20),
                  title: Text('Memory usage (free -h)'),
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: 'ps aux',
                child: ListTile(
                  leading: Icon(Icons.list, size: 20),
                  title: Text('Running processes (ps aux)'),
                  dense: true,
                ),
              ),
              const PopupMenuDivider(),
              // System updates
              const PopupMenuItem(
                value: 'sudo apt update',
                child: ListTile(
                  leading: Icon(Icons.refresh, size: 20),
                  title: Text('Update package list (apt update)'),
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: 'sudo apt update -y && sudo apt upgrade -y',
                child: ListTile(
                  leading: Icon(Icons.system_update, size: 20),
                  title: Text('Full system update'),
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: 'sudo apt autoremove -y',
                child: ListTile(
                  leading: Icon(Icons.cleaning_services, size: 20),
                  title: Text('Clean unused packages'),
                  dense: true,
                ),
              ),
              const PopupMenuDivider(),
              // Network commands
              const PopupMenuItem(
                value: 'ip addr show',
                child: ListTile(
                  leading: Icon(Icons.network_check, size: 20),
                  title: Text('Show IP addresses'),
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: 'ping -c 4 8.8.8.8',
                child: ListTile(
                  leading: Icon(Icons.wifi, size: 20),
                  title: Text('Test connectivity (ping)'),
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: 'netstat -tuln',
                child: ListTile(
                  leading: Icon(Icons.router, size: 20),
                  title: Text('Network connections'),
                  dense: true,
                ),
              ),
              const PopupMenuDivider(),
              // System information
              const PopupMenuItem(
                value: 'uname -a',
                child: ListTile(
                  leading: Icon(Icons.info, size: 20),
                  title: Text('System information'),
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: 'lscpu',
                child: ListTile(
                  leading: Icon(Icons.developer_board, size: 20),
                  title: Text('CPU information'),
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: 'lsblk',
                child: ListTile(
                  leading: Icon(Icons.storage, size: 20),
                  title: Text('Block devices'),
                  dense: true,
                ),
              ),
              const PopupMenuDivider(),
              // Service management
              const PopupMenuItem(
                value: 'systemctl status',
                child: ListTile(
                  leading: Icon(Icons.settings, size: 20),
                  title: Text('Service status'),
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: 'sudo systemctl list-units --failed',
                child: ListTile(
                  leading: Icon(Icons.error, size: 20),
                  title: Text('Failed services'),
                  dense: true,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Terminal view
          Expanded(
            child: Container(
              color: Colors.black,
              child: _session?.terminal != null
                  ? Transform.scale(
                      scale: _fontSize /
                          14.0, // Scale relative to default font size
                      child: TerminalView(
                        _session!.terminal,
                        controller: _controller,
                        scrollController: _scrollController,
                        autofocus: true,
                        deleteDetection: true,
                        keyboardType: TextInputType.text,
                        readOnly: false,
                        hardwareKeyboardOnly: false,
                        theme: TerminalTheme(
                          cursor: Colors.greenAccent,
                          selection: Colors.grey.withValues(alpha: 0.3),
                          foreground: Colors.white,
                          background: Colors.black,
                          black: Colors.black,
                          red: Colors.red,
                          green: Colors.green,
                          yellow: Colors.yellow,
                          blue: Colors.blue,
                          magenta: Colors.purple,
                          cyan: Colors.cyan,
                          white: Colors.white,
                          brightBlack: Colors.grey,
                          brightRed: Colors.redAccent,
                          brightGreen: Colors.greenAccent,
                          brightYellow: Colors.yellowAccent,
                          brightBlue: Colors.blueAccent,
                          brightMagenta: Colors.purpleAccent,
                          brightCyan: Colors.cyanAccent,
                          brightWhite: Colors.white,
                          searchHitBackground:
                              Colors.yellow.withValues(alpha: 0.5),
                          searchHitBackgroundCurrent:
                              Colors.orange.withValues(alpha: 0.7),
                          searchHitForeground: Colors.black,
                        ),
                      ),
                    )
                  : const Center(
                      child: CircularProgressIndicator(),
                    ),
            ),
          ),
          // Hotkey row (conditional)
          if (_showHotkeys)
            Container(
              color: Colors.grey[900],
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 4), // Reduced padding
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Scroll indicator
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.swipe,
                        size: 12,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Swipe for more hotkeys',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // First row - Control keys (scrollable)
                  SizedBox(
                    height: 40,
                    child: ShaderMask(
                      shaderCallback: (Rect bounds) {
                        return const LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.transparent,
                            Colors.black,
                            Colors.black,
                            Colors.transparent,
                          ],
                          stops: [0.0, 0.05, 0.95, 1.0],
                        ).createShader(bounds);
                      },
                      blendMode: BlendMode.dstIn,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            const SizedBox(width: 8), // Start padding
                            _buildHotkeyButton(
                              label: 'Ctrl+C',
                              icon: Icons.stop,
                              onPressed: () => _sendSpecialKey('CTRL_C'),
                              backgroundColor: Colors.red[700],
                              tooltip: 'Send interrupt signal (Ctrl+C)',
                            ),
                            const SizedBox(width: 4),
                            _buildHotkeyButton(
                              label: 'Ctrl+Z',
                              icon: Icons.pause,
                              onPressed: () => _sendSpecialKey('CTRL_Z'),
                              backgroundColor: Colors.orange[700],
                              tooltip: 'Suspend process (Ctrl+Z)',
                            ),
                            const SizedBox(width: 4),
                            _buildHotkeyButton(
                              label: 'Ctrl+D',
                              icon: Icons.exit_to_app,
                              onPressed: () => _sendSpecialKey('CTRL_D'),
                              backgroundColor: Colors.blue[700],
                              tooltip: 'End of transmission (Ctrl+D)',
                            ),
                            const SizedBox(width: 4),
                            _buildHotkeyButton(
                              label: 'Ctrl+L',
                              icon: Icons.clear_all,
                              onPressed: () => _sendSpecialKey('CTRL_L'),
                              backgroundColor: Colors.green[700],
                              tooltip: 'Clear screen (Ctrl+L)',
                            ),
                            const SizedBox(width: 8),
                            // Arrow keys
                            _buildHotkeyButton(
                              label: '↑',
                              icon: Icons.keyboard_arrow_up,
                              onPressed: () => _sendSpecialKey('UP'),
                              tooltip: 'Up arrow',
                            ),
                            const SizedBox(width: 4),
                            _buildHotkeyButton(
                              label: '↓',
                              icon: Icons.keyboard_arrow_down,
                              onPressed: () => _sendSpecialKey('DOWN'),
                              tooltip: 'Down arrow',
                            ),
                            const SizedBox(width: 4),
                            _buildHotkeyButton(
                              label: '←',
                              icon: Icons.keyboard_arrow_left,
                              onPressed: () => _sendSpecialKey('LEFT'),
                              tooltip: 'Left arrow',
                            ),
                            const SizedBox(width: 4),
                            _buildHotkeyButton(
                              label: '→',
                              icon: Icons.keyboard_arrow_right,
                              onPressed: () => _sendSpecialKey('RIGHT'),
                              tooltip: 'Right arrow',
                            ),
                            const SizedBox(width: 8), // End padding
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Second row - Special characters and functions (scrollable)
                  SizedBox(
                    height: 40,
                    child: ShaderMask(
                      shaderCallback: (Rect bounds) {
                        return const LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.transparent,
                            Colors.black,
                            Colors.black,
                            Colors.transparent,
                          ],
                          stops: [0.0, 0.05, 0.95, 1.0],
                        ).createShader(bounds);
                      },
                      blendMode: BlendMode.dstIn,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            const SizedBox(width: 8), // Start padding
                            _buildHotkeyButton(
                              label: 'Tab',
                              icon: Icons.keyboard_tab,
                              onPressed: () => _sendSpecialKey('TAB'),
                              tooltip: 'Tab key for auto-completion',
                            ),
                            const SizedBox(width: 4),
                            _buildHotkeyButton(
                              label: 'Esc',
                              icon: Icons.keyboard_return,
                              onPressed: () => _sendSpecialKey('ESC'),
                              tooltip: 'Escape key',
                            ),
                            const SizedBox(width: 8),
                            // Common symbols
                            _buildHotkeyButton(
                              label: '|',
                              icon: Icons.vertical_split,
                              onPressed: () => _sendText('|'),
                              tooltip: 'Pipe symbol',
                            ),
                            const SizedBox(width: 4),
                            _buildHotkeyButton(
                              label: '&',
                              icon: Icons.add,
                              onPressed: () => _sendText('&'),
                              tooltip: 'Ampersand',
                            ),
                            const SizedBox(width: 4),
                            _buildHotkeyButton(
                              label: ';',
                              icon: Icons.more_vert,
                              onPressed: () => _sendText(';'),
                              tooltip: 'Semicolon',
                            ),
                            const SizedBox(width: 4),
                            _buildHotkeyButton(
                              label: '~',
                              icon: Icons.home,
                              onPressed: () => _sendText('~'),
                              tooltip: 'Tilde (home directory)',
                            ),
                            const SizedBox(width: 4),
                            _buildHotkeyButton(
                              label: '*',
                              icon: Icons.star,
                              onPressed: () => _sendText('*'),
                              tooltip: 'Asterisk (wildcard)',
                            ),
                            const SizedBox(width: 4),
                            _buildHotkeyButton(
                              label: '?',
                              icon: Icons.help_outline,
                              onPressed: () => _sendText('?'),
                              tooltip: 'Question mark (single char wildcard)',
                            ),
                            const SizedBox(width: 8), // End padding
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
