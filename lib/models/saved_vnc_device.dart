/// Legacy VNC device model for backwards compatibility
class SavedVNCDevice {
  final String name;
  final String host;
  final int port;
  final int vncPort;
  final String path;
  final String? password;
  final String scalingMode;
  final String inputMode;
  final VNCResolutionMode resolutionMode;

  SavedVNCDevice({
    required this.name,
    required this.host,
    required this.port,
    required this.vncPort,
    required this.path,
    this.password,
    required this.scalingMode,
    required this.inputMode,
    required this.resolutionMode,
  });

  factory SavedVNCDevice.fromJson(Map<String, dynamic> json) {
    return SavedVNCDevice(
      name: json['name'] ?? '',
      host: json['host'] ?? '',
      port: json['port'] ?? 6080,
      vncPort: json['vncPort'] ?? 5900,
      path: json['path'] ?? '/vnc.html',
      password: json['password'],
      scalingMode: json['scalingMode'] ?? 'autoFitBest',
      inputMode: json['inputMode'] ?? 'directTouch',
      resolutionMode: _parseResolutionMode(json['resolutionMode']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'host': host,
      'port': port,
      'vncPort': vncPort,
      'path': path,
      'password': password,
      'scalingMode': scalingMode,
      'inputMode': inputMode,
      'resolutionMode': resolutionMode.toString().split('.').last,
    };
  }

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

// Import VNCResolutionMode enum from vnc_client
enum VNCResolutionMode {
  fixed,
  dynamic,
}
