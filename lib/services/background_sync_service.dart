import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'connection_pool_manager.dart';

/// Service to maintain connections and sync data in the background
class BackgroundSyncService {
  static final BackgroundSyncService _instance =
      BackgroundSyncService._internal();
  factory BackgroundSyncService() => _instance;
  BackgroundSyncService._internal();

  static const MethodChannel _channel =
      MethodChannel('com.litterbox/background_sync');

  final ConnectionPoolManager _connectionPool = ConnectionPoolManager();
  Timer? _syncTimer;
  Timer? _heartbeatTimer;
  bool _isRunning = false;

  final StreamController<BackgroundSyncEvent> _eventController =
      StreamController<BackgroundSyncEvent>.broadcast();

  Stream<BackgroundSyncEvent> get events => _eventController.stream;

  Future<List<Map<String, dynamic>>> _loadDevicesFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    // Preferred format in current app versions: a single JSON string list.
    final devicesRaw = prefs.getString('devices');
    if (devicesRaw != null && devicesRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(devicesRaw);
        if (decoded is List) {
          return decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      } catch (_) {
        // Fall through to legacy format.
      }
    }

    // Backward compatibility for older installs storing StringList entries.
    final devicesList = prefs.getStringList('devices') ?? const <String>[];
    return devicesList
        .map((entry) => jsonDecode(entry))
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> _saveDevicesToPrefs(List<Map<String, dynamic>> devices) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('devices', jsonEncode(devices));
  }

  /// Start background sync service
  Future<void> start({
    Duration syncInterval = const Duration(minutes: 5),
    Duration heartbeatInterval = const Duration(minutes: 1),
  }) async {
    if (_isRunning) return;

    _isRunning = true;
    _addEvent(BackgroundSyncEvent.started());

    try {
      // Register background task (Android/iOS specific)
      await _registerBackgroundTask();

      // Start periodic sync
      _syncTimer = Timer.periodic(syncInterval, (_) => _performSync());

      // Start heartbeat for connection health
      _heartbeatTimer =
          Timer.periodic(heartbeatInterval, (_) => _performHeartbeat());

      // Perform initial sync
      await _performSync();

      debugPrint('BackgroundSyncService started');
    } catch (e) {
      _addEvent(
          BackgroundSyncEvent.error('Failed to start background sync: $e'));
      _isRunning = false;
    }
  }

  /// Stop background sync service
  Future<void> stop() async {
    if (!_isRunning) return;

    _isRunning = false;
    _syncTimer?.cancel();
    _heartbeatTimer?.cancel();

    await _unregisterBackgroundTask();

    _addEvent(BackgroundSyncEvent.stopped());
    debugPrint('BackgroundSyncService stopped');
  }

  /// Perform background sync of device data
  Future<void> _performSync() async {
    try {
      _addEvent(BackgroundSyncEvent.syncStarted());

      final devices = await _loadDevicesFromPrefs();

      int synced = 0;
      int failed = 0;

      for (final deviceData in devices) {
        try {
          // Check if device supports background sync
          if (deviceData['enableBackgroundSync'] == true) {
            await _syncDeviceData(deviceData);
            synced++;
          }
        } catch (e) {
          failed++;
          debugPrint('Failed to sync device ${deviceData['name']}: $e');
        }
      }

      _addEvent(BackgroundSyncEvent.syncCompleted(synced, failed));
    } catch (e) {
      _addEvent(BackgroundSyncEvent.error('Sync failed: $e'));
    }
  }

  /// Sync individual device data
  Future<void> _syncDeviceData(Map<String, dynamic> deviceData) async {
    final host = deviceData['host'] as String;
    final port = int.tryParse(deviceData['port']?.toString() ?? '22') ?? 22;
    final username = deviceData['username'] as String;
    final password = deviceData['password'] as String;

    // Get or create connection
    final client = await _connectionPool.getSSHConnection(
      host,
      port,
      username,
      password,
      enableAutoReconnect: true,
    );

    if (client != null) {
      try {
        // Collect basic system info
        final systemInfo = await _collectSystemInfo(client);

        // Store cached data
        await _storeCachedData(deviceData['name'], systemInfo);

        debugPrint('Synced data for ${deviceData['name']}');
      } catch (e) {
        debugPrint('Error syncing ${deviceData['name']}: $e');
        rethrow;
      }
    } else {
      throw Exception('Failed to establish connection');
    }
  }

  /// Collect system information from device
  Future<Map<String, dynamic>> _collectSystemInfo(client) async {
    final info = <String, dynamic>{};

    try {
      // System uptime
      final uptimeResult = await client.run('uptime');
      info['uptime'] = uptimeResult.stdout;

      // Memory usage
      final memResult = await client.run('free -m');
      info['memory'] = memResult.stdout;

      // Disk usage
      final diskResult = await client.run('df -h');
      info['disk'] = diskResult.stdout;

      // CPU info
      final cpuResult = await client.run('top -bn1 | grep "Cpu(s)"');
      info['cpu'] = cpuResult.stdout;

      // Load average
      final loadResult = await client.run('cat /proc/loadavg');
      info['load'] = loadResult.stdout;

      info['timestamp'] = DateTime.now().toIso8601String();
    } catch (e) {
      debugPrint('Error collecting system info: $e');
    }

    return info;
  }

  /// Store cached data locally
  Future<void> _storeCachedData(
      String deviceName, Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'cached_data_$deviceName';
    await prefs.setString(key, jsonEncode(data));
  }

  /// Get cached data for device
  Future<Map<String, dynamic>?> getCachedData(String deviceName) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'cached_data_$deviceName';
    final data = prefs.getString(key);

    if (data != null) {
      try {
        return Map<String, dynamic>.from(jsonDecode(data));
      } catch (e) {
        debugPrint('Error parsing cached data: $e');
      }
    }

    return null;
  }

  /// Perform connection heartbeat check
  Future<void> _performHeartbeat() async {
    try {
      final stats = _connectionPool.getConnectionStats();
      final totalConnections = stats['totalConnections'] as int;
      final healthyConnections = stats['healthyConnections'] as int;

      _addEvent(
          BackgroundSyncEvent.heartbeat(healthyConnections, totalConnections));

      // Log connection health
      if (totalConnections > 0) {
        final healthRatio = healthyConnections / totalConnections;
        if (healthRatio < 0.5) {
          _addEvent(BackgroundSyncEvent.warning(
              'Connection health degraded: $healthyConnections/$totalConnections healthy'));
        }
      }
    } catch (e) {
      _addEvent(BackgroundSyncEvent.error('Heartbeat failed: $e'));
    }
  }

  /// Register background task with the platform
  Future<void> _registerBackgroundTask() async {
    try {
      if (!kIsWeb) {
        await _channel.invokeMethod('registerBackgroundTask', {
          'interval': 300, // 5 minutes
          'taskName': 'device_sync',
        });
      }
    } on PlatformException catch (e) {
      debugPrint('Failed to register background task: ${e.message}');
    }
  }

  /// Unregister background task
  Future<void> _unregisterBackgroundTask() async {
    try {
      if (!kIsWeb) {
        await _channel.invokeMethod('unregisterBackgroundTask');
      }
    } on PlatformException catch (e) {
      debugPrint('Failed to unregister background task: ${e.message}');
    }
  }

  /// Enable background sync for a specific device
  Future<void> enableDeviceSync(String deviceName, bool enable) async {
    final devices = await _loadDevicesFromPrefs();

    for (final device in devices) {
      if (device['name'] == deviceName) {
        device['enableBackgroundSync'] = enable;
        break;
      }
    }

    await _saveDevicesToPrefs(devices);

    _addEvent(BackgroundSyncEvent.deviceSyncToggled(deviceName, enable));
  }

  /// Check if device has background sync enabled
  Future<bool> isDeviceSyncEnabled(String deviceName) async {
    final devices = await _loadDevicesFromPrefs();

    for (final device in devices) {
      if (device['name'] == deviceName) {
        return device['enableBackgroundSync'] == true;
      }
    }

    return false;
  }

  /// Get service status
  Map<String, dynamic> getStatus() {
    return {
      'isRunning': _isRunning,
      'connectionStats': _connectionPool.getConnectionStats(),
      'lastSync': _syncTimer != null ? DateTime.now().toIso8601String() : null,
    };
  }

  void _addEvent(BackgroundSyncEvent event) {
    _eventController.add(event);
  }

  /// Dispose service
  void dispose() {
    stop();
    _eventController.close();
    _connectionPool.dispose();
  }
}

/// Background sync event types
class BackgroundSyncEvent {
  final String type;
  final String message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;

  BackgroundSyncEvent._(this.type, this.message, [this.data])
      : timestamp = DateTime.now();

  factory BackgroundSyncEvent.started() =>
      BackgroundSyncEvent._('started', 'Background sync service started');

  factory BackgroundSyncEvent.stopped() =>
      BackgroundSyncEvent._('stopped', 'Background sync service stopped');

  factory BackgroundSyncEvent.syncStarted() =>
      BackgroundSyncEvent._('sync_started', 'Background sync started');

  factory BackgroundSyncEvent.syncCompleted(int synced, int failed) =>
      BackgroundSyncEvent._(
          'sync_completed',
          'Sync completed: $synced synced, $failed failed',
          {'synced': synced, 'failed': failed});

  factory BackgroundSyncEvent.heartbeat(int healthy, int total) =>
      BackgroundSyncEvent._(
          'heartbeat',
          'Connection heartbeat: $healthy/$total healthy',
          {'healthy': healthy, 'total': total});

  factory BackgroundSyncEvent.deviceSyncToggled(String device, bool enabled) =>
      BackgroundSyncEvent._(
          'device_sync_toggled',
          'Device sync ${enabled ? 'enabled' : 'disabled'} for $device',
          {'device': device, 'enabled': enabled});

  factory BackgroundSyncEvent.warning(String message) =>
      BackgroundSyncEvent._('warning', message);

  factory BackgroundSyncEvent.error(String message) =>
      BackgroundSyncEvent._('error', message);

  @override
  String toString() => '[$type] $message';
}
