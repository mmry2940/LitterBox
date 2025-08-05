import 'package:flutter/material.dart';
import 'package:dartssh2/dartssh2.dart';
import '../main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'device_screen.dart';
import 'package:network_tools/network_tools.dart';
import 'package:network_info_plus/network_info_plus.dart';

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

  void _scanForDevices(BuildContext context) async {
    final info = NetworkInfo();
    String? ip = await info.getWifiIP();
    if (ip == null || !ip.contains('.')) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Error'),
          content: const Text('Could not determine local IP address.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    final subnet = ip.substring(0, ip.lastIndexOf('.'));
    showDialog(
      context: context,
      builder: (ctx) {
        return _ScanDialog(
            subnet: subnet, onDeviceSelected: _addDeviceFromScan);
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
  final String subnet;
  final Function(String) onDeviceSelected;

  const _ScanDialog({required this.subnet, required this.onDeviceSelected});

  @override
  State<_ScanDialog> createState() => _ScanDialogState();
}

class _ScanDialogState extends State<_ScanDialog> {
  final Set<ActiveHost> _foundHosts = <ActiveHost>{};
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  void _startScan() {
    setState(() {
      _scanning = true;
      _foundHosts.clear();
    });

    final stream = HostScannerService.instance.getAllPingableDevices(
      widget.subnet,
      firstHostId: 1,
      lastHostId: 254,
    );

    stream.listen(
      (host) {
        setState(() {
          _foundHosts.add(host);
        });
      },
      onDone: () {
        setState(() {
          _scanning = false;
        });
      },
      onError: (error) {
        setState(() {
          _scanning = false;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_scanning
          ? 'Scanning for devices...'
          : 'Found ${_foundHosts.length} devices'),
      content: SizedBox(
        width: 300,
        height: 300,
        child: _foundHosts.isEmpty && !_scanning
            ? const Center(child: Text('No devices found.'))
            : ListView.builder(
                itemCount: _foundHosts.length,
                itemBuilder: (context, index) {
                  final host = _foundHosts.elementAt(index);
                  return ListTile(
                    title: Text(host.address),
                    onTap: () {
                      Navigator.pop(context);
                      widget.onDeviceSelected(host.address);
                    },
                  );
                },
              ),
      ),
      actions: [
        if (_scanning)
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
