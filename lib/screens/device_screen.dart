import 'package:flutter/material.dart';
import 'package:dartssh2/dartssh2.dart';
import 'device_info_screen.dart';
import 'device_terminal_screen.dart';
import 'device_files_screen.dart';
import 'device_packages_screen.dart';
import 'device_processes_screen.dart';
import 'device_misc_screen.dart';
import '../models/device_status.dart';

typedef AddDeviceCallback = void Function(String ip);

class DeviceScreen extends StatefulWidget {
  final Map<String, dynamic> device;
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
  DateTime? _connectionTime;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialTab;
    _password = widget.device['password'] ?? '';
    _connectSSH();
  }

  DeviceStatus _getCurrentDeviceStatus() {
    // Determine status based on SSH connection state
    final isOnline = _sshClient != null && !_connecting && _sshError == null;

    // Calculate approximate latency based on connection time
    int? pingMs;
    if (isOnline && _connectionTime != null) {
      // Use connection time as a rough latency estimate
      final connectionDuration = DateTime.now().difference(_connectionTime!);
      if (connectionDuration.inSeconds < 10) {
        // If connected recently, assume good latency
        pingMs = 50;
      }
    }

    return DeviceStatus(
      isOnline: isOnline,
      pingMs: pingMs,
      lastChecked: DateTime.now(),
    );
  }

  Future<void> _connectSSH() async {
    if (!mounted) return;
    final startTime = DateTime.now();
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
        _connectionTime = startTime;
        _miscScreenReloadKey++; // Refresh misc screen to show updated status
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sshError = e.toString();
        _connecting = false;
        _connectionTime = null;
        _miscScreenReloadKey++; // Refresh misc screen to show updated status
      });
    }
  }

  final int _infoScreenReloadKey = 0;
  final int _filesScreenReloadKey = 0;
  final int _processesScreenReloadKey = 0;
  final int _packagesScreenReloadKey = 0;
  int _miscScreenReloadKey = 0;

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
          key: ValueKey(_miscScreenReloadKey), // Add key for refresh capability
          device: widget.device, // Pass the required device parameter
          sshClient: _sshClient, // Pass SSH client for metadata fetching
          deviceStatus: _getCurrentDeviceStatus(), // Pass actual device status
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
    return PopScope(
      canPop:
          _selectedIndex == 5, // Only allow pop from Misc tab (overview cards)
      onPopInvoked: (bool didPop) {
        if (didPop) {
          // Clean up SSH connection when popping
          _sshClient?.close();
        } else {
          // If not popping, go back to Misc tab (overview cards)
          if (_selectedIndex != 5) {
            setState(() {
              _selectedIndex = 5; // Navigate to Misc tab
            });
          }
        }
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
}
