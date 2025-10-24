import 'package:flutter/material.dart';
import '../services/security_config_service.dart';

import '../models/secure_vnc_device.dart';
import '../models/secure_adb_device.dart';

class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  bool _loading = true;
  SecurityHealthReport? _healthReport;
  Map<String, dynamic>? _securityStats;

  @override
  void initState() {
    super.initState();
    _loadSecurityData();
  }

  Future<void> _loadSecurityData() async {
    setState(() => _loading = true);

    try {
      final healthReport = await SecurityConfigService.performSecurityCheck();
      final adbStats = await SecureADBDeviceManager.getSecurityStats();
      final vncStats = await SecureVNCDeviceManager.getConnectionStats();
      setState(() {
        _healthReport = healthReport;
        _securityStats = {
          'adb': adbStats,
          'vnc': vncStats,
        };
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      _showError('Failed to load security data: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Security Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSecurityData,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHealthSection(),
                  const SizedBox(height: 24),
                  _buildStatsSection(),
                  const SizedBox(height: 24),
                  _buildActionsSection(),
                  const SizedBox(height: 24),
                  _buildRecommendationsSection(),
                ],
              ),
            ),
    );
  }

  Widget _buildHealthSection() {
    if (_healthReport == null) return const SizedBox.shrink();

    final report = _healthReport!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  report.isHealthy ? Icons.security : Icons.warning,
                  color: report.isHealthy ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                Text(
                  'Security Health',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (report.criticalCount > 0)
              _buildIssueChip('Critical', report.criticalCount, Colors.red),
            if (report.highCount > 0)
              _buildIssueChip('High', report.highCount, Colors.orange),
            if (report.mediumCount > 0)
              _buildIssueChip('Medium', report.mediumCount, Colors.yellow),

            if (report.isHealthy)
              const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 8),
                  Text('No security issues found'),
                ],
              ),

            const SizedBox(height: 16),

            // Show detailed issues
            if (report.issues.isNotEmpty) ...[
              const Text('Issues:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...report.issues.map((issue) => _buildIssueItem(issue)),
            ],

            if (report.warnings.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Warnings:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...report.warnings.map((issue) => _buildIssueItem(issue)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildIssueChip(String label, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 8),
      child: Chip(
        label: Text('$label: $count'),
        backgroundColor: color.withOpacity(0.2),
        labelStyle: TextStyle(color: color),
      ),
    );
  }

  Widget _buildIssueItem(SecurityIssue issue) {
    Color getColor() {
      switch (issue.severity) {
        case SecuritySeverity.critical:
          return Colors.red;
        case SecuritySeverity.high:
          return Colors.orange;
        case SecuritySeverity.medium:
          return Colors.yellow[700]!;
        case SecuritySeverity.low:
          return Colors.blue;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.circle, size: 8, color: getColor()),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(issue.description),
                Text(
                  issue.recommendation,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSection() {
    if (_securityStats == null) return const SizedBox.shrink();

    final adbStats = _securityStats!['adb'] as Map<String, dynamic>;
    final vncStats = _securityStats!['vnc'] as Map<String, dynamic>;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Connection Statistics',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatColumn('ADB Devices', [
                    'Total: ${adbStats['totalDevices']}',
                    'Verified: ${adbStats['verifiedDevices']}',
                    'Recent: ${adbStats['recentlyUsedDevices']}',
                  ]),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildStatColumn('VNC Devices', [
                    'Total: ${vncStats['totalDevices']}',
                    'Recent: ${vncStats['recentDevices']}',
                    'Old: ${vncStats['oldDevices']}',
                  ]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatColumn(String title, List<String> stats) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...stats
            .map((stat) => Text(stat, style: const TextStyle(fontSize: 14))),
      ],
    );
  }

  Widget _buildActionsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Security Actions',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _performSecurityCleanup,
                  icon: const Icon(Icons.cleaning_services),
                  label: const Text('Cleanup Old Data'),
                ),
                ElevatedButton.icon(
                  onPressed: _migrateLegacyData,
                  icon: const Icon(Icons.upgrade),
                  label: const Text('Migrate Legacy Data'),
                ),
                ElevatedButton.icon(
                  onPressed: _performSecurityReset,
                  icon: const Icon(Icons.warning),
                  label: const Text('Security Reset'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendationsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Security Recommendations',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            FutureBuilder<List<String>>(
              future: SecurityConfigService.getSecurityRecommendations(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const CircularProgressIndicator();
                }

                final recommendations = snapshot.data ?? [];
                return Column(
                  children: recommendations
                      .map((rec) => ListTile(
                            leading: const Icon(Icons.lightbulb_outline),
                            title: Text(rec),
                            dense: true,
                          ))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _performSecurityCleanup() async {
    try {
      await SecureADBDeviceManager.performSecurityCleanup();
      await SecureVNCDeviceManager.cleanupOldPasswords();

      _showSuccess('Security cleanup completed');
      _loadSecurityData();
    } catch (e) {
      _showError('Cleanup failed: $e');
    }
  }

  Future<void> _migrateLegacyData() async {
    try {
      final report = await SecurityConfigService.migrateLegacyData();

      if (report.isSuccessful) {
        _showSuccess(
            'Migration completed: ${report.totalMigrated} devices migrated');
      } else {
        _showError(
            'Migration failed: ${report.migrationError ?? "Unknown error"}');
      }

      _loadSecurityData();
    } catch (e) {
      _showError('Migration failed: $e');
    }
  }

  Future<void> _performSecurityReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Security Reset'),
        content: const Text(
            'This will clear ALL saved devices, passwords, and settings. '
            'This action cannot be undone. Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await SecurityConfigService.performSecurityReset();
        _showSuccess('Security reset completed');
        _loadSecurityData();
      } catch (e) {
        _showError('Reset failed: $e');
      }
    }
  }
}
