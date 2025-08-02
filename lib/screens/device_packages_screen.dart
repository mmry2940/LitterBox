import 'package:flutter/material.dart';
import 'package:dartssh2/dartssh2.dart';
import 'dart:convert';

class DevicePackagesScreen extends StatefulWidget {
  final SSHClient? sshClient;
  final String? error;
  final bool loading;
  const DevicePackagesScreen({
    super.key,
    this.sshClient,
    this.error,
    this.loading = false,
  });

  @override
  State<DevicePackagesScreen> createState() => _DevicePackagesScreenState();
}

class _DevicePackagesScreenState extends State<DevicePackagesScreen> {
  List<Map<String, String>>? _packages;
  List<Map<String, String>>? _filteredPackages;
  String? _error;
  bool _loading = false;
  String _search = '';
  String _sortColumn = 'Name';
  bool _sortAsc = true;
  late final TextEditingController _searchController;
  final Set<int> _selectedRows = {};

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    if (widget.sshClient != null) {
      _fetchPackages();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(DevicePackagesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.key != oldWidget.key && widget.sshClient != null) {
      _fetchPackages();
    }
  }

  Future<void> _fetchPackages() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = await widget.sshClient!.execute('dpkg -l');
      final output = await session.stdout
          .cast<List<int>>()
          .transform(utf8.decoder)
          .join();
      final lines = output
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();
      // dpkg -l output: header lines start with '||/ Name', skip first lines
      int headerIdx = lines.indexWhere((l) => l.startsWith('||/'));
      if (headerIdx == -1 || headerIdx + 1 >= lines.length) {
        throw Exception('No package data');
      }
      final headerLine = lines[headerIdx];
      final header = headerLine
          .replaceAll('|', '')
          .split(RegExp(r'\s+'))
          .where((h) => h.isNotEmpty)
          .toList();
      final data = lines
          .sublist(headerIdx + 1)
          .map((line) {
            if (line.length < 3 ||
                !RegExp(
                  r'^(ii|rc|un|hi|pn|pi|iU|iF|iH|iW|iC|iR|iP|iB|iA|iS|iT|iD|iE|iG|iL|iM|iN|iO|iQ|iV|iX|iY|iZ|iJ|iK|iL|iM|iN|iO|iP|iQ|iR|iS|iT|iU|iV|iW|iX|iY|iZ)',
                ).hasMatch(line.substring(0, 2))) {
              return null;
            }
            // Status, Name, Version, Arch, Description
            final cols = line.split(RegExp(r'\s+'));
            if (cols.length < 5) return null;
            return <String, String>{
              'Status': cols[0],
              'Name': cols[1],
              'Version': cols[2],
              'Arch': cols[3],
              'Description': cols.sublist(4).join(' '),
            };
          })
          .whereType<Map<String, String>>()
          .toList();
      setState(() {
        _packages = data;
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
    List<Map<String, String>> filtered = _packages ?? [];
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
      return _sortAsc ? aVal.compareTo(bVal) : bVal.compareTo(aVal);
    });
    setState(() {
      _filteredPackages = filtered;
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
      _selectedRows.clear();
    });
  }

  void _onUninstallSelected() async {
    if (_filteredPackages == null || _selectedRows.isEmpty) return;
    final pkgs = _selectedRows.map((i) => _filteredPackages![i]).toList();
    final names = pkgs.map((p) => p['Name']).whereType<String>().toList();
    String? sudoPassword;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final pwController = TextEditingController();
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Uninstall Packages'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Are you sure you want to uninstall the following packages?',
                ),
                const SizedBox(height: 8),
                ...names.map((n) => Text(n)),
                const SizedBox(height: 12),
                TextField(
                  controller: pwController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Sudo password (leave blank if not needed)',
                  ),
                  onChanged: (v) => sudoPassword = v,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  sudoPassword = pwController.text;
                  Navigator.pop(ctx, true);
                },
                child: const Text('Uninstall'),
              ),
            ],
          ),
        );
      },
    );
    if (confirmed == true && widget.sshClient != null) {
      try {
        String command;
        final joined = names
            .map((n) => "'${n.replaceAll("'", "'\\''")}'")
            .join(' ');
        if (sudoPassword != null && sudoPassword!.isNotEmpty) {
          command =
              "echo '${sudoPassword!.replaceAll("'", "'\\''")}' | sudo -S apt-get remove -y $joined";
        } else {
          command = 'sudo apt-get remove -y $joined';
        }
        final session = await widget.sshClient!.execute(command);
        final output = await session.stdout
            .cast<List<int>>()
            .transform(utf8.decoder)
            .join();
        final error = await session.stderr
            .cast<List<int>>()
            .transform(utf8.decoder)
            .join();
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Uninstall Result'),
            content: SingleChildScrollView(
              child: Text(('$output\n$error').trim()),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        _selectedRows.clear();
        _fetchPackages();
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to uninstall: $e')));
      }
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
    if (_filteredPackages != null) {
      final columns = ['Status', 'Name'];
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search packages...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => _onSearchChanged(),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  sortColumnIndex: columns.contains(_sortColumn)
                      ? columns.indexOf(_sortColumn)
                      : null,
                  sortAscending: _sortAsc,
                  columns: [
                    ...columns.map(
                      (col) => DataColumn(
                        label: Text(col),
                        onSort: (i, _) => _onSort(col),
                      ),
                    ),
                  ],
                  rows: List.generate(_filteredPackages!.length, (i) {
                    final pkg = _filteredPackages![i];
                    final selected = _selectedRows.contains(i);
                    return DataRow(
                      selected: selected,
                      color: WidgetStateProperty.resolveWith<Color?>((
                        states,
                      ) {
                        if (selected) {
                          return Theme.of(
                            context,
                          ).colorScheme.primary.withOpacity(0.2);
                        }
                        return null;
                      }),
                      onSelectChanged: (val) {
                        setState(() {
                          if (val == true) {
                            _selectedRows.add(i);
                          } else {
                            _selectedRows.remove(i);
                          }
                        });
                      },
                      cells: [
                        ...columns.map((col) => DataCell(Text(pkg[col] ?? ''))),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ),
          if (_selectedRows.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              child: Row(
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.delete),
                    label: Text('Uninstall (${_selectedRows.length})'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    onPressed: _onUninstallSelected,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _selectedRows.map((i) {
                          final pkg = _filteredPackages![i];
                          return Padding(
                            padding: const EdgeInsets.only(right: 24.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  pkg['Name'] ?? '',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text('Version: ${pkg['Version'] ?? ''}'),
                                Text('Arch: ${pkg['Arch'] ?? ''}'),
                                Text(
                                  'Description: ${pkg['Description'] ?? ''}',
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }
    if (widget.sshClient == null) {
      return const Center(child: Text('Waiting for SSH connection...'));
    }
    return const Center(child: Text('No packages loaded.'));
  }
}
