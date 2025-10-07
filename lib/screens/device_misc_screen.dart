import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import 'package:dartssh2/dartssh2.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

// Performance data point
class PerformanceData {
  final DateTime timestamp;
  final double cpuUsage;
  final double memoryUsage;
  final double storageUsed;

  const PerformanceData({
    required this.timestamp,
    required this.cpuUsage,
    required this.memoryUsage,
    required this.storageUsed,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'cpuUsage': cpuUsage,
        'memoryUsage': memoryUsage,
        'storageUsed': storageUsed,
      };

  factory PerformanceData.fromJson(Map<String, dynamic> json) =>
      PerformanceData(
        timestamp: DateTime.parse(json['timestamp']),
        cpuUsage: json['cpuUsage'],
        memoryUsage: json['memoryUsage'],
        storageUsed: json['storageUsed'],
      );
}

// Default style and gauge size definitions
const TextStyle cpuTextStyle =
    TextStyle(fontSize: 16, fontWeight: FontWeight.bold);
const TextStyle indexTextStyle = TextStyle(fontSize: 14);
const double gaugeSize = 150.0;

class DeviceMiscScreen extends StatefulWidget {
  final void Function(int tabIndex)? onCardTap;
  final Map<String, dynamic> device;

  const DeviceMiscScreen({
    super.key,
    this.onCardTap,
    required this.device,
  });

  @override
  _DeviceMiscScreenState createState() => _DeviceMiscScreenState();
}

class _DeviceMiscScreenState extends State<DeviceMiscScreen> {
  // SSH client instance
  SSHClient? _sshClient;

  // State fields
  final double _ramUsage = 0;
  bool _ramExpanded = false;
  bool _uptimeExpanded = false;
  String? _uptime;

  double _cpuUsage = 0;
  double _storageUsed = 0;
  double _storageAvailable = 0;
  String _networkInfo = "Fetching network info...";
  bool _cpuExpanded = false;
  bool _storageExpanded = false;
  bool _networkExpanded = false;

  // Performance history
  final List<PerformanceData> _performanceHistory = [];
  bool _performanceExpanded = false;
  Timer? _performanceTimer;

  @override
  void initState() {
    super.initState();
    _initializeSSHClient();
    _loadPerformanceHistory();
    _startPerformanceMonitoring();
  }

  Future<void> _initializeSSHClient() async {
    final host = widget.device['host'] ?? '127.0.0.1';
    final port = widget.device['port'] ?? 22;
    final username = widget.device['username'] ?? 'user';
    final password = widget.device['password'] ?? 'password';

    final socket = await SSHSocket.connect(host, port);
    _sshClient = SSHClient(
      socket,
      username: username,
      onPasswordRequest: () => password,
    );

    _fetchDiskInfo();
    _fetchNetworkInfo();
    _fetchBatteryInfo();
    _fetchOSInfo();
    _fetchTopProcesses();
    _fetchCPUUsage();
    _fetchStorageInfo();
  }

  Future<void> _loadPerformanceHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final deviceKey = 'performance_${widget.device['host']}';
    final jsonStr = prefs.getString(deviceKey);
    if (jsonStr != null) {
      final List<dynamic> list = json.decode(jsonStr);
      setState(() {
        _performanceHistory.clear();
        _performanceHistory.addAll(
          list.map((e) => PerformanceData.fromJson(e)).toList(),
        );
        // Keep only last 24 hours of data
        final cutoff = DateTime.now().subtract(const Duration(hours: 24));
        _performanceHistory
            .removeWhere((data) => data.timestamp.isBefore(cutoff));
      });
    }
  }

  Future<void> _savePerformanceHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final deviceKey = 'performance_${widget.device['host']}';
    final jsonStr =
        json.encode(_performanceHistory.map((e) => e.toJson()).toList());
    await prefs.setString(deviceKey, jsonStr);
  }

  void _startPerformanceMonitoring() {
    _performanceTimer =
        Timer.periodic(const Duration(minutes: 5), (timer) async {
      if (_sshClient != null) {
        await _collectPerformanceData();
      }
    });
  }

  Future<void> _collectPerformanceData() async {
    try {
      // Get current CPU usage
      final cpuSession = await _sshClient?.execute('top -bn1 | grep "Cpu(s)"');
      final cpuResult = await utf8.decodeStream(cpuSession!.stdout);
      final cpuMatch = RegExp(r'(\d+\.\d+)%id').firstMatch(cpuResult);
      final currentCpuUsage =
          cpuMatch != null ? 100.0 - double.parse(cpuMatch.group(1)!) : 0.0;

      // Get current memory usage
      final memSession = await _sshClient?.execute('free | grep Mem');
      final memResult = await utf8.decodeStream(memSession!.stdout);
      final memParts =
          memResult.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
      final totalMem = double.tryParse(memParts[1]) ?? 1.0;
      final usedMem = double.tryParse(memParts[2]) ?? 0.0;
      final currentMemoryUsage = (usedMem / totalMem) * 100.0;

      setState(() {
        _performanceHistory.add(PerformanceData(
          timestamp: DateTime.now(),
          cpuUsage: currentCpuUsage,
          memoryUsage: currentMemoryUsage,
          storageUsed: _storageUsed,
        ));

        // Keep only last 24 hours
        final cutoff = DateTime.now().subtract(const Duration(hours: 24));
        _performanceHistory
            .removeWhere((data) => data.timestamp.isBefore(cutoff));
      });

      await _savePerformanceHistory();
    } catch (e) {
      print('Error collecting performance data: $e');
    }
  }

  Future<void> _fetchDiskInfo() async {
    try {
      final session = await _sshClient?.execute('df -h');
      final result = await utf8.decodeStream(session!.stdout);
      final lines = result.split('\n');
      if (lines.length > 1) {
        final data = lines[1].split(RegExp(r'\s+'));
        setState(() {
          _storageUsed =
              double.tryParse(data[2].replaceAll(RegExp(r'[^0-9.]'), '')) ??
                  0.0;
          _storageAvailable =
              double.tryParse(data[3].replaceAll(RegExp(r'[^0-9.]'), '')) ??
                  0.0;
        });
      }
    } catch (e) {
      print('Error fetching disk info: $e');
    }
  }

  Future<void> _fetchNetworkInfo() async {
    try {
      final session = await _sshClient?.execute('ifconfig');
      final result = await utf8.decodeStream(session!.stdout);
      setState(() {
        _networkInfo = result.split('\n').firstWhere(
            (line) => line.contains('inet '),
            orElse: () => 'No IP found');
      });
    } catch (e) {
      print('Error fetching network info: $e');
    }
  }

  Future<void> _fetchCPUUsage() async {
    try {
      final session = await _sshClient?.execute('top -bn1 | grep "Cpu(s)"');
      final result = await utf8.decodeStream(session!.stdout);
      final match = RegExp(r'(\d+\.\d+)%id').firstMatch(result);
      if (match != null) {
        final idle = double.parse(match.group(1)!);
        setState(() {
          _cpuUsage = 100.0 - idle;
        });
      }
    } catch (e) {
      print('Error fetching CPU usage: $e');
    }
  }

  Future<void> _fetchStorageInfo() async {
    await _fetchDiskInfo(); // Reuse disk info logic
  }

  Future<void> _fetchBatteryInfo() async {
    try {
      final session =
          await _sshClient?.execute('upower -i \$(upower -e | grep BAT)');
      final result = await utf8.decodeStream(session!.stdout);
      final match = RegExp(r'percentage:\s+(\d+)%').firstMatch(result);
      if (match != null) {
        setState(() {
          _networkInfo = 'Battery: ${match.group(1)}%';
        });
      }
    } catch (e) {
      print('Error fetching battery info: $e');
    }
  }

  Future<void> _fetchOSInfo() async {
    try {
      final session = await _sshClient?.execute('uname -a');
      final result = await utf8.decodeStream(session!.stdout);
      setState(() {
        _networkInfo = result.trim();
      });
    } catch (e) {
      print('Error fetching OS info: $e');
    }
  }

  Future<void> _fetchTopProcesses() async {
    try {
      final session =
          await _sshClient?.execute('ps aux --sort=-%cpu | head -n 5');
      final result = await utf8.decodeStream(session!.stdout);
      setState(() {
        _networkInfo = result;
      });
    } catch (e) {
      print('Error fetching top processes: $e');
    }
  }

  @override
  void dispose() {
    _sshClient?.close();
    _performanceTimer?.cancel();
    super.dispose();
  }

  Widget _buildPerformanceChart() {
    if (_performanceHistory.isEmpty) {
      return const Center(child: Text('No performance data available'));
    }

    // Simple line chart using CustomPaint for now
    // In a real app, you'd use a charting library like fl_chart
    return CustomPaint(
      painter: PerformanceChartPainter(_performanceHistory),
      child: Container(),
    );
  }

  // Builds the system details section
  Widget _buildSystemDetailsSection() {
    return Column(
      children: [
        ExpansionTile(
          leading: const Icon(Icons.memory, color: Colors.blue),
          title: Text('CPU Usage', style: cpuTextStyle),
          initiallyExpanded: _cpuExpanded,
          onExpansionChanged: (expanded) {
            setState(() {
              _cpuExpanded = expanded;
            });
          },
          children: [
            SizedBox(
              height: gaugeSize,
              child: SfRadialGauge(
                axes: <RadialAxis>[
                  RadialAxis(
                    minimum: 0,
                    maximum: 100,
                    ranges: <GaugeRange>[
                      GaugeRange(
                          startValue: 0, endValue: 50, color: Colors.green),
                      GaugeRange(
                          startValue: 50, endValue: 80, color: Colors.orange),
                      GaugeRange(
                          startValue: 80, endValue: 100, color: Colors.red),
                    ],
                    pointers: <GaugePointer>[
                      NeedlePointer(value: _cpuUsage),
                    ],
                    annotations: <GaugeAnnotation>[
                      GaugeAnnotation(
                        widget: Text('CPU: ${_cpuUsage.toStringAsFixed(1)}%',
                            style: cpuTextStyle),
                        angle: 90,
                        positionFactor: 0.5,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
        const SizedBox(height: 16),
        ExpansionTile(
          leading: const Icon(Icons.storage, color: Colors.brown),
          title: Text('Storage Usage', style: cpuTextStyle),
          initiallyExpanded: _storageExpanded,
          onExpansionChanged: (expanded) {
            setState(() {
              _storageExpanded = expanded;
            });
          },
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text('Used: ${_storageUsed.toStringAsFixed(1)} GB',
                  style: indexTextStyle),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                  'Available: ${_storageAvailable.toStringAsFixed(1)} GB',
                  style: indexTextStyle),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ExpansionTile(
          leading: const Icon(Icons.network_check, color: Colors.green),
          title: Text('Network Information', style: cpuTextStyle),
          initiallyExpanded: _networkExpanded,
          onExpansionChanged: (expanded) {
            setState(() {
              _networkExpanded = expanded;
            });
          },
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(_networkInfo, style: indexTextStyle),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ExpansionTile(
          leading: const Icon(Icons.sd_storage, color: Colors.purple),
          title: Text('RAM Usage', style: cpuTextStyle),
          initiallyExpanded: _ramExpanded,
          onExpansionChanged: (expanded) {
            setState(() {
              _ramExpanded = expanded;
            });
          },
          children: [
            SizedBox(
              height: gaugeSize,
              child: SfRadialGauge(
                axes: <RadialAxis>[
                  RadialAxis(
                    minimum: 0,
                    maximum: 100,
                    ranges: <GaugeRange>[
                      GaugeRange(
                          startValue: 0, endValue: 50, color: Colors.green),
                      GaugeRange(
                          startValue: 50, endValue: 80, color: Colors.orange),
                      GaugeRange(
                          startValue: 80, endValue: 100, color: Colors.red),
                    ],
                    pointers: <GaugePointer>[
                      NeedlePointer(value: _ramUsage),
                    ],
                    annotations: <GaugeAnnotation>[
                      GaugeAnnotation(
                        widget: Text('RAM: ${_ramUsage.toStringAsFixed(1)}%',
                            style: cpuTextStyle),
                        angle: 90,
                        positionFactor: 0.5,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
        const SizedBox(height: 16),
        ExpansionTile(
          leading: const Icon(Icons.timer, color: Colors.teal),
          title: Text('Device Uptime', style: cpuTextStyle),
          initiallyExpanded: _uptimeExpanded,
          onExpansionChanged: (expanded) {
            setState(() {
              _uptimeExpanded = expanded;
            });
          },
          children: [
            if (_uptime != null)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text('Uptime: $_uptime', style: indexTextStyle),
              )
            else
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text('Fetching uptime...'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        ExpansionTile(
          leading: const Icon(Icons.trending_up, color: Colors.purple),
          title: Text('Performance History', style: cpuTextStyle),
          initiallyExpanded: _performanceExpanded,
          onExpansionChanged: (expanded) {
            setState(() {
              _performanceExpanded = expanded;
            });
          },
          children: [
            if (_performanceHistory.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('Collecting performance data...'),
              )
            else
              SizedBox(
                height: 200,
                child: _buildPerformanceChart(),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<_OverviewCardData> cards = [
      _OverviewCardData('Info', Icons.info, 0),
      _OverviewCardData('Terminal', Icons.terminal, 1),
      _OverviewCardData('Files', Icons.folder, 2),
      _OverviewCardData('Processes', Icons.memory, 3),
      _OverviewCardData('Packages', Icons.list, 4),
      _OverviewCardData('Details', Icons.dashboard_customize, 5),
    ];

    return Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Overview Cards Grid
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: cards
                    .map(
                      (card) => _OverviewCard(
                        title: card.title,
                        icon: card.icon,
                        onTap: () {
                          if (card.tabIndex == 5) {
                            // Show system details inline instead of navigating
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              builder: (context) => DraggableScrollableSheet(
                                expand: false,
                                builder: (context, scrollController) =>
                                    SingleChildScrollView(
                                  controller: scrollController,
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: _buildSystemDetailsSection(),
                                  ),
                                ),
                              ),
                            );
                          } else if (widget.onCardTap != null) {
                            widget.onCardTap!(card.tabIndex);
                          }
                        },
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 24),
              // System Details Section
              const Text(
                'System Details',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _buildSystemDetailsSection(),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverviewCardData {
  final String title;
  final IconData icon;
  final int tabIndex;
  _OverviewCardData(this.title, this.icon, this.tabIndex);
}

class _OverviewCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback? onTap;
  const _OverviewCard({required this.title, required this.icon, this.onTap});
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48),
              const SizedBox(height: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}

class PerformanceChartPainter extends CustomPainter {
  final List<PerformanceData> data;

  PerformanceChartPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final cpuPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final memoryPaint = Paint()
      ..color = Colors.green
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path();
    final cpuPath = Path();
    final memoryPath = Path();

    final width = size.width;
    final height = size.height;

    for (int i = 0; i < data.length; i++) {
      final x = (i / (data.length - 1)) * width;
      final y = height - (data[i].cpuUsage / 100.0) * height;
      final cpuY = height - (data[i].memoryUsage / 100.0) * height;

      if (i == 0) {
        path.moveTo(x, y);
        cpuPath.moveTo(x, cpuY);
        memoryPath.moveTo(x, y); // Using same data for simplicity
      } else {
        path.lineTo(x, y);
        cpuPath.lineTo(x, cpuY);
        memoryPath.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
    canvas.drawPath(cpuPath, cpuPaint);
    canvas.drawPath(memoryPath, memoryPaint);

    // Draw legend
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    textPainter.text = const TextSpan(
      text: 'CPU',
      style: TextStyle(color: Colors.red, fontSize: 12),
    );
    textPainter.layout();
    textPainter.paint(canvas, const Offset(10, 10));

    textPainter.text = const TextSpan(
      text: 'Memory',
      style: TextStyle(color: Colors.green, fontSize: 12),
    );
    textPainter.layout();
    textPainter.paint(canvas, const Offset(10, 30));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
