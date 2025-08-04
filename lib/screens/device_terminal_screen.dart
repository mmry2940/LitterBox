import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dartssh2/dartssh2.dart';
import 'dart:async';
import 'dart:convert';
import 'package:xterm/xterm.dart';

class DeviceTerminalScreen extends StatefulWidget {
  final SSHClient? sshClient;
  final String? error;
  final bool loading;

  const DeviceTerminalScreen({
    super.key,
    this.sshClient,
    this.error,
    this.loading = false,
  });

  @override
  State<DeviceTerminalScreen> createState() => _DeviceTerminalScreenState();
}

class _DeviceTerminalScreenState extends State<DeviceTerminalScreen> {
  late Terminal _terminal;
  SSHSession? _shellSession;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal();
    _startShell();
  }

  @override
  void dispose() {
    _shellSession?.close();
    super.dispose();
  }

  Future<void> _startShell() async {
    if (widget.sshClient == null) return;
    try {
      final session = await widget.sshClient!.shell();
      _shellSession = session;

      session.stdout.listen((data) {
        _terminal.write(String.fromCharCodes(data));
      });

      session.stderr.listen((data) {
        _terminal.write(String.fromCharCodes(data));
      });

      _terminal.onInput = (input) {
        session.write(utf8.encode(input));
      };
    } catch (e) {
      _terminal.write('Shell error: $e\n');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.error != null) {
      return Center(child: Text('SSH Error: ${widget.error}'));
    }
    if (widget.sshClient == null) {
      return const Center(child: Text('Waiting for SSH connection...'));
    }

    return TerminalView(_terminal);
  }
}
