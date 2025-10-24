import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/secure_storage_service.dart';
import '../adb_client.dart';
import 'package:crypto/crypto.dart';

/// Enhanced secure ADB device with validation and security features
class SecureADBDevice {
  final String id;
  final String name;
  final String host;
  final int port;
  final ADBConnectionType connectionType;
  final DateTime createdAt;
  final DateTime lastUsed;
  final String? label;
  final String? note;
  final bool isVerified;
  final String? deviceFingerprint;

  SecureADBDevice({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.connectionType,
    required this.createdAt,
    required this.lastUsed,
    this.label,
    this.note,
    this.isVerified = false,
    this.deviceFingerprint,
  });

  /// Generate device fingerprint for validation
  static String generateFingerprint(String host, int port, String deviceId) {
    final input =
        '$host:$port:$deviceId:${DateTime.now().millisecondsSinceEpoch}';
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16);
  }

  /// Store ADB-specific secure data (like pairing codes)
  Future<void> storePairingCode(String? code) async {
    if (code == null || code.isEmpty) {
      await SecureStorageService.removeSecureData('adb_pairing_$id');
      return;
    }

    await SecureStorageService.storeSecureData('adb_pairing_$id', code);
  }

  /// Retrieve pairing code
  Future<String?> getPairingCode() async {
    return await SecureStorageService.getSecureData('adb_pairing_$id');
  }

  /// Clear pairing code
  Future<void> clearPairingCode() async {
    await SecureStorageService.removeSecureData('adb_pairing_$id');
  }

  /// Update device with new information
  SecureADBDevice copyWith({
    String? name,
    String? host,
    int? port,
    ADBConnectionType? connectionType,
    DateTime? lastUsed,
    String? label,
    String? note,
    bool? isVerified,
    String? deviceFingerprint,
  }) {
    return SecureADBDevice(
      id: id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      connectionType: connectionType ?? this.connectionType,
      createdAt: createdAt,
      lastUsed: lastUsed ?? this.lastUsed,
      label: label ?? this.label,
      note: note ?? this.note,
      isVerified: isVerified ?? this.isVerified,
      deviceFingerprint: deviceFingerprint ?? this.deviceFingerprint,
    );
  }

  /// Convert to JSON (excluding sensitive data)
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'connectionType': connectionType.index,
        'createdAt': createdAt.toIso8601String(),
        'lastUsed': lastUsed.toIso8601String(),
        'label': label,
        'note': note,
        'isVerified': isVerified,
        'deviceFingerprint': deviceFingerprint,
      };

  /// Create from JSON
  factory SecureADBDevice.fromJson(Map<String, dynamic> json) =>
      SecureADBDevice(
        id: json['id'] ?? '',
        name: json['name'] ?? '',
        host: json['host'] ?? '',
        port: json['port'] ?? 5555,
        connectionType: ADBConnectionType.values[json['connectionType'] ?? 0],
        createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
        lastUsed: DateTime.tryParse(json['lastUsed'] ?? '') ?? DateTime.now(),
        label: json['label'],
        note: json['note'],
        isVerified: json['isVerified'] ?? false,
        deviceFingerprint: json['deviceFingerprint'],
      );

  /// Generate unique ID for device
  static String generateId(String host, int port, ADBConnectionType type) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'adb_${type.name}_${host}_${port}_$timestamp';
  }
}

/// Secure ADB device manager with enhanced security
class SecureADBDeviceManager {
  static const String _devicesKey = 'secure_adb_devices';
  static const String _authorizedKeysKey = 'adb_authorized_keys_secure';
  static const int _maxDevices = 25;
  static const int _maxKeyAge = 90; // days

  /// Save ADB device with security validation
  static Future<void> saveDevice(SecureADBDevice device,
      {String? pairingCode}) async {
    final devices = await getAllDevices();

    // Remove existing device with same host:port
    devices.removeWhere((d) => d.host == device.host && d.port == device.port);
    devices.insert(0, device);

    // Limit number of saved devices
    if (devices.length > _maxDevices) {
      final removedDevices = devices.sublist(_maxDevices);
      for (final removedDevice in removedDevices) {
        await removedDevice.clearPairingCode();
      }
      devices.removeRange(_maxDevices, devices.length);
    }

    // Save device list
    final prefs = await SharedPreferences.getInstance();
    final devicesJson = devices.map((d) => jsonEncode(d.toJson())).toList();
    await prefs.setStringList(_devicesKey, devicesJson);

    // Store pairing code if provided
    if (pairingCode != null) {
      await device.storePairingCode(pairingCode);
    }
  }

  /// Get all saved devices
  static Future<List<SecureADBDevice>> getAllDevices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final devicesJson = prefs.getStringList(_devicesKey) ?? [];

      return devicesJson
          .map((jsonStr) => SecureADBDevice.fromJson(jsonDecode(jsonStr)))
          .toList();
    } catch (e) {
      print('Failed to load ADB devices: $e');
      return [];
    }
  }

  /// Get device by ID
  static Future<SecureADBDevice?> getDevice(String id) async {
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
      await deviceToRemove.clearPairingCode();
      devices.removeWhere((d) => d.id == id);

      final prefs = await SharedPreferences.getInstance();
      final devicesJson = devices.map((d) => jsonEncode(d.toJson())).toList();
      await prefs.setStringList(_devicesKey, devicesJson);
    }
  }

  /// Verify device fingerprint
  static Future<bool> verifyDevice(String id, String actualDeviceId) async {
    final device = await getDevice(id);
    if (device == null) return false;

    final expectedFingerprint = SecureADBDevice.generateFingerprint(
        device.host, device.port, actualDeviceId);

    return device.deviceFingerprint == expectedFingerprint;
  }

  /// Update device verification status
  static Future<void> markDeviceVerified(String id, String deviceId) async {
    final devices = await getAllDevices();
    final deviceIndex = devices.indexWhere((d) => d.id == id);

    if (deviceIndex >= 0) {
      final fingerprint = SecureADBDevice.generateFingerprint(
        devices[deviceIndex].host,
        devices[deviceIndex].port,
        deviceId,
      );

      devices[deviceIndex] = devices[deviceIndex].copyWith(
        isVerified: true,
        deviceFingerprint: fingerprint,
        lastUsed: DateTime.now(),
      );

      final prefs = await SharedPreferences.getInstance();
      final devicesJson = devices.map((d) => jsonEncode(d.toJson())).toList();
      await prefs.setStringList(_devicesKey, devicesJson);
    }
  }

  /// Store authorized key with expiration
  static Future<void> storeAuthorizedKey(
      String deviceId, String keyFingerprint) async {
    final prefs = await SharedPreferences.getInstance();
    final authorizedKeys = prefs.getStringList(_authorizedKeysKey) ?? [];

    final keyData = {
      'deviceId': deviceId,
      'keyFingerprint': keyFingerprint,
      'authorizedAt': DateTime.now().toIso8601String(),
    };

    // Remove existing entry for this device
    authorizedKeys.removeWhere((keyStr) {
      try {
        final existing = jsonDecode(keyStr);
        return existing['deviceId'] == deviceId;
      } catch (e) {
        return false;
      }
    });

    authorizedKeys.add(jsonEncode(keyData));
    await prefs.setStringList(_authorizedKeysKey, authorizedKeys);
  }

  /// Check if key is authorized and not expired
  static Future<bool> isKeyAuthorized(
      String deviceId, String keyFingerprint) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final authorizedKeys = prefs.getStringList(_authorizedKeysKey) ?? [];

      for (final keyStr in authorizedKeys) {
        final keyData = jsonDecode(keyStr);
        if (keyData['deviceId'] == deviceId &&
            keyData['keyFingerprint'] == keyFingerprint) {
          final authorizedAt = DateTime.parse(keyData['authorizedAt']);
          final age = DateTime.now().difference(authorizedAt).inDays;

          if (age <= _maxKeyAge) {
            return true;
          }
        }
      }

      return false;
    } catch (e) {
      print('Failed to check key authorization: $e');
      return false;
    }
  }

  /// Clean up expired keys and old devices
  static Future<void> performSecurityCleanup() async {
    // Clean up expired keys
    final prefs = await SharedPreferences.getInstance();
    final authorizedKeys = prefs.getStringList(_authorizedKeysKey) ?? [];
    final validKeys = <String>[];

    for (final keyStr in authorizedKeys) {
      try {
        final keyData = jsonDecode(keyStr);
        final authorizedAt = DateTime.parse(keyData['authorizedAt']);
        final age = DateTime.now().difference(authorizedAt).inDays;

        if (age <= _maxKeyAge) {
          validKeys.add(keyStr);
        }
      } catch (e) {
        // Skip invalid entries
      }
    }

    await prefs.setStringList(_authorizedKeysKey, validKeys);

    // Clean up old device pairing codes
    final devices = await getAllDevices();
    final cutoffDate = DateTime.now().subtract(Duration(days: 30));

    for (final device in devices) {
      if (device.lastUsed.isBefore(cutoffDate)) {
        await device.clearPairingCode();
      }
    }
  }

  /// Get security statistics
  static Future<Map<String, dynamic>> getSecurityStats() async {
    final devices = await getAllDevices();
    final prefs = await SharedPreferences.getInstance();
    final authorizedKeys = prefs.getStringList(_authorizedKeysKey) ?? [];

    final verifiedCount = devices.where((d) => d.isVerified).length;
    final recentlyUsed = devices
        .where((d) => DateTime.now().difference(d.lastUsed).inDays <= 7)
        .length;

    return {
      'totalDevices': devices.length,
      'verifiedDevices': verifiedCount,
      'recentlyUsedDevices': recentlyUsed,
      'authorizedKeys': authorizedKeys.length,
      'lastCleanup': null, // Could track cleanup timestamp
    };
  }

  /// Clear all devices and credentials
  static Future<void> clearAll() async {
    final devices = await getAllDevices();

    // Clear all pairing codes
    for (final device in devices) {
      await device.clearPairingCode();
    }

    // Clear device list and authorized keys
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_devicesKey);
    await prefs.remove(_authorizedKeysKey);
  }
}
