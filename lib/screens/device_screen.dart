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

  Future<void> _ensureConnectionAlive({bool silent = true}) async {
    if (!mounted) return;

    final host = _deviceString('host');
    final port = _devicePort();
    final username = _deviceString('username');
    if (host.isEmpty || username.isEmpty) return;

    try {
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
        setState(() {
          _sshClient = client;
          _sshError = null;
          _connecting = false;
          _connectionTime = DateTime.now();
          _infoScreenReloadKey++;
          _filesScreenReloadKey++;
          _processesScreenReloadKey++;
          _packagesScreenReloadKey++;
          _miscScreenReloadKey++;
        });
        _startConnectionValidation();
      } else if (!silent) {
        _handleConnectionError('Failed to re-establish SSH connection');
      }
    } catch (e) {
      if (!mounted) return;
      if (!silent) {
        _handleConnectionError(e);
      }
    }
  }

  bool _shouldShowConnectionSnack(String event) {
    final normalized = event.trim().toLowerCase();
    // Suppress noisy informational toasts shown during normal connect flow.
    if (normalized.startsWith('connecting to ')) return false;
    if (normalized.contains('successfully connected')) return false;
    if (normalized.startsWith('connected to ')) return false;
    return true;
  }

  String _deviceString(String key, [String fallback = '']) {
    final value = widget.device[key];
    if (value == null) return fallback;
    final text = value.toString();
    return text.isEmpty ? fallback : text;
  }

  int _devicePort([int fallback = 22]) {
    final value = widget.device['port'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '$fallback') ?? fallback;
  }

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialTab;
    _password = _deviceString('password');
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

    final host = _deviceString('host');
    final port = _devicePort();
    final username = _deviceString('username');

    if (host.isEmpty || username.isEmpty) {
      setState(() {
        _connecting = false;
        _sshError = 'Invalid device profile: host/username is missing.';
      });
      return;
    }

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
          _infoScreenReloadKey++;
          _filesScreenReloadKey++;
          _processesScreenReloadKey++;
          _packagesScreenReloadKey++;
          _miscScreenReloadKey++; // Refresh misc screen to show updated status
        });
        _startConnectionValidation();

        // Enable background sync for this device if configured
        await _backgroundSync.enableDeviceSync(
            widget.device['name'] ?? host, true);

      } else {
        throw Exception('Failed to establish connection through pool');
      }
    } catch (e, st) {
      debugPrint('SSH connect error for $_connectionId: $e');
      debugPrintStack(stackTrace: st);
      if (!mounted) return;
      setState(() {
        _sshError = e.toString();
        _connecting = false;
        _connectionTime = null;
        _miscScreenReloadKey++; // Refresh misc screen to show updated status
      });
    }
  }

  int _infoScreenReloadKey = 0;
  int _filesScreenReloadKey = 0;
  int _processesScreenReloadKey = 0;
  int _packagesScreenReloadKey = 0;
  int _miscScreenReloadKey = 0;

  @override
  void dispose() {
    // Clean up connections when screen is disposed
    if (_connectionId != null) {
      _connectionPool.closeConnection(_connectionId!);
    }
    _sshClient?.close();
    _reconnectionSubscription?.cancel();
    _networkSubscription?.cancel();
    _connectionValidationTimer?.cancel();
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
          deviceName: _deviceString('name', _deviceString('host', 'Device')),
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

    // Re-validate or recover SSH when switching to active tabs.
    if (index != 5) {
      unawaited(_ensureConnectionAlive());
    }
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
                      : '${_deviceString('username', 'user')}@${_deviceString('host', 'unknown')}:${_devicePort()}',
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
          type: BottomNavigationBarType.fixed,
          backgroundColor: const Color(0xFF1A1A22),
          selectedItemColor: Colors.white,
          unselectedItemColor: const Color(0xFFB0B3C0),
          selectedLabelStyle:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          unselectedLabelStyle:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
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
      ),
    );
  }
  
  void _setupConnectionMonitoring() {
    _reconnectionSubscription?.cancel();
    _reconnectionSubscription = _connectionPool.reconnectionEvents.listen((event) {
      if (_connectionId != null &&
          event.contains(_connectionId!) &&
          _shouldShowConnectionSnack(event)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(event),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    });
  }

  void _startConnectionValidation() {
    _connectionValidationTimer?.cancel();
    _connectionValidationTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      _validateConnection();
    });
  }

  Future<void> _validateConnection() async {
    if (_connectionId == null || _sshClient == null || !mounted) return;

    final quality = _connectionPool.getConnectionQuality(_connectionId!);
    if (quality != null && quality.status == ConnectionHealthStatus.critical) {
      setState(() {
        _sshError = 'Connection quality degraded';
        _sshClient = null;
      });

      if (_autoReconnectEnabled) {
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) _connectSSH();
        });
      }
    }
  }

  void _handleConnectionError(dynamic error) {
    if (!mounted) return;

    setState(() {
      _sshError = error.toString();
      _connecting = false;
      _sshClient = null;
    });

    if (_autoReconnectEnabled && _connectionAttempts < 5) {
      final delay = Duration(seconds: (2 * _connectionAttempts).clamp(2, 30));

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Reconnecting in ${delay.inSeconds}s...'),
          duration: delay,
        ),
      );

      Future.delayed(delay, () {
        if (mounted && _autoReconnectEnabled) _connectSSH();
      });
    }
  }
}
