import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/security_config_service.dart';

/// Other/Miscellaneous features screen
class OtherScreen extends StatefulWidget {
  const OtherScreen({super.key});

  @override
  State<OtherScreen> createState() => _OtherScreenState();
}

class _OtherScreenState extends State<OtherScreen> {
  bool _isLoading = false;
  SecurityHealthReport? _securityReport;
  Map<String, dynamic>? _statistics;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      final stats = await _loadStatistics();
      
      setState(() {
        _statistics = stats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load data: $e')),
        );
      }
    }
  }

  Future<Map<String, dynamic>> _loadStatistics() async {
    final prefs = await SharedPreferences.getInstance();
    
    return {
      'totalConnections': prefs.getInt('total_connections') ?? 0,
      'totalSessionTime': prefs.getInt('total_session_time_seconds') ?? 0,
      'savedDevices': (prefs.getStringList('saved_vnc_devices')?.length ?? 0) +
                     (prefs.getStringList('adb_devices')?.length ?? 0),
      'lastUsed': prefs.getString('last_used_timestamp'),
    };
  }

  Future<void> _runSecurityCheck() async {
    setState(() => _isLoading = true);
    
    try {
      final report = await SecurityConfigService.performSecurityCheck();
      
      setState(() {
        _securityReport = report;
        _isLoading = false;
      });
      
      if (mounted) {
        _showSecurityReportDialog(report);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Security check failed: $e')),
        );
      }
    }
  }

  void _showSecurityReportDialog(SecurityHealthReport report) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              report.isHealthy ? Icons.check_circle : Icons.warning,
              color: report.isHealthy ? Colors.green : Colors.orange,
            ),
            const SizedBox(width: 8),
            const Text('Security Report'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (report.issues.isNotEmpty) ...[
                const Text(
                  'Issues:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...report.issues.map((issue) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.error,
                        size: 16,
                        color: _getSeverityColor(issue.severity),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(issue.description),
                            Text(
                              'Fix: ${issue.recommendation}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )),
                const Divider(),
              ],
              if (report.warnings.isNotEmpty) ...[
                const Text(
                  'Warnings:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...report.warnings.map((warning) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning, size: 16, color: Colors.orange),
                      const SizedBox(width: 8),
                      Expanded(child: Text(warning.description)),
                    ],
                  ),
                )),
                const Divider(),
              ],
              if (report.recommendations.isNotEmpty) ...[
                const Text(
                  'Recommendations:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...report.recommendations.map((rec) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.lightbulb_outline, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(rec)),
                    ],
                  ),
                )),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Color _getSeverityColor(SecuritySeverity severity) {
    switch (severity) {
      case SecuritySeverity.critical:
        return Colors.red;
      case SecuritySeverity.high:
        return Colors.orange;
      case SecuritySeverity.medium:
        return Colors.yellow;
      case SecuritySeverity.low:
        return Colors.blue;
    }
  }

  Future<void> _clearAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Data'),
        content: const Text(
          'This will delete all saved devices, credentials, and settings. '
          'This action cannot be undone. Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      
      try {
        await SecurityConfigService.performSecurityReset();
        
        setState(() => _isLoading = false);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('All data cleared successfully')),
          );
          await _loadData(); // Reload statistics
        }
      } catch (e) {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to clear data: $e')),
          );
        }
      }
    }
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Other'),
        actions: [
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        children: [
          // Statistics Section
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Statistics',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          if (_statistics != null) ...[
            _buildStatCard(
              'Total Connections',
              _statistics!['totalConnections'].toString(),
              Icons.connect_without_contact,
            ),
            _buildStatCard(
              'Session Time',
              _formatDuration(_statistics!['totalSessionTime']),
              Icons.timer,
            ),
            _buildStatCard(
              'Saved Devices',
              _statistics!['savedDevices'].toString(),
              Icons.devices,
            ),
            if (_statistics!['lastUsed'] != null)
              _buildStatCard(
                'Last Used',
                DateTime.parse(_statistics!['lastUsed']).toLocal().toString().split('.')[0],
                Icons.history,
              ),
          ],

          const Divider(height: 32),

          // Security Section
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Security',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.security),
            title: const Text('Run Security Check'),
            subtitle: const Text('Check for security issues and get recommendations'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _runSecurityCheck,
          ),
          if (_securityReport != null)
            ListTile(
              leading: Icon(
                _securityReport!.isHealthy ? Icons.check_circle : Icons.warning,
                color: _securityReport!.isHealthy ? Colors.green : Colors.orange,
              ),
              title: Text(
                _securityReport!.isHealthy
                    ? 'No issues found'
                    : '${_securityReport!.issues.length} issue(s), ${_securityReport!.warnings.length} warning(s)',
              ),
              subtitle: Text('Last checked: ${_securityReport!.timestamp.toLocal().toString().split('.')[0]}'),
              onTap: () => _showSecurityReportDialog(_securityReport!),
            ),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text('Clear All Data'),
            subtitle: const Text('Remove all devices, credentials, and settings'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _clearAllData,
          ),

          const Divider(height: 32),

          // App Info Section
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'About',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          const ListTile(
            leading: Icon(Icons.info),
            title: Text('Version'),
            subtitle: Text('1.0.0 (1)'),
          ),
          const ListTile(
            leading: Icon(Icons.apps),
            title: Text('App Name'),
            subtitle: Text('LitterBox'),
          ),
          const ListTile(
            leading: Icon(Icons.code),
            title: Text('Package Name'),
            subtitle: Text('litterbox'),
          ),

          const Divider(height: 32),

          // Debug Section
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Debug',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.bug_report),
            title: const Text('Export Logs'),
            subtitle: const Text('Export app logs for debugging'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Log export feature coming soon')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.folder),
            title: const Text('App Data Directory'),
            subtitle: const Text('View app storage location'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final prefs = await SharedPreferences.getInstance();
              if (mounted) {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Stored Keys'),
                    content: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: prefs.getKeys().map((key) => 
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(key, style: const TextStyle(fontSize: 12)),
                          )
                        ).toList(),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
              }
            },
          ),

          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        trailing: Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
