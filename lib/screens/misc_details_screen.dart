import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import 'package:dartssh2/dartssh2.dart';
import 'dart:convert';

// Default style and gauge size definitions
const TextStyle cpuTextStyle =
    TextStyle(fontSize: 16, fontWeight: FontWeight.bold);
const TextStyle indexTextStyle = TextStyle(fontSize: 14);
const double gaugeSize = 150.0;

class MiscDetailsScreen extends StatefulWidget {
  final Map<String, dynamic>? device; // Added device parameter

  const MiscDetailsScreen({Key? key, this.device}) : super(key: key);

  @override
  _MiscDetailsScreenState createState() => _MiscDetailsScreenState();
}

class _MiscDetailsScreenState extends State<MiscDetailsScreen> {
  // SSH client instance
  SSHClient? _sshClient;

  // State fields
  List<Map<String, String>> _sensors = [];
  bool _sensorsLoading = true;
  String? _sensorsError;

  double _ramUsage = 0;
  bool _ramExpanded = false;
  bool _uptimeExpanded = false;
  bool _sensorsExpanded = false;
  String? _uptime;

  double _cpuUsage = 0;
  double _storageUsed = 0;
  double _storageAvailable = 0;
  String _networkInfo = "Fetching network info...";
  bool _cpuExpanded = false;
  bool _storageExpanded = false;
  bool _networkExpanded = false;

  @override
  void initState() {
    super.initState();
    _initializeSSHClient();
  }

  Future<void> _initializeSSHClient() async {
    final host = widget.device?['host'] ?? '127.0.0.1';
    final port = widget.device?['port'] ?? 22;
    final username = widget.device?['username'] ?? 'user';
    final password = widget.device?['password'] ?? 'password';

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
    super.dispose();
  }

  // Builds the sensor section
  Widget _buildSensorsSection() {
    if (_sensorsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_sensorsError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(_sensorsError!, style: const TextStyle(color: Colors.red)),
      );
    }
    if (_sensors.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('No sensors found.'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Sensors',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 8),
        ..._sensors.map((sensor) => Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: const Icon(Icons.sensors, color: Colors.deepOrange),
                title: Text(sensor['label'] ?? ''),
                subtitle: Text(sensor['chip'] ?? ''),
                trailing: Text(sensor['value'] ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            )),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Misc Device Details")),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
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
                                startValue: 0,
                                endValue: 50,
                                color: Colors.green),
                            GaugeRange(
                                startValue: 50,
                                endValue: 80,
                                color: Colors.orange),
                            GaugeRange(
                                startValue: 80,
                                endValue: 100,
                                color: Colors.red),
                          ],
                          pointers: <GaugePointer>[
                            NeedlePointer(value: _cpuUsage),
                          ],
                          annotations: <GaugeAnnotation>[
                            GaugeAnnotation(
                              widget: Text(
                                  'CPU: ${_cpuUsage.toStringAsFixed(1)}%',
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
                                startValue: 0,
                                endValue: 50,
                                color: Colors.green),
                            GaugeRange(
                                startValue: 50,
                                endValue: 80,
                                color: Colors.orange),
                            GaugeRange(
                                startValue: 80,
                                endValue: 100,
                                color: Colors.red),
                          ],
                          pointers: <GaugePointer>[
                            NeedlePointer(value: _ramUsage),
                          ],
                          annotations: <GaugeAnnotation>[
                            GaugeAnnotation(
                              widget: Text(
                                  'RAM: ${_ramUsage.toStringAsFixed(1)}%',
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
                leading: const Icon(Icons.sensors, color: Colors.deepOrange),
                title: Text('Sensors', style: cpuTextStyle),
                initiallyExpanded: _sensorsExpanded,
                onExpansionChanged: (expanded) {
                  setState(() {
                    _sensorsExpanded = expanded;
                  });
                },
                children: [
                  _buildSensorsSection(),
                ],
              ),
              // Additional tiles for battery, OS info, processes, etc., can be added here
            ],
          ),
        ),
      ),
    );
  }
}
