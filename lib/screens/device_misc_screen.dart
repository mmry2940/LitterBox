import 'package:flutter/material.dart';
import 'package:dartssh2/dartssh2.dart';
import 'dart:convert';
import 'device_details_screen.dart';
import '../widgets/enhanced_misc_card.dart';
import '../widgets/device_summary_card.dart';
import '../models/device_status.dart';

class DeviceMiscScreen extends StatefulWidget {
  final void Function(int tabIndex)? onCardTap;
  final Map<String, dynamic> device;
  final SSHClient? sshClient;
  final DeviceStatus? deviceStatus;

  const DeviceMiscScreen({
    super.key,
    this.onCardTap,
    required this.device,
    this.sshClient,
    this.deviceStatus,
  });

  @override
  State<DeviceMiscScreen> createState() => _DeviceMiscScreenState();
}

class _DeviceMiscScreenState extends State<DeviceMiscScreen> {
  final Map<String, CardMetadata> _cardMetadata = {};
  bool _isLoadingMetadata = false;
  Map<String, dynamic>? _systemInfo;

  @override
  void initState() {
    super.initState();
    _loadAllMetadata();
  }

  Future<void> _loadAllMetadata() async {
    if (widget.sshClient == null || _isLoadingMetadata) return;

    setState(() {
      _isLoadingMetadata = true;
    });

    // Load metadata for each card in parallel
    await Future.wait([
      _loadTerminalMetadata(),
      _loadProcessMetadata(),
      _loadFilesMetadata(),
      _loadPackagesMetadata(),
      _loadSystemInfo(),
    ]);

    if (mounted) {
      setState(() {
        _isLoadingMetadata = false;
      });
    }
  }

  Future<void> _loadTerminalMetadata() async {
    try {
      // For now, just show as ready (could track active terminal tabs in future)
      setState(() {
        _cardMetadata['terminal'] = const CardMetadata(
          status: 'Ready',
          detail: 'Shell access',
          isActive: false,
        );
      });
    } catch (e) {
      setState(() {
        _cardMetadata['terminal'] = CardMetadata(
          error: e.toString(),
          isActive: false,
        );
      });
    }
  }

  Future<void> _loadProcessMetadata() async {
    if (widget.sshClient == null) return;

    try {
      // Count running processes
      final session =
          await widget.sshClient!.execute('ps aux | tail -n +2 | wc -l');
      final stdout =
          await session.stdout.cast<List<int>>().transform(utf8.decoder).join();
      final count = int.tryParse(stdout.trim()) ?? 0;

      if (mounted) {
        setState(() {
          _cardMetadata['processes'] = CardMetadata(
            count: count,
            detail: '$count running',
            status: 'Active',
            isActive: true,
          );
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cardMetadata['processes'] = CardMetadata(
            error: e.toString(),
            detail: 'Check processes',
            isActive: false,
          );
        });
      }
    }
  }

  Future<void> _loadFilesMetadata() async {
    if (widget.sshClient == null) return;

    try {
      // Get disk usage
      final session = await widget.sshClient!.execute('df -h / | tail -1');
      final stdout =
          await session.stdout.cast<List<int>>().transform(utf8.decoder).join();
      final parts = stdout.trim().split(RegExp(r'\s+'));
      final usage = parts.length >= 5 ? '${parts[2]}/${parts[1]}' : 'N/A';

      if (mounted) {
        setState(() {
          _cardMetadata['files'] = CardMetadata(
            detail: usage != 'N/A' ? usage : 'Browse files',
            status: 'Ready',
            isActive: true,
          );
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cardMetadata['files'] = CardMetadata(
            error: e.toString(),
            detail: 'Browse files',
            isActive: false,
          );
        });
      }
    }
  }

  Future<void> _loadPackagesMetadata() async {
    if (widget.sshClient == null) return;

    try {
      // Count installed packages (try dpkg, rpm, or pacman)
      final session = await widget.sshClient!.execute(
        'dpkg -l 2>/dev/null | tail -n +6 | wc -l || rpm -qa 2>/dev/null | wc -l || pacman -Q 2>/dev/null | wc -l || echo 0',
      );
      final stdout =
          await session.stdout.cast<List<int>>().transform(utf8.decoder).join();
      final count = int.tryParse(stdout.trim()) ?? 0;

      if (mounted) {
        setState(() {
          _cardMetadata['packages'] = CardMetadata(
            count: count,
            detail: count > 0 ? '$count installed' : 'View packages',
            status: 'Ready',
            isActive: count > 0,
          );
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cardMetadata['packages'] = CardMetadata(
            error: e.toString(),
            detail: 'View packages',
            isActive: false,
          );
        });
      }
    }
  }

  Future<void> _loadSystemInfo() async {
    if (widget.sshClient == null) return;

    try {
      // Get basic system info for summary card
      final uptimeSession =
          await widget.sshClient!.execute('uptime -p 2>/dev/null || uptime');
      final uptimeStdout = await uptimeSession.stdout
          .cast<List<int>>()
          .transform(utf8.decoder)
          .join();

      final memSession =
          await widget.sshClient!.execute("free -h | grep 'Mem:'");
      final memStdout = await memSession.stdout
          .cast<List<int>>()
          .transform(utf8.decoder)
          .join();
      final memParts = memStdout.trim().split(RegExp(r'\s+'));
      final memUsed = memParts.length >= 3 ? memParts[2] : 'N/A';
      final memTotal = memParts.length >= 2 ? memParts[1] : 'N/A';

      if (mounted) {
        setState(() {
          _systemInfo = {
            'uptime':
                uptimeStdout.trim().replaceAll('up ', '').split(',')[0].trim(),
            'memoryUsed': memUsed,
            'memoryTotal': memTotal != 'N/A' ? memTotal : null,
          };
        });
      }
    } catch (e) {
      // Silently fail - system info is optional
    }
  }

  List<_CardConfig> _getCardConfigs() {
    return [
      _CardConfig(
        title: 'System Info',
        description: 'View device information',
        icon: Icons.info_outline,
        color: Colors.blue,
        tabIndex: 0,
        tooltipTitle: 'System Information',
        tooltipFeatures: [
          'Device name and hostname',
          'Operating system details',
          'Architecture and kernel',
          'Connection information',
        ],
        metadata: const CardMetadata(
          status: 'Ready',
          detail: 'View details',
          isActive: true,
        ),
      ),
      _CardConfig(
        title: 'Terminal',
        description: 'Access device shell',
        icon: Icons.terminal,
        color: Colors.green,
        tabIndex: 1,
        quickActionLabel: 'Launch Shell',
        tooltipTitle: 'Terminal',
        tooltipFeatures: [
          'Interactive SSH shell',
          'Command execution',
          'Command history',
          'Clipboard support',
        ],
        metadata: _cardMetadata['terminal'],
      ),
      _CardConfig(
        title: 'File Browser',
        description: 'Explore device storage',
        icon: Icons.folder_open,
        color: Colors.orange,
        tabIndex: 2,
        quickActionLabel: 'Browse Files',
        tooltipTitle: 'File Browser',
        tooltipFeatures: [
          'Browse file system',
          'Upload/Download files',
          'Create/Delete folders',
          'File permissions',
        ],
        metadata: _cardMetadata['files'],
      ),
      _CardConfig(
        title: 'Processes',
        description: 'Monitor running processes',
        icon: Icons.memory,
        color: Colors.teal,
        tabIndex: 3,
        quickActionLabel: 'View List',
        tooltipTitle: 'Process Manager',
        tooltipFeatures: [
          'View all processes',
          'CPU and memory usage',
          'Kill/Stop processes',
          'Filter and sort',
        ],
        metadata: _cardMetadata['processes'],
      ),
      _CardConfig(
        title: 'Packages',
        description: 'Manage installed apps',
        icon: Icons.apps,
        color: Colors.purple,
        tabIndex: 4,
        quickActionLabel: 'Browse Apps',
        tooltipTitle: 'Package Manager',
        tooltipFeatures: [
          'List installed packages',
          'View app details',
          'Package information',
          'Version tracking',
        ],
        metadata: _cardMetadata['packages'],
      ),
      _CardConfig(
        title: 'Advanced Details',
        description: 'Real-time monitoring',
        icon: Icons.analytics,
        color: Colors.cyan,
        tabIndex: 5,
        isDetailsCard: true,
        quickActionLabel: 'View Metrics',
        tooltipTitle: 'Advanced Metrics',
        tooltipFeatures: [
          'CPU usage and load',
          'Memory breakdown',
          'Disk I/O statistics',
          'Network bandwidth',
          'Temperature sensors',
        ],
        metadata: const CardMetadata(
          status: 'Available',
          detail: 'System metrics',
          isActive: true,
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadAllMetadata,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Device Summary Header
                DeviceSummaryCard(
                  device: widget.device,
                  status: widget.deviceStatus,
                  systemInfo: _systemInfo,
                ),
                const SizedBox(height: 20),

                // Overview Cards Grid (3x4 Layout - Compact)
                LayoutBuilder(
                  builder: (context, constraints) {
                    // Always use 3 columns for compact grid layout
                    const int crossAxisCount = 3;

                    final cards = _getCardConfigs();

                    return GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        childAspectRatio:
                            0.75, // Slightly taller cards for better fit
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: cards.length,
                      itemBuilder: (context, index) {
                        final card = cards[index];
                        return EnhancedMiscCard(
                          title: card.title,
                          description: card.description,
                          icon: card.icon,
                          color: card.color,
                          metadata: card.metadata,
                          tooltipTitle: card.tooltipTitle,
                          tooltipFeatures: card.tooltipFeatures,
                          quickActionLabel: card.quickActionLabel,
                          onTap: () {
                            if (card.isDetailsCard) {
                              // Navigate to dedicated Details screen
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => DeviceDetailsScreen(
                                    device: widget.device,
                                  ),
                                ),
                              );
                            } else if (widget.onCardTap != null) {
                              // Switch to tab
                              widget.onCardTap!(card.tabIndex);
                            }
                          },
                          onQuickAction: () {
                            if (card.isDetailsCard) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => DeviceDetailsScreen(
                                    device: widget.device,
                                  ),
                                ),
                              );
                            } else if (widget.onCardTap != null) {
                              widget.onCardTap!(card.tabIndex);
                            }
                          },
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CardConfig {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final int tabIndex;
  final bool isDetailsCard;
  final String? quickActionLabel;
  final String? tooltipTitle;
  final List<String>? tooltipFeatures;
  final CardMetadata? metadata;

  _CardConfig({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.tabIndex,
    this.isDetailsCard = false,
    this.quickActionLabel,
    this.tooltipTitle,
    this.tooltipFeatures,
    this.metadata,
  });
}
