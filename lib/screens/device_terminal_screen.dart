import 'package:flutter/material.dart';
import 'package:dartssh2/dartssh2.dart';
import 'dart:async';
import 'dart:convert';
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
      body: Container(
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
            searchHitBackgroundCurrent: Colors.orange.withValues(alpha: 0.7),
            searchHitForeground: Colors.black,
          ),
        ),
      ),
    );
  }
}
