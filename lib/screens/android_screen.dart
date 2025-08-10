import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../adb_client.dart';

class AndroidScreen extends StatefulWidget {
  const AndroidScreen({super.key});

  @override
  State<AndroidScreen> createState() => _AndroidScreenState();
}

class _AndroidScreenState extends State<AndroidScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  late ADBClientManager _adbClient;

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _adbClient = ADBClientManager();
    _loadSavedDevices();

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

  @override
  void dispose() {
    _tabController.dispose();
    _adbClient.dispose();
    _hostController.dispose();
    _portController.dispose();
    _commandController.dispose();
    _pairingPortController.dispose();
    _pairingCodeController.dispose();
    _outputScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final devicesJson = prefs.getStringList('adb_devices') ?? [];
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

    final success = await _adbClient.pairDevice(host, pairingPort, pairingCode);

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
        title: const Text('Android ADB Console'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.link), text: 'Connect'),
            Tab(icon: Icon(Icons.terminal), text: 'Console'),
            Tab(icon: Icon(Icons.apps), text: 'Commands'),
            Tab(icon: Icon(Icons.info), text: 'Info'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildConnectionTab(),
          _buildConsoleTab(),
          _buildCommandsTab(),
          _buildInfoTab(),
        ],
      ),
    );
  }

  Widget _buildConnectionTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
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

          // Connection Type Selector
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
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                            Text('Type: ${device.connectionType.displayName}'),
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
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),

                  if (_connectionType != ADBConnectionType.usb) ...[
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
                        if (_connectionType != ADBConnectionType.pairing) ...[
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
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Pairing-specific fields
                    if (_connectionType == ADBConnectionType.pairing) ...[
                      Row(
                        children: [
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
                        ],
                      ),
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
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Icon(
                                  _connectionType == ADBConnectionType.pairing
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
                          onPressed: _adbClient.currentState ==
                                  ADBConnectionState.connected
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConsoleTab() {
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

        // Command Input
        Container(
          padding: const EdgeInsets.all(8),
          color: Colors.grey[200],
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commandController,
                  decoration: const InputDecoration(
                    hintText: 'Enter ADB command...',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onSubmitted: (_) => _executeCommand(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed:
                    _adbClient.currentState == ADBConnectionState.connected
                        ? _executeCommand
                        : null,
                child: const Text('Execute'),
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
                  }
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
                ],
              ),
            ],
          ),
        ),
      ],
    );
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
                  _tabController.animateTo(1); // Switch to console tab
                },
              );
            }).toList(),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildInfoTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          const Text(
            'Android ADB Information',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'About ADB',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Android Debug Bridge (ADB) is a versatile command-line tool that lets you communicate with a device. '
                    'The ADB command facilitates a variety of device actions, such as installing and debugging apps.',
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Connection Types',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '• Wi-Fi: Connect to Android devices over network (requires ADB over network enabled)\n'
                    '• USB: Connect via USB cable (requires ADB daemon running)\n'
                    '• Custom: Specify custom IP and port for connection',
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Setup Instructions',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '1. Enable Developer Options on your Android device\n'
                    '2. Enable USB Debugging in Developer Options\n'
                    '3. For Wi-Fi: Enable "ADB over network" or use "adb tcpip 5555"\n'
                    '4. Connect using the device IP address and port 5555',
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Security Note',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'ADB provides powerful access to your Android device. Only connect to trusted devices '
                    'and networks. The first connection may require authorization on the target device.',
                    style: TextStyle(color: Colors.red),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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
