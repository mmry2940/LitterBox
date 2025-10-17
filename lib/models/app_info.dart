class AppInfo {
  final String packageName;
  final String label;
  final bool isSystemApp;
  final bool isEnabled;
  final String version;
  final String versionCode;
  final String apkPath;
  final int size;
  final DateTime? installDate;
  final DateTime? lastUpdateDate;

  AppInfo({
    required this.packageName,
    required this.label,
    required this.isSystemApp,
    required this.isEnabled,
    required this.version,
    required this.versionCode,
    required this.apkPath,
    required this.size,
    this.installDate,
    this.lastUpdateDate,
  });

  factory AppInfo.fromPackageInfo(String packageName, Map<String, String> info) {
    return AppInfo(
      packageName: packageName,
      label: info['label'] ?? packageName,
      isSystemApp: info['flags']?.contains('SYSTEM') ?? false,
      isEnabled: info['enabled'] == 'enabled',
      version: info['versionName'] ?? 'Unknown',
      versionCode: info['versionCode'] ?? '0',
      apkPath: info['codePath'] ?? '',
      size: int.tryParse(info['size'] ?? '0') ?? 0,
      installDate: _parseDate(info['firstInstallTime']),
      lastUpdateDate: _parseDate(info['lastUpdateTime']),
    );
  }

  static DateTime? _parseDate(String? timestamp) {
    if (timestamp == null) return null;
    try {
      final millis = int.parse(timestamp);
      return DateTime.fromMillisecondsSinceEpoch(millis);
    } catch (e) {
      return null;
    }
  }

  String get sizeFormatted {
    if (size < 1024) return '${size}B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)}KB';
    if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }

  String get typeLabel => isSystemApp ? 'System' : 'User';
  String get statusLabel => isEnabled ? 'Enabled' : 'Disabled';
}
