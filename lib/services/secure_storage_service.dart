import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Secure storage service for sensitive connection data
class SecureStorageService {
  static const String _keyPrefix = 'secure_';
  static const String _saltKey = 'app_salt';

  // Generate or retrieve app-specific salt
  static Future<Uint8List> _getOrCreateSalt() async {
    final prefs = await SharedPreferences.getInstance();
    final saltString = prefs.getString(_saltKey);

    if (saltString != null) {
      return base64Decode(saltString);
    }

    // Generate new salt
    final random = Random.secure();
    final salt =
        Uint8List.fromList(List.generate(32, (_) => random.nextInt(256)));
    await prefs.setString(_saltKey, base64Encode(salt));
    return salt;
  }

  // Simple encryption using device-specific key derivation
  static Future<String> _encrypt(String plaintext, String keyId) async {
    try {
      final salt = await _getOrCreateSalt();
      final key = _deriveKey(keyId, salt);

      // Simple XOR encryption with key rotation
      final plaintextBytes = utf8.encode(plaintext);
      final encrypted = <int>[];

      for (int i = 0; i < plaintextBytes.length; i++) {
        final keyByte = key[i % key.length];
        encrypted.add(plaintextBytes[i] ^ keyByte);
      }

      return base64Encode(encrypted);
    } catch (e) {
      throw Exception('Encryption failed: $e');
    }
  }

  static Future<String> _decrypt(String ciphertext, String keyId) async {
    try {
      final salt = await _getOrCreateSalt();
      final key = _deriveKey(keyId, salt);

      final encryptedBytes = base64Decode(ciphertext);
      final decrypted = <int>[];

      for (int i = 0; i < encryptedBytes.length; i++) {
        final keyByte = key[i % key.length];
        decrypted.add(encryptedBytes[i] ^ keyByte);
      }

      return utf8.decode(decrypted);
    } catch (e) {
      throw Exception('Decryption failed: $e');
    }
  }

  static Uint8List _deriveKey(String keyId, Uint8List salt) {
    final keyMaterial = utf8.encode(keyId);
    final combined = [...keyMaterial, ...salt];
    final digest = sha256.convert(combined);
    return Uint8List.fromList(digest.bytes);
  }

  /// Store encrypted credential
  static Future<void> storeSecureData(String key, String data) async {
    final prefs = await SharedPreferences.getInstance();
    final encrypted = await _encrypt(data, key);
    await prefs.setString('$_keyPrefix$key', encrypted);
  }

  /// Retrieve and decrypt credential
  static Future<String?> getSecureData(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encrypted = prefs.getString('$_keyPrefix$key');

      if (encrypted == null) return null;

      return await _decrypt(encrypted, key);
    } catch (e) {
      print('Failed to retrieve secure data for key $key: $e');
      return null;
    }
  }

  /// Remove secure data
  static Future<void> removeSecureData(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_keyPrefix$key');
  }

  /// Clear all secure data
  static Future<void> clearAllSecureData() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_keyPrefix));

    for (final key in keys) {
      await prefs.remove(key);
    }

    // Also remove salt to force regeneration
    await prefs.remove(_saltKey);
  }

  /// Check if secure data exists
  static Future<bool> hasSecureData(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('$_keyPrefix$key');
  }

  /// Get all secure VNC devices
  Future<List<dynamic>> getSecureVNCDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final devicesJson = prefs.getString('secure_vnc_devices_list');
    if (devicesJson != null) {
      return jsonDecode(devicesJson);
    }
    return [];
  }

  /// Save secure VNC device
  Future<void> saveSecureVNCDevice(dynamic device) async {
    final prefs = await SharedPreferences.getInstance();
    final devices = await getSecureVNCDevices();
    devices.removeWhere((d) => d['id'] == device.id);
    devices.add(device.toJson());
    await prefs.setString('secure_vnc_devices_list', jsonEncode(devices));
  }

  /// Delete secure VNC device
  Future<void> deleteSecureVNCDevice(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final devices = await getSecureVNCDevices();
    devices.removeWhere((d) => d['id'] == id);
    await prefs.setString('secure_vnc_devices_list', jsonEncode(devices));
    await removeSecureData('vnc_password_$id');
  }
}

/// Enhanced connection profile with security features
abstract class SecureConnectionProfile {
  String get id;
  String get name;
  String get host;
  int get port;
  DateTime get createdAt;
  DateTime get lastUsed;

  /// Store sensitive data securely
  Future<void> storeCredentials(Map<String, String> credentials);

  /// Retrieve sensitive data
  Future<Map<String, String?>> getCredentials();

  /// Clear stored credentials
  Future<void> clearCredentials();

  /// Validate connection before use
  Future<bool> validateConnection();
}
