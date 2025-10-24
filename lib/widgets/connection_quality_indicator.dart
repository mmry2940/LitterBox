import 'package:flutter/material.dart';
import 'dart:async';
import '../services/connection_pool_manager.dart';

/// Widget that displays real-time connection quality indicators
class ConnectionQualityIndicator extends StatefulWidget {
  final String connectionId;
  final bool showDetails;
  final VoidCallback? onTap;

  const ConnectionQualityIndicator({
    super.key,
    required this.connectionId,
    this.showDetails = false,
    this.onTap,
  });

  @override
  State<ConnectionQualityIndicator> createState() =>
      _ConnectionQualityIndicatorState();
}

class _ConnectionQualityIndicatorState extends State<ConnectionQualityIndicator>
    with SingleTickerProviderStateMixin {
  final ConnectionPoolManager _connectionPool = ConnectionPoolManager();
  StreamSubscription<ConnectionQuality>? _qualitySubscription;
  ConnectionQuality? _currentQuality;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    _setupQualityStream();
    _loadInitialQuality();
  }

  @override
  void dispose() {
    _qualitySubscription?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _setupQualityStream() {
    final stream = _connectionPool.getQualityStream(widget.connectionId);
    if (stream != null) {
      _qualitySubscription = stream.listen((quality) {
        if (mounted) {
          setState(() {
            _currentQuality = quality;
          });

          // Animate on quality change
          if (quality.status == ConnectionHealthStatus.critical) {
            _pulseController.repeat(reverse: true);
          } else {
            _pulseController.stop();
            _pulseController.reset();
          }
        }
      });
    }
  }

  void _loadInitialQuality() {
    final quality = _connectionPool.getConnectionQuality(widget.connectionId);
    if (quality != null) {
      setState(() {
        _currentQuality = quality;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentQuality == null) {
      return _buildUnknownIndicator();
    }

    if (widget.showDetails) {
      return _buildDetailedIndicator();
    } else {
      return _buildSimpleIndicator();
    }
  }

  Widget _buildSimpleIndicator() {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _pulseAnimation.value,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: _currentQuality!.qualityColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _currentQuality!.qualityColor.withOpacity(0.3),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDetailedIndicator() {
    final quality = _currentQuality!;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: quality.qualityColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: quality.qualityColor.withOpacity(0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _pulseAnimation.value,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: quality.qualityColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  quality.qualityText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: quality.qualityColor,
                  ),
                ),
                Text(
                  '${quality.latencyMs}ms',
                  style: TextStyle(
                    fontSize: 9,
                    color: quality.qualityColor.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnknownIndicator() {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: Colors.grey.shade400,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// Widget that displays comprehensive connection statistics
class ConnectionStatsWidget extends StatefulWidget {
  final String connectionId;

  const ConnectionStatsWidget({
    super.key,
    required this.connectionId,
  });

  @override
  State<ConnectionStatsWidget> createState() => _ConnectionStatsWidgetState();
}

class _ConnectionStatsWidgetState extends State<ConnectionStatsWidget> {
  final ConnectionPoolManager _connectionPool = ConnectionPoolManager();
  StreamSubscription<ConnectionQuality>? _qualitySubscription;
  final List<ConnectionQuality> _qualityHistory = [];
  static const int maxHistoryLength = 60; // Keep last 60 measurements

  @override
  void initState() {
    super.initState();
    _setupQualityStream();
  }

  @override
  void dispose() {
    _qualitySubscription?.cancel();
    super.dispose();
  }

  void _setupQualityStream() {
    final stream = _connectionPool.getQualityStream(widget.connectionId);
    if (stream != null) {
      _qualitySubscription = stream.listen((quality) {
        if (mounted) {
          setState(() {
            _qualityHistory.add(quality);
            if (_qualityHistory.length > maxHistoryLength) {
              _qualityHistory.removeAt(0);
            }
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_qualityHistory.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No connection data available'),
        ),
      );
    }

    final latestQuality = _qualityHistory.last;
    final avgLatency = _qualityHistory.isNotEmpty
        ? _qualityHistory.map((q) => q.latencyMs).reduce((a, b) => a + b) /
            _qualityHistory.length
        : 0.0;
    final avgBandwidth = _qualityHistory.isNotEmpty
        ? _qualityHistory.map((q) => q.bandwidthMbps).reduce((a, b) => a + b) /
            _qualityHistory.length
        : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.signal_cellular_alt,
                  color: latestQuality.qualityColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Connection Quality',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: latestQuality.qualityColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: latestQuality.qualityColor.withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    latestQuality.qualityText,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: latestQuality.qualityColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildMetricCard(
                    'Latency',
                    '${latestQuality.latencyMs}ms',
                    'Avg: ${avgLatency.round()}ms',
                    Icons.schedule,
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricCard(
                    'Bandwidth',
                    '${latestQuality.bandwidthMbps.toStringAsFixed(1)}Mbps',
                    'Avg: ${avgBandwidth.toStringAsFixed(1)}Mbps',
                    Icons.speed,
                    Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildMetricCard(
                    'Packet Loss',
                    '${latestQuality.packetLoss.toStringAsFixed(1)}%',
                    '${_qualityHistory.length} samples',
                    Icons.warning,
                    latestQuality.packetLoss > 5 ? Colors.red : Colors.orange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricCard(
                    'Status',
                    latestQuality.qualityText,
                    'Updated ${_formatTimestamp(latestQuality.lastMeasured)}',
                    Icons.info,
                    latestQuality.qualityColor,
                  ),
                ),
              ],
            ),
            if (_qualityHistory.length > 1) ...[
              const SizedBox(height: 16),
              Text(
                'Latency Trend (last ${_qualityHistory.length} measurements)',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 60,
                child: _buildLatencyChart(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(
      String title, String value, String subtitle, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10,
              color: color.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLatencyChart() {
    if (_qualityHistory.length < 2) {
      return const Center(child: Text('Insufficient data'));
    }

    return CustomPaint(
      painter: LatencyChartPainter(_qualityHistory),
      child: Container(),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inSeconds < 60) {
      return '${diff.inSeconds}s ago';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else {
      return '${diff.inHours}h ago';
    }
  }
}

/// Custom painter for latency trend chart
class LatencyChartPainter extends CustomPainter {
  final List<ConnectionQuality> qualityHistory;

  LatencyChartPainter(this.qualityHistory);

  @override
  void paint(Canvas canvas, Size size) {
    if (qualityHistory.length < 2) return;

    final paint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path();
    final maxLatency = qualityHistory
        .map((q) => q.latencyMs)
        .reduce((a, b) => a > b ? a : b)
        .toDouble();
    final minLatency = qualityHistory
        .map((q) => q.latencyMs)
        .reduce((a, b) => a < b ? a : b)
        .toDouble();

    for (int i = 0; i < qualityHistory.length; i++) {
      final x = (i / (qualityHistory.length - 1)) * size.width;
      final normalizedLatency = (qualityHistory[i].latencyMs - minLatency) /
          (maxLatency - minLatency);
      final y = size.height - (normalizedLatency * size.height);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);

    // Draw points for recent measurements
    final pointPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;

    for (int i = qualityHistory.length - 5; i < qualityHistory.length; i++) {
      if (i >= 0) {
        final x = (i / (qualityHistory.length - 1)) * size.width;
        final normalizedLatency = (qualityHistory[i].latencyMs - minLatency) /
            (maxLatency - minLatency);
        final y = size.height - (normalizedLatency * size.height);
        canvas.drawCircle(Offset(x, y), 3, pointPaint);
      }
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
