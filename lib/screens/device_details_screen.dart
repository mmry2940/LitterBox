import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import 'package:dartssh2/dartssh2.dart';
import 'dart:convert';
import 'dart:async';

// System info model
class SystemInfo {
  final double cpuUsage;
  final double ramUsage;
  final double storageUsed;
  final double storageTotal;
  final String uptime;
  final String networkInfo;
  final String osInfo;
  final String batteryInfo;
  final List<ProcessInfo> topProcesses;

  SystemInfo({
    this.cpuUsage = 0,
    this.ramUsage = 0,
    this.storageUsed = 0,
    this.storageTotal = 100,
    this.uptime = 'Unknown',
    this.networkInfo = 'Unknown',
    this.osInfo = 'Unknown',
    this.batteryInfo = 'Not available',
    this.topProcesses = const [],
  });

  double get storageUsagePercent =>
      storageTotal > 0 ? (storageUsed / storageTotal) * 100 : 0;
}

class ProcessInfo {
  final String pid;
  final String cpu;
  final String mem;
  final String command;

  ProcessInfo({
    required this.pid,
    required this.cpu,
    required this.mem,
    required this.command,
  });
}

class DeviceDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> device;

  const DeviceDetailsScreen({
    super.key,
    required this.device,
  });

  @override
  State<DeviceDetailsScreen> createState() => _DeviceDetailsScreenState();
}

class _DeviceDetailsScreenState extends State<DeviceDetailsScreen> {
  SSHClient? _sshClient;
  SystemInfo _systemInfo = SystemInfo();
  bool _isLoading = true;
  bool _isConnected = false;
  String _connectionError = "";
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _initializeConnection();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _sshClient?.close();
    super.dispose();
  }

  Future<void> _initializeConnection() async {
    setState(() {
      _isLoading = true;
      _connectionError = "";
    });

    try {
      final host = widget.device['host'] ?? '';
      final port =
          int.tryParse(widget.device['port']?.toString() ?? '22') ?? 22;
      final username = widget.device['username'] ?? '';
      final password = widget.device['password'] ?? '';

      if (host.isEmpty || username.isEmpty) {
        throw Exception('Missing host or username configuration');
      }

      final socket = await SSHSocket.connect(host, port);
      _sshClient = SSHClient(
        socket,
        username: username,
        onPasswordRequest: () => password,
      );

      setState(() {
        _isConnected = true;
        _isLoading = false;
      });

      // Fetch initial data
      await _fetchSystemInfo();

      // Start auto-refresh every 5 seconds
      _refreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        if (mounted && _isConnected) {
          _fetchSystemInfo();
        }
      });
    } catch (e) {
      setState(() {
        _isConnected = false;
        _isLoading = false;
        _connectionError = _getConnectionErrorMessage(e.toString());
      });
    }
  }

  String _getConnectionErrorMessage(String error) {
    if (error.contains('Connection refused')) {
      return 'Connection refused. Is SSH server running?';
    } else if (error.contains('Authentication failed') ||
        error.contains('password')) {
      return 'Authentication failed. Check username and password.';
    } else if (error.contains('timed out')) {
      return 'Connection timed out. Check network and firewall.';
    } else if (error.contains('Missing host')) {
      return 'Device configuration incomplete.';
    }
    return 'Connection failed: ${error.length > 100 ? error.substring(0, 100) + '...' : error}';
  }

  Future<void> _fetchSystemInfo() async {
    if (_sshClient == null || !_isConnected) return;

    try {
      // Fetch all data concurrently
      final results = await Future.wait([
        _fetchCPUUsage(),
        _fetchRAMUsage(),
        _fetchStorageInfo(),
        _fetchUptime(),
        _fetchNetworkInfo(),
        _fetchOSInfo(),
        _fetchBatteryInfo(),
        _fetchTopProcesses(),
      ]);

      if (mounted) {
        setState(() {
          _systemInfo = SystemInfo(
            cpuUsage: results[0] as double,
            ramUsage: results[1] as double,
            storageUsed: (results[2] as Map)['used'] as double,
            storageTotal: (results[2] as Map)['total'] as double,
            uptime: results[3] as String,
            networkInfo: results[4] as String,
            osInfo: results[5] as String,
            batteryInfo: results[6] as String,
            topProcesses: results[7] as List<ProcessInfo>,
          );
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _connectionError = 'Error fetching data: ${e.toString()}';
        });
      }
    }
  }

  Future<double> _fetchCPUUsage() async {
    try {
      final session = await _sshClient?.execute('top -bn1 | grep "Cpu(s)"');
      final result = await utf8.decodeStream(session!.stdout);
      final match = RegExp(r'(\d+\.?\d*)%?\s*id').firstMatch(result);
      if (match != null) {
        final idle = double.tryParse(match.group(1)!) ?? 0;
        return 100.0 - idle;
      }
    } catch (e) {
      // Ignore
    }
    return 0.0;
  }

  Future<double> _fetchRAMUsage() async {
    try {
      final session = await _sshClient?.execute('free | grep Mem');
      final result = await utf8.decodeStream(session!.stdout);
      final parts =
          result.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
      if (parts.length >= 3) {
        final total = double.tryParse(parts[1]) ?? 1.0;
        final used = double.tryParse(parts[2]) ?? 0.0;
        return (used / total) * 100.0;
      }
    } catch (e) {
      // Ignore
    }
    return 0.0;
  }

  Future<Map<String, double>> _fetchStorageInfo() async {
    try {
      final session = await _sshClient?.execute('df -h /');
      final result = await utf8.decodeStream(session!.stdout);
      final lines = result.split('\n');
      if (lines.length > 1) {
        final parts =
            lines[1].split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
        if (parts.length >= 4) {
          final used =
              double.tryParse(parts[2].replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
          final total =
              double.tryParse(parts[1].replaceAll(RegExp(r'[^0-9.]'), '')) ?? 1;
          return {'used': used, 'total': total};
        }
      }
    } catch (e) {
      // Ignore
    }
    return {'used': 0, 'total': 1};
  }

  Future<String> _fetchUptime() async {
    try {
      final session =
          await _sshClient?.execute('uptime -p 2>/dev/null || uptime');
      final result = await utf8.decodeStream(session!.stdout);
      final match = RegExp(r'up\s+([^,]+)').firstMatch(result);
      return match?.group(1)?.trim() ?? result.trim();
    } catch (e) {
      return 'Unknown';
    }
  }

  Future<String> _fetchNetworkInfo() async {
    try {
      final session =
          await _sshClient?.execute('hostname -I 2>/dev/null || ip addr show');
      final result = await utf8.decodeStream(session!.stdout);
      final match = RegExp(r'(\d+\.\d+\.\d+\.\d+)').firstMatch(result);
      return match != null ? 'IP: ${match.group(1)}' : 'Unknown';
    } catch (e) {
      return 'Unknown';
    }
  }

  Future<String> _fetchOSInfo() async {
    try {
      final session = await _sshClient?.execute('uname -sr');
      final result = await utf8.decodeStream(session!.stdout);
      return result.trim();
    } catch (e) {
      return 'Unknown';
    }
  }

  Future<String> _fetchBatteryInfo() async {
    try {
      final session = await _sshClient?.execute(
          'cat /sys/class/power_supply/BAT*/capacity 2>/dev/null || echo "N/A"');
      final result = await utf8.decodeStream(session!.stdout);
      final capacity = result.trim();
      if (capacity != 'N/A' && capacity.isNotEmpty) {
        return '$capacity%';
      }
    } catch (e) {
      // Ignore
    }
    return 'Not available';
  }

  Future<List<ProcessInfo>> _fetchTopProcesses() async {
    try {
      final session =
          await _sshClient?.execute('ps aux --sort=-%cpu | head -n 6');
      final result = await utf8.decodeStream(session!.stdout);
      final lines =
          result.split('\n').skip(1).where((l) => l.trim().isNotEmpty).toList();

      return lines
          .take(5)
          .map((line) {
            final parts = line.trim().split(RegExp(r'\s+'));
            if (parts.length >= 11) {
              return ProcessInfo(
                pid: parts[1],
                cpu: parts[2],
                mem: parts[3],
                command: parts.sublist(10).join(' '),
              );
            }
            return null;
          })
          .whereType<ProcessInfo>()
          .toList();
    } catch (e) {
      return [];
    }
  }

  Widget _buildGauge(String title, double value, Color color, IconData icon) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SfRadialGauge(
                axes: <RadialAxis>[
                  RadialAxis(
                    minimum: 0,
                    maximum: 100,
                    showLabels: false,
                    showTicks: false,
                    axisLineStyle: const AxisLineStyle(
                      thickness: 10,
                      color: Colors.grey,
                    ),
                    pointers: <GaugePointer>[
                      RangePointer(
                        value: value,
                        width: 10,
                        color: color,
                        enableAnimation: true,
                        animationDuration: 1000,
                        animationType: AnimationType.ease,
                      ),
                    ],
                    annotations: <GaugeAnnotation>[
                      GaugeAnnotation(
                        widget: Text(
                          '${value.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                        angle: 90,
                        positionFactor: 0.1,
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

  Widget _buildInfoCard(
      String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProcessesList() {
    if (_systemInfo.topProcesses.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('No process data available'),
        ),
      );
    }

    return Column(
      children: _systemInfo.topProcesses.map((process) {
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: Colors.blue,
              child: Text(
                process.pid,
                style: const TextStyle(fontSize: 10, color: Colors.white),
              ),
            ),
            title: Text(
              process.command,
              style: const TextStyle(fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'CPU: ${process.cpu}%',
                  style: const TextStyle(fontSize: 11, color: Colors.blue),
                ),
                const SizedBox(width: 8),
                Text(
                  'MEM: ${process.mem}%',
                  style: const TextStyle(fontSize: 11, color: Colors.purple),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device['name'] ?? 'Device Details'),
        actions: [
          if (_isConnected)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _fetchSystemInfo,
              tooltip: 'Refresh',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : !_isConnected
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 64, color: Colors.red),
                        const SizedBox(height: 16),
                        Text(
                          _connectionError,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _initializeConnection,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry Connection'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchSystemInfo,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Gauges Grid
                        SizedBox(
                          height: 220,
                          child: GridView.count(
                            crossAxisCount: 2,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            children: [
                              _buildGauge('CPU', _systemInfo.cpuUsage,
                                  Colors.blue, Icons.memory),
                              _buildGauge('RAM', _systemInfo.ramUsage,
                                  Colors.purple, Icons.storage),
                              _buildGauge(
                                  'Storage',
                                  _systemInfo.storageUsagePercent,
                                  Colors.orange,
                                  Icons.sd_card),
                              _buildInfoCard('Uptime', _systemInfo.uptime,
                                  Icons.access_time, Colors.green),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // System Info Section
                        const Text(
                          'System Information',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        _buildInfoCard('OS', _systemInfo.osInfo, Icons.computer,
                            Colors.indigo),
                        const SizedBox(height: 8),
                        _buildInfoCard('Network', _systemInfo.networkInfo,
                            Icons.network_check, Colors.teal),
                        const SizedBox(height: 8),
                        _buildInfoCard('Battery', _systemInfo.batteryInfo,
                            Icons.battery_std, Colors.amber),

                        const SizedBox(height: 24),

                        // Top Processes Section
                        const Text(
                          'Top Processes',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        _buildProcessesList(),
                      ],
                    ),
                  ),
                ),
    );
  }
}
