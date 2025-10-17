import '../adb_client.dart';

class ADBConnectionManager {
  static final ADBConnectionManager _instance = ADBConnectionManager._internal();
  factory ADBConnectionManager() => _instance;
  ADBConnectionManager._internal();
  
  ADBClientManager? _adbClient;
  
  ADBClientManager getADBClient() {
    _adbClient ??= ADBClientManager()..enableFlutterAdbBackend();
    return _adbClient!;
  }
  
  ADBClientManager? get currentClient => _adbClient;
  
  bool get hasActiveConnection => 
    _adbClient != null && _adbClient!.currentState == ADBConnectionState.connected;
  
  void reset() {
    _adbClient = null;
  }
}
