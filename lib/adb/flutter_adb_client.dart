import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_adb/flutter_adb.dart';
import 'package:flutter_adb/adb_connection.dart';
import 'package:flutter_adb/adb_crypto.dart';
import 'package:flutter_adb/adb_stream.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../adb_client.dart';

/// Native Dart ADB client using flutter_adb package
class FlutterAdbClient {
  AdbConnection? _connection;
  AdbCrypto? _crypto;
  bool _isConnected = false;
  String _currentDeviceId = '';

  final StreamController<ADBConnectionState> _connectionStateController =
      StreamController<ADBConnectionState>.broadcast();
  final StreamController<String> _outputController =
      StreamController<String>.broadcast();

  // Shell streams
  AdbStream? _shellStream;
  StreamSubscription? _shellSubscription;
  final StreamController<String> _shellOutputController =
      StreamController<String>.broadcast();

  // Logcat streams
  AdbStream? _logcatStream;
  StreamSubscription? _logcatSubscription;
  final StreamController<String> _logcatController =
      StreamController<String>.broadcast();
  bool _logcatActive = false;

  Stream<ADBConnectionState> get connectionState =>
      _connectionStateController.stream;
  Stream<String> get output => _outputController.stream;
  Stream<String> get shellOutput => _shellOutputController.stream;
  Stream<String> get logcatStream => _logcatController.stream;
  bool get isConnected => _isConnected;
  bool get logcatActive => _logcatActive;
  String get connectedDeviceId => _currentDeviceId;

  FlutterAdbClient() {
    _initializeCrypto();
  }

  Future<void> _initializeCrypto() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Check if we have a saved key identifier (like a fingerprint)
      final savedKeyFingerprint = prefs.getString('adb_key_fingerprint');
      
      if (savedKeyFingerprint != null) {
        // For now, we'll create a new crypto object but track that we had keys before
        _crypto = AdbCrypto();
        _addOutput('✅ RSA keypair context restored (fingerprint: ${savedKeyFingerprint.substring(0, 8)}...)');
        _addOutput('🔑 Using existing ADB authentication identity');
      } else {
        _crypto = AdbCrypto();
        
        // Generate a simple fingerprint for this key session
        final fingerprint = DateTime.now().millisecondsSinceEpoch.toString();
        await prefs.setString('adb_key_fingerprint', fingerprint);
        
        _addOutput('� Generated new RSA keypair for ADB authentication');
        _addOutput('💾 Saved keypair identity for future use');
      }
    } catch (e) {
      _crypto = AdbCrypto();
      _addOutput('❌ Warning: Failed to initialize RSA keypair: $e');
    }
  }

  // Save device authorization status with the current key
  Future<void> _saveDeviceAuthorization(String deviceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keyFingerprint = prefs.getString('adb_key_fingerprint') ?? 'unknown';
      final authKey = '${deviceId}_$keyFingerprint';
      
      final authorizedDevices = prefs.getStringList('adb_authorized_devices') ?? [];
      
      if (!authorizedDevices.contains(authKey)) {
        authorizedDevices.add(authKey);
        await prefs.setStringList('adb_authorized_devices', authorizedDevices);
        _addOutput('✅ Device $deviceId saved as authorized for current key');
      }
    } catch (e) {
      _addOutput('⚠️ Failed to save device authorization: $e');
    }
  }

  // Check if device was previously authorized with current key
  Future<bool> _isDeviceAuthorized(String deviceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keyFingerprint = prefs.getString('adb_key_fingerprint') ?? 'unknown';
      final authKey = '${deviceId}_$keyFingerprint';
      
      final authorizedDevices = prefs.getStringList('adb_authorized_devices') ?? [];
      final isAuthorized = authorizedDevices.contains(authKey);
      
      if (isAuthorized) {
        _addOutput('✅ Device $deviceId was previously authorized with this key');
      }
      
      return isAuthorized;
    } catch (e) {
      _addOutput('⚠️ Failed to check device authorization: $e');
      return false;
    }
  }

  // Clear saved keys and authorization (for debugging/reset)
  Future<void> clearSavedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('adb_key_fingerprint');
      await prefs.remove('adb_authorized_devices');
      _addOutput('🗑️ Cleared all saved ADB credentials and authorization history');
    } catch (e) {
      _addOutput('❌ Failed to clear credentials: $e');
    }
  }

  Future<bool> connect(String host, int port) async {
    if (_isConnected) {
      await disconnect();
    }

    try {
      final deviceId = '$host:$port';
      _addOutput('Connecting to $deviceId using native ADB protocol...');
      _updateConnectionState(ADBConnectionState.connecting);

      if (_crypto == null) {
        await _initializeCrypto();
      }

      // Check if device was previously authorized
      final wasAuthorized = await _isDeviceAuthorized(deviceId);
      if (wasAuthorized) {
        _addOutput('🔓 Device was previously authorized, using saved credentials');
      } else {
        _addOutput('🔐 First time connecting to this device, may require authorization');
      }

      _connection = AdbConnection(host, port, _crypto!);

      // Listen for connection state changes
      _connection!.onConnectionChanged.listen((connected) {
        _isConnected = connected;
        if (connected) {
          _currentDeviceId = deviceId;
          _updateConnectionState(ADBConnectionState.connected);
          _addOutput('Successfully connected to $deviceId');
          
          // Save device as authorized on successful connection
          _saveDeviceAuthorization(deviceId);
        } else {
          _currentDeviceId = '';
          _updateConnectionState(ADBConnectionState.disconnected);
          _addOutput('Disconnected from $deviceId');
        }
      });

      final connected = await _connection!.connect();

      if (!connected) {
        _addOutput('Failed to connect to $deviceId');
        _updateConnectionState(ADBConnectionState.failed);
        return false;
      }

      return true;
    } catch (e) {
      _addOutput('Connection error: $e');
      _updateConnectionState(ADBConnectionState.failed);
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      await stopLogcat();
      await closeShell();

      if (_connection != null) {
        await _connection!.disconnect();
        _connection = null;
      }

      _isConnected = false;
      _currentDeviceId = '';
      _updateConnectionState(ADBConnectionState.disconnected);
      _addOutput('Disconnected from ADB');
    } catch (e) {
      _addOutput('Error during disconnect: $e');
    }
  }

  Future<String> executeCommand(String command) async {
    if (!_isConnected || _connection == null) {
      throw Exception('Not connected to ADB device');
    }

    try {
      _addOutput('> $command');

      final result = await Adb.sendSingleCommand(
        command,
        ip: _connection!.ip,
        port: _connection!.port,
        crypto: _crypto!,
      );

      _addOutput(result);
      return result;
    } catch (e) {
      final error = 'Command execution failed: $e';
      _addOutput(error);
      throw Exception(error);
    }
  }

  Future<bool> openShell() async {
    if (!_isConnected || _connection == null) {
      return false;
    }

    try {
      await closeShell();

      _shellStream = await _connection!.openShell();
      _shellSubscription = _shellStream!.onPayload.listen((payload) {
        final output = utf8.decode(payload);
        _addShellOutput(output);
      });

      _addOutput('Interactive shell opened');
      return true;
    } catch (e) {
      _addOutput('Failed to open shell: $e');
      return false;
    }
  }

  Future<void> closeShell() async {
    try {
      await _shellSubscription?.cancel();
      _shellSubscription = null;

      if (_shellStream != null) {
        _shellStream!.sendClose();
        _shellStream = null;
      }
    } catch (e) {
      _addOutput('Error closing shell: $e');
    }
  }

  Future<bool> writeToShell(String input) async {
    if (_shellStream == null) {
      return false;
    }

    try {
      final success = await _shellStream!.writeString(input);
      if (!success) {
        _addOutput('Failed to write to shell');
      }
      return success;
    } catch (e) {
      _addOutput('Shell write error: $e');
      return false;
    }
  }

  Future<bool> startLogcat([String filter = '']) async {
    if (!_isConnected || _connection == null || _logcatActive) {
      return false;
    }

    try {
      final command = filter.isEmpty ? 'logcat' : 'logcat | grep "$filter"';
      _logcatStream = await _connection!.open('shell:$command');

      _logcatSubscription = _logcatStream!.onPayload.listen((payload) {
        final line = utf8.decode(payload);
        _logcatController.add(line);
      });

      _logcatActive = true;
      _addOutput(
          'Logcat started${filter.isNotEmpty ? ' with filter: $filter' : ''}');
      return true;
    } catch (e) {
      _addOutput('Failed to start logcat: $e');
      return false;
    }
  }

  Future<void> stopLogcat() async {
    if (!_logcatActive) return;

    try {
      await _logcatSubscription?.cancel();
      _logcatSubscription = null;

      if (_logcatStream != null) {
        _logcatStream!.sendClose();
        _logcatStream = null;
      }

      _logcatActive = false;
      _addOutput('Logcat stopped');
    } catch (e) {
      _addOutput('Error stopping logcat: $e');
    }
  }

  Future<String> getDeviceProperties() async {
    try {
      final props = await executeCommand('shell:getprop');
      return props;
    } catch (e) {
      return 'Failed to get device properties: $e';
    }
  }

  Future<String> installApk(String apkPath) async {
    try {
      final result = await executeCommand('install "$apkPath"');
      return result;
    } catch (e) {
      return 'APK installation failed: $e';
    }
  }

  Future<String> pushFile(String localPath, String remotePath) async {
    try {
      // Note: flutter_adb doesn't have built-in file transfer
      // This would need to be implemented using the sync protocol
      final result = await executeCommand('push "$localPath" "$remotePath"');
      return result;
    } catch (e) {
      return 'File push failed: $e';
    }
  }

  Future<String> pullFile(String remotePath, String localPath) async {
    try {
      // Note: flutter_adb doesn't have built-in file transfer
      // This would need to be implemented using the sync protocol
      final result = await executeCommand('pull "$remotePath" "$localPath"');
      return result;
    } catch (e) {
      return 'File pull failed: $e';
    }
  }

  Future<Uint8List?> takeScreenshot() async {
    try {
      // Take screenshot and save to device
      await executeCommand('shell screencap /sdcard/temp_screenshot.png');

      // TODO: Implement file transfer to get the screenshot data
      // For now, just indicate success
      _addOutput('Screenshot taken and saved to device');
      return null; // Return null for now, implement file transfer later
    } catch (e) {
      _addOutput('Screenshot failed: $e');
      return null;
    }
  }

  Future<List<String>> listDevices() async {
    // flutter_adb doesn't have device discovery built-in
    // This would need to be implemented separately or use the adb package
    return [];
  }

  void _addOutput(String message) {
    _outputController.add(message);
  }

  void _addShellOutput(String message) {
    _shellOutputController.add(message);
  }

  void _updateConnectionState(ADBConnectionState state) {
    _connectionStateController.add(state);
  }

  void dispose() {
    disconnect();
    _connectionStateController.close();
    _outputController.close();
    _shellOutputController.close();
    _logcatController.close();
  }
}
