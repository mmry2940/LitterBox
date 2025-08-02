import 'package:flutter/material.dart';
import 'package:dartssh2/dartssh2.dart';
import 'dart:convert';

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
      final output = await session.stdout
          .cast<List<int>>()
          .transform(utf8.decoder)
          .join();
      final lines = output
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();
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

  void _onSort(String column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAsc = !_sortAsc;
      } else {
        _sortColumn = column;
        _sortAsc = true;
      }
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
      return Center(child: Text('SSH Error: \\${widget.error}'));
    }
    if (_error != null) {
      return Center(child: Text('Error: \\$_error'));
    }
    if (_filteredProcesses != null) {
      final columns = [
        'USER',
        'PID',
        '%CPU',
        '%MEM',
        'VSZ',
        'RSS',
        'STAT',
        'TIME',
        'COMMAND',
      ];
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'Search processes...',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (_) => _onSearchChanged(),
                  ),
                ),
                IconButton(
                  icon: Icon(_autoRefresh ? Icons.pause : Icons.refresh),
                  tooltip: _autoRefresh ? 'Pause Auto-Refresh' : 'Auto-Refresh',
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
            child: SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  sortColumnIndex: columns.indexOf(_sortColumn),
                  sortAscending: _sortAsc,
                  columns: [
                    ...columns.map(
                      (col) => DataColumn(
                        label: Text(col),
                        onSort: (i, _) => _onSort(col),
                      ),
                    ),
                    const DataColumn(label: Text('Actions')),
                  ],
                  rows: _filteredProcesses!
                      .map(
                        (proc) => DataRow(
                          cells: [
                            ...columns.map(
                              (col) => DataCell(Text(proc[col] ?? '')),
                            ),
                            DataCell(
                              IconButton(
                                icon: const Icon(
                                  Icons.cancel,
                                  color: Colors.red,
                                ),
                                tooltip: 'Kill',
                                onPressed: () => _onKill(proc),
                              ),
                            ),
                          ],
                        ),
                      )
                      .toList(),
                ),
              ),
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
