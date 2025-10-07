import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import 'package:dartssh2/dartssh2.dart';
import 'dart:convert';

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
  final List<Map<String, String>> _sensors = [];
  final bool _sensorsLoading = true;
  String? _sensorsError;

  final double _ramUsage = 0;
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
      appBar: AppBar(title: const Text("Device Tools")),
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
