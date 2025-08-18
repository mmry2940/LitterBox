import 'dart:convert';
import 'dart:async';
import 'dart:io' show Process;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xterm/xterm.dart';
import '../adb_client.dart';
import '../models/saved_adb_device.dart';
import '../adb/embedded_adb_manager.dart';
import '../adb/adb_mdns_discovery.dart';
import '../adb/usb_bridge.dart';

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
  // Terminal (xterm) integration
  Terminal? _terminal;
  Process? _shellProcess;
  StreamSubscription<List<int>>? _shellStdoutSub;
  StreamSubscription<List<int>>? _shellStderrSub;
  final _terminalFocusNode = FocusNode();

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
  final ScrollController _logcatScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _adb = ADBClientManager();
    _adb.enableFlutterAdbBackend();
    _adb.output.listen((line) {
      if (_localBuffer.length > 1500) _localBuffer.removeRange(0, 800);
      _localBuffer.add(line);
      _autoScroll();
    });
    
    // Listen for connection state changes to auto-start logcat
    _adb.connectionState.listen((state) {
      if (state == ADBConnectionState.connected && _autoStartLogcat) {
        // Small delay to ensure connection is fully established
        Future.delayed(const Duration(milliseconds: 500), () async {
          if (_adb.currentState == ADBConnectionState.connected && !_adb.logcatActive) {
            await _adb.startLogcat();
            if (mounted) {
              setState(() {});
              // Auto-switch to logcat tab when it starts
              setState(() => _selectedIndex = 3); // Logcat tab index
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
                          icon: Icon(Icons.terminal), label: Text('Console')),
                      NavigationRailDestination(
                          icon: Icon(Icons.code), label: Text('Terminal')),
                      NavigationRailDestination(
                          icon: Icon(Icons.list_alt), label: Text('Logcat')),
                      NavigationRailDestination(
                          icon: Icon(Icons.play_arrow),
                          label: Text('Commands')),
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
                        _selectedIndex.clamp(0, 4), // Limit for mobile
                    onTap: (index) => setState(() => _selectedIndex = index),
                    type: BottomNavigationBarType.fixed,
                    items: const [
                      BottomNavigationBarItem(
                          icon: Icon(Icons.dashboard), label: 'Dashboard'),
                      BottomNavigationBarItem(
                          icon: Icon(Icons.terminal), label: 'Console'),
                      BottomNavigationBarItem(
                          icon: Icon(Icons.code), label: 'Terminal'),
                      BottomNavigationBarItem(
                          icon: Icon(Icons.list_alt), label: 'Logcat'),
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
        return _consoleTab();
      case 2:
        return _terminalTab();
      case 3:
        return _logcatTab();
      case 4:
        return _commandsTab();
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
                    onTap: () => setState(() => _selectedIndex = 7),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openInteractiveShellInTerminal() async {
    if (_shellProcess != null) return;
    final adbPath = await EmbeddedAdbManager.instance.adbPath; // may be ''
    final deviceId = _adb.currentState == ADBConnectionState.connected
        ? _adb.connectedDeviceId
        : '';
    final args = <String>[];
    if (deviceId.isNotEmpty) {
      args.addAll(['-s', deviceId]);
    }
    args.add('shell');
    try {
      _terminal ??= Terminal(maxLines: 2000);
      _terminal!.write('Starting shell...\r\n');
      _shellProcess = await Process.start(
          adbPath != null && adbPath.isNotEmpty ? adbPath : 'adb', args);
      _shellStdoutSub = _shellProcess!.stdout.listen((data) {
        _terminal?.write(String.fromCharCodes(data));
      });
      _shellStderrSub = _shellProcess!.stderr.listen((data) {
        _terminal?.write(String.fromCharCodes(data));
      });
      _terminal!.onOutput = (String text) {
        if (_shellProcess != null) {
          _shellProcess!.stdin.write(text);
        }
      };
      _shellProcess!.exitCode.then((code) {
        _terminal?.write('\r\nShell exited (code $code)\r\n');
        _disposeShell();
      });
      setState(() {});
    } catch (e) {
      _terminal?.write('Failed to start shell: $e\r\n');
    }
  }

  void _disposeShell() {
    _shellStdoutSub?.cancel();
    _shellStderrSub?.cancel();
    _shellStdoutSub = null;
    _shellStderrSub = null;
    _shellProcess = null;
  }

  Widget _terminalTab() {
    return Column(children: [
      Expanded(
        child: _terminal == null
            ? Center(
                child: Text('No shell session. Press Open Shell.'),
              )
            : Focus(
                focusNode: _terminalFocusNode,
                child: TerminalView(
                  _terminal!,
                  autofocus: true,
                  padding: const EdgeInsets.all(4),
                ),
              ),
      ),
      Container(
        color: Colors.grey[200],
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(children: [
          ElevatedButton.icon(
            onPressed:
                _shellProcess == null ? _openInteractiveShellInTerminal : null,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Open Shell'),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _shellProcess != null
                ? () {
                    _shellProcess!.kill();
                  }
                : null,
            icon: const Icon(Icons.stop),
            label: const Text('Stop'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          ),
          const SizedBox(width: 8),
          if (_terminal != null)
            ElevatedButton.icon(
              onPressed: () {
                _terminal!.write('\x1b[2J\x1b[H');
              },
              icon: const Icon(Icons.cleaning_services),
              label: const Text('Clear'),
            ),
        ]),
      )
    ]);
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

  Widget _consoleTab() {
    return Column(children: [
      Expanded(
        child: StreamBuilder<String>(
          stream: _adb.output,
          builder: (ctx, snap) {
            // Fallback: maintain a simple local snapshot if manager lacks collectedOutput.
            final lines = _bufferSnapshot();
            return ListView.builder(
              controller: _consoleScroll,
              itemCount: lines.length,
              itemBuilder: (_, i) => Text(lines[i],
                  style:
                      const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            );
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(children: [
          Expanded(
              child: TextField(
                  controller: _cmd,
                  decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      labelText: 'Command'))),
          const SizedBox(width: 8),
          ElevatedButton(
              onPressed: () async {
                final c = _cmd.text.trim();
                if (c.isEmpty) return;
                _cmd.clear();
                await _adb.executeCommand(c);
              },
              child: const Text('Run'))
        ]),
      )
    ]);
  }


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
                          trailing: ElevatedButton(
                              onPressed: _adb.currentState ==
                                      ADBConnectionState.connected
                                  ? () async => await _adb.executeCommand(cmd)
                                  : null,
                              child: const Text('Run')),
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
}
