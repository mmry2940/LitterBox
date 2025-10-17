import 'package:flutter/material.dart';
import 'package:dartssh2/dartssh2.dart';
import '../main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:network_info_plus/network_info_plus.dart';
import 'device_screen.dart';
import 'adb_screen_refactored.dart';
import 'vnc_screen.dart';
import 'rdp_screen.dart';
import 'esp32_screen.dart';
import '_host_tile_with_retry.dart';
import '../network_init.dart';
import '../isolate_scanner.dart';
import '../widgets/enhanced_device_card.dart';
import '../models/device_status.dart';

// Device List Screen for Drawer navigation
class DeviceListScreen extends StatelessWidget {
  final List<Map<String, dynamic>> devices;
  final Set<String> favoriteDeviceHosts;
  final Function(Map<String, dynamic>)? onDeviceTap;
  const DeviceListScreen({
    super.key,
    required this.devices,
    required this.favoriteDeviceHosts,
    this.onDeviceTap,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Devices List")),
      body: devices.isEmpty
          ? const Center(child: Text('No devices added.'))
          : ListView.builder(
              itemCount: devices.length,
              itemBuilder: (context, index) {
                final device = devices[index];
                final isFavorite = favoriteDeviceHosts.contains(device['host']);
                return ListTile(
                  title: Text(
                    (device['name']?.isNotEmpty ?? false)
                        ? device['name']!
                        : '${device['username']}@${device['host']}:${device['port']}',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  leading: Icon(
                    isFavorite ? Icons.star : Icons.devices,
                    color: isFavorite ? Colors.amber : null,
                  ),
                  onTap: () {
                    if (onDeviceTap != null) onDeviceTap!(device);
                  },
                );
              },
            ),
    );
  }
}

// LiteHost is a lightweight stand-in for ActiveHost when using isolate scan
class LiteHost {
  final String address;
  final Duration? responseTime;
  LiteHost(this.address, {this.responseTime});
  // Mimic API used by HostTileWithRetry
  Future<String?> get hostName async {
    try {
      final list = await InternetAddress.lookup(address);
      if (list.isNotEmpty) return list.first.host;
    } catch (_) {}
    return null;
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  bool _multiSelectMode = false;
  final Set<int> _selectedDeviceIndexes = {};
  String _deviceSearchQuery = '';
  String _selectedGroupFilter = 'All';
  final Map<String, DeviceStatus> _deviceStatuses = {};

  final Set<String> _favoriteDeviceHosts = {};
  // Customizable dashboard tiles
  List<Map<String, dynamic>> _dashboardTiles = [];
  bool _customizeMode = false;

  Future<void> _loadDashboardTiles() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('dashboard_tiles');
    if (jsonStr != null) {
      final List<dynamic> list = json.decode(jsonStr);
      setState(() {
        _dashboardTiles = list.cast<Map<String, dynamic>>().toList();
      });
    } else {
      // Default tiles
      setState(() {
        _dashboardTiles = [
          {
            'key': 'devices',
            'label': 'Devices List',
            'icon': Icons.devices.codePoint,
            'visible': true
          },
          {
            'key': 'android',
            'label': 'Android',
            'icon': Icons.android.codePoint,
            'visible': true
          },
          {
            'key': 'vnc',
            'label': 'VNC',
            'icon': Icons.desktop_windows.codePoint,
            'visible': true
          },
          {
            'key': 'rdp',
            'label': 'RDP',
            'icon': Icons.computer.codePoint,
            'visible': true
          },
          {
            'key': 'other',
            'label': 'Other',
            'icon': Icons.more_horiz.codePoint,
            'visible': true
          },
        ];
      });
    }
  }

  Future<void> _saveDashboardTiles() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dashboard_tiles', json.encode(_dashboardTiles));
  }

  List<Map<String, dynamic>> _devices = [];

  @override
  void initState() {
    super.initState();
    _loadDevices();
    _loadDashboardTiles();
    _loadFavoriteDevices();
  }

  Future<void> _loadFavoriteDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('favorite_devices');
    if (jsonStr != null) {
      final List<dynamic> list = json.decode(jsonStr);
      setState(() {
        _favoriteDeviceHosts.clear();
        _favoriteDeviceHosts.addAll(list.cast<String>());
      });
    }
  }

  Future<void> _loadDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('devices');
    if (jsonStr != null) {
      final List<dynamic> list = json.decode(jsonStr);
      setState(() {
        _devices = list
            .cast<Map<String, dynamic>>()
            .map((e) => e.map((k, v) => MapEntry(k, v.toString())))
            .toList();
      });
    }

    // Add a test localhost device as a reference
    setState(() {
      _devices.add({
        'name': 'Localhost',
        'host': '127.0.0.1',
        'port': '22',
        'username': 'user',
        'password': 'password',
        'group': 'Local',
      });
    });

    // Check device statuses
    _checkAllDeviceStatuses();
  }

  Future<void> _saveDevices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('devices', json.encode(_devices));
      await prefs.setString(
          'favorite_devices', json.encode(_favoriteDeviceHosts.toList()));
    } catch (e) {
      _showError('Failed to save devices: $e');
    }
  }

  Future<void> _checkDeviceStatus(String host, String port) async {
    try {
      final stopwatch = Stopwatch()..start();
      final socket = await Socket.connect(host, int.parse(port))
          .timeout(const Duration(seconds: 5));
      stopwatch.stop();
      socket.destroy();

      setState(() {
        _deviceStatuses[host] = DeviceStatus(
          isOnline: true,
          pingMs: stopwatch.elapsedMilliseconds,
          lastChecked: DateTime.now(),
        );
      });
    } catch (e) {
      setState(() {
        _deviceStatuses[host] = DeviceStatus(
          isOnline: false,
          lastChecked: DateTime.now(),
        );
      });
    }
  }

  Future<void> _checkAllDeviceStatuses() async {
    for (final device in _devices) {
      final host = device['host'];
      final port = device['port'] ?? '22';
      if (host != null) {
        await _checkDeviceStatus(host, port);
        // Small delay to avoid overwhelming the network
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
  }

  void _showQuickActions(BuildContext context, Map<String, dynamic> device) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Quick Actions - ${device['name'] ?? device['host']}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildQuickActionButton(
                  icon: Icons.wifi,
                  label: 'Ping',
                  onTap: () => _pingDevice(device),
                ),
                _buildQuickActionButton(
                  icon: Icons.refresh,
                  label: 'Restart',
                  onTap: () => _restartDevice(device),
                ),
                _buildQuickActionButton(
                  icon: Icons.power_off,
                  label: 'Shutdown',
                  onTap: () => _shutdownDevice(device),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildQuickActionButton(
                  icon: Icons.edit,
                  label: 'Edit',
                  onTap: () =>
                      _showDeviceSheet(editIndex: _devices.indexOf(device)),
                ),
                _buildQuickActionButton(
                  icon: Icons.copy,
                  label: 'Duplicate',
                  onTap: () => _duplicateDevice(device),
                ),
                _buildQuickActionButton(
                  icon: Icons.delete,
                  label: 'Delete',
                  color: Colors.red,
                  onTap: () => _removeDevice(_devices.indexOf(device)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color ?? Theme.of(context).primaryColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Future<void> _pingDevice(Map<String, dynamic> device) async {
    final host = device['host'];
    if (host == null) return;

    try {
      await _checkDeviceStatus(host, device['port'] ?? '22');
      final status = _deviceStatuses[host];
      if (status?.isOnline == true) {
        _showError('Device is online (${status?.pingMs}ms)');
      } else {
        _showError('Device is offline');
      }
    } catch (e) {
      _showError('Ping failed: $e');
    }
  }

  Future<void> _restartDevice(Map<String, dynamic> device) async {
    // This would require SSH connection and running reboot command
    _showError('Restart functionality requires SSH connection');
  }

  Future<void> _shutdownDevice(Map<String, dynamic> device) async {
    // This would require SSH connection and running shutdown command
    _showError('Shutdown functionality requires SSH connection');
  }

  void _duplicateDevice(Map<String, dynamic> device) {
    final duplicatedDevice = Map<String, dynamic>.from(device);
    duplicatedDevice['name'] = '${device['name'] ?? device['host']} (Copy)';
    setState(() {
      _devices.add(duplicatedDevice);
    });
    _saveDevices();
    _showError('Device duplicated');
  }

  void _removeDevice(int index) async {
    try {
      setState(() {
        _devices.removeAt(index);
      });
      await _saveDevices();
    } catch (e) {
      _showError('Failed to remove device: $e');
    }
  }

  void _scanForDevices(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        return _ScanDialog(
          onDeviceSelected: _addDeviceFromScan,
        );
      },
    );
  }

  void _addDeviceFromScan(String ip) async {
    final nameController = TextEditingController();
    final portController = TextEditingController(text: '22');
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    bool connecting = false;
    String status = '';
    String? errorHost;
    String? errorPort;
    String? errorUsername;
    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> connectAndSave() async {
              // Validation
              setModalState(() {
                errorHost = ip.isEmpty ? 'Host is required.' : null;
                errorPort = int.tryParse(portController.text) == null
                    ? 'Port must be a number.'
                    : null;
                errorUsername = usernameController.text.isEmpty
                    ? 'Username is required.'
                    : null;
              });
              if (errorHost != null ||
                  errorPort != null ||
                  errorUsername != null) {
                return;
              }
              setModalState(() {
                connecting = true;
                status = 'Connecting...';
              });
              try {
                SSHClient(
                  await SSHSocket.connect(
                      ip, int.tryParse(portController.text) ?? 22),
                  username: usernameController.text,
                  onPasswordRequest: () => passwordController.text,
                );
                status = 'Connected!';
                setState(() {
                  final device = {
                    'name': nameController.text,
                    'host': ip,
                    'port': portController.text,
                    'username': usernameController.text,
                    'password': passwordController.text,
                  };
                  _devices.add(device);
                });
                await _saveDevices();
                await Future.delayed(const Duration(milliseconds: 500));
                Navigator.pop(ctx);
              } catch (e) {
                setModalState(() {
                  status = 'Connection failed: $e';
                });
              } finally {
                setModalState(() {
                  connecting = false;
                });
              }
            }

            return AlertDialog(
              title: const Text('Add Device'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('IP: $ip'),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Device Name (optional)',
                      ),
                    ),
                    TextField(
                      controller: portController,
                      decoration: InputDecoration(
                        labelText: 'Port',
                        errorText: errorPort,
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    TextField(
                      controller: usernameController,
                      decoration: InputDecoration(
                        labelText: 'Username',
                        errorText: errorUsername,
                      ),
                    ),
                    TextField(
                      controller: passwordController,
                      decoration: const InputDecoration(labelText: 'Password'),
                      obscureText: true,
                    ),
                    if (errorHost != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(errorHost!,
                            style: const TextStyle(color: Colors.red)),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: connecting ? null : connectAndSave,
                          child: connecting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Connect & Add'),
                        ),
                        const SizedBox(width: 16),
                        Text(status),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showDeviceSheet({int? editIndex}) {
    final isEdit = editIndex != null;
    final nameController =
        TextEditingController(text: isEdit ? _devices[editIndex]['name'] : '');
    final hostController =
        TextEditingController(text: isEdit ? _devices[editIndex]['host'] : '');
    final portController = TextEditingController(
        text: isEdit ? _devices[editIndex]['port'] ?? '22' : '22');
    final usernameController = TextEditingController(
        text: isEdit ? _devices[editIndex]['username'] : '');
    final passwordController = TextEditingController(
        text: isEdit ? _devices[editIndex]['password'] : '');
    String selectedGroup =
        isEdit ? _devices[editIndex]['group'] ?? 'Default' : 'Default';
    bool connecting = false;
    String status = '';
    String? errorHost;
    String? errorPort;
    String? errorUsername;
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> connectAndSave() async {
              // Validation
              setModalState(() {
                errorHost =
                    hostController.text.isEmpty ? 'Host is required.' : null;
                errorPort = int.tryParse(portController.text) == null
                    ? 'Port must be a number.'
                    : null;
                errorUsername = usernameController.text.isEmpty
                    ? 'Username is required.'
                    : null;
              });
              if (errorHost != null ||
                  errorPort != null ||
                  errorUsername != null) {
                return;
              }
              setModalState(() {
                connecting = true;
                status = 'Connecting...';
              });
              try {
                SSHClient(
                  await SSHSocket.connect(hostController.text,
                      int.tryParse(portController.text) ?? 22),
                  username: usernameController.text,
                  onPasswordRequest: () => passwordController.text,
                );
                setState(() {
                  final device = {
                    'name': nameController.text,
                    'host': hostController.text,
                    'port': portController.text,
                    'username': usernameController.text,
                    'password': passwordController.text,
                    'group': selectedGroup,
                  };
                  if (isEdit) {
                    _devices[editIndex] = device;
                  } else {
                    _devices.add(device);
                  }
                });
                await _saveDevices();
                await Future.delayed(const Duration(milliseconds: 500));
                Navigator.pop(ctx);
              } catch (e) {
                setModalState(() {
                  status = 'Connection failed: $e';
                });
                _showError('Failed to save device: $e');
              } finally {
                setModalState(() {
                  connecting = false;
                });
              }
            }

            return AlertDialog(
              title: Text(isEdit ? 'Edit Device' : 'Add Device'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Device Name (optional)',
                      ),
                    ),
                    TextField(
                      controller: hostController,
                      decoration: InputDecoration(
                        labelText: 'Host',
                        errorText: errorHost,
                      ),
                    ),
                    TextField(
                      controller: portController,
                      decoration: InputDecoration(
                        labelText: 'Port',
                        errorText: errorPort,
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    TextField(
                      controller: usernameController,
                      decoration: InputDecoration(
                        labelText: 'Username',
                        errorText: errorUsername,
                      ),
                    ),
                    TextField(
                      controller: passwordController,
                      decoration: const InputDecoration(labelText: 'Password'),
                      obscureText: true,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedGroup,
                      decoration: const InputDecoration(
                        labelText: 'Device Group',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'Default', child: Text('Default')),
                        DropdownMenuItem(value: 'Work', child: Text('Work')),
                        DropdownMenuItem(value: 'Home', child: Text('Home')),
                        DropdownMenuItem(
                            value: 'Servers', child: Text('Servers')),
                        DropdownMenuItem(
                            value: 'Development', child: Text('Development')),
                        DropdownMenuItem(value: 'Local', child: Text('Local')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          selectedGroup = value;
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: connecting ? null : connectAndSave,
                          child: connecting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(
                                  isEdit ? 'Connect & Save' : 'Connect & Add'),
                        ),
                        const SizedBox(width: 16),
                        Text(status),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices'),
        actions: [
          Semantics(
            label: 'Refresh device statuses',
            button: true,
            child: IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh Status',
              onPressed: _checkAllDeviceStatuses,
            ),
          ),
          Semantics(
            label: _customizeMode
                ? 'Done Customizing Dashboard'
                : 'Customize Dashboard',
            button: true,
            child: IconButton(
              icon: Icon(_customizeMode ? Icons.check : Icons.tune),
              tooltip:
                  _customizeMode ? 'Done Customizing' : 'Customize Dashboard',
              onPressed: () {
                setState(() {
                  _customizeMode = !_customizeMode;
                  if (!_customizeMode) _saveDashboardTiles();
                });
              },
            ),
          ),
          Semantics(
            label: _multiSelectMode
                ? 'Exit Multi-Select Mode'
                : 'Enable Multi-Select Mode',
            button: true,
            child: IconButton(
              icon: Icon(_multiSelectMode ? Icons.close : Icons.select_all),
              tooltip: _multiSelectMode
                  ? 'Exit Multi-Select'
                  : 'Multi-Select Devices',
              onPressed: () {
                setState(() {
                  _multiSelectMode = !_multiSelectMode;
                  if (!_multiSelectMode) _selectedDeviceIndexes.clear();
                });
              },
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ...dashboard tiles removed...
          // Device search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Search Devices',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) {
                setState(() {
                  _deviceSearchQuery = v.trim();
                });
              },
            ),
          ),
          // Device group filter
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: DropdownButtonFormField<String>(
              initialValue: _selectedGroupFilter,
              decoration: const InputDecoration(
                labelText: 'Filter by Group',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.filter_list),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 'All', child: Text('All Groups')),
                DropdownMenuItem(value: 'Default', child: Text('Default')),
                DropdownMenuItem(value: 'Work', child: Text('Work')),
                DropdownMenuItem(value: 'Home', child: Text('Home')),
                DropdownMenuItem(value: 'Servers', child: Text('Servers')),
                DropdownMenuItem(
                    value: 'Development', child: Text('Development')),
                DropdownMenuItem(value: 'Local', child: Text('Local')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedGroupFilter = value;
                  });
                }
              },
            ),
          ),
          // Devices list and batch actions
          if (_multiSelectMode && _selectedDeviceIndexes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Semantics(
                    label: 'Delete selected devices',
                    button: true,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.delete),
                      label: const Text('Delete Selected'),
                      style:
                          ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: () {
                        setState(() {
                          final indexes = _selectedDeviceIndexes.toList()
                            ..sort((a, b) => b.compareTo(a));
                          for (final idx in indexes) {
                            _devices.removeAt(idx);
                          }
                          _selectedDeviceIndexes.clear();
                          _saveDevices();
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Semantics(
                    label: 'Pin selected devices to favorites',
                    button: true,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.star),
                      label: const Text('Pin Selected'),
                      onPressed: () {
                        setState(() {
                          for (final idx in _selectedDeviceIndexes) {
                            final host = _devices[idx]['host'];
                            if (host != null) _favoriteDeviceHosts.add(host);
                          }
                          _saveDevices();
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    label: 'Unpin selected devices from favorites',
                    button: true,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.star_border),
                      label: const Text('Unpin Selected'),
                      onPressed: () {
                        setState(() {
                          for (final idx in _selectedDeviceIndexes) {
                            final host = _devices[idx]['host'];
                            if (host != null) _favoriteDeviceHosts.remove(host);
                          }
                          _saveDevices();
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Builder(
              builder: (context) {
                // Efficient filtering for large lists
                final filteredDevices = <Map<String, dynamic>>[];
                final filteredIndexes = <int>[];
                for (int i = 0; i < _devices.length; i++) {
                  final device = _devices[i];
                  if (_deviceSearchQuery.isNotEmpty) {
                    final searchLower = _deviceSearchQuery.toLowerCase();
                    final name = (device['name'] ?? '').toLowerCase();
                    final host = (device['host'] ?? '').toLowerCase();
                    final username = (device['username'] ?? '').toLowerCase();
                    if (!(name.contains(searchLower) ||
                        host.contains(searchLower) ||
                        username.contains(searchLower))) {
                      continue;
                    }
                  }
                  if (_selectedGroupFilter != 'All' &&
                      device['group'] != _selectedGroupFilter) {
                    continue;
                  }
                  filteredDevices.add(device);
                  filteredIndexes.add(i);
                }
                if (filteredDevices.isEmpty) {
                  return const Center(child: Text('No devices added.'));
                }
                return ListView.builder(
                  itemCount: filteredDevices.length,
                  padding: const EdgeInsets.all(8),
                  itemBuilder: (context, idx) {
                    final device = filteredDevices[idx];
                    final index = filteredIndexes[idx];
                    final isFavorite =
                        _favoriteDeviceHosts.contains(device['host']);
                    final isSelected = _selectedDeviceIndexes.contains(index);
                    final status = _deviceStatuses[device['host']];

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: EnhancedDeviceCard(
                        device: device,
                        isFavorite: isFavorite,
                        isSelected: isSelected,
                        status: status,
                        multiSelectMode: _multiSelectMode,
                        onTap: !_multiSelectMode
                            ? () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => DeviceScreen(
                                      device: device,
                                      initialTab:
                                          5, // Show Misc tab (overview cards)
                                    ),
                                  ),
                                );
                              }
                            : () {
                                setState(() {
                                  if (isSelected) {
                                    _selectedDeviceIndexes.remove(index);
                                  } else {
                                    _selectedDeviceIndexes.add(index);
                                  }
                                });
                              },
                        onLongPress: !_multiSelectMode
                            ? () => _showQuickActions(context, device)
                            : null,
                        onEdit: () => _showDeviceSheet(editIndex: index),
                        onDelete: () => _removeDevice(index),
                        onToggleFavorite: () {
                          setState(() {
                            if (isFavorite) {
                              _favoriteDeviceHosts.remove(device['host']);
                            } else {
                              _favoriteDeviceHosts.add(device['host']!);
                            }
                            _saveDevices();
                          });
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            builder: (ctx) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('New'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showDeviceSheet();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.wifi_tethering),
                    title: const Text('Scan'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _scanForDevices(context);
                    },
                  ),
                  if (_customizeMode)
                    ListTile(
                      leading: const Icon(Icons.visibility),
                      title: const Text('Show Hidden Tiles'),
                      onTap: () {
                        setState(() {
                          for (final tile in _dashboardTiles) {
                            tile['visible'] = true;
                          }
                        });
                      },
                    ),
                ],
              );
            },
          );
        },
        child: const Icon(Icons.add),
      ),
      drawer: Drawer(
        child: ListView(
          children: [
            DrawerHeader(
              child: Column(
                children: [
                  const Text('LitterBox'),
                  const SizedBox(height: 10),
                  Image.asset(
                    'assets/splash_2.jpg',
                    height: 100,
                    fit: BoxFit.contain,
                  ),
                ],
              ),
            ),

// ...existing code...
            ListTile(
              title: const Text("Device's"),
              leading: const Icon(Icons.devices),
              onTap: () {
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
            ),

            ListTile(
              title: const Text('Android'),
              leading: const Icon(Icons.android),
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) => const AdbRefactoredScreen(),
                ));
              },
            ),
            ListTile(
              title: const Text('ESP32'),
              leading: const Icon(Icons.memory),
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) => const ESP32Screen(),
                ));
              },
            ),
            ListTile(
              title: const Text('VNC'),
              leading: const Icon(Icons.desktop_windows),
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) => const VNCScreen(),
                ));
              },
            ),
            ListTile(
              title: const Text('RDP'),
              leading: const Icon(Icons.computer),
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) => const RDPScreen(),
                ));
              },
            ),
            ListTile(
              title: const Text('Other'),
              leading: const Icon(Icons.more_horiz),
              onTap: () {
                // Placeholder for Other screen
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Other'),
                    content: const Text('Other screen not implemented yet.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
              },
            ),
            const Divider(),
            SwitchListTile(
              title: const Text('Dark Mode'),
              value: themeModeNotifier.value == ThemeMode.dark,
              onChanged: (val) {
                setState(() {
                  themeModeNotifier.value =
                      val ? ThemeMode.dark : ThemeMode.light;
                });
              },
              secondary: const Icon(Icons.brightness_6),
            ),
            ListTile(
              title: const Text('Settings'),
              onTap: () {
                Navigator.pushNamed(context, '/settings');
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanDialog extends StatefulWidget {
  final Function(String) onDeviceSelected;
  const _ScanDialog({required this.onDeviceSelected});

  @override
  State<_ScanDialog> createState() => _ScanDialogState();
}

class _ScanDialogState extends State<_ScanDialog> {
  final Set<LiteHost> _foundHosts = <LiteHost>{};
  bool _scanning = false;
  String _errorMessage = '';
  StreamSubscription<String>? _scanSubscription;
  String? _subnet;
  String? _networkInfo;
  bool _fetchingNetworkInfo = true;
  bool _initializingTools = true;
  String _progressText = '';
  bool _loadedCached = false;
  DateTime? _cacheTime;

  @override
  void initState() {
    super.initState();
    _fetchNetworkInfoAndStartScan();
  }

  Future<void> _fetchNetworkInfoAndStartScan() async {
    setState(() {
      _fetchingNetworkInfo = true;
    });
    final info = NetworkInfo();
    String? ip = await info.getWifiIP();
    String? wifiName = await info.getWifiName();
    String? wifiBSSID = await info.getWifiBSSID();
    print('Detected IP: $ip');
    print('WiFi Name: $wifiName');
    print('WiFi BSSID: $wifiBSSID');
    if (ip == null || !ip.contains('.')) {
      setState(() {
        _fetchingNetworkInfo = false;
        _errorMessage =
            'Could not determine local IP address.\nDetected IP: ${ip ?? 'null'}\nWiFi: ${wifiName ?? 'null'}\nBSSID: ${wifiBSSID ?? 'null'}\nPlease ensure you are connected to WiFi and have granted location permissions.';
      });
      return;
    }
    final subnet = ip.substring(0, ip.lastIndexOf('.'));
    setState(() {
      _subnet = subnet;
      _networkInfo = 'IP: $ip\nWiFi: ${wifiName ?? 'Unknown'}';
      _fetchingNetworkInfo = false;
    });
    // Load cached results (if any) immediately
    await _loadCachedResults();
    // Ensure network tools initialized & show status
    setState(() => _initializingTools = true);
    final ok = await NetworkToolsInitializer.ensureInitialized();
    setState(() => _initializingTools = false);
    if (!ok) {
      setState(() {
        _errorMessage =
            'Network tools failed to initialize; scan may be limited.';
      });
    }
    // Debounce start if already scanning or pending
    await Future.delayed(const Duration(milliseconds: 300));
    if (!_scanning) _startScan();
  }

  Future<void> _loadCachedResults() async {
    if (_subnet == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'scan_cache_$_subnet';
      final jsonStr = prefs.getString(key);
      if (jsonStr == null) return;
      final data = json.decode(jsonStr) as Map<String, dynamic>;
      final ts = DateTime.tryParse(data['timestamp'] as String? ?? '');
      final List<dynamic> ips = data['ips'] as List<dynamic>? ?? [];
      if (ips.isNotEmpty) {
        setState(() {
          _foundHosts.addAll(ips.map((e) => LiteHost(e.toString())));
          _loadedCached = true;
          _cacheTime = ts;
        });
      }
    } catch (e) {
      // ignore cache errors
    }
  }

  Future<void> _cacheResults() async {
    if (_subnet == null || _foundHosts.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'scan_cache_$_subnet';
      final data = {
        'timestamp': DateTime.now().toIso8601String(),
        'ips': _foundHosts.map((h) => h.address).toList(),
      };
      await prefs.setString(key, json.encode(data));
    } catch (_) {}
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    super.dispose();
  }

  DateTime? _lastScanStarted;
  Timer? _debounceTimer;

  void _startScan() {
    if (!mounted || _subnet == null) return;
    // Debounce rapid calls (within 1s)
    final now = DateTime.now();
    if (_lastScanStarted != null &&
        now.difference(_lastScanStarted!).inMilliseconds < 1000) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 800), () {
        if (!_scanning) _startScan();
      });
      return;
    }
    _lastScanStarted = now;
    setState(() {
      _scanning = true;
      _foundHosts.clear();
      _errorMessage = '';
    });
    print('Starting isolate scan for subnet: $_subnet');
    try {
      final stream =
          isolateSubnetScan(_subnet!, firstHostId: 1, lastHostId: 254);
      _scanSubscription = stream.listen((msg) {
        if (msg.startsWith('progress:')) {
          final pct = msg.split(':').last;
          if (mounted) setState(() => _progressText = '$pct%');
          return;
        }
        final ip = msg;
        if (mounted) {
          setState(() {
            // Represent ActiveHost minimally (placeholder wrapper) - for now just store via custom ActiveHost-like stand-in
            _foundHosts.add(LiteHost(ip));
          });
        }
      }, onDone: () {
        _cacheResults();
        if (mounted) {
          setState(() {
            _scanning = false;
          });
        }
      }, onError: (e) {
        if (mounted) {
          setState(() {
            _scanning = false;
            _errorMessage = 'Scan error: $e';
          });
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _errorMessage = 'Failed to start scan: $e';
        });
      }
    }
  }

  void _cancelScan() {
    if (!_scanning) return;
    _scanSubscription?.cancel();
    _cacheResults();
    setState(() {
      _scanning = false;
      _progressText = 'Cancelled';
    });
  }

  void _testNetworkConnectivity() async {
    print('=== Network Connectivity Test ===');
    final info = NetworkInfo();
    String? ip = await info.getWifiIP();
    String? wifiName = await info.getWifiName();
    String? wifiBSSID = await info.getWifiBSSID();

    print('IP: $ip');
    print('WiFi Name: $wifiName');
    print('WiFi BSSID: $wifiBSSID');
    print('Subnet: [$_subnet');
    print('================================');

    // Show the results in a dialog
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Network Test Results'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('IP Address: ${ip ?? 'Not detected'}'),
              Text('WiFi Name: ${wifiName ?? 'Not detected'}'),
              Text('WiFi BSSID: ${wifiBSSID ?? 'Not detected'}'),
              Text('Scan Subnet: ${_subnet ?? 'Unknown'}'),
              const SizedBox(height: 16),
              const Text(
                'Check the debug console for detailed logs.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_fetchingNetworkInfo)
            Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                const Text('Preparing scan...'),
              ],
            )
          else if (_initializingTools)
            Row(children: const [
              SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 12),
              Text('Initializing network tools...')
            ])
          else if (_subnet != null)
            Text(_scanning
                ? 'Scanning $_subnet.1-254... ${_progressText.isNotEmpty ? _progressText : ''}'
                : 'Found ${_foundHosts.length} devices${_loadedCached && _cacheTime != null ? ' (cached)' : ''}'),
          if (_networkInfo != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _networkInfo!,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
        ],
      ),
      content: SizedBox(
        width: 300,
        height: 300,
        child: _fetchingNetworkInfo
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage.isNotEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error, color: Colors.red, size: 48),
                        const SizedBox(height: 16),
                        Text(_errorMessage, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _fetchNetworkInfoAndStartScan,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : _foundHosts.isEmpty && !_scanning
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.wifi_off, size: 48, color: Colors.grey),
                            SizedBox(height: 16),
                            Text('No devices found on this network.'),
                            SizedBox(height: 8),
                            Text(
                              'Make sure devices are connected and responsive to ping.',
                              style:
                                  TextStyle(fontSize: 12, color: Colors.grey),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _foundHosts.length,
                        itemBuilder: (context, index) {
                          final host = _foundHosts.elementAt(index);
                          return HostTileWithRetry(
                            host: host,
                            onDeviceSelected: widget.onDeviceSelected,
                          );
                        },
                      ),
      ),
      actions: [
        if (_fetchingNetworkInfo) const SizedBox.shrink(),
        if (!_scanning &&
            _foundHosts.isEmpty &&
            _errorMessage.isEmpty &&
            !_fetchingNetworkInfo)
          TextButton(
            onPressed: _testNetworkConnectivity,
            child: const Text('Test Network'),
          ),
        if (_scanning)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              const Text('Scanning...'),
              const SizedBox(width: 16),
              TextButton(onPressed: _cancelScan, child: const Text('Cancel')),
            ],
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
