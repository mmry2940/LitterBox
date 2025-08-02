import 'package:flutter/material.dart';
import 'package:dartssh2/dartssh2.dart';
import '../main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'device_screen.dart';

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

  void _showDeviceSheet({int? editIndex}) {
    final isEdit = editIndex != null;
    final nameController = TextEditingController(
      text: isEdit ? _devices[editIndex]['name'] ?? '' : '',
    );
    final hostController = TextEditingController(
      text: isEdit ? _devices[editIndex]['host'] : '',
    );
    final portController = TextEditingController(
      text: isEdit ? _devices[editIndex]['port'] : '22',
    );
    final usernameController = TextEditingController(
      text: isEdit ? _devices[editIndex]['username'] : '',
    );
    final passwordController = TextEditingController();
    String status = '';
    bool connecting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 24,
          ),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              Future<void> connectAndSave() async {
                setModalState(() {
                  connecting = true;
                  status = 'Connecting...';
                });
                try {
                  SSHClient(
                    await SSHSocket.connect(
                      hostController.text,
                      int.tryParse(portController.text) ?? 22,
                    ),
                    username: usernameController.text,
                    onPasswordRequest: () => passwordController.text,
                  );
                  status = 'Connected!';
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
                  Navigator.pop(context);
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

              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEdit ? 'Edit Device' : 'Add Device',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 8),
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
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  isEdit ? 'Connect & Save' : 'Connect & Add',
                                ),
                        ),
                        const SizedBox(width: 16),
                        Text(status),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _removeDevice(int index) async {
    setState(() {
      _devices.removeAt(index);
    });
    await _saveDevices();
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
                        ), // 5 = Misc/Overview (cards)
                      ),
                    );
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showDeviceSheet(),
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
                  themeModeNotifier.value = val ? ThemeMode.dark : ThemeMode.light;
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
