import 'package:flutter/material.dart';
import '../models/device_status.dart';

class DeviceSummaryCard extends StatelessWidget {
  final Map<String, dynamic> device;
  final DeviceStatus? status;
  final Map<String, dynamic>? systemInfo;

  const DeviceSummaryCard({
    super.key,
    required this.device,
    this.status,
    this.systemInfo,
  });

  String _getDeviceDisplayName() {
    if (device['name'] != null && device['name'].toString().isNotEmpty) {
      return device['name'] as String;
    }
    return '${device['username']}@${device['host']}';
  }

  String _getConnectionInfo() {
    final host = device['host'] ?? 'unknown';
    final port = device['port'] ?? '22';
    final username = device['username'] ?? 'user';
    return '$username@$host:$port';
  }

  String _getConnectionType() {
    final port = device['port'];
    if (port == '5555') return 'ADB';
    if (port == '5900' || port == '5901') return 'VNC';
    if (port == '3389') return 'RDP';
    return 'SSH';
  }

  IconData _getConnectionIcon() {
    final type = _getConnectionType();
    switch (type) {
      case 'ADB':
        return Icons.phone_android;
      case 'VNC':
        return Icons.desktop_windows;
      case 'RDP':
        return Icons.computer;
      default:
        return Icons.terminal;
    }
  }

  Color _getConnectionColor() {
    final type = _getConnectionType();
    switch (type) {
      case 'ADB':
        return Colors.green;
      case 'VNC':
        return Colors.purple;
      case 'RDP':
        return Colors.cyan;
      default:
        return Colors.blue;
    }
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    Color? color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: (color ?? Colors.blue).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: color ?? Colors.blue),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color ?? Colors.blue,
              ),
              textAlign: TextAlign.center,
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connectionColor = _getConnectionColor();
    final isOnline = status?.isOnline ?? false;
    final statusColor = isOnline ? Colors.green : Colors.red;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              connectionColor.withOpacity(0.1),
              connectionColor.withOpacity(0.05),
              Colors.transparent,
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Device name and status row
              Row(
                children: [
                  Icon(
                    _getConnectionIcon(),
                    size: 32,
                    color: connectionColor,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getDeviceDisplayName(),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              _getConnectionInfo(),
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: connectionColor.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _getConnectionType(),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: connectionColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Status indicator
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: statusColor.withOpacity(0.5),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isOnline ? 'Connected' : 'Offline',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // System info stats row (if available)
              if (systemInfo != null) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (systemInfo!['uptime'] != null)
                      _buildStatItem(
                        icon: Icons.access_time,
                        label: 'Uptime',
                        value: systemInfo!['uptime'] as String,
                        color: Colors.blue,
                      ),
                    if (systemInfo!['uptime'] != null &&
                        (systemInfo!['memoryUsed'] != null ||
                            systemInfo!['cpuUsage'] != null))
                      const SizedBox(width: 8),
                    if (systemInfo!['memoryUsed'] != null &&
                        systemInfo!['memoryTotal'] != null)
                      _buildStatItem(
                        icon: Icons.memory,
                        label: 'Memory',
                        value:
                            '${systemInfo!['memoryUsed']}/${systemInfo!['memoryTotal']}',
                        color: Colors.purple,
                      ),
                    if (systemInfo!['memoryUsed'] != null &&
                        systemInfo!['cpuUsage'] != null)
                      const SizedBox(width: 8),
                    if (systemInfo!['cpuUsage'] != null)
                      _buildStatItem(
                        icon: Icons.speed,
                        label: 'CPU',
                        value: '${systemInfo!['cpuUsage']}%',
                        color: Colors.orange,
                      ),
                  ],
                ),
              ],

              // Ping info (if available)
              if (status != null &&
                  status!.isOnline &&
                  status!.pingMs != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.network_check,
                        size: 16,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Latency: ${status!.pingMs}ms',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
