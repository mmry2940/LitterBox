import '../adb_client.dart';

/// Singleton ADB connection manager that ensures only one ADB connection exists
/// and can be shared across different screens
class SharedADBManager {
  static SharedADBManager? _instance;
  static ADBClientManager? _adbClient;
  
  // Private constructor
  SharedADBManager._();
  
  /// Get the singleton instance
  static SharedADBManager get instance {
    _instance ??= SharedADBManager._();
    return _instance!;
  }
  
  /// Get the shared ADB client, creating it if necessary
  ADBClientManager getSharedClient() {
    if (_adbClient == null) {
      _adbClient = ADBClientManager();
      _adbClient!.enableFlutterAdbBackend();
    }
    return _adbClient!;
  }
  
  /// Check if there's an active connection
  bool get hasActiveConnection => 
    _adbClient != null && _adbClient!.currentState == ADBConnectionState.connected;
  
  /// Get the current connection state
  ADBConnectionState get connectionState => 
    _adbClient?.currentState ?? ADBConnectionState.disconnected;
  
  /// Get the connected device ID
  String get connectedDeviceId => _adbClient?.connectedDeviceId ?? '';
  
  /// Reset the connection (for cleanup)
  Future<void> reset() async {
    if (_adbClient != null) {
      try {
        await _adbClient!.disconnect();
      } catch (e) {
        print('Error disconnecting ADB: $e');
      }
      _adbClient = null;
    }
  }
  
  /// Force dispose everything (for app shutdown)
  void dispose() {
    _adbClient = null;
    _instance = null;
  }
}
