import 'package:flutter/material.dart';
import 'dart:async';
import '../services/connection_pool_manager.dart';
import '../services/background_sync_service.dart';
import 'connection_quality_indicator.dart';

/// Widget that displays connection management status and controls
class ConnectionManagementPanel extends StatefulWidget {
  const ConnectionManagementPanel({super.key});

  @override
  State<ConnectionManagementPanel> createState() =>
      _ConnectionManagementPanelState();
}

class _ConnectionManagementPanelState extends State<ConnectionManagementPanel> {
  final ConnectionPoolManager _connectionPool = ConnectionPoolManager();
  final BackgroundSyncService _backgroundSync = BackgroundSyncService();

  StreamSubscription<String>? _reconnectionSubscription;
  StreamSubscription<BackgroundSyncEvent>? _syncEventsSubscription;
  Timer? _statsRefreshTimer;

  Map<String, dynamic>? _connectionStats;
  Map<String, dynamic>? _syncStatus;
  final List<String> _recentEvents = [];

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _setupEventStreams();

    // Refresh stats periodically
    _statsRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        _loadInitialData();
      }
    });
  }

  @override
  void dispose() {
    _reconnectionSubscription?.cancel();
    _syncEventsSubscription?.cancel();
    _statsRefreshTimer?.cancel();
    super.dispose();
  }

  void _setupEventStreams() {
    // Listen to reconnection events
    _reconnectionSubscription =
        _connectionPool.reconnectionEvents.listen((event) {
      if (mounted) {
        setState(() {
          _recentEvents.insert(0, event);
          if (_recentEvents.length > 10) {
            _recentEvents.removeLast();
          }
        });
      }
    });

    // Listen to background sync events
    _syncEventsSubscription = _backgroundSync.events.listen((event) {
      if (mounted) {
        setState(() {
          _recentEvents.insert(0, event.toString());
          if (_recentEvents.length > 10) {
            _recentEvents.removeLast();
          }
        });
      }
    });
  }

  void _loadInitialData() {
    setState(() {
      _connectionStats = _connectionPool.getConnectionStats();
      _syncStatus = _backgroundSync.getStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.hub, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'Connection Management',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadInitialData,
                  tooltip: 'Refresh Stats',
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Connection Pool Stats
            if (_connectionStats != null) ...[
              _buildStatsSection(
                'Connection Pool',
                Icons.network_check,
                [
                  _buildStatItem('Total Connections',
                      '${_connectionStats!['totalConnections']}'),
                  _buildStatItem('Healthy Connections',
                      '${_connectionStats!['healthyConnections']}'),
                  _buildStatItem('Active Reconnections',
                      '${_connectionStats!['activeReconnections']}'),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // Background Sync Status
            if (_syncStatus != null) ...[
              _buildStatsSection(
                'Background Sync',
                Icons.sync,
                [
                  _buildStatItem(
                    'Status',
                    _syncStatus!['isRunning'] ? 'Running' : 'Stopped',
                    color:
                        _syncStatus!['isRunning'] ? Colors.green : Colors.red,
                  ),
                  if (_syncStatus!['lastSync'] != null)
                    _buildStatItem('Last Sync',
                        _formatTimestamp(_syncStatus!['lastSync'])),
                ],
                trailing: Switch(
                  value: _syncStatus!['isRunning'] ?? false,
                  onChanged: (enabled) async {
                    if (enabled) {
                      await _backgroundSync.start();
                    } else {
                      await _backgroundSync.stop();
                    }
                    _loadInitialData();
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Active Connections
            if (_connectionStats != null &&
                _connectionStats!['connections'] != null) ...[
              _buildConnectionsList(),
              const SizedBox(height: 16),
            ],

            // Recent Events
            if (_recentEvents.isNotEmpty) ...[
              Text(
                'Recent Events',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Container(
                height: 120,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _recentEvents.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        _recentEvents[index],
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                            ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatsSection(
    String title,
    IconData icon,
    List<Widget> stats, {
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: Colors.blue.shade700),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.blue.shade700,
                ),
              ),
              const Spacer(),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: stats,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color ?? Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildConnectionsList() {
    final rawConnections = _connectionStats!['connections'];
    final connections = rawConnections is List ? rawConnections : const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Active Connections',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(maxHeight: 200),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: connections.length,
            itemBuilder: (context, index) {
              final connection = connections[index];
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 2),
                child: ListTile(
                  dense: true,
                  leading: ConnectionQualityIndicator(
                    connectionId: connection['id'],
                    showDetails: false,
                  ),
                  title: Text(
                    connection['id'],
                    style: const TextStyle(fontSize: 12),
                  ),
                  subtitle: Text(
                    'Quality: ${connection['quality']} • Last used: ${_formatTimestamp(connection['lastUsed'])}',
                    style: const TextStyle(fontSize: 10),
                  ),
                  trailing: Icon(
                    connection['healthy'] ? Icons.check_circle : Icons.error,
                    color: connection['healthy'] ? Colors.green : Colors.red,
                    size: 16,
                  ),
                  onTap: () {
                    // Show detailed connection stats
                    showDialog(
                      context: context,
                      builder: (context) => Dialog(
                        child: Container(
                          width: 400,
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Connection Details',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 16),
                              ConnectionStatsWidget(
                                connectionId: connection['id'],
                              ),
                              const SizedBox(height: 16),
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('Close'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _formatTimestamp(String? timestamp) {
    if (timestamp == null) return 'Unknown';

    try {
      final dateTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final diff = now.difference(dateTime);

      if (diff.inSeconds < 60) {
        return '${diff.inSeconds}s ago';
      } else if (diff.inMinutes < 60) {
        return '${diff.inMinutes}m ago';
      } else if (diff.inHours < 24) {
        return '${diff.inHours}h ago';
      } else {
        return '${diff.inDays}d ago';
      }
    } catch (e) {
      return 'Unknown';
    }
  }
}

/// Floating action button for connection management
class ConnectionManagementFAB extends StatelessWidget {
  const ConnectionManagementFAB({super.key});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: () => _showConnectionPanel(context),
      tooltip: 'Connection Management',
      child: const Icon(Icons.hub),
    );
  }

  void _showConnectionPanel(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  'Connection Management',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(),
            const Expanded(
              child: SingleChildScrollView(
                child: ConnectionManagementPanel(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
