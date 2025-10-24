import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dartssh2/dartssh2.dart';
import 'device_info_screen.dart';
import 'device_terminal_screen.dart';
import 'device_files_screen.dart';
import 'device_packages_screen.dart';
import 'device_processes_screen.dart';
import 'device_misc_screen.dart';
import '../models/device_status.dart';
import '../services/connection_pool_manager.dart';
import '../services/background_sync_service.dart';
import '../widgets/connection_quality_indicator.dart';

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

  // Enhanced connection management with stability improvements
  final ConnectionPoolManager _connectionPool = ConnectionPoolManager();
  final BackgroundSyncService _backgroundSync = BackgroundSyncService();
  String? _connectionId;
  bool _autoReconnectEnabled = true;

  // Connection monitoring
  StreamSubscription<String>? _reconnectionSubscription;
  StreamSubscription<String>? _networkSubscription;
  Timer? _connectionValidationTimer;
  int _connectionAttempts = 0;
  DateTime? _lastConnectionAttempt;

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

    final host = widget.device['host']!;
    final port = int.tryParse(widget.device['port'] ?? '22') ?? 22;
    final username = widget.device['username']!;

    _connectionId = 'ssh:$username@$host:$port';
    _connectionAttempts++;
    _lastConnectionAttempt = DateTime.now();

    setState(() {
      _connecting = true;
      _sshError = null;
    });

    // Setup connection monitoring
    _setupConnectionMonitoring();

    try {
      // Use enhanced connection pool with retry logic
      final client = await _connectionPool.getSSHConnection(
        host,
        port,
        username,
        _password,
        enableAutoReconnect: _autoReconnectEnabled,
        timeout: const Duration(seconds: 20),
        maxRetries: 3,
      );

      if (!mounted) return;

      if (client != null) {
        // Validate connection before using
        // Check connection quality before proceeding
        final connectionQuality =
            _connectionPool.getConnectionQuality(_connectionId!);
        if (connectionQuality != null &&
            connectionQuality.status == ConnectionHealthStatus.critical) {
          throw Exception('Connection quality is critical');
        }

        setState(() {
          _sshClient = client;
          _connecting = false;
          _connectionTime = DateTime.now();
          _miscScreenReloadKey++; // Refresh misc screen to show updated status
        });

        // Enable background sync for this device if configured
        await _backgroundSync.enableDeviceSync(
            widget.device['name'] ?? host, true);

        // Listen to reconnection events
        _connectionPool.reconnectionEvents.listen((event) {
          if (mounted && event.contains(_connectionId!)) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(event),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        });
      } else {
        throw Exception('Failed to establish connection through pool');
      }
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

  @override
  void dispose() {
    // Clean up connections when screen is disposed
    if (_connectionId != null) {
      _connectionPool.closeConnection(_connectionId!);
    }
    super.dispose();
  }

  /// Show detailed connection statistics dialog
  void _showConnectionDetails() {
    if (_connectionId == null) return;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.network_check, color: Colors.blue),
                  const SizedBox(width: 8),
                  Text(
                    'Connection Statistics',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 8),
              ConnectionStatsWidget(connectionId: _connectionId!),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

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
          title: Row(
            children: [
              Expanded(
                child: Text(
                  widget.device['name']?.isNotEmpty == true
                      ? widget.device['name']!
                      : '${widget.device['username']}@${widget.device['host']}:${widget.device['port']}',
                ),
              ),
              if (_connectionId != null) ...[
                const SizedBox(width: 8),
                ConnectionQualityIndicator(
                  connectionId: _connectionId!,
                  showDetails: false,
                  onTap: () => _showConnectionDetails(),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
          actions: [
            if (_sshClient != null)
              IconButton(
                icon: Icon(
                    _autoReconnectEnabled ? Icons.sync : Icons.sync_disabled),
                tooltip: _autoReconnectEnabled
                    ? 'Auto-reconnect enabled'
                    : 'Auto-reconnect disabled',
                onPressed: () {
                  setState(() {
                    _autoReconnectEnabled = !_autoReconnectEnabled;
                  });

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Auto-reconnect ${_autoReconnectEnabled ? 'enabled' : 'disabled'}',
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
            IconButton(
              icon: const Icon(Icons.network_check),
              tooltip: 'Connection Statistics',
              onPressed: _showConnectionDetails,
            ),
          ],
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
        // No floatingActionButton here; add device button is only on HomeScreen\n      ),\n    );\n  }\n  \n  void _setupConnectionMonitoring() {\n    _reconnectionSubscription?.cancel();\n    _reconnectionSubscription = _connectionPool.reconnectionEvents.listen((event) {\n      if (_connectionId != null && event.contains(_connectionId!)) {\n        if (mounted) {\n          ScaffoldMessenger.of(context).showSnackBar(\n            SnackBar(\n              content: Text(event),\n              duration: const Duration(seconds: 2),\n            ),\n          );\n        }\n      }\n    });\n  }\n  \n  void _startConnectionValidation() {\n    _connectionValidationTimer?.cancel();\n    _connectionValidationTimer = Timer.periodic(const Duration(minutes: 2), (_) {\n      _validateConnection();\n    });\n  }\n  \n  Future<void> _validateConnection() async {\n    if (_connectionId == null || _sshClient == null || !mounted) return;\n    \n    final quality = _connectionPool.getConnectionQuality(_connectionId!);\n    if (quality != null && quality.status == ConnectionHealthStatus.critical) {\n      setState(() {\n        _sshError = 'Connection quality degraded';\n        _sshClient = null;\n      });\n      \n      if (_autoReconnectEnabled) {\n        Future.delayed(const Duration(seconds: 3), () {\n          if (mounted) _connectSSH();\n        });\n      }\n    }\n  }\n  \n  void _handleConnectionError(dynamic error) {\n    if (!mounted) return;\n    \n    setState(() {\n      _sshError = error.toString();\n      _connecting = false;\n      _sshClient = null;\n    });\n    \n    if (_autoReconnectEnabled && _connectionAttempts < 5) {\n      final delay = Duration(seconds: (2 * _connectionAttempts).clamp(2, 30));\n      \n      ScaffoldMessenger.of(context).showSnackBar(\n        SnackBar(\n          content: Text('Reconnecting in ${delay.inSeconds}s...'),\n          duration: delay,\n        ),\n      );\n      \n      Future.delayed(delay, () {\n        if (mounted && _autoReconnectEnabled) _connectSSH();\n      });\n    }\n  }\n  \n  @override\n  void dispose() {\n    _sshClient?.close();\n    _reconnectionSubscription?.cancel();\n    _networkSubscription?.cancel();\n    _connectionValidationTimer?.cancel();\n    super.dispose();\n  }\n}
      ),
    );
  }
}
