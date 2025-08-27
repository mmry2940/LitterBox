import 'package:flutter/material.dart';
import 'package:dartssh2/dartssh2.dart';
import '../main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'device_screen.dart';
import 'dart:io';
import '../network_init.dart';
import '../isolate_scanner.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '_host_tile_with_retry.dart';
import 'adb_screen_refactored.dart';
import 'android_sdk_screen.dart';
import 'vnc_screen.dart';
import 'rdp_screen.dart';

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

    // Add a test localhost device as a reference
    setState(() {
      _devices.add({
        'name': 'Localhost',
        'host': '127.0.0.1',
        'port': '22',
        'username': 'user',
        'password': 'password',
      });
    });
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
            ListTile(
              leading: const Icon(Icons.devices),
              title: const Text('Devices List'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const HomeScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.android),
              title: const Text('Android'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AdbRefactoredScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_system_daydream),
              title: const Text('Android SDK & Emulator'),
              subtitle: const Text('Setup SDK and manage emulators'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AndroidSDKScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.desktop_windows),
              title: const Text('VNC'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const VNCScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.computer),
              title: const Text('RDP'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const RDPScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.more_horiz),
              title: const Text('Other'),
              onTap: () {
                // Navigate to the Other screen (to be implemented)
              },
            ),
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
