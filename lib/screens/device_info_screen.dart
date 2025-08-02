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
      final output = await session.stdout
          .cast<List<int>>()
          .transform(utf8.decoder)
          .join();
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
      String cpu = '';
      String mem = '';
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
      if (lscpuStart != -1 && lscpuEnd != -1) {
        cpu = lines.sublist(lscpuStart, lscpuEnd).join('\n');
      }
      if (freeStart != -1) {
        mem = lines.sublist(freeStart).join('\n');
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (kernel.isNotEmpty)
              Card(
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: Colors.blueGrey.shade100),
                  borderRadius: BorderRadius.circular(8),
                ),
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Kernel',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(kernel),
                    ],
                  ),
                ),
              ),
            if (cpu.isNotEmpty)
              Card(
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: Colors.blueGrey.shade100),
                  borderRadius: BorderRadius.circular(8),
                ),
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'CPU Info',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(cpu),
                    ],
                  ),
                ),
              ),
            if (mem.isNotEmpty)
              Card(
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: Colors.blueGrey.shade100),
                  borderRadius: BorderRadius.circular(8),
                ),
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Memory',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(mem),
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
