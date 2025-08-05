import 'package:flutter/material.dart';
import 'package:dartssh2/dartssh2.dart';
import 'device_info_screen.dart';
import 'device_terminal_screen.dart';
import 'device_files_screen.dart';
import 'device_packages_screen.dart';
import 'device_processes_screen.dart';
import 'device_misc_screen.dart';
import 'package:network_tools/network_tools.dart';
import 'package:network_info_plus/network_info_plus.dart';

typedef AddDeviceCallback = void Function(String ip);

class DeviceScreen extends StatefulWidget {
  final Map<String, String> device;
  final int initialTab;
  final AddDeviceCallback? onAddDevice;
  const DeviceScreen(
      {super.key, required this.device, this.initialTab = 0, this.onAddDevice});

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  late int _selectedIndex;
  SSHClient? _sshClient;
  String? _sshError;
  bool _connecting = true;
  late String _password;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialTab;
    _password = widget.device['password'] ?? '';
    _connectSSH();
  }

  Future<void> _connectSSH() async {
    if (!mounted) return;
    setState(() {
      _connecting = true;
      _sshError = null;
    });
    try {
      final socket = await SSHSocket.connect(
        widget.device['host']!,
        int.tryParse(widget.device['port'] ?? '22') ?? 22,
      );
      final client = SSHClient(
        socket,
        username: widget.device['username']!,
        onPasswordRequest: () => _password,
      );
      if (!mounted) return;
      setState(() {
        _sshClient = client;
        _connecting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sshError = e.toString();
        _connecting = false;
      });
    }
  }

  final int _infoScreenReloadKey = 0;
  final int _filesScreenReloadKey = 0;
  final int _processesScreenReloadKey = 0;
  final int _packagesScreenReloadKey = 0;

  List<Widget> get _pages => [
        DeviceInfoScreen(
          key: ValueKey(_infoScreenReloadKey),
          sshClient: _sshClient,
          error: _sshError,
          loading: _connecting,
        ),
        DeviceTerminalScreen(
          sshClient: _sshClient,
          error: _sshError,
          loading: _connecting,
        ),
        DeviceFilesScreen(
          key: ValueKey(_filesScreenReloadKey),
          sshClient: _sshClient,
          error: _sshError,
          loading: _connecting,
        ),
        DeviceProcessesScreen(
          key: ValueKey(_processesScreenReloadKey),
          sshClient: _sshClient,
          error: _sshError,
          loading: _connecting,
        ),
        DevicePackagesScreen(
          key: ValueKey(_packagesScreenReloadKey),
          sshClient: _sshClient,
          error: _sshError,
          loading: _connecting,
        ),
        DeviceMiscScreen(
          device: widget.device, // Pass the required device parameter
          onCardTap: (tab) {
            if (!mounted) return;
            setState(() {
              _selectedIndex = tab;
            });
          },
        ),
      ];

  void _onItemTapped(int index) {
    if (!mounted) return;
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_selectedIndex != 5) {
          if (!mounted) return false;
          setState(() {
            _selectedIndex = 5;
          });
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.device['name']?.isNotEmpty == true
                ? widget.device['name']!
                : '${widget.device['username']}@${widget.device['host']}:${widget.device['port']}',
          ),
        ),
        body: _pages[_selectedIndex],
        bottomNavigationBar: BottomNavigationBar(
          items: const <BottomNavigationBarItem>[
            BottomNavigationBarItem(icon: Icon(Icons.info), label: 'Info'),
            BottomNavigationBarItem(
              icon: Icon(Icons.terminal),
              label: 'Terminal',
            ),
            BottomNavigationBarItem(icon: Icon(Icons.folder), label: 'Files'),
            BottomNavigationBarItem(
              icon: Icon(Icons.memory),
              label: 'Processes',
            ),
            BottomNavigationBarItem(icon: Icon(Icons.list), label: 'Packages'),
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_customize),
              label: 'Misc',
            ),
          ],
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
        ),
        // No floatingActionButton here; add device button is only on HomeScreen
      ),
    );
  }

  void _scanForDevices(BuildContext context) async {
    final info = NetworkInfo();
    String? ip = await info.getWifiIP();
    if (ip == null || !ip.contains('.')) {
      // Show error dialog if IP not found
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Error'),
          content: const Text('Could not determine local IP address.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('OK'))
          ],
        ),
      );
      return;
    }
    final subnet = ip.substring(0, ip.lastIndexOf('.'));
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        List<String> foundHosts = [];
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Scanning $subnet.x'),
              content: SizedBox(
                width: 300,
                height: 300,
                child: StreamBuilder<ActiveHost>(
                  stream: HostScannerService.instance.getAllPingableDevices(
                    subnet,
                    firstHostId: 1,
                    lastHostId: 254,
                    progressCallback: (progress) {},
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        foundHosts.isEmpty) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Text('Error: \\${snapshot.error}');
                    }
                    if (snapshot.hasData) {
                      final host = snapshot.data!;
                      if (!foundHosts.contains(host.address)) {
                        foundHosts.add(host.address);
                      }
                    }
                    if (foundHosts.isEmpty) {
                      return const Center(
                          child: Text('No devices found yet...'));
                    }
                    return ListView.builder(
                      itemCount: foundHosts.length,
                      itemBuilder: (context, idx) {
                        final ip = foundHosts[idx];
                        return ListTile(
                          title: Text(ip),
                          onTap: () {
                            Navigator.pop(ctx);
                            if (widget.onAddDevice != null) {
                              widget.onAddDevice!(ip);
                            }
                          },
                        );
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
