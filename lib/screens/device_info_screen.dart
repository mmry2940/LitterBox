import 'package:flutter/material.dart';
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

class _DeviceInfoScreenState extends State<DeviceInfoScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.sshClient != null) {
      _fetchInfo();
    }
  }

  String? _info;
  String? _error;
  bool _loading = false;

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
    try {
      final session = await widget.sshClient!.execute(
        'uname -a && lscpu && free -h',
      );
      final output =
          await session.stdout.cast<List<int>>().transform(utf8.decoder).join();
      setState(() {
        _info = output;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
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
    if (_info != null) {
      // Split info into sections: kernel, lscpu, free -h
      final lines = _info!.split('\n');
      String kernel = '';
      List<List<String>> cpuRows = [];
      List<List<String>> memRows = [];
      int lscpuStart = -1, lscpuEnd = -1, freeStart = -1;
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].contains('Linux') && kernel.isEmpty) {
          kernel = lines[i];
        }
        if (lines[i].trim().startsWith('Architecture:')) {
          lscpuStart = i;
        }
        if (lscpuStart != -1 && lscpuEnd == -1 && lines[i].trim().isEmpty) {
          lscpuEnd = i;
        }
        if (lines[i].trim().startsWith('total') && freeStart == -1) {
          freeStart = i - 1;
        }
      }
      if (lscpuStart != -1 && lscpuEnd == -1) lscpuEnd = lines.length;
      // Parse CPU info into table rows
      if (lscpuStart != -1 && lscpuEnd != -1) {
        for (var line in lines.sublist(lscpuStart, lscpuEnd)) {
          final parts = line.split(':');
          if (parts.length == 2) {
            cpuRows.add([parts[0].trim(), parts[1].trim()]);
          } else if (parts.length == 1 && parts[0].trim().isNotEmpty) {
            cpuRows.add([parts[0].trim(), '']);
          }
        }
      }
      // Pad all CPU rows to 2 columns
      for (var i = 0; i < cpuRows.length; i++) {
        while (cpuRows[i].length < 2) {
          cpuRows[i].add('');
        }
      }
      // Parse Memory info into table rows
      int memMaxCols = 0;
      if (freeStart != -1) {
        final memLines = lines.sublist(freeStart);
        for (var i = 0; i < memLines.length; i++) {
          final row = memLines[i]
              .split(RegExp(r'\\s+'))
              .where((e) => e.isNotEmpty)
              .toList();
          if (row.isNotEmpty) {
            memRows.add(row);
            if (row.length > memMaxCols) memMaxCols = row.length;
          }
        }
        // Pad all memory rows to the same length
        for (var i = 0; i < memRows.length; i++) {
          while (memRows[i].length < memMaxCols) {
            memRows[i].add('');
          }
        }
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (kernel.isNotEmpty)
              Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Kernel',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(kernel,
                          style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ),
              ),
            if (cpuRows.isNotEmpty)
              Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('CPU Info',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Table(
                        columnWidths: const {
                          0: IntrinsicColumnWidth(),
                          1: FlexColumnWidth()
                        },
                        defaultVerticalAlignment:
                            TableCellVerticalAlignment.middle,
                        children: cpuRows
                            .map((row) => TableRow(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 4),
                                      child: Text(row[0],
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w500)),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 4),
                                      child: Text(row[1]),
                                    ),
                                  ],
                                ))
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ),
            if (memRows.isNotEmpty)
              Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Memory',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Table(
                        defaultVerticalAlignment:
                            TableCellVerticalAlignment.middle,
                        children: memRows
                            .map((row) => TableRow(
                                  children: row
                                      .map((cell) => Padding(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 4, horizontal: 4),
                                            child: Text(cell,
                                                textAlign: TextAlign.center),
                                          ))
                                      .toList(),
                                ))
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    }
    if (widget.sshClient == null) {
      return const Center(child: Text('Waiting for SSH connection...'));
    }
    return const Center(child: Text('No device info loaded.'));
  }
}
