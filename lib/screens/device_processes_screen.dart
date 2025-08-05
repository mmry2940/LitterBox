import 'package:flutter/material.dart';
import 'package:dartssh2/dartssh2.dart';
import 'dart:convert';

// Widget to display a process info chip
class ProcessInfoChip extends StatelessWidget {
  final String label;
  final String? value;
  const ProcessInfoChip({required this.label, required this.value, Key? key})
      : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
      ),
      child:
          Text('$label: ${value ?? ''}', style: const TextStyle(fontSize: 12)),
    );
  }
}

// Widget to display process details in a bottom sheet
class ProcessDetailSheet extends StatelessWidget {
  final Map<String, String> proc;
  const ProcessDetailSheet({required this.proc, Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            proc['COMMAND'] ?? '',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 10),
          ...proc.entries.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Text('${e.key}: ',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Expanded(child: Text(e.value)),
                  ],
                ),
              )),
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
  String _sortColumn = 'PID';
  bool _sortAsc = true;
  bool _autoRefresh = false;
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
      setState(() {
        _processes = data;
        _applyFilterSort();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _applyFilterSort() {
    List<Map<String, String>> filtered = _processes ?? [];
    if (_search.isNotEmpty) {
      filtered = filtered
          .where(
            (p) => p.values.any(
              (v) => v.toLowerCase().contains(_search.toLowerCase()),
            ),
          )
          .toList();
    }
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
    setState(() {
      _filteredProcesses = filtered;
    });
  }

  void _onSearchChanged() {
    setState(() {
      _search = _searchController.text;
      _applyFilterSort();
    });
  }

  void _onKill(Map<String, String> process) async {
    final pid = process['PID'];
    if (pid == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kill Process'),
        content: Text('Are you sure you want to kill PID $pid?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kill'),
          ),
        ],
      ),
    );
    if (confirmed == true && widget.sshClient != null) {
      try {
        await widget.sshClient!.execute('kill -9 $pid');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Killed PID $pid')));
        _fetchProcesses();
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to kill PID $pid: $e')));
      }
    }
  }

  void _toggleAutoRefresh() {
    setState(() {
      _autoRefresh = !_autoRefresh;
    });
    if (_autoRefresh) {
      _startAutoRefresh();
    }
  }

  void _startAutoRefresh() async {
    while (_autoRefresh && mounted) {
      await _fetchProcesses();
      await Future.delayed(const Duration(seconds: 5));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading || _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.error != null) {
      return Center(child: Text('SSH Error: ${widget.error}'));
    }
    if (_error != null) {
      return Center(child: Text('Error: $_error'));
    }
    if (_filteredProcesses != null) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search processes...',
                      prefixIcon: const Icon(Icons.search),
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
                  icon: Icon(_autoRefresh ? Icons.pause : Icons.play_arrow),
                  tooltip: _autoRefresh
                      ? 'Pause Auto-Refresh'
                      : 'Start Auto-Refresh',
                  onPressed: _toggleAutoRefresh,
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh',
                  onPressed: _fetchProcesses,
                ),
              ],
            ),
          ),
          Expanded(
            child: _filteredProcesses!.isEmpty
                ? const Center(child: Text('No processes found.'))
                : ListView.separated(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    itemCount: _filteredProcesses!.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, idx) {
                      final proc = _filteredProcesses![idx];
                      return Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 2,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          title: Row(
                            children: [
                              Expanded(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Text(
                                    proc['COMMAND'] ?? '',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'PID: ${proc['PID'] ?? ''}',
                                  style: const TextStyle(
                                      fontSize: 13, color: Colors.blue),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Row(
                              children: [
                                ProcessInfoChip(
                                    label: 'CPU', value: proc['%CPU']),
                                const SizedBox(width: 8),
                                ProcessInfoChip(
                                    label: 'MEM', value: proc['%MEM']),
                                const SizedBox(width: 8),
                                ProcessInfoChip(
                                    label: 'USER', value: proc['USER']),
                                const SizedBox(width: 8),
                                ProcessInfoChip(
                                    label: 'STAT', value: proc['STAT']),
                              ],
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.cancel, color: Colors.red),
                            tooltip: 'Kill',
                            onPressed: () => _onKill(proc),
                          ),
                          onTap: () {
                            showModalBottomSheet(
                              context: context,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(18)),
                              ),
                              builder: (ctx) => ProcessDetailSheet(proc: proc),
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      );
    }
    if (widget.sshClient == null) {
      return const Center(child: Text('Waiting for SSH connection...'));
    }
    return const Center(child: Text('No processes loaded.'));
  }
}
