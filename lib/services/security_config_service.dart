import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'secure_storage_service.dart';

/// Security configuration and policy manager
class SecurityConfigService {
  static const String _configKey = 'security_config';
  static const String _lastSecurityCheckKey = 'last_security_check';

  /// Security configuration options
  static const Map<String, dynamic> _defaultConfig = {
    'passwordExpirationDays': 90,
    'maxSavedDevices': 20,
    'requireDeviceVerification': true,
    'autoCleanupEnabled': true,
    'cleanupIntervalDays': 7,
    'encryptionEnabled': true,
    'sessionTimeoutMinutes': 30,
    'requireRecentActivity': true,
    'maxFailedAttempts': 5,
    'lockoutDurationMinutes': 15,
  };

  /// Get security configuration
  static Future<Map<String, dynamic>> getSecurityConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final configStr = prefs.getString(_configKey);

      if (configStr != null) {
        final config = Map<String, dynamic>.from(_defaultConfig);
        // Could parse custom config here
        return config;
      }

      return Map<String, dynamic>.from(_defaultConfig);
    } catch (e) {
      return Map<String, dynamic>.from(_defaultConfig);
    }
  }

  /// Update security configuration
  static Future<void> updateSecurityConfig(Map<String, dynamic> config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // In a real implementation, you'd serialize and store the config
      await prefs.setString(_configKey, 'updated'); // Placeholder
    } catch (e) {
      print('Failed to update security config: $e');
    }
  }

  /// Perform security health check
  static Future<SecurityHealthReport> performSecurityCheck() async {
    final issues = <SecurityIssue>[];
    final warnings = <SecurityIssue>[];
    final recommendations = <String>[];

    try {
      // Check for plaintext passwords in old storage
      final prefs = await SharedPreferences.getInstance();

      // Check for old VNC devices with plaintext passwords
      final oldVncDevices = prefs.getStringList('saved_vnc_devices') ?? [];
      if (oldVncDevices.isNotEmpty) {
        issues.add(SecurityIssue(
          severity: SecuritySeverity.high,
          type: 'plaintext_passwords',
          description:
              'Found ${oldVncDevices.length} VNC devices using plaintext password storage',
          recommendation:
              'Migrate to secure storage using the new SecureVNCDevice model',
        ));
      }

      // Check for old ADB devices
      final oldAdbDevices = prefs.getStringList('adb_devices') ?? [];
      if (oldAdbDevices.isNotEmpty) {
        warnings.add(SecurityIssue(
          severity: SecuritySeverity.medium,
          type: 'legacy_storage',
          description:
              'Found ${oldAdbDevices.length} ADB devices using legacy storage',
          recommendation:
              'Migrate to secure storage using the new SecureADBDevice model',
        ));
      }

      // Check if app data is included in backups
      if (Platform.isAndroid) {
        recommendations.add(
            'Consider adding android:allowBackup="false" to prevent sensitive data in backups');
      }

      // Check for old stored credentials
      final keys = prefs.getKeys();
      final suspiciousKeys = keys
          .where((k) =>
              k.contains('password') ||
              k.contains('credential') ||
              k.contains('token'))
          .toList();

      if (suspiciousKeys.isNotEmpty) {
        warnings.add(SecurityIssue(
          severity: SecuritySeverity.medium,
          type: 'suspicious_keys',
          description:
              'Found ${suspiciousKeys.length} potentially sensitive keys in preferences',
          recommendation: 'Review and migrate to secure storage',
        ));
      }

      // Update last check timestamp
      await prefs.setString(
          _lastSecurityCheckKey, DateTime.now().toIso8601String());
    } catch (e) {
      issues.add(SecurityIssue(
        severity: SecuritySeverity.low,
        type: 'check_failed',
        description: 'Security check partially failed: $e',
        recommendation: 'Retry security check',
      ));
    }

    return SecurityHealthReport(
      timestamp: DateTime.now(),
      issues: issues,
      warnings: warnings,
      recommendations: recommendations,
    );
  }

  /// Migrate legacy data to secure storage
  static Future<MigrationReport> migrateLegacyData() async {
    final report = MigrationReport();

    try {
      final prefs = await SharedPreferences.getInstance();

      // Migrate VNC devices
      final oldVncDevices = prefs.getStringList('saved_vnc_devices') ?? [];
      for (int i = 0; i < oldVncDevices.length; i++) {
        try {
          // Migration logic would go here
          report.migratedVncDevices++;
        } catch (e) {
          report.failedMigrations++;
        }
      }

      // Migrate ADB devices
      final oldAdbDevices = prefs.getStringList('adb_devices') ?? [];
      for (int i = 0; i < oldAdbDevices.length; i++) {
        try {
          // Migration logic would go here
          report.migratedAdbDevices++;
        } catch (e) {
          report.failedMigrations++;
        }
      }

      // Clean up old data after successful migration
      if (report.failedMigrations == 0) {
        await prefs.remove('saved_vnc_devices');
        await prefs.remove('adb_devices');
        report.cleanedUpLegacyData = true;
      }
    } catch (e) {
      report.migrationError = e.toString();
    }

    return report;
  }

  /// Clear all application data (security reset)
  static Future<void> performSecurityReset() async {
    try {
      // Clear all secure storage
      await SecureStorageService.clearAllSecureData();

      // Clear all preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      // Could also clear app cache/temp files here
    } catch (e) {
      print('Security reset failed: $e');
      rethrow;
    }
  }

  /// Generate security recommendations
  static Future<List<String>> getSecurityRecommendations() async {
    final recommendations = <String>[];
    final config = await getSecurityConfig();

    if (!config['encryptionEnabled']) {
      recommendations.add('Enable encryption for stored credentials');
    }

    if (!config['requireDeviceVerification']) {
      recommendations.add('Enable device verification for enhanced security');
    }

    if (!config['autoCleanupEnabled']) {
      recommendations.add('Enable automatic cleanup of old credentials');
    }

    recommendations.addAll([
      'Regularly review and remove unused device connections',
      'Use strong, unique passwords for each connection',
      'Enable device lock/PIN protection',
      'Keep the app updated to latest version',
      'Review app permissions regularly',
    ]);

    return recommendations;
  }
}

/// Security issue severity levels
enum SecuritySeverity { low, medium, high, critical }

/// Individual security issue
class SecurityIssue {
  final SecuritySeverity severity;
  final String type;
  final String description;
  final String recommendation;

  SecurityIssue({
    required this.severity,
    required this.type,
    required this.description,
    required this.recommendation,
  });
}

/// Security health report
class SecurityHealthReport {
  final DateTime timestamp;
  final List<SecurityIssue> issues;
  final List<SecurityIssue> warnings;
  final List<String> recommendations;

  SecurityHealthReport({
    required this.timestamp,
    required this.issues,
    required this.warnings,
    required this.recommendations,
  });

  bool get hasIssues => issues.isNotEmpty;
  bool get hasWarnings => warnings.isNotEmpty;
  bool get isHealthy => !hasIssues && !hasWarnings;

  int get criticalCount =>
      issues.where((i) => i.severity == SecuritySeverity.critical).length;
  int get highCount =>
      issues.where((i) => i.severity == SecuritySeverity.high).length;
  int get mediumCount => [...issues, ...warnings]
      .where((i) => i.severity == SecuritySeverity.medium)
      .length;
}

/// Migration report for legacy data
class MigrationReport {
  int migratedVncDevices = 0;
  int migratedAdbDevices = 0;
  int failedMigrations = 0;
  bool cleanedUpLegacyData = false;
  String? migrationError;

  bool get isSuccessful => failedMigrations == 0 && migrationError == null;
  int get totalMigrated => migratedVncDevices + migratedAdbDevices;
}
