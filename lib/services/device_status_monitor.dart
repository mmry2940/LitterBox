import 'dart:async';
import 'dart:io';
import '../models/saved_adb_device.dart';
import '../adb_client.dart';

/// Result of a device status check
class DeviceStatusResult {
  final String deviceId;
  final bool isOnline;
  final int? latencyMs;
  final DateTime timestamp;
  final String? error;

  const DeviceStatusResult({
    required this.deviceId,
    required this.isOnline,
    this.latencyMs,
    required this.timestamp,
    this.error,
  });

  /// Get color based on latency
  String get statusColor {
    if (!isOnline) return 'red';
    if (latencyMs == null) return 'gray';
    if (latencyMs! < 50) return 'green';
    if (latencyMs! < 200) return 'yellow';
    if (latencyMs! < 500) return 'orange';
    return 'red';
  }

  /// Get status text
  String get statusText {
    if (!isOnline) return 'Offline';
    if (latencyMs == null) return 'Unknown';
    return '${latencyMs}ms';
  }
}

/// Monitors device connectivity and latency
class DeviceStatusMonitor {
  final Map<String, DeviceStatusResult> _statusCache = {};
  final Map<String, Timer?> _monitorTimers = {};
  final StreamController<DeviceStatusResult> _statusStream = 
      StreamController<DeviceStatusResult>.broadcast();

  /// Stream of status updates
  Stream<DeviceStatusResult> get statusUpdates => _statusStream.stream;

  /// Get cached status for a device
  DeviceStatusResult? getStatus(String deviceId) => _statusCache[deviceId];

  /// Start monitoring a device
  void startMonitoring(
    SavedADBDevice device, {
    Duration interval = const Duration(seconds: 30),
  }) {
    final deviceId = '${device.host}:${device.port}';
    
    // Cancel existing timer if any
    stopMonitoring(deviceId);

    // Initial check
    _checkDevice(device);

    // Set up periodic checks
    _monitorTimers[deviceId] = Timer.periodic(interval, (_) {
      _checkDevice(device);
    });
  }

  /// Stop monitoring a device
  void stopMonitoring(String deviceId) {
    _monitorTimers[deviceId]?.cancel();
    _monitorTimers.remove(deviceId);
  }

  /// Stop monitoring all devices
  void stopAll() {
    for (final timer in _monitorTimers.values) {
      timer?.cancel();
    }
    _monitorTimers.clear();
  }

  /// Check device status
  Future<DeviceStatusResult> _checkDevice(SavedADBDevice device) async {
    final deviceId = '${device.host}:${device.port}';
    final startTime = DateTime.now();

    try {
      // For USB devices, we can't ping - rely on ADB
      if (device.connectionType == ADBConnectionType.usb) {
        final result = DeviceStatusResult(
          deviceId: deviceId,
          isOnline: device.isConnected ?? false,
          latencyMs: null,
          timestamp: DateTime.now(),
        );
        _statusCache[deviceId] = result;
        _statusStream.add(result);
        return result;
      }

      // For network devices, try TCP connection
      Socket? socket;
      try {
        socket = await Socket.connect(
          device.host,
          device.port,
          timeout: const Duration(seconds: 3),
        );

        final latency = DateTime.now().difference(startTime).inMilliseconds;

        final result = DeviceStatusResult(
          deviceId: deviceId,
          isOnline: true,
          latencyMs: latency,
          timestamp: DateTime.now(),
        );

        _statusCache[deviceId] = result;
        _statusStream.add(result);
        return result;
      } catch (e) {
        final result = DeviceStatusResult(
          deviceId: deviceId,
          isOnline: false,
          latencyMs: null,
          timestamp: DateTime.now(),
          error: e.toString(),
        );

        _statusCache[deviceId] = result;
        _statusStream.add(result);
        return result;
      } finally {
        socket?.destroy();
      }
    } catch (e) {
      final result = DeviceStatusResult(
        deviceId: deviceId,
        isOnline: false,
        latencyMs: null,
        timestamp: DateTime.now(),
        error: e.toString(),
      );

      _statusCache[deviceId] = result;
      _statusStream.add(result);
      return result;
    }
  }

  /// Manually trigger a status check
  Future<DeviceStatusResult> checkNow(SavedADBDevice device) {
    return _checkDevice(device);
  }

  /// Dispose and clean up
  void dispose() {
    stopAll();
    _statusStream.close();
  }
}
