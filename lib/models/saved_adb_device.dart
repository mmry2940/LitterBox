import '../adb_client.dart';

/// Persisted ADB device connection profile.
class SavedADBDevice {
  final String name;
  final String host;
  final int port;
  final ADBConnectionType connectionType;

  SavedADBDevice({
    required this.name,
    required this.host,
    required this.port,
    required this.connectionType,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'host': host,
        'port': port,
        'connectionType': connectionType.index,
      };

  factory SavedADBDevice.fromJson(Map<String, dynamic> json) => SavedADBDevice(
        name: json['name'] ?? '',
        host: json['host'] ?? '',
        port: json['port'] ?? 5555,
        connectionType: ADBConnectionType.values[json['connectionType'] ?? 0],
      );
}
