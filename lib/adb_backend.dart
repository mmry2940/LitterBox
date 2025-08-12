import 'dart:async';
import 'dart:io';

/// Abstraction so we can swap between internal mock/server and real adb wrapper
abstract class ADBBackend {
  Future<void> init();
  Future<List<ADBBackendDevice>> listDevices();
  Future<String> shell(String serial, String command);
  /// Connect to a device over TCP (adb connect host:port)
  Future<bool> connect(String host, int port);
  /// Disconnect a previously connected device (adb disconnect host:port)
  Future<bool> disconnect(String host, int port);
  Future<void> dispose();
}

class ADBBackendDevice {
  final String serial;
  final String state;
  ADBBackendDevice(this.serial, this.state);
}

/// Implementation using the published `adb` package which shells out to the
/// installed adb binary. Assumes adb binary is available in PATH on host.
class ExternalAdbBackend implements ADBBackend {
  bool _initialized = false;

  Future<ProcessResult> _run(List<String> args) async {
    return await Process.run('adb', args);
  }

  @override
  Future<void> init() async {
    if (_initialized) return;
    final res = await _run(['version']);
    if (res.exitCode != 0) {
      throw Exception('adb not available: ${res.stderr}');
    }
    _initialized = true;
  }

  @override
  Future<List<ADBBackendDevice>> listDevices() async {
    final res = await _run(['devices']);
    if (res.exitCode != 0) {
      throw Exception('adb devices failed: ${res.stderr}');
    }
    final lines = (res.stdout as String)
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final devices = <ADBBackendDevice>[];
    for (final line in lines.skip(1)) { // skip header
      if (line.contains('\t')) {
        final parts = line.split('\t');
        if (parts.length >= 2) {
          devices.add(ADBBackendDevice(parts[0], parts[1]));
        }
      }
    }
    return devices;
  }

  @override
  Future<String> shell(String serial, String command) async {
    final args = ['-s', serial, 'shell'];
    if (command.isNotEmpty) {
      args.addAll(command.split(' '));
    }
    final res = await _run(args);
    if (res.exitCode != 0) {
      return (res.stderr as String).trim();
    }
    return (res.stdout as String).trim();
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<bool> connect(String host, int port) async {
    final target = '$host:$port';
    final res = await _run(['connect', target]);
    if (res.exitCode != 0) return false;
    final out = (res.stdout as String).toLowerCase();
    if (out.contains('connected to') || out.contains('already connected')) {
      return true;
    }
    return false;
  }

  @override
  Future<bool> disconnect(String host, int port) async {
    final target = '$host:$port';
    final res = await _run(['disconnect', target]);
    if (res.exitCode != 0) return false;
    final out = (res.stdout as String).toLowerCase();
    if (out.contains('disconnected') || out.contains('no such device')) {
      return true; // treat no-such-device as already disconnected
    }
    return false;
  }
}
