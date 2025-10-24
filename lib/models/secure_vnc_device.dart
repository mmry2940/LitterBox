import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/secure_storage_service.dart';
import '../vnc_client.dart';

/// VNC display settings configuration
class VNCDisplaySettings {
  final String scalingMode;
  final String inputMode;
  final VNCResolutionMode resolutionMode;

  VNCDisplaySettings({
    required this.scalingMode,
    required this.inputMode,
    required this.resolutionMode,
  });

  Map<String, dynamic> toJson() => {
        'scalingMode': scalingMode,
        'inputMode': inputMode,
        'resolutionMode': resolutionMode.toString().split('.').last,
      };

  factory VNCDisplaySettings.fromJson(Map<String, dynamic> json) =>
      VNCDisplaySettings(
        scalingMode: json['scalingMode'] ?? 'autoFitBest',
        inputMode: json['inputMode'] ?? 'directTouch',
        resolutionMode: _parseResolutionMode(json['resolutionMode']),
      );

  static VNCResolutionMode _parseResolutionMode(dynamic value) {
    if (value is String) {
      switch (value.toLowerCase()) {
        case 'dynamic':
          return VNCResolutionMode.dynamic;
        case 'fixed':
        default:
          return VNCResolutionMode.fixed;
      }
    }
    return VNCResolutionMode.fixed;
  }
}

/// Secure VNC device profile with encrypted credential storage
class SecureVNCDevice {
  final String id;
  final String name;
  final String host;
  final int port;
  final int vncPort;
  final String path;
  final VNCDisplaySettings displaySettings;
  final DateTime createdAt;
  final DateTime lastUsed;
  final Map<String, dynamic> metadata;

  SecureVNCDevice({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.vncPort,
    required this.path,
    required this.displaySettings,
    required this.createdAt,
    required this.lastUsed,
    this.metadata = const {},
  });

  /// Store VNC password securely (alias for storePassword)
  Future<void> setPassword(String? password) async {
    await storePassword(password);
  }

  /// Store VNC password securely
  Future<void> storePassword(String? password) async {
    if (password == null || password.isEmpty) {
      await SecureStorageService.removeSecureData('vnc_password_$id');
      return;
    }

    await SecureStorageService.storeSecureData('vnc_password_$id', password);
  }

  /// Retrieve VNC password
  Future<String?> getPassword() async {
    return await SecureStorageService.getSecureData('vnc_password_$id');
  }

  /// Clear stored password
  Future<void> clearPassword() async {
    await SecureStorageService.removeSecureData('vnc_password_$id');
  }

  /// Update last used timestamp
  SecureVNCDevice copyWithLastUsed(DateTime lastUsed) {
    return SecureVNCDevice(
      id: id,
      name: name,
      host: host,
      port: port,
      vncPort: vncPort,
      path: path,
      displaySettings: displaySettings,
      createdAt: createdAt,
      lastUsed: lastUsed,
      metadata: metadata,
    );
  }

  /// Convert to JSON (without sensitive data)
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'vncPort': vncPort,
        'path': path,
        'displaySettings': displaySettings.toJson(),
        'createdAt': createdAt.toIso8601String(),
        'lastUsed': lastUsed.toIso8601String(),
        'metadata': metadata,
      };

  /// Create from JSON
  factory SecureVNCDevice.fromJson(Map<String, dynamic> json) =>
      SecureVNCDevice(
        id: json['id'] ?? '',
        name: json['name'] ?? '',
        host: json['host'] ?? '',
        port: json['port'] ?? 6080,
        vncPort: json['vncPort'] ?? 5900,
        path: json['path'] ?? '/vnc.html',
        displaySettings:
            VNCDisplaySettings.fromJson(json['displaySettings'] ?? {}),
        createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
        lastUsed: DateTime.tryParse(json['lastUsed'] ?? '') ?? DateTime.now(),
        metadata: json['metadata'] ?? {},
      );

  /// Generate unique ID for device
  static String generateId(String host, int port) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'vnc_${host}_${port}_$timestamp';
  }
}

/// Secure VNC device manager
class SecureVNCDeviceManager {
  static const String _devicesKey = 'secure_vnc_devices';
  static const int _maxDevices = 20;
  static const int _maxPasswordAge = 30; // days

  /// Save VNC device with secure password storage
  static Future<void> saveDevice(
      SecureVNCDevice device, String? password) async {
    // Store device metadata (non-sensitive)
    final devices = await getAllDevices();
    devices.removeWhere((d) => d.id == device.id);
    devices.insert(0, device);

    // Keep only recent devices
    if (devices.length > _maxDevices) {
      // Remove old devices and their passwords
      final removedDevices = devices.sublist(_maxDevices);
      for (final removedDevice in removedDevices) {
        await removedDevice.clearPassword();
      }
      devices.removeRange(_maxDevices, devices.length);
    }

    // Save device list
    final prefs = await SharedPreferences.getInstance();
    final devicesJson = devices.map((d) => jsonEncode(d.toJson())).toList();
    await prefs.setStringList(_devicesKey, devicesJson);

    // Store password securely
    await device.storePassword(password);
  }

  /// Get all saved devices
  static Future<List<SecureVNCDevice>> getAllDevices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final devicesJson = prefs.getStringList(_devicesKey) ?? [];

      return devicesJson
          .map((jsonStr) => SecureVNCDevice.fromJson(jsonDecode(jsonStr)))
          .toList();
    } catch (e) {
      print('Failed to load VNC devices: $e');
      return [];
    }
  }

  /// Get device by ID
  static Future<SecureVNCDevice?> getDevice(String id) async {
    final devices = await getAllDevices();
    try {
      return devices.firstWhere((d) => d.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Delete device and its credentials
  static Future<void> deleteDevice(String id) async {
    final devices = await getAllDevices();
    final deviceToRemove = devices.where((d) => d.id == id).firstOrNull;

    if (deviceToRemove != null) {
      await deviceToRemove.clearPassword();
      devices.removeWhere((d) => d.id == id);

      final prefs = await SharedPreferences.getInstance();
      final devicesJson = devices.map((d) => jsonEncode(d.toJson())).toList();
      await prefs.setStringList(_devicesKey, devicesJson);
    }
  }

  /// Clean up old passwords
  static Future<void> cleanupOldPasswords() async {
    final devices = await getAllDevices();
    final cutoffDate = DateTime.now().subtract(Duration(days: _maxPasswordAge));

    for (final device in devices) {
      if (device.lastUsed.isBefore(cutoffDate)) {
        await device.clearPassword();
      }
    }
  }

  /// Update device last used timestamp
  static Future<void> updateLastUsed(String id) async {
    final devices = await getAllDevices();
    final deviceIndex = devices.indexWhere((d) => d.id == id);

    if (deviceIndex >= 0) {
      devices[deviceIndex] =
          devices[deviceIndex].copyWithLastUsed(DateTime.now());

      final prefs = await SharedPreferences.getInstance();
      final devicesJson = devices.map((d) => jsonEncode(d.toJson())).toList();
      await prefs.setStringList(_devicesKey, devicesJson);
    }
  }

  /// Clear all devices and credentials
  static Future<void> clearAll() async {
    final devices = await getAllDevices();

    // Clear all passwords
    for (final device in devices) {
      await device.clearPassword();
    }

    // Clear device list
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_devicesKey);
  }

  /// Get connection statistics
  static Future<Map<String, dynamic>> getConnectionStats() async {
    final devices = await getAllDevices();
    final now = DateTime.now();

    final recentDevices =
        devices.where((d) => now.difference(d.lastUsed).inDays <= 7).length;

    final oldDevices =
        devices.where((d) => now.difference(d.lastUsed).inDays > 30).length;

    return {
      'totalDevices': devices.length,
      'recentDevices': recentDevices,
      'oldDevices': oldDevices,
      'lastCleanup': null, // Could be implemented
    };
  }
}
