import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dartssh2/dartssh2.dart';
import 'dart:convert';

class DeviceInfoScreen extends StatefulWidget {
  final SSHClient? sshClient;
  final String? error;
  final bool loading;
  const DeviceInfoScreen({
    super.key,
    this.sshClient,
    this.error,
    this.loading = false,
  });

  @override
  State<DeviceInfoScreen> createState() => _DeviceInfoScreenState();
}

class SystemInfo {
  final String hostname;
  final String kernel;
  final String architecture;
  final String cpuModel;
  final int cpuCores;
  final double cpuUsage;
  final String memoryTotal;
  final String memoryUsed;
  final String memoryFree;
  final double memoryUsagePercent;
  final String swapTotal;
  final String swapUsed;
  final double swapUsagePercent;
  final String uptime;
  final String osVersion;
  final Map<String, String> additionalInfo;

  SystemInfo({
    required this.hostname,
    required this.kernel,
    required this.architecture,
    required this.cpuModel,
    required this.cpuCores,
    required this.cpuUsage,
    required this.memoryTotal,
    required this.memoryUsed,
    required this.memoryFree,
    required this.memoryUsagePercent,
    required this.swapTotal,
    required this.swapUsed,
    required this.swapUsagePercent,
    required this.uptime,
    required this.osVersion,
    required this.additionalInfo,
  });
}

class _DeviceInfoScreenState extends State<DeviceInfoScreen>
    with TickerProviderStateMixin {
  SystemInfo? _systemInfo;
  String? _error;
  bool _loading = false;
  final Map<String, bool> _expandedSections = {
    'system': true,
    'cpu': true,
    'memory': true,
    'network': false,
    'storage': false,
    'additional': false,
  };

  late AnimationController _refreshController;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _refreshController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    if (widget.sshClient != null) {
      _fetchInfo();
    }
  }

  @override
  void dispose() {
    _refreshController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(DeviceInfoScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.sshClient != oldWidget.sshClient && widget.sshClient != null) ||
        widget.key != oldWidget.key) {
      _fetchInfo();
    }
  }

  Future<void> _fetchInfo() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    _refreshController.repeat();

    try {
      // Comprehensive system information gathering
      final commands = [
        'hostname',
        'uname -a',
        'lscpu',
        'free -h',
        'uptime',
        'cat /etc/os-release 2>/dev/null || echo "OS: Unknown"',
        'df -h /',
        'ps aux | head -1; ps aux | sort -nrk 3,3 | head -5',
        'iostat -c 1 1 2>/dev/null || echo "CPU usage: N/A"',
      ].join(' && echo "---SECTION_SEPARATOR---" && ');

      final session = await widget.sshClient!.execute(commands);
      final output =
          await session.stdout.cast<List<int>>().transform(utf8.decoder).join();

      _systemInfo = _parseSystemInfo(output);
      _refreshController.stop();
      _fadeController.forward();

      setState(() {
        _loading = false;
      });
    } catch (e) {
      _refreshController.stop();
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  SystemInfo _parseSystemInfo(String output) {
    final sections = output.split('---SECTION_SEPARATOR---');

    // Default values
    String hostname = 'Unknown';
    String kernel = 'Unknown';
    String architecture = 'Unknown';
    String cpuModel = 'Unknown';
    int cpuCores = 0;
    double cpuUsage = 0.0;
    String memoryTotal = '0B';
    String memoryUsed = '0B';
    String memoryFree = '0B';
    double memoryUsagePercent = 0.0;
    String swapTotal = '0B';
    String swapUsed = '0B';
    double swapUsagePercent = 0.0;
    String uptime = 'Unknown';
    String osVersion = 'Unknown';
    Map<String, String> additionalInfo = {};

    for (int i = 0; i < sections.length && i < 9; i++) {
      final section = sections[i].trim();
      final lines = section.split('\n');

      switch (i) {
        case 0: // hostname
          if (lines.isNotEmpty) hostname = lines.first.trim();
          break;
        case 1: // uname -a
          if (lines.isNotEmpty) {
            final parts = lines.first.split(' ');
            if (parts.length >= 3) {
              kernel = '${parts[0]} ${parts[2]}';
              if (parts.length >= 5) architecture = parts[4];
            }
          }
          break;
        case 2: // lscpu
          for (final line in lines) {
            if (line.contains(':')) {
              final parts = line.split(':');
              final key = parts[0].trim();
              final value = parts[1].trim();

              if (key.contains('Model name')) {
                cpuModel = value;
              } else if (key.contains('CPU(s)')) {
                cpuCores = int.tryParse(value) ?? 0;
              }
              additionalInfo[key] = value;
            }
          }
          break;
        case 3: // free -h
          for (final line in lines) {
            if (line.startsWith('Mem:')) {
              final parts = line.split(RegExp(r'\s+'));
              if (parts.length >= 4) {
                memoryTotal = parts[1];
                memoryUsed = parts[2];
                memoryFree = parts[3];
                memoryUsagePercent =
                    _calculateMemoryPercent(parts[1], parts[2]);
              }
            } else if (line.startsWith('Swap:')) {
              final parts = line.split(RegExp(r'\s+'));
              if (parts.length >= 3) {
                swapTotal = parts[1];
                swapUsed = parts[2];
                swapUsagePercent = _calculateMemoryPercent(parts[1], parts[2]);
              }
            }
          }
          break;
        case 4: // uptime
          if (lines.isNotEmpty) uptime = lines.first.trim();
          break;
        case 5: // os-release
          for (final line in lines) {
            if (line.contains('PRETTY_NAME')) {
              osVersion = line.split('=')[1].replaceAll('"', '');
            }
          }
          break;
      }
    }

    return SystemInfo(
      hostname: hostname,
      kernel: kernel,
      architecture: architecture,
      cpuModel: cpuModel,
      cpuCores: cpuCores,
      cpuUsage: cpuUsage,
      memoryTotal: memoryTotal,
      memoryUsed: memoryUsed,
      memoryFree: memoryFree,
      memoryUsagePercent: memoryUsagePercent,
      swapTotal: swapTotal,
      swapUsed: swapUsed,
      swapUsagePercent: swapUsagePercent,
      uptime: uptime,
      osVersion: osVersion,
      additionalInfo: additionalInfo,
    );
  }

  double _calculateMemoryPercent(String total, String used) {
    try {
      final totalNum = _parseMemorySize(total);
      final usedNum = _parseMemorySize(used);
      if (totalNum > 0) {
        return (usedNum / totalNum * 100).clamp(0.0, 100.0);
      }
    } catch (e) {
      // Ignore parsing errors
    }
    return 0.0;
  }

  double _parseMemorySize(String size) {
    if (size.isEmpty || size == '0') return 0.0;

    final regex = RegExp(r'(\d+\.?\d*)([KMGT]?)');
    final match = regex.firstMatch(size.toUpperCase());

    if (match != null) {
      final number = double.tryParse(match.group(1) ?? '') ?? 0.0;
      final unit = match.group(2) ?? '';

      switch (unit) {
        case 'K':
          return number * 1024;
        case 'M':
          return number * 1024 * 1024;
        case 'G':
          return number * 1024 * 1024 * 1024;
        case 'T':
          return number * 1024 * 1024 * 1024 * 1024;
        default:
          return number;
      }
    }

    return 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (widget.loading || _loading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _refreshController,
                builder: (context, child) {
                  return Transform.rotate(
                    angle: _refreshController.value * 2 * 3.14159,
                    child: Icon(
                      Icons.refresh,
                      size: 48,
                      color: colorScheme.primary,
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              Text(
                'Gathering system information...',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (widget.error != null) {
      return _buildErrorState('SSH Connection Error', widget.error!);
    }

    if (_error != null) {
      return _buildErrorState('Data Fetch Error', _error!);
    }

    if (_systemInfo != null) {
      return Scaffold(
        body: FadeTransition(
          opacity: _fadeAnimation,
          child: RefreshIndicator(
            onRefresh: _fetchInfo,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeaderCard(),
                  const SizedBox(height: 16),
                  _buildSystemOverviewCard(),
                  const SizedBox(height: 16),
                  _buildCPUCard(),
                  const SizedBox(height: 16),
                  _buildMemoryCard(),
                  const SizedBox(height: 16),
                  _buildAdditionalInfoCard(),
                ],
              ),
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _fetchInfo,
          tooltip: 'Refresh Information',
          child: AnimatedBuilder(
            animation: _refreshController,
            builder: (context, child) {
              return Transform.rotate(
                angle: _refreshController.value * 2 * 3.14159,
                child: const Icon(Icons.refresh),
              );
            },
          ),
        ),
      );
    }

    if (widget.sshClient == null) {
      return _buildErrorState('No Connection', 'Waiting for SSH connection...');
    }

    return _buildErrorState('No Data', 'No device information available.');
  }

  Widget _buildErrorState(String title, String message) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline,
                size: 64,
                color: colorScheme.error,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: colorScheme.error,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => _fetchInfo(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final info = _systemInfo!;

    return Card(
      elevation: 2,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.primaryContainer,
              colorScheme.primaryContainer.withOpacity(0.7),
            ],
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.computer,
                    color: colorScheme.onPrimary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        info.hostname,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        info.osVersion,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color:
                              colorScheme.onPrimaryContainer.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _copyToClipboard(info.hostname),
                  icon: Icon(
                    Icons.copy,
                    color: colorScheme.onPrimaryContainer,
                  ),
                  tooltip: 'Copy hostname',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surface.withOpacity(0.8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.schedule,
                    size: 16,
                    color: colorScheme.onSurface.withOpacity(0.7),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Uptime: ${info.uptime}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemOverviewCard() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final info = _systemInfo!;

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  'System Overview',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildInfoRow(
                'Kernel', info.kernel, Icons.settings_system_daydream),
            const SizedBox(height: 12),
            _buildInfoRow(
                'Architecture', info.architecture, Icons.architecture),
            const SizedBox(height: 12),
            _buildInfoRow('CPU Model', info.cpuModel, Icons.memory),
            const SizedBox(height: 12),
            _buildInfoRow(
                'CPU Cores', '${info.cpuCores} cores', Icons.developer_board),
          ],
        ),
      ),
    );
  }

  Widget _buildCPUCard() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final info = _systemInfo!;

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.developer_board,
                  color: colorScheme.secondary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  'Processor',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${info.cpuCores} Cores',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colorScheme.outline.withOpacity(0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Model',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.7),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    info.cpuModel,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemoryCard() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final info = _systemInfo!;

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.memory,
                  color: colorScheme.tertiary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  'Memory',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildMemorySection(
              'RAM',
              info.memoryUsed,
              info.memoryTotal,
              info.memoryUsagePercent,
              colorScheme.tertiary,
            ),
            const SizedBox(height: 16),
            if (info.swapTotal != '0B' && info.swapTotal.isNotEmpty)
              _buildMemorySection(
                'Swap',
                info.swapUsed,
                info.swapTotal,
                info.swapUsagePercent,
                colorScheme.error,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemorySection(
      String title, String used, String total, double percentage, Color color) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${percentage.toStringAsFixed(1)}%',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$used / $total',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percentage / 100,
              backgroundColor: colorScheme.outline.withOpacity(0.2),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdditionalInfoCard() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final info = _systemInfo!;

    if (info.additionalInfo.isEmpty) return const SizedBox.shrink();

    return Card(
      elevation: 1,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Row(
            children: [
              Icon(
                Icons.info_outline,
                color: colorScheme.primary,
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                'Additional Information',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          initiallyExpanded: _expandedSections['additional'] ?? false,
          onExpansionChanged: (expanded) {
            setState(() {
              _expandedSections['additional'] = expanded;
            });
          },
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                children: info.additionalInfo.entries
                    .map((entry) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child:
                              _buildInfoRow(entry.key, entry.value, Icons.info),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.1),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: colorScheme.onSurface.withOpacity(0.7),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withOpacity(0.8),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w400,
              ),
              textAlign: TextAlign.end,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => _copyToClipboard(value),
            icon: Icon(
              Icons.copy,
              size: 16,
              color: colorScheme.onSurface.withOpacity(0.5),
            ),
            constraints: const BoxConstraints(
              minWidth: 24,
              minHeight: 24,
            ),
            padding: EdgeInsets.zero,
            tooltip: 'Copy',
          ),
        ],
      ),
    );
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied to clipboard'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
