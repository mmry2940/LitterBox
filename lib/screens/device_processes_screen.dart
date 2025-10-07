import 'package:flutter/material.dart';
import 'package:dartssh2/dartssh2.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/services.dart';

// Widget to display a process info chip with color coding
class ProcessInfoChip extends StatelessWidget {
  final String label;
  final String? value;
  final Color? color;
  const ProcessInfoChip(
      {required this.label, required this.value, this.color, super.key});

  @override
  Widget build(BuildContext context) {
    // Parse numeric values for color coding
    double? numValue;
    Color chipColor = color ?? Colors.grey.shade200;
    Color textColor = Colors.black87;

    if (label == 'CPU' || label == 'MEM') {
      numValue = double.tryParse(value ?? '0');
      if (numValue != null) {
        if (numValue > 50) {
          chipColor = Colors.red.shade100;
          textColor = Colors.red.shade900;
        } else if (numValue > 20) {
          chipColor = Colors.orange.shade100;
          textColor = Colors.orange.shade900;
        } else {
          chipColor = Colors.green.shade100;
          textColor = Colors.green.shade900;
        }
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: textColor.withOpacity(0.2)),
      ),
      child: Text(
        '$label: ${value ?? ''}',
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: textColor),
      ),
    );
  }
}

// Widget to display process details in a bottom sheet
class ProcessDetailSheet extends StatelessWidget {
  final Map<String, String> proc;
  final Function(String) onSignal;

  const ProcessDetailSheet(
      {required this.proc, required this.onSignal, super.key});

  @override
  Widget build(BuildContext context) {
    final cpu = double.tryParse(proc['%CPU'] ?? '0') ?? 0;
    final mem = double.tryParse(proc['%MEM'] ?? '0') ?? 0;

    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.terminal, size: 28, color: Colors.blue),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  proc['COMMAND'] ?? 'Unknown',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 18),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Divider(height: 24),

          // Key metrics
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                    'PID', proc['PID'] ?? '-', Icons.tag, Colors.blue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                    'USER', proc['USER'] ?? '-', Icons.person, Colors.purple),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  'CPU',
                  '${cpu.toStringAsFixed(1)}%',
                  Icons.memory,
                  cpu > 50
                      ? Colors.red
                      : (cpu > 20 ? Colors.orange : Colors.green),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  'MEM',
                  '${mem.toStringAsFixed(1)}%',
                  Icons.storage,
                  mem > 50
                      ? Colors.red
                      : (mem > 20 ? Colors.orange : Colors.green),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Additional details
          _buildDetailRow('Status', proc['STAT'] ?? '-'),
          _buildDetailRow('TTY', proc['TTY'] ?? '-'),
          _buildDetailRow('Start Time', proc['START'] ?? '-'),
          _buildDetailRow('CPU Time', proc['TIME'] ?? '-'),
          _buildDetailRow('VSZ', proc['VSZ'] ?? '-'),
          _buildDetailRow('RSS', proc['RSS'] ?? '-'),

          const SizedBox(height: 20),

          // Actions
          const Text(
            'Process Actions',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  onSignal('SIGTERM');
                },
                icon: const Icon(Icons.stop, size: 18),
                label: const Text('Terminate'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  onSignal('SIGKILL');
                },
                icon: const Icon(Icons.cancel, size: 18),
                label: const Text('Kill'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  onSignal('SIGSTOP');
                },
                icon: const Icon(Icons.pause, size: 18),
                label: const Text('Pause'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  onSignal('SIGCONT');
                },
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('Continue'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(
      String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: color.withOpacity(0.8)),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class DeviceProcessesScreen extends StatefulWidget {
  final SSHClient? sshClient;
  final String? error;
  final bool loading;
  const DeviceProcessesScreen({
    super.key,
    this.sshClient,
    this.error,
    this.loading = false,
  });

  @override
  State<DeviceProcessesScreen> createState() => _DeviceProcessesScreenState();
}

class _DeviceProcessesScreenState extends State<DeviceProcessesScreen> {
  List<Map<String, String>>? _processes;
  List<Map<String, String>>? _filteredProcesses;
  String? _error;
  bool _loading = false;
  String _search = '';
  String _sortColumn = '%CPU';
  bool _sortAsc = false;
  bool _autoRefresh = false;
  String _stateFilter = 'All';
  Timer? _autoRefreshTimer;
  late final TextEditingController _searchController;
  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    if (widget.sshClient != null) {
      _fetchProcesses();
    }
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(DeviceProcessesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.key != oldWidget.key && widget.sshClient != null) {
      _fetchProcesses();
    }
  }

  Future<void> _fetchProcesses() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = await widget.sshClient!.execute('ps aux');
      final output =
          await session.stdout.cast<List<int>>().transform(utf8.decoder).join();
      final lines =
          output.split('\n').where((l) => l.trim().isNotEmpty).toList();
      if (lines.isEmpty) throw Exception('No process data');
      final header = lines.first.split(RegExp(r'\s+'));
      final data = lines
          .sublist(1)
          .map((line) {
            final cols = line.split(RegExp(r'\s+', multiLine: true));
            // ps aux: USER PID %CPU %MEM VSZ RSS TTY STAT START TIME COMMAND
            // Sometimes COMMAND has spaces, so join the rest
            if (cols.length < header.length) return null;
            final map = <String, String>{};
            for (int i = 0; i < header.length - 1; i++) {
              map[header[i]] = cols[i];
            }
            map[header.last] = cols.sublist(header.length - 1).join(' ');
            return map;
          })
          .whereType<Map<String, String>>()
          .toList();
      if (!mounted) return;
      _processes = data;
      _applyFilterSort();
      setState(() {
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _applyFilterSort() {
    List<Map<String, String>> filtered = _processes ?? [];

    // Apply state filter
    if (_stateFilter != 'All') {
      filtered = filtered.where((p) {
        final stat = p['STAT'] ?? '';
        if (stat.isEmpty) return false;
        final firstChar = stat[0];
        return firstChar == _stateFilter[0];
      }).toList();
    }

    // Apply search filter
    if (_search.isNotEmpty) {
      filtered = filtered
          .where(
            (p) => p.values.any(
              (v) => v.toLowerCase().contains(_search.toLowerCase()),
            ),
          )
          .toList();
    }

    // Apply sorting
    filtered.sort((a, b) {
      final aVal = a[_sortColumn] ?? '';
      final bVal = b[_sortColumn] ?? '';
      if (_sortColumn == 'PID' ||
          _sortColumn == '%CPU' ||
          _sortColumn == '%MEM') {
        final aNum = double.tryParse(aVal) ?? 0;
        final bNum = double.tryParse(bVal) ?? 0;
        return _sortAsc ? aNum.compareTo(bNum) : bNum.compareTo(aNum);
      }
      return _sortAsc ? aVal.compareTo(bVal) : bVal.compareTo(aVal);
    });

    // Update state directly without nested setState
    _filteredProcesses = filtered;
  }

  void _onSearchChanged() {
    if (!mounted) return;
    _search = _searchController.text;
    _applyFilterSort();
    setState(() {});
  }

  void _onSendSignal(Map<String, String> process, String signal) async {
    final pid = process['PID'];
    final processUser = process['USER'];
    if (pid == null) return;

    String signalName = signal;
    String command = '';

    switch (signal) {
      case 'SIGTERM':
        command = 'kill $pid';
        signalName = 'SIGTERM';
        break;
      case 'SIGKILL':
        command = 'kill -9 $pid';
        signalName = 'SIGKILL';
        break;
      case 'SIGSTOP':
        command = 'kill -STOP $pid';
        signalName = 'SIGSTOP';
        break;
      case 'SIGCONT':
        command = 'kill -CONT $pid';
        signalName = 'SIGCONT';
        break;
      default:
        return;
    }

    // Check if this might need sudo
    bool mightNeedSudo = processUser != null &&
        processUser != 'root' &&
        !['mobile', 'shell', 'system'].contains(processUser);

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Send $signalName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Send $signalName to PID $pid?'),
            const SizedBox(height: 8),
            Text(
              'Process: ${process['COMMAND']}',
              style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            ),
            Text(
              'User: ${processUser ?? "unknown"}',
              style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            ),
            if (!mightNeedSudo) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning,
                        color: Colors.orange.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This is a system process. May require root/sudo.',
                        style: TextStyle(
                            fontSize: 11, color: Colors.orange.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx,
                {'confirmed': false, 'useSudo': false, 'useTerminal': false}),
            child: const Text('Cancel'),
          ),
          if (!mightNeedSudo)
            TextButton(
              onPressed: () => Navigator.pop(ctx,
                  {'confirmed': true, 'useSudo': false, 'useTerminal': true}),
              child: const Text('Run in Terminal'),
              style: TextButton.styleFrom(foregroundColor: Colors.blue),
            ),
          if (!mightNeedSudo)
            TextButton(
              onPressed: () => Navigator.pop(ctx,
                  {'confirmed': true, 'useSudo': true, 'useTerminal': false}),
              child: const Text('Try with sudo -n'),
              style: TextButton.styleFrom(foregroundColor: Colors.orange),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx,
                {'confirmed': true, 'useSudo': false, 'useTerminal': false}),
            child: Text(mightNeedSudo ? 'Send Signal' : 'Try Anyway'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
        ],
      ),
    );

    if (result != null &&
        result['confirmed'] == true &&
        widget.sshClient != null &&
        mounted) {
      final useSudo = result['useSudo'] == true;
      final useTerminal = result['useTerminal'] == true;

      // If user chose terminal, copy command and show instructions
      if (useTerminal) {
        if (mounted) {
          // Copy command to clipboard
          await Clipboard.setData(ClipboardData(text: 'sudo $command'));

          // Show snackbar with instructions
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Command copied: sudo $command\n\nSwitch to Terminal tab and paste the command'),
              backgroundColor: Colors.blue,
              duration: const Duration(seconds: 6),
              action: SnackBarAction(
                label: 'Got it',
                textColor: Colors.white,
                onPressed: () {},
              ),
            ),
          );
        }
        return;
      }

      // If sudo requested, prompt for password
      String? sudoPassword;
      if (useSudo) {
        TextEditingController? passwordController;
        try {
          passwordController = TextEditingController();
          final passwordConfirmed = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('Sudo Password Required'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Enter your sudo password to execute:'),
                  const SizedBox(height: 8),
                  Text(
                    'sudo $command',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.blue.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.lock),
                      helperText: 'Password will not be stored',
                    ),
                    onSubmitted: (_) => Navigator.pop(ctx, true),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Execute'),
                ),
              ],
            ),
          );

          if (passwordConfirmed != true || !mounted) {
            return;
          }

          sudoPassword = passwordController.text;

          if (sudoPassword.isEmpty) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Password cannot be empty'),
                  backgroundColor: Colors.red,
                  duration: Duration(seconds: 2),
                ),
              );
            }
            return;
          }
        } finally {
          passwordController?.dispose();
        }
      }

      // Build final command
      final finalCommand = useSudo ? 'sudo -S $command' : command;

      try {
        // Execute the command and wait for completion
        final session = await widget.sshClient!.execute(finalCommand);

        // If using sudo with password, send password to stdin
        if (useSudo && sudoPassword != null) {
          session.stdin.add(utf8.encode('$sudoPassword\n'));
          await session.stdin.close();
          // Give sudo a moment to process the password
          await Future.delayed(const Duration(milliseconds: 100));
        }

        // Read the output streams concurrently to avoid blocking
        final stdout = utf8.decodeStream(session.stdout);
        final stderrFuture = utf8.decodeStream(session.stderr);

        // Wait for streams and exit code
        await stdout; // Consume stdout
        final stderr = await stderrFuture;
        final exitCode = await session.exitCode ?? 1;

        if (mounted) {
          if (exitCode == 0) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('$signalName sent to PID $pid'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
              ),
            );
          } else {
            // Filter out sudo password prompts from stderr
            String errorMsg = stderr.trim();
            // Remove common sudo prompt messages
            errorMsg = errorMsg
                .replaceAll(RegExp(r'\[sudo\] password for .+:'), '')
                .replaceAll(RegExp(r'sudo: '), '')
                .trim();

            if (errorMsg.isEmpty) {
              errorMsg = 'Command failed with exit code $exitCode';
            }

            // Provide helpful suggestions
            String suggestion = '';
            if (errorMsg.contains('Operation not permitted') ||
                errorMsg.contains('Permission denied')) {
              if (!useSudo) {
                suggestion =
                    '\n\nTip: This process may require root access. Try "Try with sudo -n" option.';
              } else {
                suggestion =
                    '\n\nTip: Incorrect password or user not in sudoers file.';
              }
            } else if (errorMsg.contains('No such process')) {
              suggestion = '\n\nThe process may have already exited.';
            } else if (errorMsg.contains('sudo') &&
                (errorMsg.contains('incorrect password') ||
                    errorMsg.contains('authentication'))) {
              suggestion = '\n\nIncorrect password. Please try again.';
            } else if (errorMsg.contains('not in the sudoers file')) {
              suggestion =
                  '\n\nYour user account does not have sudo privileges.';
            }

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed: $errorMsg$suggestion'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 5),
                action: SnackBarAction(
                  label: 'Dismiss',
                  textColor: Colors.white,
                  onPressed: () {},
                ),
              ),
            );
          }
        }

        // Refresh process list after a short delay
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          _fetchProcesses();
        }
      } catch (e) {
        if (mounted) {
          String errorMsg = e.toString();
          String suggestion = '';

          if (errorMsg.contains('Operation not permitted') ||
              errorMsg.contains('Permission denied')) {
            suggestion =
                '\n\nTip: Check SSH user has permission to kill this process or try with sudo.';
          } else if (errorMsg.contains('sudo') &&
              (errorMsg.contains('incorrect password') ||
                  errorMsg.contains('authentication'))) {
            suggestion = '\n\nIncorrect password. Please try again.';
          } else if (errorMsg.contains('not in the sudoers file')) {
            suggestion = '\n\nYour user account does not have sudo privileges.';
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed: $errorMsg$suggestion'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'Dismiss',
                textColor: Colors.white,
                onPressed: () {},
              ),
            ),
          );
        }
      }
    }
  }

  void _toggleAutoRefresh() {
    if (!mounted) return;
    setState(() {
      _autoRefresh = !_autoRefresh;
    });

    if (_autoRefresh) {
      _startAutoRefresh();
    } else {
      _stopAutoRefresh();
    }
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted) {
        _fetchProcesses();
      } else {
        timer.cancel();
      }
    });
  }

  void _stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
  }

  void _changeSortColumn(String column) {
    if (!mounted) return;
    if (_sortColumn == column) {
      _sortAsc = !_sortAsc;
    } else {
      _sortColumn = column;
      _sortAsc = column == '%CPU' || column == '%MEM' ? false : true;
    }
    _applyFilterSort();
    setState(() {});
  }

  void _changeStateFilter(String filter) {
    if (!mounted) return;
    _stateFilter = filter;
    _applyFilterSort();
    setState(() {});
  }

  double _getTotalCPU() {
    if (_processes == null) return 0;
    double total = 0;
    for (var proc in _processes!) {
      total += double.tryParse(proc['%CPU'] ?? '0') ?? 0;
    }
    return total;
  }

  double _getTotalMEM() {
    if (_processes == null) return 0;
    double total = 0;
    for (var proc in _processes!) {
      total += double.tryParse(proc['%MEM'] ?? '0') ?? 0;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading || _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text('SSH Error: ${widget.error}'),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _fetchProcesses(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text('Error: $_error'),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _fetchProcesses,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_filteredProcesses != null) {
      final totalProc = _processes?.length ?? 0;
      final filteredProc = _filteredProcesses!.length;
      final totalCPU = _getTotalCPU();
      final totalMEM = _getTotalMEM();

      return RefreshIndicator(
        onRefresh: _fetchProcesses,
        child: Column(
          children: [
            // Summary Cards
            Container(
              padding: const EdgeInsets.all(12),
              color:
                  Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
              child: Row(
                children: [
                  Expanded(
                    child: _buildSummaryCard(
                      'Total',
                      '$totalProc',
                      Icons.apps,
                      Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildSummaryCard(
                      'Showing',
                      '$filteredProc',
                      Icons.filter_list,
                      Colors.purple,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildSummaryCard(
                      'CPU',
                      '${totalCPU.toStringAsFixed(1)}%',
                      Icons.memory,
                      totalCPU > 80 ? Colors.red : Colors.green,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildSummaryCard(
                      'MEM',
                      '${totalMEM.toStringAsFixed(1)}%',
                      Icons.storage,
                      totalMEM > 80 ? Colors.red : Colors.green,
                    ),
                  ),
                ],
              ),
            ),

            // Search and Controls
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search processes...',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _search.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _searchController.clear();
                                      _onSearchChanged();
                                    },
                                  )
                                : null,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                vertical: 0, horizontal: 12),
                          ),
                          onChanged: (_) => _onSearchChanged(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(_autoRefresh
                            ? Icons.pause_circle
                            : Icons.play_circle),
                        tooltip: _autoRefresh
                            ? 'Pause Auto-Refresh'
                            : 'Start Auto-Refresh (5s)',
                        onPressed: _toggleAutoRefresh,
                        color: _autoRefresh ? Colors.orange : Colors.blue,
                        iconSize: 32,
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Refresh Now',
                        onPressed: _fetchProcesses,
                        iconSize: 32,
                        color: Colors.blue,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Filter Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        const Text('Filter: ',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        ...['All', 'Running', 'Sleeping', 'Stopped', 'Zombie']
                            .map((filter) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(filter),
                              selected: _stateFilter == filter,
                              onSelected: (_) => _changeStateFilter(filter),
                              selectedColor: Colors.blue.shade200,
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Sort Controls
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        const Text('Sort: ',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        ...[
                          {'label': 'CPU', 'col': '%CPU'},
                          {'label': 'MEM', 'col': '%MEM'},
                          {'label': 'PID', 'col': 'PID'},
                          {'label': 'User', 'col': 'USER'},
                        ].map((sort) {
                          final isSelected = _sortColumn == sort['col'];
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(sort['label']!),
                                  if (isSelected) ...[
                                    const SizedBox(width: 4),
                                    Icon(
                                      _sortAsc
                                          ? Icons.arrow_upward
                                          : Icons.arrow_downward,
                                      size: 16,
                                    ),
                                  ],
                                ],
                              ),
                              selected: isSelected,
                              onSelected: (_) =>
                                  _changeSortColumn(sort['col']!),
                              selectedColor: Colors.green.shade200,
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Process List
            Expanded(
              child: _filteredProcesses!.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off,
                              size: 64, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          Text(
                            'No processes found',
                            style: TextStyle(
                                fontSize: 16, color: Colors.grey.shade600),
                          ),
                          if (_search.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: () {
                                _searchController.clear();
                                _onSearchChanged();
                              },
                              icon: const Icon(Icons.clear),
                              label: const Text('Clear Search'),
                            ),
                          ],
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      itemCount: _filteredProcesses!.length,
                      itemBuilder: (context, idx) {
                        final proc = _filteredProcesses![idx];
                        final cpu = double.tryParse(proc['%CPU'] ?? '0') ?? 0;
                        final mem = double.tryParse(proc['%MEM'] ?? '0') ?? 0;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: cpu > 50 || mem > 50
                                  ? Colors.red.withOpacity(0.3)
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          elevation: cpu > 50 || mem > 50 ? 4 : 2,
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            leading: CircleAvatar(
                              backgroundColor: cpu > 50
                                  ? Colors.red.shade100
                                  : Colors.blue.shade100,
                              child: Text(
                                proc['PID'] ?? '',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: cpu > 50
                                      ? Colors.red.shade900
                                      : Colors.blue.shade900,
                                ),
                              ),
                            ),
                            title: Text(
                              proc['COMMAND'] ?? '',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  ProcessInfoChip(
                                      label: 'CPU', value: proc['%CPU']),
                                  ProcessInfoChip(
                                      label: 'MEM', value: proc['%MEM']),
                                  ProcessInfoChip(
                                    label: 'USER',
                                    value: proc['USER'],
                                    color: Colors.indigo.shade50,
                                  ),
                                  ProcessInfoChip(
                                    label: 'STAT',
                                    value: proc['STAT'],
                                    color: _getStatColor(proc['STAT'] ?? ''),
                                  ),
                                ],
                              ),
                            ),
                            trailing: PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert),
                              tooltip: 'Actions',
                              onSelected: (signal) =>
                                  _onSendSignal(proc, signal),
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'SIGTERM',
                                  child: Row(
                                    children: [
                                      Icon(Icons.stop,
                                          color: Colors.orange, size: 20),
                                      SizedBox(width: 8),
                                      Text('Terminate (SIGTERM)'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'SIGKILL',
                                  child: Row(
                                    children: [
                                      Icon(Icons.cancel,
                                          color: Colors.red, size: 20),
                                      SizedBox(width: 8),
                                      Text('Kill (SIGKILL)'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'SIGSTOP',
                                  child: Row(
                                    children: [
                                      Icon(Icons.pause,
                                          color: Colors.blue, size: 20),
                                      SizedBox(width: 8),
                                      Text('Pause (SIGSTOP)'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'SIGCONT',
                                  child: Row(
                                    children: [
                                      Icon(Icons.play_arrow,
                                          color: Colors.green, size: 20),
                                      SizedBox(width: 8),
                                      Text('Continue (SIGCONT)'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            onTap: () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(20)),
                                ),
                                builder: (ctx) => ProcessDetailSheet(
                                  proc: proc,
                                  onSignal: (signal) =>
                                      _onSendSignal(proc, signal),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    }

    if (widget.sshClient == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('Waiting for SSH connection...'),
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.hourglass_empty, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('No processes loaded'),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _fetchProcesses,
            icon: const Icon(Icons.refresh),
            label: const Text('Load Processes'),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
      String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
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
            label,
            style: TextStyle(
              fontSize: 10,
              color: color.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatColor(String stat) {
    if (stat.startsWith('R')) return Colors.green.shade50;
    if (stat.startsWith('S') || stat.startsWith('I'))
      return Colors.blue.shade50;
    if (stat.startsWith('Z')) return Colors.red.shade50;
    if (stat.startsWith('T')) return Colors.orange.shade50;
    return Colors.grey.shade50;
  }
}
