import 'package:flutter/material.dart';
import 'package:dartssh2/dartssh2.dart';
import '../main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'device_screen.dart';
import 'package:network_tools/network_tools.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:sshuttle_flutter/screens/_host_tile_with_retry.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, String>> _devices = [];

  @override
  void initState() {
    super.initState();
    _loadDevices();
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
  }

  Future<void> _saveDevices() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('devices', json.encode(_devices));
  }

  void _removeDevice(int index) async {
    setState(() {
      _devices.removeAt(index);
    });
    await _saveDevices();
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
    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> connectAndSave() async {
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
                      decoration: const InputDecoration(labelText: 'Port'),
                      keyboardType: TextInputType.number,
                    ),
                    TextField(
                      controller: usernameController,
                      decoration: const InputDecoration(labelText: 'Username'),
                    ),
                    TextField(
                      controller: passwordController,
                      decoration: const InputDecoration(labelText: 'Password'),
                      obscureText: true,
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
    bool connecting = false;
    String status = '';
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> connectAndSave() async {
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
                      decoration: const InputDecoration(labelText: 'Host'),
                    ),
                    TextField(
                      controller: portController,
                      decoration: const InputDecoration(labelText: 'Port'),
                      keyboardType: TextInputType.number,
                    ),
                    TextField(
                      controller: usernameController,
                      decoration: const InputDecoration(labelText: 'Username'),
                    ),
                    TextField(
                      controller: passwordController,
                      decoration: const InputDecoration(labelText: 'Password'),
                      obscureText: true,
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
      appBar: AppBar(title: const Text('Devices')),
      body: _devices.isEmpty
          ? const Center(child: Text('No devices added.'))
          : ListView.builder(
              itemCount: _devices.length,
              itemBuilder: (context, index) {
                final device = _devices[index];
                return ListTile(
                  title: Text(
                    (device['name']?.isNotEmpty ?? false)
                        ? device['name']!
                        : '${device['username']}@${device['host']}:${device['port']}',
                  ),
                  subtitle: (device['name']?.isNotEmpty ?? false)
                      ? Text(
                          '${device['username']}@${device['host']}:${device['port']}',
                        )
                      : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _showDeviceSheet(editIndex: index),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _removeDevice(index),
                      ),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DeviceScreen(
                          device: device,
                          initialTab: 5,
                        ),
                      ),
                    );
                  },
                );
              },
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
            const DrawerHeader(child: Text('sshuttle')),
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
  final Set<ActiveHost> _foundHosts = <ActiveHost>{};
  bool _scanning = false;
  String _errorMessage = '';
  StreamSubscription<ActiveHost>? _scanSubscription;
  String? _subnet;
  String? _networkInfo;
  bool _fetchingNetworkInfo = true;

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
    // Wait 3 seconds before starting scan
    await Future.delayed(const Duration(milliseconds: 1500));
    _startScan();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    super.dispose();
  }

  void _startScan() {
    if (!mounted || _subnet == null) return;
    setState(() {
      _scanning = true;
      _foundHosts.clear();
      _errorMessage = '';
    });
    print('Starting scan for subnet: $_subnet');
    try {
      final stream = HostScannerService.instance.getAllPingableDevices(
        _subnet!,
        firstHostId: 1,
        lastHostId: 254,
        progressCallback: (progress) {
          print('Scan progress: $progress');
        },
      );
      _scanSubscription = stream.listen(
        (host) async {
          print('Found host: ${host.address}');
          try {
            print('Host details: ${host.toString()}');
            final hostname = await host.hostName;
            print('Hostname: $hostname');
          } catch (e) {
            print('Error accessing host properties: $e');
          }
          if (mounted) {
            setState(() {
              _foundHosts.add(host);
            });
          }
        },
        onDone: () {
          print('Scan completed. Found ${_foundHosts.length} hosts');
          if (mounted) {
            setState(() {
              _scanning = false;
            });
          }
        },
        onError: (error) {
          print('Scan error: $error');
          if (mounted) {
            if (error.toString().contains('RangeError') &&
                error.toString().contains('Invalid value')) {
              print('Range limit reached - ending scan normally');
              setState(() {
                _scanning = false;
              });
            } else {
              setState(() {
                _scanning = false;
                _errorMessage = 'Scan error: $error';
              });
            }
          }
        },
      );
    } catch (e) {
      print('Failed to start scan: $e');
      if (mounted) {
        if (e.toString().contains('RangeError') &&
            e.toString().contains('Invalid value')) {
          print('Range limit reached during scan setup - ending scan normally');
          setState(() {
            _scanning = false;
          });
        } else {
          setState(() {
            _scanning = false;
            _errorMessage = 'Failed to start scan: $e';
          });
        }
      }
    }
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
    print('Subnet: [${_subnet}');
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
          else if (_subnet != null)
            Text(_scanning
                ? 'Scanning $_subnet.1-254...'
                : 'Found ${_foundHosts.length} devices'),
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
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 8),
              Text('Scanning...'),
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
