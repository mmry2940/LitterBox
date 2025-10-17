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
  final String loadAverage;
  final double temperature;
  final String diskIO;
  final String networkBandwidth;
  final MemoryDetails memoryDetails;
  final int totalProcesses;
  final String kernelVersion;
  final String hostname;

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
    this.loadAverage = 'Unknown',
    this.temperature = 0,
    this.diskIO = 'Unknown',
    this.networkBandwidth = 'Unknown',
    this.memoryDetails = const MemoryDetails(),
    this.totalProcesses = 0,
    this.kernelVersion = 'Unknown',
    this.hostname = 'Unknown',
  });

  double get storageUsagePercent =>
      storageTotal > 0 ? (storageUsed / storageTotal) * 100 : 0;
}

class MemoryDetails {
  final double total;
  final double used;
  final double free;
  final double available;
  final double cached;
  final double buffers;
  final double swapTotal;
  final double swapUsed;

  const MemoryDetails({
    this.total = 0,
    this.used = 0,
    this.free = 0,
    this.available = 0,
    this.cached = 0,
    this.buffers = 0,
    this.swapTotal = 0,
    this.swapUsed = 0,
  });

  double get usedPercent => total > 0 ? (used / total) * 100 : 0;
  double get swapPercent => swapTotal > 0 ? (swapUsed / swapTotal) * 100 : 0;
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
    return 'Connection failed: ${error.length > 100 ? '${error.substring(0, 100)}...' : error}';
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
        _fetchLoadAverage(),
        _fetchTemperature(),
        _fetchDiskIO(),
        _fetchNetworkBandwidth(),
        _fetchMemoryDetails(),
        _fetchTotalProcesses(),
        _fetchKernelVersion(),
        _fetchHostname(),
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
            loadAverage: results[8] as String,
            temperature: results[9] as double,
            diskIO: results[10] as String,
            networkBandwidth: results[11] as String,
            memoryDetails: results[12] as MemoryDetails,
            totalProcesses: results[13] as int,
            kernelVersion: results[14] as String,
            hostname: results[15] as String,
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

  Future<String> _fetchLoadAverage() async {
    try {
      final session = await _sshClient?.execute('cat /proc/loadavg');
      final result = await utf8.decodeStream(session!.stdout);
      final parts = result.trim().split(' ');
      if (parts.length >= 3) {
        return '${parts[0]} / ${parts[1]} / ${parts[2]}';
      }
    } catch (e) {
      // Ignore
    }
    return 'Unknown';
  }

  Future<double> _fetchTemperature() async {
    try {
      // Try multiple temperature sources
      final session = await _sshClient?.execute(
          'cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || sensors 2>/dev/null | grep "Core 0" | awk \'{print \$3}\' | tr -d "+°C"');
      final result = await utf8.decodeStream(session!.stdout);
      final temp = double.tryParse(result.trim());
      if (temp != null) {
        // If reading from thermal_zone, divide by 1000
        return temp > 200 ? temp / 1000 : temp;
      }
    } catch (e) {
      // Ignore
    }
    return 0;
  }

  Future<String> _fetchDiskIO() async {
    try {
      final session = await _sshClient?.execute(
          'iostat -d 1 2 | tail -n 2 | head -n 1 | awk \'{print \$3" kB/s read, "\$4" kB/s write"}\' 2>/dev/null || echo "N/A"');
      final result = await utf8.decodeStream(session!.stdout);
      return result.trim();
    } catch (e) {
      return 'Unknown';
    }
  }

  Future<String> _fetchNetworkBandwidth() async {
    try {
      final session = await _sshClient?.execute(
          'cat /proc/net/dev | grep -E "eth0|wlan0|enp|wlp" | head -n 1 | awk \'{printf "↓ %.1f MB ↑ %.1f MB", \$2/1024/1024, \$10/1024/1024}\'');
      final result = await utf8.decodeStream(session!.stdout);
      return result.trim().isNotEmpty ? result.trim() : 'Unknown';
    } catch (e) {
      return 'Unknown';
    }
  }

  Future<MemoryDetails> _fetchMemoryDetails() async {
    try {
      final session = await _sshClient?.execute('free -b');
      final result = await utf8.decodeStream(session!.stdout);
      final lines = result.split('\n');

      double total = 0,
          used = 0,
          free = 0,
          available = 0,
          cached = 0,
          buffers = 0;
      double swapTotal = 0, swapUsed = 0;

      for (var line in lines) {
        if (line.startsWith('Mem:')) {
          final parts =
              line.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
          if (parts.length >= 7) {
            total = double.tryParse(parts[1]) ?? 0;
            used = double.tryParse(parts[2]) ?? 0;
            free = double.tryParse(parts[3]) ?? 0;
            available = double.tryParse(parts[6]) ?? 0;
            cached = double.tryParse(parts[5]) ?? 0;
            buffers = double.tryParse(parts[4]) ?? 0;
          }
        } else if (line.startsWith('Swap:')) {
          final parts =
              line.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
          if (parts.length >= 3) {
            swapTotal = double.tryParse(parts[1]) ?? 0;
            swapUsed = double.tryParse(parts[2]) ?? 0;
          }
        }
      }

      return MemoryDetails(
        total: total / (1024 * 1024 * 1024), // Convert to GB
        used: used / (1024 * 1024 * 1024),
        free: free / (1024 * 1024 * 1024),
        available: available / (1024 * 1024 * 1024),
        cached: cached / (1024 * 1024 * 1024),
        buffers: buffers / (1024 * 1024 * 1024),
        swapTotal: swapTotal / (1024 * 1024 * 1024),
        swapUsed: swapUsed / (1024 * 1024 * 1024),
      );
    } catch (e) {
      return const MemoryDetails();
    }
  }

  Future<int> _fetchTotalProcesses() async {
    try {
      final session = await _sshClient?.execute('ps aux | wc -l');
      final result = await utf8.decodeStream(session!.stdout);
      return int.tryParse(result.trim()) ?? 0;
    } catch (e) {
      return 0;
    }
  }

  Future<String> _fetchKernelVersion() async {
    try {
      final session = await _sshClient?.execute('uname -r');
      final result = await utf8.decodeStream(session!.stdout);
      return result.trim();
    } catch (e) {
      return 'Unknown';
    }
  }

  Future<String> _fetchHostname() async {
    try {
      final session = await _sshClient?.execute('hostname');
      final result = await utf8.decodeStream(session!.stdout);
      return result.trim();
    } catch (e) {
      return 'Unknown';
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

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemoryDetailsCard() {
    final mem = _systemInfo.memoryDetails;
    if (mem.total == 0) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Memory details unavailable'),
        ),
      );
    }

    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMemoryRow('Total', mem.total, Colors.blue),
            _buildMemoryRow('Used', mem.used, Colors.red),
            _buildMemoryRow('Free', mem.free, Colors.green),
            _buildMemoryRow('Available', mem.available, Colors.teal),
            _buildMemoryRow('Cached', mem.cached, Colors.orange),
            _buildMemoryRow('Buffers', mem.buffers, Colors.purple),
            if (mem.swapTotal > 0) ...[
              const Divider(height: 20),
              _buildMemoryRow('Swap Total', mem.swapTotal, Colors.indigo),
              _buildMemoryRow('Swap Used', mem.swapUsed, Colors.deepOrange),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: mem.swapPercent / 100,
                backgroundColor: Colors.grey[300],
                color: Colors.deepOrange,
                minHeight: 8,
              ),
              const SizedBox(height: 4),
              Text(
                'Swap Usage: ${mem.swapPercent.toStringAsFixed(1)}%',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMemoryRow(String label, double valueGB, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
          Text(
            '${valueGB.toStringAsFixed(2)} GB',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
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

                        // System Stats Row
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatCard(
                                  'Load Avg',
                                  _systemInfo.loadAverage,
                                  Icons.equalizer,
                                  Colors.cyan),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildStatCard(
                                  'Processes',
                                  '${_systemInfo.totalProcesses}',
                                  Icons.apps,
                                  Colors.deepPurple),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatCard(
                                'Temp',
                                _systemInfo.temperature > 0
                                    ? '${_systemInfo.temperature.toStringAsFixed(1)}°C'
                                    : 'N/A',
                                Icons.thermostat,
                                _systemInfo.temperature > 75
                                    ? Colors.red
                                    : Colors.orange,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildStatCard(
                                  'Hostname',
                                  _systemInfo.hostname,
                                  Icons.dns,
                                  Colors.blueGrey),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // Memory Details
                        const Text(
                          'Memory Breakdown',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        _buildMemoryDetailsCard(),

                        const SizedBox(height: 24),

                        // Disk & Network IO
                        const Text(
                          'I/O Statistics',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        _buildInfoCard('Disk I/O', _systemInfo.diskIO,
                            Icons.storage, Colors.brown),
                        const SizedBox(height: 8),
                        _buildInfoCard(
                            'Network Traffic',
                            _systemInfo.networkBandwidth,
                            Icons.swap_vert,
                            Colors.green),

                        const SizedBox(height: 24),

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
                        _buildInfoCard('Kernel', _systemInfo.kernelVersion,
                            Icons.settings_system_daydream, Colors.deepOrange),
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
