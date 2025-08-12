import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../adb_client.dart';
import '../adb_backend.dart';
import '../webadb_server.dart';

class AndroidScreen extends StatefulWidget {
  const AndroidScreen({super.key});

  @override
  State<AndroidScreen> createState() => _AndroidScreenState();
}

class _AndroidScreenState extends State<AndroidScreen>
    with TickerProviderStateMixin {
  // Navigation indices: 0 Dashboard,1 Console,2 Logcat,3 Commands,4 Files/Ports,5 Info
  int _navIndex = 0;
  late ADBClientManager _adbClient;
  List<ADBBackendDevice> _externalDevices = [];
  String _selectedBackend = 'external'; // external | internal
  WebAdbServer? _webAdbServer;
  final _webAdbPortController = TextEditingController(text: '8587');

  // Connection form controllers
  final _hostController = TextEditingController(text: '192.168.1.100');
  final _portController = TextEditingController(text: '5555');
  final _commandController = TextEditingController();
  final _pairingPortController = TextEditingController(text: '37205');
  final _pairingCodeController = TextEditingController();

  // State variables
  ADBConnectionType _connectionType = ADBConnectionType.wifi;
  bool _isConnecting = false;
  List<SavedADBDevice> _savedDevices = [];
  SavedADBDevice? _selectedDevice;
  final ScrollController _outputScrollController = ScrollController();
  // Batch selection for saved devices
  final Set<String> _selectedSavedDeviceNames = {};
  bool _batchMode = false;
  // Recent paths and forwards
  List<String> _recentApkPaths = [];
  List<String> _recentLocalPaths = [];
  List<String> _recentRemotePaths = [];
  List<String> _recentForwards = [];
  // Logcat filters
  final TextEditingController _logcatFilterController = TextEditingController();
  String _activeLogcatFilter = '';

  @override
  void initState() {
    super.initState();
    _adbClient = ADBClientManager();
    // Enable external adb backend (real adb binary) replacing internal mock server
    _adbClient
        .enableExternalAdbBackend()
        .then((_) => _refreshExternalDevices());
    _loadSavedDevices();
    _applyPersistedRuntimeSettings();

    // Listen to connection state changes
    _adbClient.connectionState.listen((state) {
      if (mounted) {
        setState(() {
          _isConnecting = state == ADBConnectionState.connecting;
        });
      }
    });

    // Auto-scroll output to bottom when new content arrives
    _adbClient.output.listen((_) {
      if (_outputScrollController.hasClients) {
        Future.delayed(const Duration(milliseconds: 100), () {
          _outputScrollController.animateTo(
            _outputScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        });
      }
    });
  }

  Future<void> _applyPersistedRuntimeSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final buffer = prefs.getInt('console_buffer_lines');
    final verbose = prefs.getBool('verbose_logging');
    final progress = prefs.getBool('adb_progress_notifications');
    _adbClient.applySettings(
      bufferLines: buffer,
      verbose: verbose,
      progressNotifications: progress,
    );
    // Auto-connect last or first saved device if setting enabled
    final auto = prefs.getBool('auto_connect_adb') ?? false;
    if (auto) {
      // wait a tick for saved devices
      Future.delayed(const Duration(milliseconds: 300), () {
        if (_savedDevices.isNotEmpty &&
            mounted &&
            _adbClient.currentState != ADBConnectionState.connected) {
          _loadDevice(_savedDevices.first);
          _connect();
        }
      });
    }
  }

  @override
  void dispose() {
    _adbClient.dispose();
    _hostController.dispose();
    _portController.dispose();
    _commandController.dispose();
    _pairingPortController.dispose();
    _pairingCodeController.dispose();
    _outputScrollController.dispose();
    _logcatFilterController.dispose();
    _webAdbPortController.dispose();
    super.dispose();
  }

  Future<void> _refreshExternalDevices() async {
    if (!_adbClient.usingExternalBackend) return;
    final devices = await _adbClient.refreshBackendDevices();
    if (mounted) setState(() => _externalDevices = devices);
  }

  Future<void> _loadSavedDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final devicesJson = prefs.getStringList('adb_devices') ?? [];
    _recentApkPaths = prefs.getStringList('recent_apk') ?? [];
    _recentLocalPaths = prefs.getStringList('recent_local') ?? [];
    _recentRemotePaths = prefs.getStringList('recent_remote') ?? [];
    _recentForwards = prefs.getStringList('recent_forwards') ?? [];
    setState(() {
      _savedDevices = devicesJson
          .map((json) => SavedADBDevice.fromJson(jsonDecode(json)))
          .toList();
    });
  }

  Future<void> _saveDevice() async {
    if (_hostController.text.isEmpty) return;

    final device = SavedADBDevice(
      name: '${_hostController.text}:${_portController.text}',
      host: _hostController.text,
      port: int.tryParse(_portController.text) ?? 5555,
      connectionType: _connectionType,
    );

    final prefs = await SharedPreferences.getInstance();
    _savedDevices.add(device);
    final devicesJson =
        _savedDevices.map((d) => jsonEncode(d.toJson())).toList();
    await prefs.setStringList('adb_devices', devicesJson);

    setState(() {});

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Device saved successfully')),
      );
    }
  }

  Future<void> _persistRecents(SharedPreferences prefs) async {
    await prefs.setStringList('recent_apk', _recentApkPaths.take(10).toList());
    await prefs.setStringList(
        'recent_local', _recentLocalPaths.take(10).toList());
    await prefs.setStringList(
        'recent_remote', _recentRemotePaths.take(10).toList());
    await prefs.setStringList(
        'recent_forwards', _recentForwards.take(10).toList());
  }

  Future<void> _deleteDevice(int index) async {
    final prefs = await SharedPreferences.getInstance();
    _savedDevices.removeAt(index);
    final devicesJson =
        _savedDevices.map((d) => jsonEncode(d.toJson())).toList();
    await prefs.setStringList('adb_devices', devicesJson);

    setState(() {
      if (_selectedDevice != null && index < _savedDevices.length) {
        _selectedDevice = null;
      }
    });
  }

  void _loadDevice(SavedADBDevice device) {
    setState(() {
      _hostController.text = device.host;
      _portController.text = device.port.toString();
      _connectionType = device.connectionType;
      _selectedDevice = device;
    });
  }

  Future<void> _connect() async {
    bool success = false;

    switch (_connectionType) {
      case ADBConnectionType.wifi:
      case ADBConnectionType.custom:
        final host = _hostController.text.trim();
        final port = int.tryParse(_portController.text) ?? 5555;
        success = await _adbClient.connectWifi(host, port);
        break;
      case ADBConnectionType.usb:
        success = await _adbClient.connectUSB();
        break;
      case ADBConnectionType.pairing:
        // For pairing, we use the pair method instead
        await _pairDevice();
        return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(success ? 'Connected successfully' : 'Connection failed'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  Future<void> _pairDevice() async {
    final host = _hostController.text.trim();
    final pairingPort = int.tryParse(_pairingPortController.text) ?? 37205;
    final connectionPort = int.tryParse(_portController.text) ?? 5555;
    final pairingCode = _pairingCodeController.text.trim();

    if (host.isEmpty || pairingCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter host IP and pairing code'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final success = await _adbClient.pairDevice(
        host, pairingPort, pairingCode, connectionPort);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(success ? 'Device paired successfully!' : 'Pairing failed'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  Future<void> _disconnect() async {
    await _adbClient.disconnect();
  }

  // Removed legacy ADB server checker (internal mock server removed)

  Future<void> _executeCommand() async {
    final command = _commandController.text.trim();
    if (command.isEmpty) return;

    await _adbClient.executeCommand(command);
    _commandController.clear();
  }

  void _executePresetCommand(String command) {
    _commandController.text = command;
    _executeCommand();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Android Device Manager'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            tooltip: 'Refresh Devices',
            icon: const Icon(Icons.refresh),
            onPressed: _refreshExternalDevices,
          ),
          if (_adbClient.logcatActive)
            IconButton(
              tooltip: 'Stop Logcat',
              icon: const Icon(Icons.stop_circle, color: Colors.orange),
              onPressed: () async {
                await _adbClient.stopLogcat();
                setState(() {});
              },
            )
          else if (_adbClient.currentState == ADBConnectionState.connected)
            IconButton(
              tooltip: 'Start Logcat',
              icon: const Icon(Icons.play_arrow),
              onPressed: () async {
                await _adbClient.startLogcat();
                setState(() {
                  _navIndex = 2; // switch to logcat view
                });
              },
            ),
          IconButton(
            tooltip: 'Clear Console',
            icon: const Icon(Icons.cleaning_services_outlined),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              final confirm = prefs.getBool('confirm_clear_logcat') ?? true;
              if (confirm) {
                final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Clear console output?'),
                        content: const Text(
                            'This will remove all buffered console lines.'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancel')),
                          ElevatedButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Clear')),
                        ],
                      ),
                    ) ??
                    false;
                if (!ok) return;
              }
              setState(() {
                _adbClient.clearOutput();
              });
            },
          ),
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _navIndex,
            onDestinationSelected: (i) => setState(() => _navIndex = i),
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard),
                  label: Text('Dashboard')),
              NavigationRailDestination(
                  icon: Icon(Icons.terminal_outlined),
                  selectedIcon: Icon(Icons.terminal),
                  label: Text('Console')),
              NavigationRailDestination(
                  icon: Icon(Icons.list_alt),
                  selectedIcon: Icon(Icons.list),
                  label: Text('Logcat')),
              NavigationRailDestination(
                  icon: Icon(Icons.flash_on_outlined),
                  selectedIcon: Icon(Icons.flash_on),
                  label: Text('Commands')),
              NavigationRailDestination(
                  icon: Icon(Icons.folder_copy_outlined),
                  selectedIcon: Icon(Icons.folder_copy),
                  label: Text('Files')),
              NavigationRailDestination(
                  icon: Icon(Icons.info_outline),
                  selectedIcon: Icon(Icons.info),
                  label: Text('Info')),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _lazyBody()),
        ],
      ),
    );
  }

  // Cache built tabs when first visited
  final Map<int, Widget> _tabCache = {};

  Widget _lazyBody() {
    // Preserve state per tab by caching the widget tree once created
    if (!_tabCache.containsKey(_navIndex)) {
      _tabCache[_navIndex] = _buildBodyByIndex();
    }
    // Use IndexedStack to keep previous tabs alive without rebuilding
    return IndexedStack(
      index: _navIndex,
      children: List.generate(6, (i) => _tabCache[i] ?? const SizedBox()),
    );
  }

  Widget _buildBodyByIndex() {
    switch (_navIndex) {
      case 0:
        return _buildDashboard();
      case 1:
        return _buildConsoleTab();
      case 2:
        return _buildLogcatTab();
      case 3:
        return _buildCommandsTab();
      case 4:
        return _buildFilesTab();
      case 5:
      default:
        return _buildInfoTab();
    }
  }

  Widget _buildDashboard() {
    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth > 900;
      final left = _buildConnectionTab();
      final right = Column(
        children: [
          _buildDeviceSummaryCard(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildQuickActions(),
            ),
          ),
        ],
      );
      return Padding(
        padding: const EdgeInsets.all(8.0),
        child: isWide
            ? Row(children: [
                Expanded(child: left),
                const SizedBox(width: 12),
                Expanded(child: right),
              ])
            : Column(children: [
                Expanded(child: left),
                const SizedBox(height: 12),
                SizedBox(
                  height: 320,
                  child: right,
                )
              ]),
      );
    });
  }

  Widget _buildDeviceSummaryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Current Device',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_adbClient.currentState == ADBConnectionState.connected)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('State: ${_getStateText(_adbClient.currentState)}'),
                  if (_adbClient.usingExternalBackend)
                    const Text('Backend: adb (external)'),
                  if (_adbClient.logcatActive) const Text('Logcat: streaming'),
                ],
              )
            else
              const Text('No active device'),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Quick Actions',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _qaButton('Start Logcat', Icons.play_arrow, () async {
                  if (!_adbClient.logcatActive) {
                    await _adbClient.startLogcat();
                    setState(() => _navIndex = 2);
                  }
                },
                    enabled: _adbClient.currentState ==
                            ADBConnectionState.connected &&
                        !_adbClient.logcatActive),
                _qaButton('Stop Logcat', Icons.stop, () async {
                  await _adbClient.stopLogcat();
                  setState(() {});
                }, enabled: _adbClient.logcatActive),
                _qaButton('Clear Logcat', Icons.cleaning_services, () {
                  _adbClient.clearLogcat();
                  setState(() {});
                }, enabled: _adbClient.logcatActive),
                _qaButton('Console', Icons.terminal,
                    () => setState(() => _navIndex = 1),
                    enabled: true),
                _qaButton('Commands', Icons.flash_on,
                    () => setState(() => _navIndex = 3),
                    enabled: true),
                _qaButton('Files', Icons.folder_copy,
                    () => setState(() => _navIndex = 4),
                    enabled: true),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _qaButton(String label, IconData icon, VoidCallback onPressed,
      {bool enabled = true}) {
    return SizedBox(
      height: 38,
      child: ElevatedButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, size: 16),
        label: Text(label),
      ),
    );
  }

  Widget _buildConnectionTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Connection Status
            StreamBuilder<ADBConnectionState>(
              stream: _adbClient.connectionState,
              initialData: _adbClient.currentState,
              builder: (context, snapshot) {
                final state = snapshot.data ?? ADBConnectionState.disconnected;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Icon(
                          _getStateIcon(state),
                          color: _getStateColor(state),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Status: ${_getStateText(state)}',
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),

            // Backend Selector (internal vs external)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.settings_input_component, size: 18),
                        const SizedBox(width: 6),
                        const Text('ADB Backend',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        Tooltip(
                          message:
                              'External uses system adb (real devices). Internal is a mock backend for demo/offline.',
                          child: const Icon(Icons.info_outline, size: 16),
                        )
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedBackend,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'Backend',
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: 'external',
                                child: Text('External (system adb)')),
                            DropdownMenuItem(
                                value: 'internal',
                                child: Text('Internal (mock)')),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => _selectedBackend = v);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () async {
                          if (_selectedBackend == 'external') {
                            await _adbClient.enableExternalAdbBackend();
                          } else {
                            await _adbClient.enableInternalAdbBackend();
                          }
                          await _refreshExternalDevices();
                          if (mounted) setState(() {});
                        },
                        child: const Text('Apply'),
                      )
                    ]),
                    const SizedBox(height: 12),
                    Text('Active: ${_adbClient.backendLabel}',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.primary)),
                    if (_selectedBackend == 'external' &&
                        _externalDevices.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: _realDeviceHelp(),
                      )
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // WebADB Bridge Controls
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.public, size: 18),
                        const SizedBox(width: 6),
                        const Text('WebADB Bridge',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        Tooltip(
                          message:
                              'Starts a lightweight HTTP + WebSocket bridge for browser clients (/devices, /connect, /disconnect, /shell).',
                          child: const Icon(Icons.info_outline, size: 16),
                        )
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        SizedBox(
                          width: 110,
                          child: TextField(
                            controller: _webAdbPortController,
                            decoration: const InputDecoration(
                              labelText: 'Port',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            keyboardType: TextInputType.number,
                            enabled: !(_webAdbServer?.running ?? false),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          icon: Icon((_webAdbServer?.running ?? false)
                              ? Icons.stop
                              : Icons.play_arrow),
                          label: Text((_webAdbServer?.running ?? false)
                              ? 'Stop'
                              : 'Start'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: (_webAdbServer?.running ?? false)
                                ? Colors.red
                                : null,
                          ),
                          onPressed: () async {
                            if (!(_webAdbServer?.running ?? false)) {
                              final port = int.tryParse(
                                      _webAdbPortController.text.trim()) ??
                                  8587;
                              _webAdbServer =
                                  WebAdbServer(_adbClient, port: port);
                              final ok = await _webAdbServer!.start();
                              if (ok && mounted) setState(() {});
                            } else {
                              await _webAdbServer?.stop();
                              if (mounted) setState(() {});
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: (_webAdbServer?.running ?? false)
                          ? Text(
                              'Running at http://<host>:${_webAdbServer!.port} (WS: /shell)',
                              key: const ValueKey('webadb_on'),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.primary),
                            )
                          : const Text('Stopped',
                              key: ValueKey('webadb_off'),
                              style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Connection Type Selector
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Connection Type',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<ADBConnectionType>(
                      value: _connectionType,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: ADBConnectionType.values.map((type) {
                        return DropdownMenuItem(
                          value: type,
                          child: Text(type.displayName),
                        );
                      }).toList(),
                      onChanged: (ADBConnectionType? value) {
                        if (value != null) {
                          setState(() {
                            _connectionType = value;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Saved Devices with batch mode
            if (_savedDevices.isNotEmpty) ...[
              const Text(
                'Saved Devices',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (_batchMode)
                    Text('${_selectedSavedDeviceNames.length} selected',
                        style: const TextStyle(fontSize: 12)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _batchMode = !_batchMode;
                        if (!_batchMode) _selectedSavedDeviceNames.clear();
                      });
                    },
                    icon: Icon(_batchMode ? Icons.close : Icons.select_all),
                    label: Text(_batchMode ? 'Cancel' : 'Select'),
                  ),
                  if (_batchMode)
                    TextButton.icon(
                      onPressed: _selectedSavedDeviceNames.isEmpty
                          ? null
                          : () async {
                              final prefs =
                                  await SharedPreferences.getInstance();
                              _savedDevices.removeWhere((d) =>
                                  _selectedSavedDeviceNames.contains(d.name));
                              _selectedSavedDeviceNames.clear();
                              final devicesJson = _savedDevices
                                  .map((d) => jsonEncode(d.toJson()))
                                  .toList();
                              await prefs.setStringList(
                                  'adb_devices', devicesJson);
                              setState(() {});
                            },
                      icon: const Icon(Icons.delete_forever),
                      label: const Text('Delete'),
                    ),
                ],
              ),
              SizedBox(
                height: 120,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _savedDevices.length,
                  itemBuilder: (context, index) {
                    final device = _savedDevices[index];
                    return Card(
                      margin: const EdgeInsets.only(right: 8),
                      color: _batchMode &&
                              _selectedSavedDeviceNames.contains(device.name)
                          ? Colors.lightBlue.shade50
                          : null,
                      child: InkWell(
                        onTap: () {
                          if (_batchMode) {
                            setState(() {
                              if (_selectedSavedDeviceNames
                                  .contains(device.name)) {
                                _selectedSavedDeviceNames.remove(device.name);
                              } else {
                                _selectedSavedDeviceNames.add(device.name);
                              }
                            });
                          } else {
                            _loadDevice(device);
                          }
                        },
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
                              if (_batchMode)
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Icon(
                                    _selectedSavedDeviceNames
                                            .contains(device.name)
                                        ? Icons.check_circle
                                        : Icons.circle_outlined,
                                    size: 16,
                                    color: _selectedSavedDeviceNames
                                            .contains(device.name)
                                        ? Colors.blue
                                        : Colors.grey,
                                  ),
                                ),
                              Text('${device.host}:${device.port}'),
                              Text(
                                  'Type: ${device.connectionType.displayName}'),
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
            const Text(
              'Connection Details',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            if (_connectionType != ADBConnectionType.usb) ...[
              _responsiveRow([
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
                if (_connectionType != ADBConnectionType.pairing)
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
              ]),
              const SizedBox(height: 16),

              // Pairing-specific fields
              if (_connectionType == ADBConnectionType.pairing) ...[
                _responsiveRow([
                  Expanded(
                    flex: 1,
                    child: TextField(
                      controller: _pairingPortController,
                      decoration: const InputDecoration(
                        labelText: 'Pairing Port',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.settings_ethernet),
                        hintText: '37205',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _pairingCodeController,
                      decoration: const InputDecoration(
                        labelText: 'Pairing Code',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.security),
                        hintText: '123456',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                const Card(
                  color: Colors.blue,
                  child: Padding(
                    padding: EdgeInsets.all(12.0),
                    child: Text(
                      'Enable "Wireless debugging" in Developer Options, then tap "Pair device with pairing code"',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ] else ...[
              const Card(
                color: Colors.blue,
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'USB Connection will attempt to connect to localhost:5037\n'
                    'Make sure ADB daemon is running on your computer.',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // External adb (real) device list replacing mock server controls
            if (_adbClient.usingExternalBackend)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.usb, size: 16),
                            const SizedBox(width: 6),
                            const Text('ADB Devices (external)',
                                style: TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.bold)),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.refresh, size: 18),
                              tooltip: 'Refresh devices',
                              onPressed: _refreshExternalDevices,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        if (_externalDevices.isEmpty)
                          const Text('No devices detected',
                              style: TextStyle(fontSize: 12))
                        else
                          ..._externalDevices
                              .take(4)
                              .map(
                                (d) => Padding(
                                  padding:
                                      const EdgeInsets.only(left: 4, top: 2),
                                  child: Text(
                                    '• ${d.serial} (${d.state})',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              )
                              .toList(),
                        if (_externalDevices.length > 4)
                          Text(
                            '+ ${_externalDevices.length - 4} more',
                            style: const TextStyle(
                                fontSize: 11, fontStyle: FontStyle.italic),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isConnecting
                        ? null
                        : (_connectionType == ADBConnectionType.pairing
                            ? _pairDevice
                            : _connect),
                    icon: _isConnecting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(_connectionType == ADBConnectionType.pairing
                            ? Icons.link
                            : Icons.wifi),
                    label: Text(_isConnecting
                        ? (_connectionType == ADBConnectionType.pairing
                            ? 'Pairing...'
                            : 'Connecting...')
                        : (_connectionType == ADBConnectionType.pairing
                            ? 'Pair Device'
                            : 'Connect')),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor:
                          _connectionType == ADBConnectionType.pairing
                              ? Colors.orange
                              : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (_connectionType != ADBConnectionType.pairing) ...[
                  ElevatedButton.icon(
                    onPressed:
                        _adbClient.currentState == ADBConnectionState.connected
                            ? _disconnect
                            : null,
                    icon: const Icon(Icons.link_off),
                    label: const Text('Disconnect'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saveDevice,
                icon: const Icon(Icons.save),
                label: const Text('Save Device'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _realDeviceHelp() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text('No devices detected. Steps to connect:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        SizedBox(height: 4),
        Text('1. Enable Developer Options on your Android device.',
            style: TextStyle(fontSize: 11)),
        Text('2. Turn on USB Debugging (Developer Options).',
            style: TextStyle(fontSize: 11)),
        Text(
            '3. For Wi-Fi: In Developer Options tap "Wireless debugging" > Pair or enable.',
            style: TextStyle(fontSize: 11)),
        Text('4. Ensure adb is installed and in system PATH.',
            style: TextStyle(fontSize: 11)),
        Text('5. Run: adb devices (should list your device).',
            style: TextStyle(fontSize: 11)),
      ],
    );
  }

  Widget _buildConsoleTab() {
    int historyIndex = _adbClient.commandHistoryList.length;
    return StatefulBuilder(builder: (context, setInnerState) {
      return Column(
        children: [
          // Output Area
          Expanded(
            child: Container(
              color: Colors.black87,
              child: StreamBuilder<String>(
                stream: _adbClient.output,
                builder: (context, snapshot) {
                  return ListView.builder(
                    controller: _outputScrollController,
                    padding: const EdgeInsets.all(8),
                    itemCount: _adbClient.outputBuffer.length,
                    itemBuilder: (context, index) {
                      final output = _adbClient.outputBuffer[index];
                      return SelectableText(
                        output,
                        style: const TextStyle(
                          color: Colors.green,
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
          // Command/Input + Controls
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.grey[200],
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: RawKeyboardListener(
                        focusNode: FocusNode(),
                        onKey: (evt) {
                          if (evt.isKeyPressed(LogicalKeyboardKey.arrowUp)) {
                            if (_adbClient.commandHistoryList.isNotEmpty) {
                              historyIndex = (historyIndex - 1).clamp(
                                  0, _adbClient.commandHistoryList.length - 1);
                              _commandController.text =
                                  _adbClient.commandHistoryList[historyIndex];
                              _commandController.selection =
                                  TextSelection.fromPosition(TextPosition(
                                      offset: _commandController.text.length));
                              setInnerState(() {});
                            }
                          } else if (evt
                              .isKeyPressed(LogicalKeyboardKey.arrowDown)) {
                            if (_adbClient.commandHistoryList.isNotEmpty) {
                              historyIndex = (historyIndex + 1).clamp(
                                  0, _adbClient.commandHistoryList.length);
                              if (historyIndex ==
                                  _adbClient.commandHistoryList.length) {
                                _commandController.clear();
                              } else {
                                _commandController.text =
                                    _adbClient.commandHistoryList[historyIndex];
                                _commandController.selection =
                                    TextSelection.fromPosition(TextPosition(
                                        offset:
                                            _commandController.text.length));
                              }
                              setInnerState(() {});
                            }
                          }
                        },
                        child: TextField(
                          controller: _commandController,
                          decoration: InputDecoration(
                            hintText: _adbClient.interactiveShellActive
                                ? 'Interactive shell input (press Enter)'
                                : 'Enter ADB command...',
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                          ),
                          onSubmitted: (_) {
                            if (_adbClient.interactiveShellActive) {
                              _adbClient.sendInteractiveShellInput(
                                  _commandController.text.trim());
                              _commandController.clear();
                            } else {
                              _executeCommand();
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (!_adbClient.interactiveShellActive)
                      ElevatedButton(
                        onPressed: _adbClient.currentState ==
                                ADBConnectionState.connected
                            ? _executeCommand
                            : null,
                        child: const Text('Execute'),
                      )
                    else
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red),
                        onPressed: _adbClient.stopInteractiveShell,
                        child: const Text('Stop'),
                      ),
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert),
                      onSelected: (value) {
                        switch (value) {
                          case 'clear_output':
                            _adbClient.clearOutput();
                            break;
                          case 'clear_history':
                            _adbClient.clearHistory();
                            break;
                          case 'start_shell':
                            _adbClient.startInteractiveShell();
                            break;
                          case 'stop_shell':
                            _adbClient.stopInteractiveShell();
                            break;
                        }
                        setInnerState(() {});
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'clear_output',
                          child: Text('Clear Output'),
                        ),
                        const PopupMenuItem(
                          value: 'clear_history',
                          child: Text('Clear History'),
                        ),
                        if (!_adbClient.interactiveShellActive)
                          const PopupMenuItem(
                            value: 'start_shell',
                            child: Text('Start Interactive Shell'),
                          )
                        else
                          const PopupMenuItem(
                            value: 'stop_shell',
                            child: Text('Stop Interactive Shell'),
                          ),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    Switch(
                      value: _adbClient.interactiveShellActive,
                      onChanged: (v) async {
                        if (v) {
                          await _adbClient.startInteractiveShell();
                        } else {
                          await _adbClient.stopInteractiveShell();
                        }
                        setInnerState(() {});
                      },
                    ),
                    Text(_adbClient.interactiveShellActive
                        ? 'Interactive Shell Active'
                        : 'Execute Single Commands'),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
    });
  }

  Widget _buildCommandsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Quick Commands',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        ...ADBCommands.commandCategories.entries.map((category) {
          return ExpansionTile(
            title: Text(
              category.key,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            children: category.value.map((command) {
              return ListTile(
                title: Text(
                  command,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                subtitle: Text(ADBCommands.getCommandDescription(command)),
                trailing: ElevatedButton(
                  onPressed:
                      _adbClient.currentState == ADBConnectionState.connected
                          ? () => _executePresetCommand(command)
                          : null,
                  child: const Text('Run'),
                ),
                onTap: () {
                  _commandController.text = command;
                  setState(() => _navIndex = 1); // Switch to console view
                },
              );
            }).toList(),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildLogcatTab() {
    return Column(
      children: [
        Expanded(
          child: Container(
            color: Colors.black,
            child: StreamBuilder<String>(
              stream: _adbClient.logcatStream,
              builder: (context, snapshot) {
                return ListView.builder(
                  padding: const EdgeInsets.all(4),
                  itemCount: _adbClient.logcatBuffer.length,
                  itemBuilder: (context, index) {
                    final line = _adbClient.logcatBuffer[index];
                    if (_activeLogcatFilter.isNotEmpty &&
                        !line
                            .toLowerCase()
                            .contains(_activeLogcatFilter.toLowerCase())) {
                      return const SizedBox.shrink();
                    }
                    Color c = Colors.white;
                    if (line.contains(' E ') || line.contains(' E/'))
                      c = Colors.redAccent;
                    else if (line.contains(' W ') || line.contains(' W/'))
                      c = Colors.orangeAccent;
                    else if (line.contains(' I ') || line.contains(' I/'))
                      c = Colors.lightBlueAccent;
                    return Text(line,
                        style: TextStyle(
                            color: c, fontFamily: 'monospace', fontSize: 11));
                  },
                );
              },
            ),
          ),
        ),
        Container(
          color: Colors.grey[200],
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              ElevatedButton.icon(
                onPressed: _adbClient.logcatActive
                    ? null
                    : () async {
                        await _adbClient.startLogcat();
                        setState(() {});
                      },
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _adbClient.logcatActive
                    ? () async {
                        await _adbClient.stopLogcat();
                        setState(() {});
                      }
                    : null,
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () {
                  _adbClient.clearLogcat();
                  setState(() {});
                },
                icon: const Icon(Icons.cleaning_services),
                label: const Text('Clear'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _logcatFilterController,
                  decoration: InputDecoration(
                    hintText: 'Filter (tag / text / level)...',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: () {
                        setState(() {
                          _activeLogcatFilter =
                              _logcatFilterController.text.trim();
                        });
                      },
                    ),
                  ),
                  onSubmitted: (_) {
                    setState(() {
                      _activeLogcatFilter = _logcatFilterController.text.trim();
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              if (_activeLogcatFilter.isNotEmpty)
                IconButton(
                  tooltip: 'Clear filter',
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(() {
                      _activeLogcatFilter = '';
                      _logcatFilterController.clear();
                    });
                  },
                ),
              const Spacer(),
              Text('${_adbClient.logcatBuffer.length} lines',
                  style: const TextStyle(fontSize: 12)),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildFilesTab() {
    final apkPathController = TextEditingController();
    final pushLocalController = TextEditingController();
    final pushRemoteController = TextEditingController(text: '/sdcard/');
    final pullRemoteController = TextEditingController();
    final pullLocalController = TextEditingController();
    final forwardLocalPortController = TextEditingController(text: '9000');
    final forwardRemoteSpecController = TextEditingController(text: 'tcp:9000');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.folder_copy, size: 18),
              const SizedBox(width: 6),
              const Text('File & Port Operations',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Install APK',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _responsiveRow([
                    Expanded(
                      child: TextField(
                        controller: apkPathController,
                        decoration: const InputDecoration(
                            labelText: 'APK File Path',
                            border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                        onPressed: _adbClient.currentState ==
                                ADBConnectionState.connected
                            ? () async {
                                final ok = await _adbClient
                                    .installApk(apkPathController.text);
                                if (apkPathController.text.isNotEmpty) {
                                  _recentApkPaths
                                      .remove(apkPathController.text);
                                  _recentApkPaths.insert(
                                      0, apkPathController.text);
                                  final prefs =
                                      await SharedPreferences.getInstance();
                                  _persistRecents(prefs);
                                }
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(ok
                                              ? 'APK installed'
                                              : 'Install failed')));
                                }
                              }
                            : null,
                        child: const Text('Install'))
                  ]),
                  if (_recentApkPaths.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: _recentApkPaths
                          .map((p) => ActionChip(
                                label: Text(p.split('/').last,
                                    overflow: TextOverflow.ellipsis),
                                onPressed: () => apkPathController.text = p,
                              ))
                          .toList(),
                    )
                  ]
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Push File',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _responsiveRow([
                    Expanded(
                      child: TextField(
                        controller: pushLocalController,
                        decoration: const InputDecoration(
                            labelText: 'Local Path',
                            border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: pushRemoteController,
                        decoration: const InputDecoration(
                            labelText: 'Remote Path',
                            border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                        onPressed: _adbClient.currentState ==
                                ADBConnectionState.connected
                            ? () async {
                                final ok = await _adbClient.pushFile(
                                    pushLocalController.text,
                                    pushRemoteController.text);
                                if (pushLocalController.text.isNotEmpty) {
                                  _recentLocalPaths
                                      .remove(pushLocalController.text);
                                  _recentLocalPaths.insert(
                                      0, pushLocalController.text);
                                }
                                if (pushRemoteController.text.isNotEmpty) {
                                  _recentRemotePaths
                                      .remove(pushRemoteController.text);
                                  _recentRemotePaths.insert(
                                      0, pushRemoteController.text);
                                }
                                final prefs =
                                    await SharedPreferences.getInstance();
                                _persistRecents(prefs);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(ok
                                              ? 'File pushed'
                                              : 'Push failed')));
                                }
                              }
                            : null,
                        child: const Text('Push'))
                  ]),
                  if (_recentLocalPaths.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _recentLocalPaths
                            .map((p) => Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: ActionChip(
                                    label: Text(p.split('/').last,
                                        overflow: TextOverflow.ellipsis),
                                    onPressed: () =>
                                        pushLocalController.text = p,
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                  ],
                  if (_recentRemotePaths.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _recentRemotePaths
                            .map((p) => Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: ActionChip(
                                    label: Text(p,
                                        overflow: TextOverflow.ellipsis),
                                    onPressed: () =>
                                        pushRemoteController.text = p,
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                  ]
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Pull File',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _responsiveRow([
                    Expanded(
                      child: TextField(
                        controller: pullRemoteController,
                        decoration: const InputDecoration(
                            labelText: 'Remote Path',
                            border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: pullLocalController,
                        decoration: const InputDecoration(
                            labelText: 'Local Path',
                            border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                        onPressed: _adbClient.currentState ==
                                ADBConnectionState.connected
                            ? () async {
                                final ok = await _adbClient.pullFile(
                                    pullRemoteController.text,
                                    pullLocalController.text);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(ok
                                              ? 'File pulled'
                                              : 'Pull failed')));
                                }
                              }
                            : null,
                        child: const Text('Pull'))
                  ])
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Port Forward',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _responsiveRow([
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: forwardLocalPortController,
                        decoration: const InputDecoration(
                            labelText: 'Local', border: OutlineInputBorder()),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: forwardRemoteSpecController,
                        decoration: const InputDecoration(
                            labelText: 'Remote Spec (tcp:NN)',
                            border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                        onPressed: _adbClient.currentState ==
                                ADBConnectionState.connected
                            ? () async {
                                final lp = int.tryParse(
                                        forwardLocalPortController.text) ??
                                    0;
                                final ok = await _adbClient.forwardPort(
                                    lp, forwardRemoteSpecController.text);
                                if (ok) {
                                  final fr =
                                      '${forwardLocalPortController.text}:${forwardRemoteSpecController.text}';
                                  _recentForwards.remove(fr);
                                  _recentForwards.insert(0, fr);
                                  final prefs =
                                      await SharedPreferences.getInstance();
                                  _persistRecents(prefs);
                                }
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(ok
                                              ? 'Forward added'
                                              : 'Forward failed')));
                                }
                              }
                            : null,
                        child: const Text('Add')),
                    const SizedBox(width: 4),
                    ElevatedButton(
                        onPressed: _adbClient.currentState ==
                                ADBConnectionState.connected
                            ? () async {
                                final lp = int.tryParse(
                                        forwardLocalPortController.text) ??
                                    0;
                                final ok = await _adbClient.removeForward(lp);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(ok
                                              ? 'Forward removed'
                                              : 'Remove failed')));
                                }
                              }
                            : null,
                        child: const Text('Remove'))
                  ]),
                  if (_recentForwards.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: _recentForwards
                          .map((f) => ActionChip(
                                label: Text(f, overflow: TextOverflow.ellipsis),
                                onPressed: () {
                                  final parts = f.split(':');
                                  if (parts.length >= 2) {
                                    forwardLocalPortController.text = parts[0];
                                    forwardRemoteSpecController.text =
                                        parts.sublist(1).join(':');
                                  }
                                },
                              ))
                          .toList(),
                    )
                  ]
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Responsive helper: switches to Column when horizontal space is tight
  Widget _responsiveRow(List<Widget> children) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // If width under 640, stack vertically with spacing
        final narrow = constraints.maxWidth < 640;
        if (!narrow) return Row(children: children);

        final List<Widget> colChildren = [];
        for (int i = 0; i < children.length; i++) {
          final w = children[i];
          // Convert horizontal spacing boxes to vertical spacing
          if (w is SizedBox && w.width != null && w.height == null) {
            // skip leading spacing
            if (colChildren.isNotEmpty) {
              colChildren.add(SizedBox(height: w.width ?? 8));
            }
            continue;
          }
          Widget toAdd = w;
          // Strip Expanded/Flexible when stacking vertically (causes unbounded height issues in scroll views)
          if (w is Expanded) {
            toAdd = w.child;
          } else if (w is Flexible) {
            toAdd = w.child;
          }
          colChildren.add(toAdd);
          if (i != children.length - 1) {
            colChildren.add(const SizedBox(height: 8));
          }
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: colChildren,
        );
      },
    );
  }

  Widget _buildInfoTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          Text(
            'Android ADB Setup Guide',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          _infoSection(
            icon: Icons.settings_system_daydream,
            accent: Colors.blue,
            title: 'ADB Server Setup',
            body: [
              '1. Install Android SDK Platform Tools',
              '2. Add ADB to your system PATH',
              '3. Run "adb start-server" in terminal',
              '4. Use "Check ADB Server" button to verify',
            ],
            footerMonospace:
                'Download: https://developer.android.com/studio/releases/platform-tools',
          ),
          _infoSection(
            icon: Icons.wifi,
            accent: Colors.green,
            title: 'Wireless ADB Setup',
            body: [
              'Android 11+ (Wireless Debugging):',
              '  1. Enable Developer Options',
              '  2. Enable "Wireless debugging"',
              '  3. Tap "Pair device with pairing code"',
              '  4. Enter pairing code + port here',
              '  5. Connect using IP:5555',
              '',
              'Older Android (ADB over network):',
              '  1. Connect via USB first',
              '  2. Run: adb tcpip 5555',
              '  3. Disconnect USB',
              '  4. Connect using device IP:5555',
            ],
          ),
          _infoSection(
            icon: Icons.usb,
            accent: Colors.orange,
            title: 'USB Debugging Setup',
            body: [
              '1. Enable Developer Options (tap Build number 7 times)',
              '2. Enable "USB debugging"',
              '3. Connect device via USB',
              '4. Accept authorization prompt',
              '5. Choose USB connection type here',
            ],
          ),
          _infoSection(
            icon: Icons.cable,
            accent: Colors.purple,
            title: 'Connection Types',
            body: [
              '• Wi‑Fi: Network connect (IP:5555)',
              '• USB: Via local adb daemon (localhost:5037)',
              '• Custom: Any host:port',
              '• Pairing: Android 11+ wireless pairing workflow',
            ],
          ),
          _infoSection(
            icon: Icons.info_outline,
            accent: Colors.indigo,
            title: 'About ADB',
            body: [
              'Android Debug Bridge (ADB) lets you communicate with devices to install apps, debug, open a shell, forward ports, and more.',
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoSection({
    required IconData icon,
    required Color accent,
    required String title,
    required List<String> body,
    String? footerMonospace,
  }) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: textColor,
        );
    final bodyStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          height: 1.3,
          color: textColor.withOpacity(0.87),
        );
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: accent.withOpacity(.35), width: 1),
      ),
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: accent, width: 4)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: accent),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: titleStyle)),
              ],
            ),
            const SizedBox(height: 8),
            ...body.map((l) => Text(l, style: bodyStyle)),
            if (footerMonospace != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withOpacity(.07),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  footerMonospace,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: _darken(accent),
                  ),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }

  Color _darken(Color c, [double amount = .25]) {
    final hsl = HSLColor.fromColor(c);
    final lightness = (hsl.lightness - amount).clamp(0.0, 1.0);
    return hsl.withLightness(lightness).toColor();
  }

  // Helper methods for connection state display
  Color _getStateColor(ADBConnectionState state) {
    switch (state) {
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

  IconData _getStateIcon(ADBConnectionState state) {
    switch (state) {
      case ADBConnectionState.connected:
        return Icons.check_circle;
      case ADBConnectionState.connecting:
        return Icons.hourglass_empty;
      case ADBConnectionState.failed:
        return Icons.error;
      case ADBConnectionState.disconnected:
        return Icons.cancel;
    }
  }

  String _getStateText(ADBConnectionState state) {
    switch (state) {
      case ADBConnectionState.connected:
        return 'Connected';
      case ADBConnectionState.connecting:
        return 'Connecting...';
      case ADBConnectionState.failed:
        return 'Connection Failed';
      case ADBConnectionState.disconnected:
        return 'Disconnected';
    }
  }
}

// Model class for saved ADB devices
class SavedADBDevice {
  final String name;
  final String host;
  final int port;
  final ADBConnectionType connectionType;

  SavedADBDevice({
    required this.name,
    required this.host,
    required this.port,
    required this.connectionType,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'host': host,
      'port': port,
      'connectionType': connectionType.index,
    };
  }

  factory SavedADBDevice.fromJson(Map<String, dynamic> json) {
    return SavedADBDevice(
      name: json['name'] ?? '',
      host: json['host'] ?? '',
      port: json['port'] ?? 5555,
      connectionType: ADBConnectionType.values[json['connectionType'] ?? 0],
    );
  }
}
