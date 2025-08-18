import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../adb_client.dart';
import '../adb_backend.dart';
import '../adb/flutter_adb_client.dart';
import '../models/saved_adb_device.dart';
import '../models/app_info.dart';
import '../adb/adb_mdns_discovery.dart';
import '../adb/usb_bridge.dart';
import '../services/shared_adb_manager.dart';
import 'apps_screen.dart';

/// Modular refactored ADB & WebADB UI.
class AdbRefactoredScreen extends StatefulWidget {
  const AdbRefactoredScreen({super.key});
  @override
  State<AdbRefactoredScreen> createState() => _AdbRefactoredScreenState();
}

class _AdbRefactoredScreenState extends State<AdbRefactoredScreen>
    with TickerProviderStateMixin {
  late final ADBClientManager _adb;
  int _selectedIndex = 0; // Replace TabController with index-based navigation

  // Connection & pairing
  final _host = TextEditingController();
  final _port = TextEditingController(text: '5555');
  final _pairingPort = TextEditingController(text: '37205');
  final _pairingCode = TextEditingController();
  ADBConnectionType _connectionType = ADBConnectionType.wifi;
  // mDNS discovery
  final AdbMdnsDiscovery _mdns = AdbMdnsDiscovery();
  List<AdbMdnsServiceInfo> _mdnsServices = [];
  bool _mdnsScanning = false;
  DateTime? _lastMdnsScan;
  // USB devices
  List<UsbDeviceInfo> _usbDevices = [];
  StreamSubscription? _usbEventsSub;

  // Console
  final _cmd = TextEditingController();
  final _consoleScroll = ScrollController();
  final List<String> _localBuffer = [];
  
  // Shell output buffer for flutter_adb
  final List<String> _shellOutputBuffer = [];
  StreamSubscription<String>? _shellOutputSub;

  // Logcat
  final _logcatFilter = TextEditingController();
  String _activeLogcatFilter = '';
  String _logcatLevel = 'All'; // Filter by log level

  // Files
  final _apkPath = TextEditingController();
  final _pushLocal = TextEditingController();
  final _pushRemote = TextEditingController(text: '/sdcard/');
  final _pullRemote = TextEditingController();
  final _pullLocal = TextEditingController();
  final _forwardLocalPort = TextEditingController(text: '9000');
  final _forwardRemoteSpec = TextEditingController(text: 'tcp:9000');

  // Recents
  List<String> _recentApk = [];
  List<String> _recentLocal = [];
  List<String> _recentRemote = [];
  List<String> _recentForwards = [];

  // Saved devices
  List<SavedADBDevice> _savedDevices = [];
  SavedADBDevice? _selectedSaved;
  // (Optional future) bool _showWebToken = false; // reserved for show/hide token toggle

  bool _loadingConnect = false;
  int _logcatLinesShown = 0;
  bool _autoStartLogcat = true; // Preference for auto-starting logcat
  bool _autoOpenShell = true; // Preference for auto-opening shell on connection
  final ScrollController _logcatScrollController = ScrollController();

  // App management state
  List<AppInfo> _installedApps = [];
  List<AppInfo> _systemApps = [];
  bool _loadingApps = false;
  String _appSearchQuery = '';
  String _selectedAppFilter = 'All'; // All, User, System, Enabled, Disabled

  @override
  void initState() {
    super.initState();
    
    // Use the shared ADB manager to ensure connection reuse
    _adb = SharedADBManager.instance.getSharedClient();
    
    _adb.output.listen((line) {
      if (_localBuffer.length > 1500) _localBuffer.removeRange(0, 800);
      _localBuffer.add(line);
      _autoScroll();
    });
    
    // Listen for connection state changes to auto-start logcat and shell
    _adb.connectionState.listen((state) {
      if (state == ADBConnectionState.connected) {
        // Small delay to ensure connection is fully established
        Future.delayed(const Duration(milliseconds: 500), () async {
          if (_adb.currentState == ADBConnectionState.connected) {
            
            // Auto-start logcat if enabled
            if (_autoStartLogcat && !_adb.logcatActive) {
              await _adb.startLogcat();
              if (mounted) {
                setState(() {});
                // Auto-switch to logcat tab when it starts
                setState(() => _selectedIndex = 3); // Logcat tab index
              }
            }
            
            // Auto-open shell for Flutter ADB backend
            if (_autoOpenShell && _adb.backend is FlutterAdbBackend) {
              await _openFlutterAdbShell();
              if (mounted) {
                setState(() {});
                // Auto-switch to terminal tab when shell opens
                if (!_autoStartLogcat) { // Only switch if logcat isn't taking priority
                  setState(() => _selectedIndex = 1); // Terminal tab index
                }
              }
            }
          }
        });
      }
    });
    
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _recentApk = prefs.getStringList('recent_apk') ?? [];
      _recentLocal = prefs.getStringList('recent_local') ?? [];
      _recentRemote = prefs.getStringList('recent_remote') ?? [];
      _recentForwards = prefs.getStringList('recent_forwards') ?? [];
      _autoStartLogcat = prefs.getBool('auto_start_logcat') ?? true;
      _autoOpenShell = prefs.getBool('auto_open_shell') ?? true;
      _savedDevices = (prefs.getStringList('adb_devices') ?? [])
          .map((j) => SavedADBDevice.fromJson(jsonDecode(j)))
          .toList();
      final cachedMdns = prefs.getString('mdns_cache');
      if (cachedMdns != null) {
        try {
          final list = (jsonDecode(cachedMdns) as List)
              .map(
                  (e) => AdbMdnsServiceInfo.fromJson(e as Map<String, dynamic>))
              .toList();
          _mdnsServices = list;
        } catch (_) {}
      }
    });
    _startUsbEvents();
  }

  Future<void> _persistRecents() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('recent_apk', _recentApk.take(12).toList());
    await prefs.setStringList('recent_local', _recentLocal.take(12).toList());
    await prefs.setStringList('recent_remote', _recentRemote.take(12).toList());
    await prefs.setStringList(
        'recent_forwards', _recentForwards.take(12).toList());
  }

  Future<void> _saveAutoLogcatPreference() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_start_logcat', _autoStartLogcat);
  }

  Future<void> _saveAutoShellPreference() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_open_shell', _autoOpenShell);
  }

  Future<void> _saveDevice() async {
    if (_host.text.trim().isEmpty) return;
    final dev = SavedADBDevice(
      name: '${_host.text}:${_port.text}',
      host: _host.text.trim(),
      port: int.tryParse(_port.text.trim()) ?? 5555,
      connectionType: _connectionType,
    );
    _savedDevices.removeWhere((d) => d.name == dev.name);
    _savedDevices.insert(0, dev);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('adb_devices',
        _savedDevices.map((d) => jsonEncode(d.toJson())).toList());
    if (mounted) setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Device saved')));
    }
  }

  void _loadDevice(SavedADBDevice d) {
    setState(() {
      _host.text = d.host;
      _port.text = d.port.toString();
      _connectionType = d.connectionType;
      _selectedSaved = d;
    });
  }

  void _autoScroll() {
    if (!_consoleScroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_consoleScroll.hasClients) return;
      _consoleScroll.jumpTo(_consoleScroll.position.maxScrollExtent);
    });
  }

  List<String> _bufferSnapshot() => _adb.outputBuffer.isNotEmpty
      ? _adb.outputBuffer
      : List.unmodifiable(_localBuffer);

  List<String> _shellBufferSnapshot() {
    if (_adb.backend is FlutterAdbBackend) {
      return _shellOutputBuffer.isNotEmpty
          ? List.unmodifiable(_shellOutputBuffer)
          : ['Flutter ADB shell ready. Type commands to interact with the device.'];
    } else {
      // For non-flutter_adb backends, show regular output
      return _bufferSnapshot();
    }
  }

  @override
  void dispose() {
    _adb.dispose();
    _cmd.dispose();
    _host.dispose();
    _port.dispose();
    _pairingPort.dispose();
    _pairingCode.dispose();
    _apkPath.dispose();
    _pushLocal.dispose();
    _pushRemote.dispose();
    _pullRemote.dispose();
    _pullLocal.dispose();
    _forwardLocalPort.dispose();
    _forwardRemoteSpec.dispose();
    _logcatFilter.dispose();
    _logcatScrollController.dispose();
    _usbEventsSub?.cancel();
    _shellOutputSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideScreen = constraints.maxWidth >= 800;

          return Scaffold(
            appBar: AppBar(
              title: const Text('ADB Manager'),
              actions: [
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    switch (v) {
                      case 'output_mode':
                        setState(() {
                          _adb.setOutputMode(
                              _adb.outputMode == ADBOutputMode.raw
                                  ? ADBOutputMode.verbose
                                  : ADBOutputMode.raw);
                        });
                        break;
                      case 'clear_output':
                        _adb.clearOutput();
                        break;
                      case 'clear_history':
                        _adb.clearHistory();
                        break;
                    }
                  },
                  itemBuilder: (c) => [
                    PopupMenuItem(
                      value: 'output_mode',
                      child: Text('Mode: ${_adb.outputMode.name}'),
                    ),
                    const PopupMenuItem(
                      value: 'clear_output',
                      child: Text('Clear Output'),
                    ),
                    const PopupMenuItem(
                      value: 'clear_history',
                      child: Text('Clear History'),
                    ),
                  ],
                )
              ],
            ),
            body: Row(
              children: [
                if (isWideScreen) ...[
                  // Desktop/Tablet: NavigationRail + Device Panel
                  NavigationRail(
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: (index) =>
                        setState(() => _selectedIndex = index),
                    labelType: NavigationRailLabelType.selected,
                    destinations: const [
                      NavigationRailDestination(
                          icon: Icon(Icons.dashboard),
                          label: Text('Dashboard')),
                      NavigationRailDestination(
                          icon: Icon(Icons.terminal), label: Text('Terminal')),
                      NavigationRailDestination(
                          icon: Icon(Icons.list_alt), label: Text('Logcat')),
                      NavigationRailDestination(
                          icon: Icon(Icons.play_arrow),
                          label: Text('Commands')),
                      NavigationRailDestination(
                          icon: Icon(Icons.apps), label: Text('Apps')),
                      NavigationRailDestination(
                          icon: Icon(Icons.folder), label: Text('Files')),
                      NavigationRailDestination(
                          icon: Icon(Icons.info), label: Text('Info')),
                    ],
                  ),
                  SizedBox(width: 250, child: _devicePanel()),
                ],
                // Main content area
                Expanded(child: _buildSelectedContent()),
              ],
            ),
            bottomNavigationBar: isWideScreen
                ? null
                : BottomNavigationBar(
                    currentIndex:
                        _selectedIndex.clamp(0, 5), // Updated limit for mobile
                    onTap: (index) => setState(() => _selectedIndex = index),
                    type: BottomNavigationBarType.fixed,
                    items: const [
                      BottomNavigationBarItem(
                          icon: Icon(Icons.dashboard), label: 'Dashboard'),
                      BottomNavigationBarItem(
                          icon: Icon(Icons.terminal), label: 'Terminal'),
                      BottomNavigationBarItem(
                          icon: Icon(Icons.list_alt), label: 'Logcat'),
                      BottomNavigationBarItem(
                          icon: Icon(Icons.play_arrow), label: 'Commands'),
                      BottomNavigationBarItem(
                          icon: Icon(Icons.apps), label: 'Apps'),
                      BottomNavigationBarItem(
                          icon: Icon(Icons.more_horiz), label: 'More'),
                    ],
                  ),
          );
        },
    );
  }

  Widget _buildSelectedContent() {
    switch (_selectedIndex) {
      case 0:
        return _dashboardTab();
      case 1:
        return _unifiedTerminalTab();
      case 2:
        return _logcatTab();
      case 3:
        return _commandsTab();
      case 4:
        return _appsTab();
      case 5:
        return _filesTab();
      case 6:
        return _infoTab();
      default:
        return _dashboardTab();
    }
  }

  Widget _devicePanel() {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.phone_android),
            title: const Text('Device Panel'),
            subtitle: Text(_adb.currentState.name),
          ),
          const Divider(),
          Expanded(
            child: Column(
              children: [
                // Connection Status
                ListTile(
                  leading: Icon(
                    _adb.currentState == ADBConnectionState.connected
                        ? Icons.check_circle
                        : Icons.error,
                    color: _adb.currentState == ADBConnectionState.connected
                        ? Colors.green
                        : Colors.red,
                  ),
                  title: Text(_adb.currentState == ADBConnectionState.connected
                      ? 'Connected'
                      : 'Disconnected'),
                  subtitle: _adb.currentState == ADBConnectionState.connected
                      ? Text(_adb.connectedDeviceId)
                      : null,
                ),
                // Quick Actions
                if (_adb.currentState == ADBConnectionState.connected) ...[
                  const Divider(),
                  const ListTile(
                    leading: Icon(Icons.flash_on),
                    title: Text('Quick Actions'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.screenshot),
                    title: const Text('Screenshot'),
                    onTap: () async {
                      await _adb.executeCommand(
                          'shell screencap /sdcard/screenshot.png');
                      await _adb.executeCommand('pull /sdcard/screenshot.png');
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.info),
                    title: const Text('Device Info'),
                    onTap: () => setState(() => _selectedIndex = 6),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _unifiedTerminalTab() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: Theme.of(context).primaryColor.withOpacity(0.1),
            child: const TabBar(
              tabs: [
                Tab(icon: Icon(Icons.terminal), text: 'Shell'),
                Tab(icon: Icon(Icons.code), text: 'Commands'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _shellTerminalView(),
                _commandConsoleView(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _shellTerminalView() {
    return Column(
      children: [
        // Terminal output area
        Expanded(
          child: Container(
            color: Colors.black,
            padding: const EdgeInsets.all(8),
            child: StreamBuilder<String>(
              stream: _adb.backend is FlutterAdbBackend 
                  ? (_adb.backend as FlutterAdbBackend).client?.output
                  : _adb.output,
              builder: (context, snapshot) {
                // Use shell-specific buffer for flutter_adb
                final lines = _shellBufferSnapshot();
                
                // Auto-scroll to bottom when new content arrives
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_consoleScroll.hasClients) {
                    _consoleScroll.animateTo(
                      _consoleScroll.position.maxScrollExtent,
                      duration: const Duration(milliseconds: 100),
                      curve: Curves.easeOut,
                    );
                  }
                });
                
                return ListView.builder(
                  controller: _consoleScroll,
                  itemCount: lines.length,
                  itemBuilder: (_, i) => SelectableText(
                    lines[i],
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.green,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        // Terminal controls
        Container(
          color: Colors.grey[900],
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              // Input field
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _cmd,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        color: Colors.white,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        labelText: 'Shell Command',
                        labelStyle: TextStyle(color: Colors.grey),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.grey),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.blue),
                        ),
                      ),
                      onSubmitted: (value) => _executeShellCommand(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _executeShellCommand,
                    icon: const Icon(Icons.send),
                    label: const Text('Send'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Control buttons
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _openFlutterAdbShell,
                    icon: const Icon(Icons.power_settings_new),
                    label: Text(_isShellActive() ? 'Shell Active' : 'Open Shell'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isShellActive() ? Colors.orange : Colors.green
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _closeFlutterAdbShell,
                    icon: const Icon(Icons.power_off),
                    label: const Text('Close Shell'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _clearTerminal,
                    icon: const Icon(Icons.clear_all),
                    label: const Text('Clear'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _commandConsoleView() {
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<String>(
            stream: _adb.output,
            builder: (ctx, snap) {
              final lines = _bufferSnapshot();
              return ListView.builder(
                controller: _consoleScroll,
                itemCount: lines.length,
                itemBuilder: (_, i) => SelectableText(
                  lines[i],
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _cmd,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    labelText: 'ADB Command',
                  ),
                  onSubmitted: (value) => _executeAdbCommand(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _executeAdbCommand,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Run'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _executeShellCommand() async {
    final command = _cmd.text.trim();
    if (command.isEmpty) return;
    
    _cmd.clear();
    
    // Add command to shell buffer to show what was executed
    _addToShellBuffer('❯ $command');
    
    // Try flutter_adb shell first
    if (_adb.backend is FlutterAdbBackend) {
      final flutterAdbBackend = _adb.backend as FlutterAdbBackend;
      final client = flutterAdbBackend.client;
      if (client != null) {
        final success = await client.writeToShell('$command\n');
        if (!success) {
          _adb.addOutput('❌ Failed to send command to shell');
          _addToShellBuffer('❌ Failed to send command to shell');
        }
      } else {
        _adb.addOutput('❌ No connected flutter_adb client');
        _addToShellBuffer('❌ No connected flutter_adb client');
      }
    } else {
      // Fallback to regular command execution
      await _adb.executeCommand('shell $command');
    }
  }

  Future<void> _executeAdbCommand() async {
    final command = _cmd.text.trim();
    if (command.isEmpty) return;
    
    _cmd.clear();
    await _adb.executeCommand(command);
  }

  Future<void> _openFlutterAdbShell() async {
    if (_adb.backend is FlutterAdbBackend) {
      final flutterAdbBackend = _adb.backend as FlutterAdbBackend;
      final client = flutterAdbBackend.client;
      if (client != null) {
        // Start listening to shell output before opening shell
        _setupShellOutputListener(client);
        
        final success = await client.openShell();
        if (success) {
          _adb.addOutput('✅ Interactive shell opened via flutter_adb');
          _addToShellBuffer('🚀 Flutter ADB shell session started');
          _addToShellBuffer('💡 Type commands and press Enter to execute');
        } else {
          _adb.addOutput('❌ Failed to open shell - ensure device is connected');
        }
      } else {
        _adb.addOutput('❌ No connected flutter_adb client');
      }
    } else {
      _adb.addOutput('❌ Flutter ADB shell requires Flutter ADB backend');
      _adb.addOutput('💡 Switch to Flutter ADB backend in Info tab');
    }
  }

  void _setupShellOutputListener(FlutterAdbClient client) {
    // Cancel any existing subscription
    _shellOutputSub?.cancel();
    
    // Clear the shell buffer
    _shellOutputBuffer.clear();
    
    // Listen to dedicated shell output stream
    _shellOutputSub = client.shellOutput.listen((output) {
      _addToShellBuffer(output);
      // Trigger UI rebuild
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _addToShellBuffer(String line) {
    setState(() {
      // Split multi-line output
      final lines = line.split('\n');
      for (final l in lines) {
        if (l.trim().isNotEmpty) {
          _shellOutputBuffer.add(l);
        }
      }
      
      // Keep buffer size manageable (last 1000 lines)
      if (_shellOutputBuffer.length > 1000) {
        _shellOutputBuffer.removeRange(0, _shellOutputBuffer.length - 1000);
      }
    });
  }

  Future<void> _closeFlutterAdbShell() async {
    if (_adb.backend is FlutterAdbBackend) {
      final flutterAdbBackend = _adb.backend as FlutterAdbBackend;
      final client = flutterAdbBackend.client;
      if (client != null) {
        await client.closeShell();
        _adb.addOutput('⏹️ Interactive shell closed');
        _addToShellBuffer('🔚 Shell session ended');
      }
    }
    
    // Clean up shell output listener
    _shellOutputSub?.cancel();
    _shellOutputSub = null;
  }

  bool _isShellActive() {
    if (_adb.backend is FlutterAdbBackend) {
      final flutterAdbBackend = _adb.backend as FlutterAdbBackend;
      final client = flutterAdbBackend.client;
      return client != null && _shellOutputSub != null;
    }
    return false;
  }

  void _clearTerminal() {
    _adb.clearOutput();
    
    // Also clear shell buffer if using flutter_adb
    if (_adb.backend is FlutterAdbBackend) {
      setState(() {
        _shellOutputBuffer.clear();
        _addToShellBuffer('🧹 Terminal cleared');
      });
    }
  }

  // App Management Methods
  Future<String?> _executeShellCommandForOutput(String command) async {
    if (_adb.currentState != ADBConnectionState.connected) {
      _adb.addOutput('❌ Not connected to device');
      return null;
    }

    try {
      _adb.addOutput('🔍 Executing: $command');
      
      // Check if we have external backend available (like we see in executeCommand)
      if (_adb.backend != null && _adb.connectedDeviceId.isNotEmpty) {
        _adb.addOutput('📱 Device: ${_adb.connectedDeviceId}');
        final result = await _adb.backend!.shell(_adb.connectedDeviceId, command);
        _adb.addOutput('✅ Command result: ${result.length} characters');
        if (result.length > 100) {
          _adb.addOutput('📋 Preview: ${result.substring(0, 100)}...');
        } else {
          _adb.addOutput('📋 Full result: $result');
        }
        return result;
      } else {
        _adb.addOutput('❌ No backend (${_adb.backend != null ? "available" : "null"}) or device ID (${_adb.connectedDeviceId})');
        return null;
      }
    } catch (e) {
      _adb.addOutput('❌ Error executing command: $e');
      return null;
    }
  }

  Future<void> _loadInstalledApps() async {
    if (_adb.currentState != ADBConnectionState.connected) {
      _adb.addOutput('❌ Cannot load apps: Device not connected');
      return;
    }

    _adb.addOutput('🔄 Starting to load apps...');
    setState(() => _loadingApps = true);

    try {
      final allApps = <AppInfo>[];
      
      _adb.addOutput('📦 Getting user packages...');
      // Get list of user packages (3rd party)
      final userPackagesOutput = await _executeShellCommandForOutput('pm list packages -3');
      if (userPackagesOutput != null) {
        _adb.addOutput('📝 User packages output: ${userPackagesOutput.length} chars');
        for (final line in userPackagesOutput.split('\n')) {
          if (line.startsWith('package:')) {
            final packageName = line.substring(8).trim();
            if (packageName.isNotEmpty) {
              allApps.add(_createAppInfoFromPackageName(packageName, false));
            }
          }
        }
        _adb.addOutput('✅ Found ${allApps.length} user packages');
      } else {
        _adb.addOutput('❌ No user packages output received');
      }
      
      _adb.addOutput('⚙️ Getting system packages...');
      // Get list of system packages (limited to first 30 for performance)
      final systemPackagesOutput = await _executeShellCommandForOutput('pm list packages -s');
      if (systemPackagesOutput != null) {
        _adb.addOutput('📝 System packages output: ${systemPackagesOutput.length} chars');
        final systemLines = systemPackagesOutput.split('\n').where((line) => line.startsWith('package:')).take(30);
        for (final line in systemLines) {
          final packageName = line.substring(8).trim();
          if (packageName.isNotEmpty) {
            allApps.add(_createAppInfoFromPackageName(packageName, true));
          }
        }
        _adb.addOutput('✅ Found ${allApps.where((app) => app.isSystemApp).length} system packages');
      } else {
        _adb.addOutput('❌ No system packages output received');
      }

      setState(() {
        _installedApps = allApps.where((app) => !app.isSystemApp).toList();
        _systemApps = allApps.where((app) => app.isSystemApp).toList();
        _loadingApps = false;
      });
      
      _adb.addOutput('✅ Loaded ${allApps.length} apps (${_installedApps.length} user, ${_systemApps.length} system)');
    } catch (e) {
      setState(() => _loadingApps = false);
      _adb.addOutput('❌ Error loading apps: $e');
    }
  }

  AppInfo _createAppInfoFromPackageName(String packageName, bool isSystemApp) {
    // Create basic app info - detailed info loaded on-demand
    return AppInfo(
      packageName: packageName,
      label: packageName.split('.').last, // Use last part as label
      isSystemApp: isSystemApp,
      isEnabled: true, // Assume enabled by default
      version: 'Unknown',
      versionCode: '0',
      apkPath: '',
      size: 0,
    );
  }

  Future<AppInfo?> _getDetailedPackageInfo(String packageName) async {
    try {
      final output = await _executeShellCommandForOutput('dumpsys package $packageName');
      if (output == null) return null;
      
      final info = _parsePackageInfo(packageName, output);
      return info;
    } catch (e) {
      return null;
    }
  }

  AppInfo _parsePackageInfo(String packageName, String dumpsysOutput) {
    final lines = dumpsysOutput.split('\n');
    String label = packageName;
    bool isSystemApp = false;
    bool isEnabled = true;
    String version = 'Unknown';
    String versionCode = '0';
    String apkPath = '';
    int size = 0;

    for (final line in lines) {
      final trimmed = line.trim();
      
      if (trimmed.startsWith('versionName=')) {
        version = trimmed.substring(12);
      } else if (trimmed.startsWith('versionCode=')) {
        versionCode = trimmed.substring(12).split(' ')[0];
      } else if (trimmed.startsWith('codePath=')) {
        apkPath = trimmed.substring(9);
        if (apkPath.contains('/system/')) {
          isSystemApp = true;
        }
      } else if (trimmed.contains('SYSTEM')) {
        isSystemApp = true;
      } else if (trimmed.contains('enabled=')) {
        isEnabled = !trimmed.contains('enabled=false');
      }
    }

    return AppInfo(
      packageName: packageName,
      label: label,
      isSystemApp: isSystemApp,
      isEnabled: isEnabled,
      version: version,
      versionCode: versionCode,
      apkPath: apkPath,
      size: size,
    );
  }

  Future<void> _uninstallApp(String packageName) async {
    try {
      await _adb.executeCommand('shell pm uninstall $packageName');
      _adb.addOutput('✅ Uninstalled $packageName');
      _loadInstalledApps(); // Refresh list
    } catch (e) {
      _adb.addOutput('❌ Failed to uninstall $packageName: $e');
    }
  }

  Future<void> _enableDisableApp(String packageName, bool enable) async {
    try {
      final command = enable ? 'enable' : 'disable-user';
      await _adb.executeCommand('shell pm $command $packageName');
      _adb.addOutput('✅ ${enable ? 'Enabled' : 'Disabled'} $packageName');
      _loadInstalledApps(); // Refresh list
    } catch (e) {
      _adb.addOutput('❌ Failed to ${enable ? 'enable' : 'disable'} $packageName: $e');
    }
  }

  Future<void> _clearAppData(String packageName) async {
    try {
      await _adb.executeCommand('shell pm clear $packageName');
      _adb.addOutput('✅ Cleared data for $packageName');
    } catch (e) {
      _adb.addOutput('❌ Failed to clear data for $packageName: $e');
    }
  }

  // Dashboard (connection + saved devices + quick actions)
  Widget _dashboardTab() {
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth > 950;
      final left = _connectionCard();
      return Padding(
        padding: const EdgeInsets.all(12),
        child: wide
            ? Row(children: [
                Expanded(child: left),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(children: [
                    _currentDeviceCard(),
                    const SizedBox(height: 8),
                    _quickActionsCard(),
                    const SizedBox(height: 8),
                    Expanded(
                        child: _savedDevicesWidget(scrollableParent: false)),
                  ]),
                )
              ])
            : SingleChildScrollView(
                child: Column(children: [
                  left,
                  const SizedBox(height: 12),
                  _currentDeviceCard(),
                  const SizedBox(height: 8),
                  _quickActionsCard(),
                  const SizedBox(height: 8),
                  _savedDevicesWidget(scrollableParent: true),
                ]),
              ),
      );
    });
  }

  Card _connectionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.cable, size: 18),
              const SizedBox(width: 6),
              const Text('Connection',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text(_adb.currentState.name,
                  style: TextStyle(
                      color: _stateColor(_adb.currentState), fontSize: 12)),
            ]),
            const SizedBox(height: 12),
            // Discovery rows
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: _mdnsScanning
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.wifi_tethering),
                  label: Text(
                      _mdnsScanning ? 'Scanning mDNS...' : 'Discover Wi‑Fi'),
                  onPressed: _mdnsScanning ? null : _runMdnsScan,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.usb),
                  label: const Text('Refresh USB'),
                  onPressed: _refreshUsb,
                ),
              )
            ]),
            if (_mdnsServices.isNotEmpty) ...[
              const SizedBox(height: 8),
              _mdnsListWidget(),
            ],
            if (_usbDevices.isNotEmpty) ...[
              const SizedBox(height: 8),
              _usbListWidget(),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<ADBConnectionType>(
              value: _connectionType,
              items: ADBConnectionType.values
                  .map((t) =>
                      DropdownMenuItem(value: t, child: Text(t.displayName)))
                  .toList(),
              onChanged: (v) =>
                  setState(() => _connectionType = v ?? ADBConnectionType.wifi),
              decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  labelText: 'Type'),
            ),
            const SizedBox(height: 12),
            if (_connectionType != ADBConnectionType.usb)
              Row(children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _host,
                    decoration: const InputDecoration(
                        labelText: 'Host / IP',
                        border: OutlineInputBorder(),
                        isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                if (_connectionType != ADBConnectionType.pairing)
                  SizedBox(
                    width: 100,
                    child: TextField(
                      controller: _port,
                      decoration: const InputDecoration(
                          labelText: 'Port',
                          border: OutlineInputBorder(),
                          isDense: true),
                      keyboardType: TextInputType.number,
                    ),
                  ),
              ]),
            if (_connectionType == ADBConnectionType.pairing) ...[
              const SizedBox(height: 8),
              Row(children: [
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _pairingPort,
                    decoration: const InputDecoration(
                        labelText: 'Pair Port',
                        border: OutlineInputBorder(),
                        isDense: true),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _pairingCode,
                    decoration: const InputDecoration(
                        labelText: 'Pair Code',
                        border: OutlineInputBorder(),
                        isDense: true),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              const Text('Enable Wireless debugging > Pair device with code',
                  style: TextStyle(fontSize: 11)),
            ],
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: _loadingConnect
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(_connectionType == ADBConnectionType.pairing
                          ? Icons.link
                          : Icons.wifi),
                  label: Text(_loadingConnect
                      ? (_connectionType == ADBConnectionType.pairing
                          ? 'Pairing...'
                          : 'Connecting...')
                      : (_connectionType == ADBConnectionType.pairing
                          ? 'Pair'
                          : 'Connect')),
                  onPressed: _loadingConnect
                      ? null
                      : () async {
                          setState(() => _loadingConnect = true);
                          bool ok = false;
                          switch (_connectionType) {
                            case ADBConnectionType.wifi:
                            case ADBConnectionType.custom:
                              ok = await _adb.connectWifi(_host.text.trim(),
                                  int.tryParse(_port.text) ?? 5555);
                              break;
                            case ADBConnectionType.usb:
                              ok = await _adb.connectUSB();
                              break;
                            case ADBConnectionType.pairing:
                              await _adb.pairDevice(
                                  _host.text.trim(),
                                  int.tryParse(_pairingPort.text) ?? 37205,
                                  _pairingCode.text.trim(),
                                  int.tryParse(_port.text) ?? 5555);
                              ok = true;
                              break;
                          }
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(ok ? 'Success' : 'Failed'),
                                backgroundColor:
                                    ok ? Colors.green : Colors.red));
                          }
                          setState(() => _loadingConnect = false);
                        },
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                icon: const Icon(Icons.link_off),
                label: const Text('Disconnect'),
                onPressed: _adb.currentState == ADBConnectionState.connected
                    ? () async {
                        await _adb.disconnect();
                        setState(() {});
                      }
                    : null,
              )
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: OutlinedButton.icon(
                      icon: const Icon(Icons.save),
                      label: const Text('Save Device'),
                      onPressed: _saveDevice)),
              const SizedBox(width: 8),
              Expanded(
                  child: OutlinedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh Devices'),
                      onPressed: () async {
                        await _adb.refreshBackendDevices();
                        setState(() {});
                      })),
            ])
          ],
        ),
      ),
    );
  }

  Future<void> _runMdnsScan() async {
    setState(() {
      _mdnsScanning = true;
    });
    try {
      await _mdns.scanOnce();
      final results = _mdns.currentCache();
      setState(() {
        _mdnsServices = results;
        _lastMdnsScan = DateTime.now();
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'mdns_cache', jsonEncode(results.map((e) => e.toJson()).toList()));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('mDNS error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _mdnsScanning = false;
        });
      }
    }
  }

  Widget _mdnsListWidget() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.wifi, size: 16),
        const SizedBox(width: 4),
        const Text('Discovered Wi‑Fi Devices',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const Spacer(),
        if (_lastMdnsScan != null)
          Text(_timeAgo(_lastMdnsScan!), style: const TextStyle(fontSize: 10))
      ]),
      const SizedBox(height: 4),
      SizedBox(
        height: 120,
        child: ListView.builder(
          itemCount: _mdnsServices.length,
          itemBuilder: (c, i) {
            final s = _mdnsServices[i];
            final host = s.ip ?? s.ipv6 ?? s.host;
            final statusIcon = s.reachable == null
                ? const Icon(Icons.help_outline, size: 14, color: Colors.grey)
                : s.reachable == true
                    ? const Icon(Icons.check_circle,
                        size: 14, color: Colors.green)
                    : const Icon(Icons.error,
                        size: 14, color: Colors.redAccent);
            return ListTile(
              dense: true,
              leading: statusIcon,
              title: Text('$host:${s.port}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13)),
              subtitle: Text(
                [
                  if (s.txt['device'] != null) s.txt['device']!,
                  if (s.ip != null) 'v4:${s.ip}',
                  if (s.ipv6 != null) 'v6:${s.ipv6}'
                ].join(' • '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10),
              ),
              trailing: IconButton(
                  icon: const Icon(Icons.play_arrow, size: 18),
                  onPressed: () {
                    _host.text = host;
                    _port.text = s.port.toString();
                    setState(() => _connectionType = ADBConnectionType.wifi);
                  }),
            );
          },
        ),
      ),
    ]);
  }

  Future<void> _refreshUsb() async {
    try {
      final list = await UsbBridge.listDevices();
      setState(() => _usbDevices = list);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('USB error: $e')));
      }
    }
  }

  void _startUsbEvents() async {
    // Platform side handles events over EventChannel name adb_usb_events
    const events = EventChannel('adb_usb_events');
    _usbEventsSub = events.receiveBroadcastStream().listen((event) async {
      if (event is Map) {
        final devices = (event['devices'] as List?) ?? [];
        final parsed = devices.map((d) {
          final m = Map<String, dynamic>.from(d as Map);
          return UsbDeviceInfo(
            deviceId: (m['deviceId'] as int?) ?? -1,
            vendorId: (m['vendorId'] as int?) ?? 0,
            productId: (m['productId'] as int?) ?? 0,
            serial: m['serial'] as String?,
            name: m['name'] as String? ?? '',
            hasPermission: (m['hasPermission'] as bool?) ?? false,
          );
        }).toList();
        setState(() => _usbDevices = parsed);
      }
    });
    // initial manual load
    await _refreshUsb();
  }

  Widget _usbListWidget() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.usb, size: 16),
        const SizedBox(width: 4),
        const Text('USB Devices', style: TextStyle(fontWeight: FontWeight.bold))
      ]),
      const SizedBox(height: 4),
      SizedBox(
        height: 110,
        child: ListView.builder(
          itemCount: _usbDevices.length,
          itemBuilder: (c, i) {
            final d = _usbDevices[i];
            return ListTile(
              dense: true,
              leading: Icon(d.hasPermission ? Icons.usb : Icons.usb_off,
                  size: 16,
                  color: d.hasPermission ? Colors.green : Colors.orange),
              title: Text(d.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13)),
              subtitle: Text(d.serial ?? 'VID:${d.vendorId} PID:${d.productId}',
                  style: const TextStyle(fontSize: 11)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (!d.hasPermission)
                  IconButton(
                      icon: const Icon(Icons.lock_open, size: 18),
                      onPressed: () async {
                        final ok =
                            await UsbBridge.requestPermission(d.deviceId);
                        if (ok) _refreshUsb();
                      }),
                IconButton(
                    icon: const Icon(Icons.play_arrow, size: 18),
                    onPressed: () {
                      setState(() => _connectionType = ADBConnectionType.usb);
                    })
              ]),
              onTap: () {
                setState(() => _connectionType = ADBConnectionType.usb);
              },
            );
          },
        ),
      ),
    ]);
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  Card _currentDeviceCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Icon(Icons.phone_android, color: _stateColor(_adb.currentState)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Text('State: ${_adb.currentState.name}')]),
            ),
          ]),
        ),
      );

  Card _quickActionsCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Quick Actions',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _qa('Console', Icons.terminal,
                  () => setState(() => _selectedIndex = 1)),
              _qa('Start Logcat', Icons.play_arrow, () async {
                if (!_adb.logcatActive) {
                  await _adb.startLogcat();
                  setState(() => _selectedIndex = 3);
                }
              }, enabled: !_adb.logcatActive),
              _qa('Stop Logcat', Icons.stop, () async {
                await _adb.stopLogcat();
                setState(() {});
              }, enabled: _adb.logcatActive),
              _qa('Files', Icons.folder_copy,
                  () => setState(() => _selectedIndex = 5)),
              _qa('Info', Icons.info_outline,
                  () => setState(() => _selectedIndex = 6)),
              _qa('Key Status', Icons.vpn_key, () async {
                await _adb.showCredentialStatus();
                setState(() => _selectedIndex = 1); // Switch to terminal to see output
              }),
              _qa('Clear Keys', Icons.delete_forever, () async {
                // Show confirmation dialog
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Clear RSA Keys'),
                    content: const Text(
                      'This will clear all saved RSA keys and device authorization history. '
                      'You will need to re-authorize this app on all devices.\n\n'
                      'Continue?'
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                );
                
                if (confirmed == true) {
                  await _adb.clearSavedCredentials();
                  setState(() => _selectedIndex = 1); // Switch to terminal to see output
                }
              }),
            ])
          ]),
        ),
      );

  Widget _savedDevicesWidget({required bool scrollableParent}) {
    if (_savedDevices.isEmpty) {
      return const Card(
          child: Padding(
              padding: EdgeInsets.all(12), child: Text('No saved devices')));
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Saved Devices',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (scrollableParent)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: _savedDevicesList(shrinkWrap: true),
            )
          else
            Expanded(child: _savedDevicesList()),
        ]),
      ),
    );
  }

  Widget _savedDevicesList({bool shrinkWrap = false}) => ListView.builder(
        shrinkWrap: shrinkWrap,
        physics: shrinkWrap ? const ClampingScrollPhysics() : null,
        itemCount: _savedDevices.length,
        itemBuilder: (c, i) {
          final d = _savedDevices[i];
          return ListTile(
            selected: _selectedSaved?.name == d.name,
            leading: const Icon(Icons.memory),
            title: Text(d.name, overflow: TextOverflow.ellipsis),
            subtitle: Text(d.connectionType.displayName, maxLines: 1),
            onTap: () => _loadDevice(d),
            trailing: IconButton(
                icon: const Icon(Icons.delete, size: 18),
                onPressed: () async {
                  _savedDevices.removeAt(i);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setStringList(
                      'adb_devices',
                      _savedDevices
                          .map((d) => jsonEncode(d.toJson()))
                          .toList());
                  setState(() {});
                }),
          );
        },
      );

  Widget _qa(String label, IconData icon, VoidCallback onTap,
          {bool enabled = true}) =>
      SizedBox(
        height: 36,
        child: ElevatedButton.icon(
            onPressed: enabled ? onTap : null,
            icon: Icon(icon, size: 16),
            label: Text(label)),
      );

  Widget _logcatTab() {
    return Column(children: [
      Expanded(
        child: Container(
          color: Colors.black,
          child: StreamBuilder<String>(
            stream: _adb.logcatStream,
            builder: (c, s) {
              final buffer = _adb.logcatBuffer;
              if (_logcatLinesShown != buffer.length) {
                _logcatLinesShown = buffer.length;
                // Auto-scroll to bottom when new content arrives
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_logcatScrollController.hasClients) {
                    _logcatScrollController.animateTo(
                      _logcatScrollController.position.maxScrollExtent,
                      duration: const Duration(milliseconds: 100),
                      curve: Curves.easeOut,
                    );
                  }
                });
              }
              if (buffer.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _adb.logcatActive ? Icons.hourglass_empty : Icons.play_circle_outline,
                        size: 48,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _adb.logcatActive 
                          ? 'Logcat is running but no output yet...\nCheck if device is generating logs'
                          : 'No logcat data\nTap "Start Logcat" to begin',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Debug Info:',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Connection: ${_adb.currentState.name}\n'
                        'Device: ${_adb.connectedDeviceId.isEmpty ? "None" : _adb.connectedDeviceId}\n'
                        'Logcat Active: ${_adb.logcatActive ? "Yes" : "No"}',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[600], fontSize: 11, fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                );
              }
              
              return ListView.builder(
                controller: _logcatScrollController,
                padding: const EdgeInsets.all(4),
                itemCount: buffer.length,
                itemBuilder: (ctx, i) {
                  final line = buffer[i];
                  
                  // Apply text filter
                  if (_activeLogcatFilter.isNotEmpty &&
                      !line
                          .toLowerCase()
                          .contains(_activeLogcatFilter.toLowerCase())) {
                    return const SizedBox.shrink();
                  }
                  
                  // Apply level filter
                  if (_logcatLevel != 'All') {
                    final levelChar = _logcatLevel[0]; // E, W, I, D, V
                    if (!line.contains(' $levelChar ')) {
                      return const SizedBox.shrink();
                    }
                  }
                  
                  Color color = Colors.white;
                  if (line.contains(' E ')) {
                    color = Colors.redAccent;
                  } else if (line.contains(' W '))
                    color = Colors.orangeAccent;
                  else if (line.contains(' I ')) color = Colors.lightBlueAccent;
                  else if (line.contains(' D ')) color = Colors.grey[300]!;
                  else if (line.contains(' V ')) color = Colors.grey[500]!;
                  
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: SelectableText(line,
                        style: TextStyle(
                            color: color, fontSize: 11, fontFamily: 'monospace')),
                  );
                },
              );
            },
          ),
        ),
      ),
      Container(
        color: Colors.grey[200],
        padding: const EdgeInsets.all(6),
        child: Row(children: [
          ElevatedButton.icon(
              onPressed: _adb.logcatActive
                  ? null
                  : () async {
                      await _adb.startLogcat();
                      setState(() {});
                    },
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start')),
          const SizedBox(width: 6),
          ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: _adb.logcatActive
                  ? () async {
                      await _adb.stopLogcat();
                      setState(() {});
                    }
                  : null,
              icon: const Icon(Icons.stop),
              label: const Text('Stop')),
          const SizedBox(width: 6),
          ElevatedButton.icon(
              onPressed: () {
                _adb.clearLogcat();
                setState(() {});
              },
              icon: const Icon(Icons.cleaning_services),
              label: const Text('Clear')),
          const SizedBox(width: 6),
          ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              onPressed: () async {
                await _adb.executeCommand('devices');
              },
              icon: const Icon(Icons.bug_report),
              label: const Text('Test ADB')),
          const SizedBox(width: 12),
          Text('Level:', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
          const SizedBox(width: 4),
          DropdownButton<String>(
            value: _logcatLevel,
            isDense: true,
            items: ['All', 'Error', 'Warning', 'Info', 'Debug', 'Verbose']
                .map((level) => DropdownMenuItem(value: level, child: Text(level, style: const TextStyle(fontSize: 12))))
                .toList(),
            onChanged: (value) {
              setState(() => _logcatLevel = value!);
            },
          ),
          const SizedBox(width: 12),
          Expanded(
              child: TextField(
            controller: _logcatFilter,
            decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                hintText: 'Filter...',
                suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: () => setState(() =>
                        _activeLogcatFilter = _logcatFilter.text.trim()))),
            onSubmitted: (_) =>
                setState(() => _activeLogcatFilter = _logcatFilter.text.trim()),
          )),
          if (_activeLogcatFilter.isNotEmpty)
            IconButton(
                onPressed: () {
                  _logcatFilter.clear();
                  setState(() => _activeLogcatFilter = '');
                },
                icon: const Icon(Icons.close)),
          const SizedBox(width: 8),
          Text('${_adb.logcatBuffer.length} lines',
              style: const TextStyle(fontSize: 12))
        ]),
      ),
      // Second row with settings
      Container(
        color: Colors.grey[100],
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(children: [
          Icon(Icons.settings, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text('Auto-start on connect:', 
              style: TextStyle(fontSize: 12, color: Colors.grey[700])),
          const SizedBox(width: 8),
          Switch(
            value: _autoStartLogcat,
            onChanged: (value) async {
              setState(() => _autoStartLogcat = value);
              await _saveAutoLogcatPreference();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_autoStartLogcat 
                      ? 'Logcat will auto-start on connection' 
                      : 'Logcat auto-start disabled'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
          const Spacer(),
          if (_adb.logcatActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('ACTIVE', 
                  style: TextStyle(color: Colors.white, fontSize: 10)),
            ),
        ]),
      ),
      // Third row with quick filters
      Container(
        color: Colors.grey[50],
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(children: [
          Text('Quick filters:', 
              style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          const SizedBox(width: 8),
          _quickFilterButton('Errors', 'Error', Colors.red[100]!),
          const SizedBox(width: 4),
          _quickFilterButton('Warnings', 'Warning', Colors.orange[100]!),
          const SizedBox(width: 4),
          _quickFilterButton('All', 'All', Colors.grey[200]!),
          const Spacer(),
          if (_activeLogcatFilter.isNotEmpty || _logcatLevel != 'All')
            TextButton(
              onPressed: () {
                setState(() {
                  _activeLogcatFilter = '';
                  _logcatLevel = 'All';
                  _logcatFilter.clear();
                });
              },
              child: const Text('Clear Filters', style: TextStyle(fontSize: 11)),
            ),
        ]),
      )
    ]);
  }

  Widget _quickFilterButton(String label, String level, Color color) {
    final isSelected = _logcatLevel == level;
    return GestureDetector(
      onTap: () {
        setState(() => _logcatLevel = level);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.transparent,
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.black87 : Colors.grey[600],
          ),
        ),
      ),
    );
  }

  Widget _commandsTab() => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Connection Status Card
          Card(
            color: _adb.currentState == ADBConnectionState.connected 
                ? Colors.green.withOpacity(0.1)
                : Colors.red.withOpacity(0.1),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    _adb.currentState == ADBConnectionState.connected 
                        ? Icons.check_circle 
                        : Icons.error,
                    color: _adb.currentState == ADBConnectionState.connected 
                        ? Colors.green 
                        : Colors.red,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _adb.currentState == ADBConnectionState.connected 
                              ? 'Device Connected' 
                              : 'No Device Connected',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        if (_adb.currentState == ADBConnectionState.connected)
                          Text('Device: ${_adb.connectedDeviceId}', 
                               style: const TextStyle(fontSize: 12))
                        else
                          const Text('Connect a device to run commands', 
                                   style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Quick Commands',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...ADBCommands.commandCategories.entries.map((e) => ExpansionTile(
                title: Text(e.key,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                children: e.value
                    .map((cmd) => ListTile(
                          title: Text(cmd,
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 12)),
                          subtitle:
                              Text(ADBCommands.getCommandDescription(cmd)),
                          trailing: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ElevatedButton.icon(
                                onPressed: _adb.currentState ==
                                        ADBConnectionState.connected
                                    ? () async {
                                        print('🔄 Executing quick command: $cmd');
                                        _adb.addOutput('🚀 Quick command: $cmd');
                                        try {
                                          await _adb.executeCommand(cmd);
                                          _adb.addOutput('✅ Command completed: $cmd');
                                        } catch (e) {
                                          _adb.addOutput('❌ Command failed: $cmd - Error: $e');
                                        }
                                      }
                                    : null,
                                icon: Icon(_adb.currentState == ADBConnectionState.connected 
                                    ? Icons.play_arrow 
                                    : Icons.error),
                                label: Text(_adb.currentState == ADBConnectionState.connected 
                                    ? 'Run' 
                                    : 'No Device'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _adb.currentState == ADBConnectionState.connected 
                                      ? Colors.green 
                                      : Colors.grey,
                                ),
                              ),
                              if (_adb.currentState != ADBConnectionState.connected)
                                const Text(
                                  'Connect device first',
                                  style: TextStyle(fontSize: 10, color: Colors.grey),
                                ),
                            ],
                          ),
                          onTap: () {
                            _cmd.text = cmd;
                            setState(() => _selectedIndex = 1);
                          },
                        ))
                    .toList(),
              ))
        ],
      );

  Widget _filesTab() => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sectionTitle('Install APK', Icons.install_mobile),
          Row(children: [
            Expanded(
                child: TextField(
                    controller: _apkPath,
                    decoration: const InputDecoration(
                        labelText: 'APK Path',
                        border: OutlineInputBorder(),
                        isDense: true))),
            const SizedBox(width: 8),
            ElevatedButton(
                onPressed: _adb.currentState == ADBConnectionState.connected
                    ? () async {
                        final ok = await _adb.installApk(_apkPath.text.trim());
                        if (_apkPath.text.isNotEmpty) {
                          _recentApk.remove(_apkPath.text.trim());
                          _recentApk.insert(0, _apkPath.text.trim());
                          _persistRecents();
                        }
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(ok ? 'Installed' : 'Failed')));
                        }
                      }
                    : null,
                child: const Text('Install'))
          ]),
          _recentChips(_recentApk, (v) => _apkPath.text = v),
          const SizedBox(height: 16),
          _sectionTitle('Push File', Icons.upload_file),
          Row(children: [
            Expanded(
                child: TextField(
                    controller: _pushLocal,
                    decoration: const InputDecoration(
                        labelText: 'Local Path',
                        border: OutlineInputBorder(),
                        isDense: true))),
            const SizedBox(width: 8),
            Expanded(
                child: TextField(
                    controller: _pushRemote,
                    decoration: const InputDecoration(
                        labelText: 'Remote Path',
                        border: OutlineInputBorder(),
                        isDense: true))),
            const SizedBox(width: 8),
            ElevatedButton(
                onPressed: _adb.currentState == ADBConnectionState.connected
                    ? () async {
                        final ok = await _adb.pushFile(
                            _pushLocal.text.trim(), _pushRemote.text.trim());
                        if (_pushLocal.text.isNotEmpty) {
                          _recentLocal.remove(_pushLocal.text.trim());
                          _recentLocal.insert(0, _pushLocal.text.trim());
                        }
                        if (_pushRemote.text.isNotEmpty) {
                          _recentRemote.remove(_pushRemote.text.trim());
                          _recentRemote.insert(0, _pushRemote.text.trim());
                        }
                        _persistRecents();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(ok ? 'Pushed' : 'Failed')));
                        }
                      }
                    : null,
                child: const Text('Push'))
          ]),
          _recentChips(_recentLocal, (v) => _pushLocal.text = v,
              label: 'Recent Local'),
          _recentChips(_recentRemote, (v) => _pushRemote.text = v,
              label: 'Recent Remote'),
          const SizedBox(height: 16),
          _sectionTitle('Pull File', Icons.download),
          Row(children: [
            Expanded(
                child: TextField(
                    controller: _pullRemote,
                    decoration: const InputDecoration(
                        labelText: 'Remote Path',
                        border: OutlineInputBorder(),
                        isDense: true))),
            const SizedBox(width: 8),
            Expanded(
                child: TextField(
                    controller: _pullLocal,
                    decoration: const InputDecoration(
                        labelText: 'Local Path',
                        border: OutlineInputBorder(),
                        isDense: true))),
            const SizedBox(width: 8),
            ElevatedButton(
                onPressed: _adb.currentState == ADBConnectionState.connected
                    ? () async {
                        final ok = await _adb.pullFile(
                            _pullRemote.text.trim(), _pullLocal.text.trim());
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(ok ? 'Pulled' : 'Failed')));
                        }
                      }
                    : null,
                child: const Text('Pull'))
          ]),
          const SizedBox(height: 16),
          _sectionTitle('Port Forward', Icons.cable),
          Row(children: [
            SizedBox(
                width: 100,
                child: TextField(
                    controller: _forwardLocalPort,
                    decoration: const InputDecoration(
                        labelText: 'Local',
                        border: OutlineInputBorder(),
                        isDense: true),
                    keyboardType: TextInputType.number)),
            const SizedBox(width: 8),
            Expanded(
                child: TextField(
                    controller: _forwardRemoteSpec,
                    decoration: const InputDecoration(
                        labelText: 'Remote Spec',
                        border: OutlineInputBorder(),
                        isDense: true))),
            const SizedBox(width: 8),
            ElevatedButton(
                onPressed: _adb.currentState == ADBConnectionState.connected
                    ? () async {
                        final lp = int.tryParse(_forwardLocalPort.text) ?? 0;
                        final ok = await _adb.forwardPort(
                            lp, _forwardRemoteSpec.text.trim());
                        if (ok) {
                          final fr =
                              '${_forwardLocalPort.text}:${_forwardRemoteSpec.text}';
                          _recentForwards.remove(fr);
                          _recentForwards.insert(0, fr);
                          _persistRecents();
                        }
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(ok ? 'Forward Added' : 'Failed')));
                        }
                      }
                    : null,
                child: const Text('Add')),
            const SizedBox(width: 4),
            ElevatedButton(
                onPressed: _adb.currentState == ADBConnectionState.connected
                    ? () async {
                        final lp = int.tryParse(_forwardLocalPort.text) ?? 0;
                        final ok = await _adb.removeForward(lp);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(ok ? 'Removed' : 'Failed')));
                        }
                      }
                    : null,
                child: const Text('Remove'))
          ]),
          _recentChips(_recentForwards, (v) {
            final parts = v.split(':');
            if (parts.length >= 2) {
              _forwardLocalPort.text = parts[0];
              _forwardRemoteSpec.text = parts.sublist(1).join(':');
            }
          }, label: 'Recent Forwards'),
        ]),
      );

  Widget _recentChips(List<String> items, ValueChanged<String> onTap,
      {String? label}) {
    if (items.isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (label != null)
          Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.bold))),
        Wrap(
            spacing: 6,
            runSpacing: 6,
            children: items
                .map((p) => ActionChip(
                    label: Text(p.split('/').last,
                        overflow: TextOverflow.ellipsis),
                    onPressed: () => onTap(p)))
                .toList())
      ]),
    );
  }

  Widget _sectionTitle(String title, IconData icon) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold))
        ]),
      );

  Widget _infoTab() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Backend Selection Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ADB Backend', 
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    const Text('Choose the ADB backend for your platform:', 
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () async {
                            await _adb.enableFlutterAdbBackend();
                          },
                          icon: const Icon(Icons.android, size: 16),
                          label: const Text('Flutter ADB', style: TextStyle(fontSize: 12)),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                        ),
                        ElevatedButton.icon(
                          onPressed: () async {
                            await _adb.enableExternalAdbBackend();
                          },
                          icon: const Icon(Icons.computer, size: 16),
                          label: const Text('System ADB', style: TextStyle(fontSize: 12)),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                        ),
                        ElevatedButton.icon(
                          onPressed: () async {
                            await _adb.enableInternalAdbBackend();
                          },
                          icon: const Icon(Icons.bug_report, size: 16),
                          label: const Text('Mock ADB', style: TextStyle(fontSize: 12)),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '• Flutter ADB: Native on Android, no system dependencies\n'
                      '• System ADB: Requires adb command in PATH\n'
                      '• Mock ADB: For testing without real devices',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Auto-Connect Settings Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Auto-Connect Settings', 
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    ListTile(
                      leading: const Icon(Icons.auto_awesome, color: Colors.orange),
                      title: const Text('Auto-start Logcat on connect'),
                      subtitle: const Text('Automatically start logcat when device connects'),
                      trailing: Switch(
                        value: _autoStartLogcat,
                        onChanged: (value) async {
                          setState(() => _autoStartLogcat = value);
                          await _saveAutoLogcatPreference();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(_autoStartLogcat 
                                  ? 'Logcat will auto-start on connection' 
                                  : 'Logcat auto-start disabled'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.terminal, color: Colors.blue),
                      title: const Text('Auto-open Shell on connect'),
                      subtitle: const Text('Automatically open shell for Flutter ADB backend'),
                      trailing: Switch(
                        value: _autoOpenShell,
                        onChanged: (value) async {
                          setState(() => _autoOpenShell = value);
                          await _saveAutoShellPreference();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(_autoOpenShell 
                                  ? 'Shell will auto-open on Flutter ADB connection' 
                                  : 'Shell auto-open disabled'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Help sections - define sections here
            ..._getHelpSections().map((section) => _helpSection(section.$1, section.$2, section.$3)),
          ],
        ),
      ),
    );
  }

  List<(String, IconData, List<String>)> _getHelpSections() {
    return [
      (
        'ADB Server Setup',
        Icons.settings_system_daydream,
        [
          'Install Platform Tools & add to PATH',
          'adb start-server',
          'Check devices: adb devices'
        ]
      ),
      (
        'Wireless Debugging',
        Icons.wifi,
        [
          'Enable Developer Options',
          'Enable Wireless debugging',
          'Pair with code (Android 11+)',
          'Connect via IP:5555'
        ]
      ),
      (
        'USB Debugging',
        Icons.usb,
        [
          'Enable USB debugging on device',
          'Connect cable & authorize',
          'adb devices should list device'
        ]
      ),
      (
        'Tips',
        Icons.info_outline,
        [
          'Use verbose mode for timestamps',
          'Interactive shell for multi-line tasks',
          'Forward ports for local web debugging'
        ]
      )
    ];
  }

  Widget _helpSection(String title, IconData icon, List<String> steps) {
    return Card(
      child: ExpansionTile(
        leading: Icon(icon, color: Theme.of(context).primaryColor),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: steps.map((step) => 
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Expanded(child: Text(step, style: const TextStyle(fontSize: 14))),
                    ],
                  ),
                )
              ).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Color _stateColor(ADBConnectionState s) {
    switch (s) {
      case ADBConnectionState.connected:
        return Colors.green;
      case ADBConnectionState.connecting:
        return Colors.orange;
      case ADBConnectionState.failed:
        return Colors.red;
      case ADBConnectionState.disconnected:
        return Colors.grey;
    }
  }

  // Apps Tab - Enhanced App Management
  Widget _appsTab() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with load and search controls
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
              ElevatedButton.icon(
                onPressed: _adb.currentState == ADBConnectionState.connected && !_loadingApps
                    ? _loadInstalledApps
                    : null,
                icon: _loadingApps 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
                label: Text(_loadingApps ? 'Loading...' : 'Load Apps'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              ),
              const SizedBox(width: 8),
              // Apps Manager button
              ElevatedButton.icon(
                onPressed: _adb.currentState == ADBConnectionState.connected
                    ? () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const AppsScreen(),
                          ),
                        );
                      }
                    : null,
                icon: const Icon(Icons.apps_outlined),
                label: const Text('Apps Manager'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              ),
              const SizedBox(width: 8),
              // Debug button to test shell execution
              ElevatedButton.icon(
                onPressed: _adb.currentState == ADBConnectionState.connected
                    ? () async {
                        _adb.addOutput('🧪 Testing shell command execution...');
                        final testResult = await _executeShellCommandForOutput('echo "Hello from device"');
                        _adb.addOutput('🧪 Test result: ${testResult ?? "null"}');
                      }
                    : null,
                icon: const Icon(Icons.bug_report, size: 16),
                label: const Text('Debug'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 250,
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search apps...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onChanged: (value) => setState(() => _appSearchQuery = value),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _adb.currentState == ADBConnectionState.connected
                    ? _loadSystemInfo
                    : null,
                icon: const Icon(Icons.info, size: 16),
                label: const Text('System Info'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              ),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: _selectedAppFilter,
                items: const [
                  DropdownMenuItem(value: 'All', child: Text('All Apps')),
                  DropdownMenuItem(value: 'User', child: Text('User Apps')),
                  DropdownMenuItem(value: 'System', child: Text('System Apps')),
                  DropdownMenuItem(value: 'Enabled', child: Text('Enabled')),
                  DropdownMenuItem(value: 'Disabled', child: Text('Disabled')),
                ],
                onChanged: (value) => setState(() => _selectedAppFilter = value!),
              ),
            ],
            ),
          ),
          const SizedBox(height: 16),
          
          // Connection status and stats
          if (_adb.currentState != ADBConnectionState.connected)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                border: Border.all(color: Colors.orange.shade200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning, color: Colors.orange),
                  SizedBox(width: 12),
                  Text('Connect to a device to manage apps', 
                      style: TextStyle(color: Colors.orange)),
                ],
              ),
            )
          else ...[
            // App statistics
            Row(
              children: [
                _buildAppStatCard('User Apps', _installedApps.length, Colors.blue),
                const SizedBox(width: 12),
                _buildAppStatCard('System Apps', _systemApps.length, Colors.green),
                const SizedBox(width: 12),
                _buildAppStatCard('Total', _installedApps.length + _systemApps.length, Colors.purple),
              ],
            ),
            const SizedBox(height: 16),
            
            // App list
            Expanded(
              child: _buildAppList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAppStatCard(String title, int count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          border: Border.all(color: color.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(count.toString(), 
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
            Text(title, style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildAppList() {
    final allApps = [..._installedApps, ..._systemApps];
    final filteredApps = allApps.where((app) {
      // Apply search filter
      if (_appSearchQuery.isNotEmpty) {
        final query = _appSearchQuery.toLowerCase();
        if (!app.packageName.toLowerCase().contains(query) &&
            !app.label.toLowerCase().contains(query)) {
          return false;
        }
      }
      
      // Apply type filter
      switch (_selectedAppFilter) {
        case 'User':
          return !app.isSystemApp;
        case 'System':
          return app.isSystemApp;
        case 'Enabled':
          return app.isEnabled;
        case 'Disabled':
          return !app.isEnabled;
        default:
          return true;
      }
    }).toList();

    if (filteredApps.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.apps, size: 48, color: Colors.grey),
            SizedBox(height: 16),
            Text('No apps found', style: TextStyle(color: Colors.grey)),
            Text('Try loading apps or adjusting filters', 
                style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: filteredApps.length,
      itemBuilder: (context, index) {
        final app = filteredApps[index];
        return _buildAppListItem(app);
      },
    );
  }

  Widget _buildAppListItem(AppInfo app) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Icon(
          app.isSystemApp ? Icons.android : Icons.apps,
          color: app.isSystemApp ? Colors.green : Colors.blue,
        ),
        title: Text(
          app.label.isNotEmpty ? app.label : app.packageName,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(app.packageName, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: app.isSystemApp ? Colors.green.shade100 : Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(app.typeLabel, 
                      style: TextStyle(fontSize: 10, 
                          color: app.isSystemApp ? Colors.green.shade700 : Colors.blue.shade700)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: app.isEnabled ? Colors.green.shade100 : Colors.red.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(app.statusLabel, 
                      style: TextStyle(fontSize: 10, 
                          color: app.isEnabled ? Colors.green.shade700 : Colors.red.shade700)),
                ),
              ],
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // App details
                _buildAppDetailRow('Version', app.version),
                _buildAppDetailRow('Version Code', app.versionCode),
                _buildAppDetailRow('APK Path', app.apkPath),
                if (app.size > 0) _buildAppDetailRow('Size', app.sizeFormatted),
                
                const SizedBox(height: 16),
                
                // Action buttons
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _showAppDetails(app),
                      icon: const Icon(Icons.info, size: 16),
                      label: const Text('Details'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                    ),
                    if (!app.isSystemApp) ...[
                      ElevatedButton.icon(
                        onPressed: () => _uninstallApp(app.packageName),
                        icon: const Icon(Icons.delete, size: 16),
                        label: const Text('Uninstall'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      ),
                    ],
                    ElevatedButton.icon(
                      onPressed: () => _enableDisableApp(app.packageName, !app.isEnabled),
                      icon: Icon(app.isEnabled ? Icons.block : Icons.check, size: 16),
                      label: Text(app.isEnabled ? 'Disable' : 'Enable'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: app.isEnabled ? Colors.orange : Colors.green),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _clearAppData(app.packageName),
                      icon: const Icon(Icons.cleaning_services, size: 16),
                      label: const Text('Clear Data'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: SelectableText(value, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  void _showAppDetails(AppInfo app) async {
    // Load detailed info if needed
    AppInfo detailedApp = app;
    if (app.version == 'Unknown') {
      final detailed = await _getDetailedPackageInfo(app.packageName);
      if (detailed != null) {
        detailedApp = detailed;
      }
    }

    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(detailedApp.label.isNotEmpty ? detailedApp.label : detailedApp.packageName),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildAppDetailRow('Package Name', detailedApp.packageName),
              _buildAppDetailRow('Version', detailedApp.version),
              _buildAppDetailRow('Version Code', detailedApp.versionCode),
              _buildAppDetailRow('Type', detailedApp.typeLabel),
              _buildAppDetailRow('Status', detailedApp.statusLabel),
              _buildAppDetailRow('APK Path', detailedApp.apkPath),
              if (detailedApp.size > 0) _buildAppDetailRow('Size', detailedApp.sizeFormatted),
              if (detailedApp.installDate != null) 
                _buildAppDetailRow('Installed', detailedApp.installDate.toString()),
              if (detailedApp.lastUpdateDate != null) 
                _buildAppDetailRow('Last Updated', detailedApp.lastUpdateDate.toString()),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadSystemInfo() async {
    if (_adb.currentState != ADBConnectionState.connected) {
      return;
    }

    try {
      final deviceModel = await _executeShellCommandForOutput('getprop ro.product.model') ?? 'Unknown';
      final androidVersion = await _executeShellCommandForOutput('getprop ro.build.version.release') ?? 'Unknown';
      final apiLevel = await _executeShellCommandForOutput('getprop ro.build.version.sdk') ?? 'Unknown';
      final buildId = await _executeShellCommandForOutput('getprop ro.build.id') ?? 'Unknown';
      final manufacturer = await _executeShellCommandForOutput('getprop ro.product.manufacturer') ?? 'Unknown';
      
      _adb.addOutput('📱 Device Info:');
      _adb.addOutput('  Model: ${deviceModel.trim()}');
      _adb.addOutput('  Manufacturer: ${manufacturer.trim()}');
      _adb.addOutput('  Android: ${androidVersion.trim()} (API ${apiLevel.trim()})');
      _adb.addOutput('  Build ID: ${buildId.trim()}');
      
      // Show in dialog too
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Device Information'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAppDetailRow('Model', deviceModel.trim()),
                _buildAppDetailRow('Manufacturer', manufacturer.trim()),
                _buildAppDetailRow('Android Version', androidVersion.trim()),
                _buildAppDetailRow('API Level', apiLevel.trim()),
                _buildAppDetailRow('Build ID', buildId.trim()),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      _adb.addOutput('❌ Error loading system info: $e');
    }
  }
}
