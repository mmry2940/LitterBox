import 'dart:async';
import '../adb_client.dart';
import 'flutter_adb_client.dart';

enum AdbBackendType {
  external, // Uses external adb command
  internal, // Uses embedded adb binaries
  native, // Uses flutter_adb native implementation
  hybrid, // Uses both external/internal + native as needed
}

/// Enhanced ADB manager with multiple backend support
class EnhancedAdbManager {
  ADBClientManager? _traditionalClient;
  FlutterAdbClient? _nativeClient;
  AdbBackendType _currentBackend = AdbBackendType.hybrid;
  bool _preferNativeForConnections = true;

  final StreamController<ADBConnectionState> _connectionStateController =
      StreamController<ADBConnectionState>.broadcast();
  final StreamController<String> _outputController =
      StreamController<String>.broadcast();

  ADBConnectionState _state = ADBConnectionState.disconnected;
  String _connectedDeviceId = '';

  Stream<ADBConnectionState> get connectionState =>
      _connectionStateController.stream;
  Stream<String> get output => _outputController.stream;
  ADBConnectionState get currentState => _state;
  String get connectedDeviceId => _connectedDeviceId;
  AdbBackendType get currentBackend => _currentBackend;
  bool get preferNativeForConnections => _preferNativeForConnections;

  // Access to underlying clients
  ADBClientManager? get traditionalClient => _traditionalClient;
  FlutterAdbClient? get nativeClient => _nativeClient;

  EnhancedAdbManager() {
    _initializeClients();
  }

  void _initializeClients() {
    // Initialize traditional client
    _traditionalClient = ADBClientManager();
    _traditionalClient!.enableExternalAdbBackend();

    // Initialize native client
    _nativeClient = FlutterAdbClient();

    // Forward outputs from both clients
    _traditionalClient!.output.listen((line) {
      _outputController.add('[Traditional] $line');
    });

    _nativeClient!.output.listen((line) {
      _outputController.add('[Native] $line');
    });

    // Forward connection state from the active client
    _traditionalClient!.connectionState.listen((state) {
      if (_currentBackend != AdbBackendType.native) {
        _updateConnectionState(state);
        _connectedDeviceId = _traditionalClient!.connectedDeviceId;
      }
    });

    _nativeClient!.connectionState.listen((state) {
      if (_currentBackend == AdbBackendType.native ||
          _preferNativeForConnections) {
        _updateConnectionState(state);
        _connectedDeviceId = _nativeClient!.connectedDeviceId;
      }
    });
  }

  void setBackend(AdbBackendType backend) {
    _currentBackend = backend;
    _addOutput('Switched to ${backend.name} backend');
  }

  void setPreferNativeForConnections(bool prefer) {
    _preferNativeForConnections = prefer;
    _addOutput(
        'Native connections preference: ${prefer ? 'enabled' : 'disabled'}');
  }

  Future<bool> connectWifi(String host, int port) async {
    switch (_currentBackend) {
      case AdbBackendType.native:
        return await _nativeClient!.connect(host, port);

      case AdbBackendType.hybrid:
        if (_preferNativeForConnections) {
          final success = await _nativeClient!.connect(host, port);
          if (success) return true;
          // Fallback to traditional
          _addOutput(
              'Native connection failed, falling back to traditional ADB');
        }
        return await _traditionalClient!.connectWifi(host, port);

      case AdbBackendType.external:
      case AdbBackendType.internal:
        return await _traditionalClient!.connectWifi(host, port);
    }
  }

  Future<bool> connectUsb(String deviceId) async {
    // USB connections typically work better with traditional adb
    switch (_currentBackend) {
      case AdbBackendType.native:
        _addOutput(
            'USB connections not supported in native mode, using traditional ADB');
        return await _traditionalClient!.connectUSB();

      default:
        return await _traditionalClient!.connectUSB();
    }
  }

  Future<void> disconnect() async {
    await _nativeClient?.disconnect();
    await _traditionalClient?.disconnect();
    _updateConnectionState(ADBConnectionState.disconnected);
    _connectedDeviceId = '';
  }

  Future<String> executeCommand(String command) async {
    final activeClient = _getActiveClient();

    if (activeClient == _nativeClient) {
      return await _nativeClient!.executeCommand(command);
    } else {
      await _traditionalClient!.executeCommand(command);
      return 'Command executed'; // Traditional client doesn't return result
    }
  }

  Future<bool> startLogcat([String filter = '']) async {
    final activeClient = _getActiveClient();

    if (activeClient == _nativeClient) {
      return await _nativeClient!.startLogcat(filter);
    } else {
      if (filter.isNotEmpty) {
        return await _traditionalClient!.startLogcat(filters: [filter]);
      } else {
        return await _traditionalClient!.startLogcat();
      }
    }
  }

  Future<void> stopLogcat() async {
    await _nativeClient?.stopLogcat();
    await _traditionalClient?.stopLogcat();
  }

  Stream<String> get logcatStream {
    final activeClient = _getActiveClient();

    if (activeClient == _nativeClient) {
      return _nativeClient!.logcatStream;
    } else {
      return _traditionalClient!.logcatStream;
    }
  }

  bool get logcatActive {
    if (_nativeClient?.logcatActive == true) return true;
    if (_traditionalClient?.logcatActive == true) return true;
    return false;
  }

  Future<bool> openShell() async {
    final activeClient = _getActiveClient();

    if (activeClient == _nativeClient) {
      return await _nativeClient!.openShell();
    } else {
      return await _traditionalClient!.startInteractiveShell();
    }
  }

  Future<bool> writeToShell(String input) async {
    final activeClient = _getActiveClient();

    if (activeClient == _nativeClient) {
      return await _nativeClient!.writeToShell(input);
    } else {
      // Traditional client handles shell input differently
      await _traditionalClient!.executeCommand(input);
      return true;
    }
  }

  Future<void> closeShell() async {
    await _nativeClient?.closeShell();
    await _traditionalClient?.stopInteractiveShell();
  }

  Future<String> getDeviceInfo() async {
    final activeClient = _getActiveClient();

    if (activeClient == _nativeClient) {
      return await _nativeClient!.getDeviceProperties();
    } else {
      // Use traditional client for device info
      final commands = [
        'getprop ro.build.version.release',
        'getprop ro.product.model',
        'getprop ro.product.manufacturer',
        'getprop ro.build.version.sdk'
      ];

      final results = <String>[];
      for (final cmd in commands) {
        try {
          await _traditionalClient!.executeCommand(cmd);
          // Note: Traditional client outputs to stream, not return value
        } catch (e) {
          results.add('Error executing $cmd: $e');
        }
      }

      return 'Device info commands executed (see console output)';
    }
  }

  Future<List<String>> listDevices() async {
    switch (_currentBackend) {
      case AdbBackendType.native:
        return await _nativeClient!.listDevices();

      default:
        // Use traditional client for device listing
        final devices = await _traditionalClient!.backend?.listDevices() ?? [];
        return devices.map((d) => d.serial).toList();
    }
  }

  // File operations (prefer traditional ADB for better file transfer support)
  Future<String> pushFile(String localPath, String remotePath) async {
    if (_traditionalClient != null) {
      await _traditionalClient!
          .executeCommand('push "$localPath" "$remotePath"');
      return 'File push initiated (see console for result)';
    } else {
      return await _nativeClient!.pushFile(localPath, remotePath);
    }
  }

  Future<String> pullFile(String remotePath, String localPath) async {
    if (_traditionalClient != null) {
      await _traditionalClient!
          .executeCommand('pull "$remotePath" "$localPath"');
      return 'File pull initiated (see console for result)';
    } else {
      return await _nativeClient!.pullFile(remotePath, localPath);
    }
  }

  Future<String> installApk(String apkPath) async {
    if (_traditionalClient != null) {
      await _traditionalClient!.executeCommand('install "$apkPath"');
      return 'APK installation initiated (see console for result)';
    } else {
      return await _nativeClient!.installApk(apkPath);
    }
  }

  /// Determines which client should handle the current operation
  dynamic _getActiveClient() {
    if (_state == ADBConnectionState.connected) {
      if (_nativeClient?.isConnected == true) {
        return _nativeClient;
      } else if (_traditionalClient?.currentState ==
          ADBConnectionState.connected) {
        return _traditionalClient;
      }
    }

    // Default based on backend preference
    switch (_currentBackend) {
      case AdbBackendType.native:
        return _nativeClient;
      case AdbBackendType.hybrid:
        return _preferNativeForConnections ? _nativeClient : _traditionalClient;
      default:
        return _traditionalClient;
    }
  }

  void _addOutput(String message) {
    _outputController.add(message);
  }

  void _updateConnectionState(ADBConnectionState state) {
    _state = state;
    _connectionStateController.add(state);
  }

  void dispose() {
    _nativeClient?.dispose();
    _traditionalClient?.dispose();
    _connectionStateController.close();
    _outputController.close();
  }

  // Backend-specific methods
  void enableExternalAdbBackend() {
    _traditionalClient?.enableExternalAdbBackend();
  }

  void enableInternalAdbBackend() {
    _traditionalClient?.enableInternalAdbBackend();
  }

  ADBOutputMode get outputMode =>
      _traditionalClient?.outputMode ?? ADBOutputMode.raw;
  void setOutputMode(ADBOutputMode mode) =>
      _traditionalClient?.setOutputMode(mode);

  List<String> get outputBuffer => _traditionalClient?.outputBuffer ?? [];
  void clearOutput() => _traditionalClient?.clearOutput();

  List<String> get commandHistoryList =>
      _traditionalClient?.commandHistoryList ?? [];
  void clearHistory() => _traditionalClient?.clearHistory();

  Map<String, List<String>> get quickCommands =>
      _traditionalClient?.quickCommands ?? {};
}
