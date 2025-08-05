import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import 'package:dartssh2/dartssh2.dart';

class MiscDetailsScreen extends StatefulWidget {
  final Map<String, String> device;

  const MiscDetailsScreen({super.key, required this.device});

  @override
  State<MiscDetailsScreen> createState() => _MiscDetailsScreenState();
}

class _MiscDetailsScreenState extends State<MiscDetailsScreen> {
  double _ramUsage = 0;
  double _cpuUsage = 0;
  late Timer _timer;
  late SSHClient _sshClient;
  List<double> _cpuUsageHistory = [];

  @override
  void initState() {
    super.initState();
    _initializeSSHClient();
  }

  Future<void> _initializeSSHClient() async {
    try {
      // Use the host, port, username, and password from the selected device
      final socket = await SSHSocket.connect(
        widget.device['host']!,
        int.tryParse(widget.device['port'] ?? '22') ?? 22,
      );
      _sshClient = SSHClient(
        socket,
        username: widget.device['username']!,
        onPasswordRequest: () => widget.device['password'] ?? '',
      );

      _startMonitoring();
    } catch (e) {
      print('Error initializing SSH client: $e');
    }
  }

  void _startMonitoring() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final ramUsage = await _getRamUsage();
      final cpuUsage = await _getCpuUsage();

      // Add the new CPU usage value to the history
      _cpuUsageHistory.add(cpuUsage);
      if (_cpuUsageHistory.length > 5) {
        _cpuUsageHistory.removeAt(0); // Keep the history size to 5
      }

      // Calculate the moving average
      final smoothedCpuUsage =
          _cpuUsageHistory.reduce((a, b) => a + b) / _cpuUsageHistory.length;

      print('Smoothed CPU Usage: $smoothedCpuUsage'); // Log the smoothed value

      setState(() {
        _ramUsage = ramUsage;
        _cpuUsage = smoothedCpuUsage;
      });
    });
  }

  Future<double> _getRamUsage() async {
    try {
      final session = await _sshClient.execute('free -m');
      final output = await utf8.decodeStream(session.stdout);
      session.close();

      final lines = output.split('\n');
      if (lines.length > 1) {
        final memoryLine = lines[1].split(RegExp(r'\s+'));
        final totalMemory = int.parse(memoryLine[1]);
        final usedMemory = int.parse(memoryLine[2]);
        return (usedMemory / totalMemory) * 100;
      }
    } catch (e) {
      print('Error fetching RAM usage: $e');
    }
    return 0;
  }

  Future<double> _getCpuUsage() async {
    try {
      final session = await _sshClient.execute(
          "top -bn1 | grep 'Cpu(s)' | cut -d ',' -f 1 | cut -d ':' -f 2");
      final output = await utf8.decodeStream(session.stdout);
      session.close();

      print('Raw CPU usage output: $output'); // Log the raw output

      // Clean the output by trimming spaces and removing the 'us' suffix
      final cleanedOutput = output.trim().replaceAll('us', '').trim();

      // Normalize the value to ensure it is within the range 0-100
      final cpuUsage = double.parse(cleanedOutput);
      return cpuUsage.clamp(0, 100);
    } catch (e) {
      print('Error fetching CPU usage: $e');
    }
    return 0;
  }

  @override
  void dispose() {
    if (_timer.isActive) {
      _timer.cancel();
    }
    _sshClient.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Misc Details'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: Column(
                children: [
                  SfRadialGauge(
                    axes: <RadialAxis>[
                      RadialAxis(
                        minimum: 0,
                        maximum: 100,
                        ranges: <GaugeRange>[
                          GaugeRange(
                              startValue: 0, endValue: 50, color: Colors.green),
                          GaugeRange(
                              startValue: 50,
                              endValue: 80,
                              color: Colors.orange),
                          GaugeRange(
                              startValue: 80, endValue: 100, color: Colors.red),
                        ],
                        pointers: <GaugePointer>[
                          NeedlePointer(value: _cpuUsage),
                        ],
                        annotations: <GaugeAnnotation>[
                          GaugeAnnotation(
                            widget: Text(
                              'CPU: ${_cpuUsage.toStringAsFixed(1)}%',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            angle: 90,
                            positionFactor: 0.5,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Additional CPU Index: ${(_cpuUsage * 1.5).toStringAsFixed(1)}%', // Example additional index
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
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
                        widget: Text(
                          'RAM: ${_ramUsage.toStringAsFixed(1)}%',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        angle: 90,
                        positionFactor: 0.5,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
