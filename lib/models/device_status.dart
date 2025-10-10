class DeviceStatus {
  final bool isOnline;
  final int? pingMs;
  final DateTime lastChecked;

  const DeviceStatus({
    required this.isOnline,
    this.pingMs,
    required this.lastChecked,
  });

  DeviceStatus copyWith({
    bool? isOnline,
    int? pingMs,
    DateTime? lastChecked,
  }) {
    return DeviceStatus(
      isOnline: isOnline ?? this.isOnline,
      pingMs: pingMs ?? this.pingMs,
      lastChecked: lastChecked ?? this.lastChecked,
    );
  }
}
