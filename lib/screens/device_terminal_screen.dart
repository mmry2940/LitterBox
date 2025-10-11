import 'package:flutter/material.dart';
import 'package:dartssh2/dartssh2.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:xterm/xterm.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

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

class _DeviceTerminalScreenState extends State<DeviceTerminalScreen> {
  late Terminal _terminal;
  late TerminalController _controller;
  SSHSession? _shellSession;
  final ScrollController _scrollController = ScrollController();
  bool _isConnected = false;
  String _connectionStatus = 'Connecting...';
  Timer? _cursorTrackingTimer;
  bool _showHotkeys = true;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(
      maxLines: 10000, // Large buffer for command history
    );
    _controller = TerminalController();

    // Start periodic cursor tracking to ensure visibility
    _cursorTrackingTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _ensureCursorVisible(),
    );

    _startForegroundService();
    _startShell();
  }

  void _ensureCursorVisible() {
    if (!mounted || !_isConnected) return;

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
    _cursorTrackingTimer?.cancel();
    _shellSession?.close();
    _scrollController.dispose();
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

  Future<void> _startShell() async {
    if (widget.sshClient == null) {
      setState(() {
        _connectionStatus = 'No SSH client available';
        _isConnected = false;
      });
      return;
    }

    setState(() {
      _connectionStatus = 'Establishing shell session...';
    });

    try {
      final session = await widget.sshClient!.shell();
      _shellSession = session;

      setState(() {
        _connectionStatus = 'Connected';
        _isConnected = true;
      });

      // Write welcome message
      _terminal.write('\x1b[32m=== SSH Terminal Connected ===\x1b[0m\r\n');
      _terminal.write(
          '\x1b[90mTerminal session established successfully\x1b[0m\r\n\r\n');

      session.stdout.listen((data) {
        final output = String.fromCharCodes(data);
        _terminal.write(output);
        // Auto-scroll after receiving output
        if (output.isNotEmpty) {
          _scrollToBottom();
        }
      });

      session.stderr.listen((data) {
        final output = String.fromCharCodes(data);
        _terminal.write(output);
        // Auto-scroll after receiving output
        if (output.isNotEmpty) {
          _scrollToBottom();
        }
      });

      _terminal.onOutput = (output) {
        session.write(utf8.encode(output));
        // Don't scroll here - let the server echo handle it
      };

      // Handle session closure
      session.done.then((_) {
        setState(() {
          _connectionStatus = 'Disconnected';
          _isConnected = false;
        });
        _terminal.write('\r\n\x1b[31m=== SSH Session Closed ===\x1b[0m\r\n');
      });
    } catch (e) {
      setState(() {
        _connectionStatus = 'Connection failed';
        _isConnected = false;
      });
      _terminal.write('\x1b[31mShell error: $e\x1b[0m\r\n');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration:
              const Duration(milliseconds: 50), // Faster response for typing
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clearTerminal() {
    _terminal.buffer.clear();
    _terminal.write('\x1b[2J\x1b[H'); // Clear screen and move cursor to home
  }

  void _sendCommand(String command) {
    if (_shellSession != null && _isConnected) {
      _shellSession!.write(utf8.encode('$command\n'));
      _scrollToBottom();
    }
  }

  void _sendSpecialKey(String key) {
    if (_shellSession == null || !_isConnected) return;

    switch (key) {
      case 'CTRL_C':
        _shellSession!.write(Uint8List.fromList([3])); // ETX (End of Text)
        break;
      case 'CTRL_Z':
        _shellSession!.write(Uint8List.fromList([26])); // SUB (Substitute)
        break;
      case 'CTRL_D':
        _shellSession!
            .write(Uint8List.fromList([4])); // EOT (End of Transmission)
        break;
      case 'CTRL_L':
        _clearTerminal();
        break;
      case 'ESC':
        _shellSession!.write(Uint8List.fromList([27])); // ESC
        break;
      case 'TAB':
        _shellSession!.write(Uint8List.fromList([9])); // TAB
        break;
      case 'UP':
        _shellSession!.write(utf8.encode('\x1b[A'));
        break;
      case 'DOWN':
        _shellSession!.write(utf8.encode('\x1b[B'));
        break;
      case 'LEFT':
        _shellSession!.write(utf8.encode('\x1b[D'));
        break;
      case 'RIGHT':
        _shellSession!.write(utf8.encode('\x1b[C'));
        break;
    }
  }

  void _sendText(String text) {
    if (_shellSession != null && _isConnected) {
      _shellSession!.write(utf8.encode(text));
    }
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
        onPressed: _isConnected ? onPressed : null,
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
              color: _isConnected ? Colors.green : Colors.red,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isConnected ? Icons.wifi : Icons.wifi_off,
                  size: 16,
                  color: Colors.white,
                ),
                const SizedBox(width: 4),
                Text(
                  _connectionStatus,
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
          // Quick commands menu
          PopupMenuButton<String>(
            onSelected: _sendCommand,
            icon: const Icon(Icons.terminal),
            tooltip: 'Quick Commands',
            itemBuilder: (context) => [
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
                value: 'top',
                child: ListTile(
                  leading: Icon(Icons.memory, size: 20),
                  title: Text('System monitor (top)'),
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
                value: 'ps aux',
                child: ListTile(
                  leading: Icon(Icons.list, size: 20),
                  title: Text('Running processes (ps aux)'),
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
              child: TerminalView(
                _terminal,
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
                  searchHitBackground: Colors.yellow.withValues(alpha: 0.5),
                  searchHitBackgroundCurrent:
                      Colors.orange.withValues(alpha: 0.7),
                  searchHitForeground: Colors.black,
                ),
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
