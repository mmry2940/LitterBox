import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
// Bluetooth functionality integrated into ESP32Service
import '../services/esp32_service.dart';
import '../widgets/esp32_scan_test_dialog.dart';

class ESP32Screen extends StatefulWidget {
  const ESP32Screen({super.key});

  @override
  State<ESP32Screen> createState() => _ESP32ScreenState();
}

class _ESP32ScreenState extends State<ESP32Screen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<ESP32Device> _devices = [];
  ESP32Device? _selectedDevice;
  final TextEditingController _replController = TextEditingController();
  final List<String> _replHistory = [];
  final ScrollController _replScrollController = ScrollController();
  String _currentDirectory = '/';
  List<String> _files = [];
  final ESP32Service _esp32Service = ESP32Service();
  StreamSubscription? _devicesSubscription;
  bool _isScanning = false;
  bool _isLoadingDeviceInfo = false;
  bool _isLoadingGPIO = false;
  bool _isLoadingSensors = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _loadDevices();
    _devicesSubscription = _esp32Service.devicesStream.listen((devices) {
      setState(() {
        final connectedDevices = devices.where((d) => d.status == ESP32ConnectionStatus.connected).toList();
        _devices.addAll(connectedDevices.where((d) => !_devices.any((existing) => existing.id == d.id)));
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _replController.dispose();
    _replScrollController.dispose();
    _devicesSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final devicesJson = prefs.getStringList('esp32_devices') ?? [];
    setState(() {
      _devices = devicesJson.map((json) => ESP32Device.fromJson(jsonDecode(json))).toList();
    });
  }

  Future<void> _saveDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final devicesJson = _devices.map((device) => jsonEncode(device.toJson())).toList();
    await prefs.setStringList('esp32_devices', devicesJson);
  }

  Future<void> _scanForDevices() async {
    if (_isScanning) return;
    
    setState(() {
      _isScanning = true;
    });

    try {
      // Show progress dialog with more detailed information
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Scanning for ESP32 Devices'),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('🔍 Scanning local network...'),
              SizedBox(height: 8),
              Text('📱 Looking for Bluetooth devices...'),
              SizedBox(height: 8),
              Text('⏱️ This may take up to 2 minutes.'),
              SizedBox(height: 16),
              Text('💡 Tip: Make sure your ESP32 is powered on and connected to the same network.',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
            ],
          ),
        ),
      );

      int foundDevices = 0;
      
      // Scan for Bluetooth devices
      try {
        final bluetoothDevices = await _esp32Service.scanBluetoothDevices();
        for (final btDeviceMap in bluetoothDevices) {
          final device = ESP32Device(
            id: 'bt_${btDeviceMap['address']}',
            name: btDeviceMap['name'] ?? 'Unknown ESP32',
            connectionType: ESP32ConnectionType.bluetooth,
            address: btDeviceMap['address']!,
          );
          
          if (!_devices.any((d) => d.id == device.id)) {
            setState(() {
              _devices.add(device);
            });
            foundDevices++;
          }
        }
      } catch (e) {
        debugPrint('Bluetooth scan error: $e');
      }

      // Scan for LAN devices
      try {
        final lanDevices = await _esp32Service.scanLANDevices();
        
        for (final lanAddress in lanDevices) {
          final parts = lanAddress.split(':');
          final ip = parts[0];
          final port = int.tryParse(parts[1]) ?? 80;
          
          final device = ESP32Device(
            id: 'lan_$ip:$port',
            name: 'ESP32 ($ip:$port)',
            connectionType: ESP32ConnectionType.lan,
            address: ip,
            port: port,
          );
          
          if (!_devices.any((d) => d.id == device.id)) {
            setState(() {
              _devices.add(device);
            });
            foundDevices++;
          }
        }
      } catch (e) {
        debugPrint('LAN scan error: $e');
      }
      
      // Close progress dialog
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      _saveDevices();
      
      // Show results with appropriate message
      if (mounted) {
        final message = foundDevices > 0 
            ? 'Found $foundDevices ESP32 device${foundDevices == 1 ? '' : 's'}'
            : 'No ESP32 devices found. Try adding a device manually or check your network connection.';
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: foundDevices > 0 ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 4),
            action: foundDevices == 0 ? SnackBarAction(
              label: 'Add Manual',
              onPressed: _addDevice,
            ) : null,
          ),
        );
      }
    } catch (e) {
      // Close progress dialog if still open
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Scan failed: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: _scanForDevices,
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    }
  }

  Future<void> _connectToDevice(ESP32Device device) async {
    if (device.status == ESP32ConnectionStatus.connecting) return;
    
    // Show connecting dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Connecting to ${device.name}...'),
            const SizedBox(height: 8),
            Text(
              device.connectionType == ESP32ConnectionType.bluetooth
                  ? 'Establishing Bluetooth connection'
                  : 'Testing HTTP connection to ${device.address}:${device.port}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
    
    try {
      final success = await _esp32Service.connectDevice(device);
      
      // Close connecting dialog
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      
      if (success) {
        setState(() {
          _selectedDevice = device;
        });
        _saveDevices();
        _loadFiles();
        
        // Listen for REPL data
        final connection = _esp32Service.getConnection(device.id);
        connection?.dataStream.listen((data) {
          if (mounted) {
            setState(() {
              _replHistory.add(data);
            });
            _scrollToBottom();
          }
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Connected to ${device.name}')),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
          
          // Auto-switch to REPL tab on successful connection
          _tabController.animateTo(2);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Failed to connect to ${device.name}')),
                ],
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: 'Retry',
                onPressed: () => _connectToDevice(device),
              ),
            ),
          );
        }
      }
    } catch (e) {
      // Close connecting dialog if still open
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection error: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  void _disconnectDevice(ESP32Device device) {
    _esp32Service.disconnectDevice(device.id);
    setState(() {
      if (_selectedDevice?.id == device.id) {
        _selectedDevice = null;
        // Clear REPL history when disconnecting
        _replHistory.clear();
      }
    });
    _saveDevices();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.link_off, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text('Disconnected from ${device.name}')),
          ],
        ),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'Reconnect',
          onPressed: () => _connectToDevice(device),
        ),
      ),
    );
  }

  Future<void> _loadFiles() async {
    if (_selectedDevice == null) return;
    
    final connection = _esp32Service.getConnection(_selectedDevice!.id);
    if (connection != null) {
      final files = await connection.listFiles(_currentDirectory);
      setState(() {
        _files = files;
      });
    }
  }

  void _addDevice() {
    showDialog(
      context: context,
      builder: (context) => _AddDeviceDialog(
        onAdd: (device) {
          setState(() {
            _devices.add(device);
          });
          _saveDevices();
        },
      ),
    );
  }

  void _editDevice(ESP32Device device) {
    showDialog(
      context: context,
      builder: (context) => _AddDeviceDialog(
        device: device,
        onAdd: (updatedDevice) {
          setState(() {
            final index = _devices.indexWhere((d) => d.id == device.id);
            if (index != -1) {
              _devices[index] = updatedDevice;
            }
          });
          _saveDevices();
        },
      ),
    );
  }

  void _deleteDevice(ESP32Device device) {
    _esp32Service.disconnectDevice(device.id);
    setState(() {
      _devices.removeWhere((d) => d.id == device.id);
      if (_selectedDevice?.id == device.id) {
        _selectedDevice = null;
      }
    });
    _saveDevices();
  }

  Future<void> _sendReplCommand(String command) async {
    if (_selectedDevice == null || command.trim().isEmpty) return;

    final connection = _esp32Service.getConnection(_selectedDevice!.id);
    if (connection != null) {
      setState(() {
        _replHistory.add('>>> $command');
      });
      
      await connection.sendCommand(command);
      _replController.clear();
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_replScrollController.hasClients) {
        _replScrollController.animateTo(
          _replScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ESP32 Manager'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.devices), text: 'Devices'),
            Tab(icon: Icon(Icons.folder), text: 'Files'),
            Tab(icon: Icon(Icons.terminal), text: 'REPL'),
            Tab(icon: Icon(Icons.memory), text: 'Info'),
            Tab(icon: Icon(Icons.settings_input_component), text: 'GPIO'),
            Tab(icon: Icon(Icons.sensors), text: 'Sensors'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDevicesTab(),
          _buildFilesTab(),
          _buildReplTab(),
          _buildDeviceInfoTab(),
          _buildGPIOTab(),
          _buildSensorsTab(),
        ],
      ),
    );
  }

  Widget _buildDevicesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isScanning ? null : _scanForDevices,
                  icon: _isScanning 
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                  label: Text(_isScanning ? 'Scanning...' : 'Scan for Devices'),
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: _addDevice,
                icon: const Icon(Icons.add),
                label: const Text('Add Manual'),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => const ESP32ScanTestDialog(),
                  );
                },
                icon: const Icon(Icons.bug_report),
                label: const Text('Test Scan'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _devices.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.memory, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'No ESP32 devices found',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Scan for devices or add manually',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _devices.length,
                  itemBuilder: (context, index) {
                    final device = _devices[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _getStatusColor(device.status),
                          child: Icon(
                            device.connectionType == ESP32ConnectionType.bluetooth
                                ? Icons.bluetooth
                                : Icons.wifi,
                            color: Colors.white,
                          ),
                        ),
                        title: Text(device.name),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              device.connectionType == ESP32ConnectionType.bluetooth
                                  ? 'Bluetooth: ${device.address}'
                                  : 'LAN: ${device.address}:${device.port}',
                            ),
                            Text(
                              _getStatusText(device.status),
                              style: TextStyle(
                                color: _getStatusColor(device.status),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        trailing: PopupMenuButton(
                          itemBuilder: (context) => [
                            if (device.status == ESP32ConnectionStatus.disconnected)
                              PopupMenuItem(
                                value: 'connect',
                                child: const Row(
                                  children: [
                                    Icon(Icons.link),
                                    SizedBox(width: 8),
                                    Text('Connect'),
                                  ],
                                ),
                              ),
                            if (device.status == ESP32ConnectionStatus.connected)
                              PopupMenuItem(
                                value: 'disconnect',
                                child: const Row(
                                  children: [
                                    Icon(Icons.link_off),
                                    SizedBox(width: 8),
                                    Text('Disconnect'),
                                  ],
                                ),
                              ),
                            PopupMenuItem(
                              value: 'edit',
                              child: const Row(
                                children: [
                                  Icon(Icons.edit),
                                  SizedBox(width: 8),
                                  Text('Edit'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: const Row(
                                children: [
                                  Icon(Icons.delete),
                                  SizedBox(width: 8),
                                  Text('Delete'),
                                ],
                              ),
                            ),
                          ],
                          onSelected: (value) {
                            switch (value) {
                              case 'connect':
                                _connectToDevice(device);
                                break;
                              case 'disconnect':
                                _disconnectDevice(device);
                                break;
                              case 'edit':
                                _editDevice(device);
                                break;
                              case 'delete':
                                _deleteDevice(device);
                                break;
                            }
                          },
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFilesTab() {
    if (_selectedDevice == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_off, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No device connected',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            Text(
              'Connect to an ESP32 device to browse files',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Current Directory: $_currentDirectory',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _loadFiles,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _files.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Loading files...'),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _files.length,
                  itemBuilder: (context, index) {
                    final file = _files[index];
                    final isDirectory = !file.contains('.');
                    
                    return ListTile(
                      leading: Icon(
                        isDirectory ? Icons.folder : Icons.description,
                        color: isDirectory ? Colors.blue : Colors.grey,
                      ),
                      title: Text(file),
                      subtitle: Text(isDirectory ? 'Directory' : 'File'),
                      onTap: () {
                        if (isDirectory) {
                          setState(() {
                            _currentDirectory = '$_currentDirectory/$file'.replaceAll('//', '/');
                          });
                          _loadFiles();
                        }
                      },
                      trailing: !isDirectory
                          ? PopupMenuButton(
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'view',
                                  child: Row(
                                    children: [
                                      Icon(Icons.visibility),
                                      SizedBox(width: 8),
                                      Text('View'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete),
                                      SizedBox(width: 8),
                                      Text('Delete'),
                                    ],
                                  ),
                                ),
                              ],
                              onSelected: (value) async {
                                final connection = _esp32Service.getConnection(_selectedDevice!.id);
                                if (connection != null) {
                                  final filePath = '$_currentDirectory/$file'.replaceAll('//', '/');
                                  
                                  if (value == 'view') {
                                    final content = await connection.readFile(filePath);
                                    if (content != null && mounted) {
                                      showDialog(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: Text('File: $file'),
                                          content: SingleChildScrollView(
                                            child: Text(content),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(context),
                                              child: const Text('Close'),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                  } else if (value == 'delete') {
                                    final confirmed = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Delete File'),
                                        content: Text('Are you sure you want to delete $file?'),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(context, false),
                                            child: const Text('Cancel'),
                                          ),
                                          TextButton(
                                            onPressed: () => Navigator.pop(context, true),
                                            child: const Text('Delete'),
                                          ),
                                        ],
                                      ),
                                    );
                                    
                                    if (confirmed == true) {
                                      final success = await connection.deleteFile(filePath);
                                      if (success) {
                                        _loadFiles();
                                      }
                                    }
                                  }
                                }
                              },
                            )
                          : null,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildReplTab() {
    if (_selectedDevice == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.terminal, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No device connected',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            Text(
              'Connect to an ESP32 device to use REPL',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                _selectedDevice!.connectionType == ESP32ConnectionType.bluetooth
                    ? Icons.bluetooth_connected
                    : Icons.wifi,
                color: Colors.green,
              ),
              const SizedBox(width: 8),
              Text(
                'Connected to ${_selectedDevice!.name}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _replHistory.clear();
                  });
                },
                icon: const Icon(Icons.clear),
                label: const Text('Clear'),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: _replScrollController,
                    itemCount: _replHistory.length,
                    itemBuilder: (context, index) {
                      final line = _replHistory[index];
                      final isCommand = line.startsWith('>>>');
                      return Text(
                        line,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          color: isCommand ? Colors.cyan : Colors.white,
                          fontSize: 14,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text(
                      '>>> ',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: Colors.cyan,
                        fontSize: 14,
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _replController,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          color: Colors.white,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Enter Python command...',
                          hintStyle: TextStyle(color: Colors.grey),
                        ),
                        onSubmitted: _sendReplCommand,
                      ),
                    ),
                    IconButton(
                      onPressed: () => _sendReplCommand(_replController.text),
                      icon: const Icon(Icons.send, color: Colors.cyan),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Color _getStatusColor(ESP32ConnectionStatus status) {
    switch (status) {
      case ESP32ConnectionStatus.connected:
        return Colors.green;
      case ESP32ConnectionStatus.connecting:
        return Colors.orange;
      case ESP32ConnectionStatus.error:
        return Colors.red;
      case ESP32ConnectionStatus.disconnected:
        return Colors.grey;
    }
  }

  String _getStatusText(ESP32ConnectionStatus status) {
    switch (status) {
      case ESP32ConnectionStatus.connected:
        return 'Connected';
      case ESP32ConnectionStatus.connecting:
        return 'Connecting...';
      case ESP32ConnectionStatus.error:
        return 'Error';
      case ESP32ConnectionStatus.disconnected:
        return 'Disconnected';
    }
  }

  // New Advanced Tab Builders

  Widget _buildDeviceInfoTab() {
    if (_selectedDevice == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No device connected',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            Text(
              'Connect to an ESP32 device to view information',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshDeviceInfo,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoCard('Device Information', [
                _buildInfoRow('Name', _selectedDevice!.name),
                _buildInfoRow('Address', '${_selectedDevice!.address}:${_selectedDevice!.port ?? 'N/A'}'),
                _buildInfoRow('Connection', _selectedDevice!.connectionType.name.toUpperCase()),
                _buildInfoRow('Status', _getStatusText(_selectedDevice!.status)),
                if (_selectedDevice!.firmwareVersion != null)
                  _buildInfoRow('Firmware', _selectedDevice!.firmwareVersion!),
                if (_selectedDevice!.chipModel != null)
                  _buildInfoRow('Chip Model', _selectedDevice!.chipModel!),
                if (_selectedDevice!.macAddress != null)
                  _buildInfoRow('MAC Address', _selectedDevice!.macAddress!),
              ]),
              const SizedBox(height: 16),
              _buildInfoCard('Memory Information', [
                if (_selectedDevice!.freeMemory != null)
                  _buildInfoRow('Free Memory', '${_selectedDevice!.freeMemory} bytes'),
                if (_selectedDevice!.totalMemory != null)
                  _buildInfoRow('Total Memory', '${_selectedDevice!.totalMemory} bytes'),
                if (_selectedDevice!.cpuFrequency != null)
                  _buildInfoRow('CPU Frequency', '${_selectedDevice!.cpuFrequency} MHz'),
              ]),
              const SizedBox(height: 16),
              _buildInfoCard('Available Libraries', [
                if (_selectedDevice!.availableLibraries != null)
                  ...(_selectedDevice!.availableLibraries!.take(10).map((lib) => 
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.library_books, size: 16),
                      title: Text(lib, style: const TextStyle(fontSize: 14)),
                    )
                  ).toList())
                else
                  const ListTile(
                    dense: true,
                    title: Text('Loading libraries...'),
                  ),
              ]),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isLoadingDeviceInfo ? null : _refreshDeviceInfo,
                      icon: _isLoadingDeviceInfo 
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      label: Text(_isLoadingDeviceInfo ? 'Loading...' : 'Refresh Info'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _softResetDevice,
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Soft Reset'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGPIOTab() {
    if (_selectedDevice == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.settings_input_component, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No device connected',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            Text(
              'Connect to an ESP32 device to control GPIO',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    final gpioStates = _selectedDevice!.gpioStates ?? {};
    final gpioPins = [0, 2, 4, 5, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23, 25, 26, 27, 32, 33];

    return RefreshIndicator(
      onRefresh: _refreshGPIOStates,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.settings_input_component),
                const SizedBox(width: 8),
                const Text(
                  'GPIO Control',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _isLoadingGPIO ? null : _refreshGPIOStates,
                  icon: _isLoadingGPIO 
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(_isLoadingGPIO ? 'Loading...' : 'Refresh'),
                ),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 1.2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: gpioPins.length,
              itemBuilder: (context, index) {
                final pin = gpioPins[index];
                final isHigh = gpioStates[pin.toString()] ?? false;
                
                return Card(
                  child: InkWell(
                    onTap: () => _toggleGPIO(pin, !isHigh),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'GPIO $pin',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isHigh ? Colors.green : Colors.red,
                            ),
                            child: Icon(
                              isHigh ? Icons.flash_on : Icons.flash_off,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isHigh ? 'HIGH' : 'LOW',
                            style: TextStyle(
                              fontSize: 12,
                              color: isHigh ? Colors.green : Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSensorsTab() {
    if (_selectedDevice == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sensors, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No device connected',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            Text(
              'Connect to an ESP32 device to read sensors',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    final sensorData = _selectedDevice!.sensorData ?? {};

    return RefreshIndicator(
      onRefresh: _refreshSensorData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.sensors),
                  const SizedBox(width: 8),
                  const Text(
                    'Sensor Readings',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: _isLoadingSensors ? null : _refreshSensorData,
                    icon: _isLoadingSensors 
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: Text(_isLoadingSensors ? 'Loading...' : 'Refresh'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (sensorData.isNotEmpty) ...[
                _buildSensorCard('Temperature', sensorData['temperature_raw'], 'ADC Units', Icons.thermostat),
                const SizedBox(height: 12),
                _buildSensorCard('Light Level', sensorData['light_raw'], 'ADC Units', Icons.light_mode),
                const SizedBox(height: 12),
                _buildSensorCard('Hall Sensor', sensorData['hall_sensor'], 'ADC Units', Icons.explore),
                const SizedBox(height: 12),
                _buildSensorCard('Uptime', sensorData['uptime'], 'ms', Icons.timer),
              ] else ...[
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Icon(Icons.info_outline, size: 48, color: Colors.grey),
                        SizedBox(height: 8),
                        Text('No sensor data available'),
                        Text('Make sure sensors are connected to the ESP32'),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'Sensor Information:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('• Temperature: Connect sensor to GPIO 36'),
                      Text('• Light (LDR): Connect to GPIO 34'),
                      Text('• Hall Sensor: Built-in ESP32 sensor'),
                      Text('• Custom sensors can be added via GPIO pins'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper Methods for Advanced Features

  Widget _buildInfoCard(String title, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSensorCard(String name, dynamic value, String unit, IconData icon) {
    final displayValue = value?.toString() ?? 'N/A';
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(icon, size: 32, color: Colors.blue),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '$displayValue $unit',
                    style: const TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Advanced Feature Methods

  Future<void> _refreshDeviceInfo() async {
    if (_selectedDevice == null || _isLoadingDeviceInfo) return;
    
    setState(() {
      _isLoadingDeviceInfo = true;
    });
    
    try {
      final connection = _esp32Service.getConnection(_selectedDevice!.id);
      if (connection != null) {
        final deviceInfo = await connection.getDeviceInfo();
        if (deviceInfo != null && mounted) {
          setState(() {
            _selectedDevice!.firmwareVersion = deviceInfo['firmware']?.toString();
            _selectedDevice!.chipModel = deviceInfo['platform']?.toString();
            _selectedDevice!.macAddress = deviceInfo['mac']?.toString();
            _selectedDevice!.freeMemory = deviceInfo['memory_free'];
            _selectedDevice!.totalMemory = (deviceInfo['memory_free'] ?? 0) + (deviceInfo['memory_alloc'] ?? 0);
            _selectedDevice!.cpuFrequency = deviceInfo['freq']?.toDouble();
          });
        }
        
        final libraries = await connection.getAvailableLibraries();
        if (libraries != null && mounted) {
          setState(() {
            _selectedDevice!.availableLibraries = libraries;
          });
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Device information updated'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to refresh device info: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingDeviceInfo = false;
        });
      }
    }
  }

  Future<void> _refreshGPIOStates() async {
    if (_selectedDevice == null || _isLoadingGPIO) return;
    
    setState(() {
      _isLoadingGPIO = true;
    });
    
    try {
      final connection = _esp32Service.getConnection(_selectedDevice!.id);
      if (connection != null) {
        final gpioStates = await connection.getGPIOStates();
        if (gpioStates != null && mounted) {
          setState(() {
            _selectedDevice!.gpioStates = gpioStates.map((k, v) => MapEntry(k, v));
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('GPIO states updated'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to refresh GPIO states: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingGPIO = false;
        });
      }
    }
  }

  Future<void> _refreshSensorData() async {
    if (_selectedDevice == null || _isLoadingSensors) return;
    
    setState(() {
      _isLoadingSensors = true;
    });
    
    try {
      final connection = _esp32Service.getConnection(_selectedDevice!.id);
      if (connection != null) {
        final sensorData = await connection.getSensorData();
        if (sensorData != null && mounted) {
          setState(() {
            _selectedDevice!.sensorData = sensorData;
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sensor data updated'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to refresh sensor data: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingSensors = false;
        });
      }
    }
  }

  Future<void> _toggleGPIO(int pin, bool value) async {
    if (_selectedDevice == null) return;
    
    // Show immediate feedback
    setState(() {
      _selectedDevice!.gpioStates ??= {};
      _selectedDevice!.gpioStates![pin.toString()] = value;
    });
    
    try {
      final connection = _esp32Service.getConnection(_selectedDevice!.id);
      if (connection != null) {
        final success = await connection.setGPIO(pin, value);
        
        if (success) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(
                      value ? Icons.flash_on : Icons.flash_off,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 8),
                    Text('GPIO $pin set to ${value ? 'HIGH' : 'LOW'}'),
                  ],
                ),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } else {
          // Revert the optimistic update
          setState(() {
            _selectedDevice!.gpioStates![pin.toString()] = !value;
          });
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.error, color: Colors.white),
                    const SizedBox(width: 8),
                    Text('Failed to set GPIO $pin'),
                  ],
                ),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 3),
                action: SnackBarAction(
                  label: 'Retry',
                  onPressed: () => _toggleGPIO(pin, value),
                ),
              ),
            );
          }
        }
      }
    } catch (e) {
      // Revert the optimistic update
      setState(() {
        _selectedDevice!.gpioStates![pin.toString()] = !value;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('GPIO error: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _softResetDevice() async {
    if (_selectedDevice == null) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Soft Reset Device'),
        content: const Text('This will restart the ESP32. Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      final connection = _esp32Service.getConnection(_selectedDevice!.id);
      if (connection != null) {
        await connection.stopScript();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Device reset command sent'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }
}

class _AddDeviceDialog extends StatefulWidget {
  final ESP32Device? device;
  final Function(ESP32Device) onAdd;

  const _AddDeviceDialog({
    this.device,
    required this.onAdd,
  });

  @override
  State<_AddDeviceDialog> createState() => _AddDeviceDialogState();
}

class _AddDeviceDialogState extends State<_AddDeviceDialog> {
  late TextEditingController _nameController;
  late TextEditingController _addressController;
  late TextEditingController _portController;
  late TextEditingController _passwordController;
  ESP32ConnectionType _connectionType = ESP32ConnectionType.lan;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.device?.name ?? '');
    _addressController = TextEditingController(text: widget.device?.address ?? '');
    _portController = TextEditingController(text: widget.device?.port?.toString() ?? '80');
    _passwordController = TextEditingController(text: widget.device?.password ?? '');
    _connectionType = widget.device?.connectionType ?? ESP32ConnectionType.lan;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _portController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.device == null ? 'Add ESP32 Device' : 'Edit ESP32 Device'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Device Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<ESP32ConnectionType>(
              value: _connectionType,
              decoration: const InputDecoration(
                labelText: 'Connection Type',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: ESP32ConnectionType.lan,
                  child: Row(
                    children: [
                      Icon(Icons.wifi),
                      SizedBox(width: 8),
                      Text('LAN/WiFi'),
                    ],
                  ),
                ),
                DropdownMenuItem(
                  value: ESP32ConnectionType.bluetooth,
                  child: Row(
                    children: [
                      Icon(Icons.bluetooth),
                      SizedBox(width: 8),
                      Text('Bluetooth'),
                    ],
                  ),
                ),
              ],
              onChanged: (value) {
                setState(() {
                  _connectionType = value!;
                });
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _addressController,
              decoration: InputDecoration(
                labelText: _connectionType == ESP32ConnectionType.bluetooth 
                    ? 'Bluetooth Address' 
                    : 'IP Address',
                border: const OutlineInputBorder(),
                hintText: _connectionType == ESP32ConnectionType.bluetooth 
                    ? '00:11:22:33:44:55' 
                    : '192.168.1.100',
              ),
            ),
            if (_connectionType == ESP32ConnectionType.lan) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _portController,
                decoration: const InputDecoration(
                  labelText: 'Port',
                  border: OutlineInputBorder(),
                  hintText: '80',
                ),
                keyboardType: TextInputType.number,
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'Password (Optional)',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_nameController.text.isNotEmpty && _addressController.text.isNotEmpty) {
              final device = ESP32Device(
                id: widget.device?.id ?? 
                    '${_connectionType.name}_${_addressController.text}_${DateTime.now().millisecondsSinceEpoch}',
                name: _nameController.text,
                connectionType: _connectionType,
                address: _addressController.text,
                port: _connectionType == ESP32ConnectionType.lan 
                    ? int.tryParse(_portController.text) ?? 80 
                    : null,
                password: _passwordController.text.isEmpty ? null : _passwordController.text,
              );
              
              widget.onAdd(device);
              Navigator.pop(context);
            }
          },
          child: Text(widget.device == null ? 'Add' : 'Update'),
        ),
      ],
    );
  }
}