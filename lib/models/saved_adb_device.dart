import '../adb_client.dart';

/// Persisted ADB device connection profile.
class SavedADBDevice {
  final String name;
  final String host;
  final int port;
  final ADBConnectionType connectionType;
  String? label;
  String? note;
  final DateTime? lastUsed;
  final bool? isConnected;

  SavedADBDevice({
    required this.name,
    required this.host,
    required this.port,
    required this.connectionType,
    this.label,
    this.note,
    this.lastUsed,
    this.isConnected,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'host': host,
        'port': port,
        'connectionType': connectionType.index,
        'label': label,
        'note': note,
        'lastUsed': lastUsed?.toIso8601String(),
        'isConnected': isConnected,
      };

  factory SavedADBDevice.fromJson(Map<String, dynamic> json) => SavedADBDevice(
        name: json['name'] ?? '',
        host: json['host'] ?? '',
        port: json['port'] ?? 5555,
        connectionType: ADBConnectionType.values[json['connectionType'] ?? 0],
        label: json['label'],
        note: json['note'],
        lastUsed: json['lastUsed'] != null ? DateTime.tryParse(json['lastUsed']) : null,
        isConnected: json['isConnected'],
      );
}
