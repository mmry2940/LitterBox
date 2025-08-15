import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

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

  // Advanced operations (may be unsupported by some implementations)
  Future<bool> installApk(String serial, String filePath) async {
    throw UnimplementedError();
  }

  Future<bool> pushFile(
      String serial, String localPath, String remotePath) async {
    throw UnimplementedError();
  }

  Future<bool> pullFile(
      String serial, String remotePath, String localPath) async {
    throw UnimplementedError();
  }

  Future<bool> forward(String serial, int localPort, String remoteSpec) async {
    throw UnimplementedError();
  }

  Future<bool> removeForward(String serial, int localPort) async {
    throw UnimplementedError();
  }

  Stream<String>? streamLogcat(String serial,
      {List<String> filters = const []}) {
    return null; // optional
  }

  Future<void> stopLogcat(String serial) async {}

  // Advanced helpers (optional implementations)
  Future<Map<String, String>> getProps(String serial) async => {};
  Future<bool> uninstallApk(String serial, String packageName) async => false;
  Future<bool> reboot(String serial, {String? mode}) async => false;
  Future<List<String>> listForwards(String serial) async => [];
  Future<bool> pair(String host, int pairingPort, String code) async => false;
  Future<Uint8List?> screencap(String serial) async => null;
  Future<String> execOut(String serial, List<String> args) async => '';
  // Progress streaming fallbacks
  Stream<TransferProgress> pushFileWithProgress(
          String serial, String localPath, String remotePath) =>
      const Stream.empty();
  Stream<TransferProgress> pullFileWithProgress(
          String serial, String remotePath, String localPath) =>
      const Stream.empty();
}

/// Lightweight in-process fallback backend (mock / minimal internal ADB)
/// Provides simulated devices and basic command responses without requiring
/// an external adb binary. Useful for environments where adb isn't installed
/// or for offline demo/testing. Not a full protocol implementation.
class InternalAdbBackend implements ADBBackend {
  bool _initialized = false;
  final List<ADBBackendDevice> _devices = [
    ADBBackendDevice('internal-emulator-5554', 'device'),
    ADBBackendDevice('internal-virtual-001', 'device'),
  ];
  final Map<String, StreamController<String>> _logcatControllers = {};

  @override
  Future<void> init() async {
    // Simulate async init delay
    if (_initialized) return;
    await Future.delayed(const Duration(milliseconds: 150));
    _initialized = true;
  }

  @override
  Future<List<ADBBackendDevice>> listDevices() async {
    if (!_initialized) await init();
    return List.unmodifiable(_devices);
  }

  @override
  Future<String> shell(String serial, String command) async {
    if (!_initialized) await init();
    // Provide canned responses similar to server mock
    final now = DateTime.now();
    switch (command.trim()) {
      case 'getprop ro.build.version.release':
        return '15';
      case 'getprop ro.product.model':
        return 'Internal Virtual Device';
      case 'whoami':
        return 'shell';
      case 'pwd':
        return '/data/local/tmp';
      case 'date':
        return now.toIso8601String();
      case 'ls':
        return 'cache\ndata\ndownload\nsdcard';
      default:
        return 'Executed: $command';
    }
  }

  @override
  Future<bool> connect(String host, int port) async {
    // Simulate success; create a pseudo network device entry
    final serial = '$host:$port';
    if (_devices.indexWhere((d) => d.serial == serial) == -1) {
      _devices.add(ADBBackendDevice(serial, 'device'));
    }
    return true;
  }

  @override
  Future<bool> disconnect(String host, int port) async {
    final serial = '$host:$port';
    _devices.removeWhere((d) => d.serial == serial);
    return true;
  }

  @override
  Future<void> dispose() async {
    for (final c in _logcatControllers.values) {
      await c.close();
    }
    _logcatControllers.clear();
  }

  // Simple stubs for file transfer and port forwarding (no-ops)
  @override
  Future<bool> installApk(String serial, String filePath) async => false;
  @override
  Future<bool> pushFile(
          String serial, String localPath, String remotePath) async =>
      false;
  @override
  Future<bool> pullFile(
          String serial, String remotePath, String localPath) async =>
      false;
  @override
  Future<bool> forward(String serial, int localPort, String remoteSpec) async =>
      false;
  @override
  Future<bool> removeForward(String serial, int localPort) async => false;
  @override
  Future<bool> uninstallApk(String serial, String packageName) async => false;
  @override
  Future<bool> reboot(String serial, {String? mode}) async => false;
  @override
  Future<List<String>> listForwards(String serial) async => const [];
  @override
  Future<bool> pair(String host, int pairingPort, String code) async => false;
  @override
  Stream<TransferProgress> pushFileWithProgress(
          String serial, String localPath, String remotePath) =>
      const Stream.empty();
  @override
  Stream<TransferProgress> pullFileWithProgress(
          String serial, String remotePath, String localPath) =>
      const Stream.empty();

  // Optional: minimal logcat streamer producing synthetic lines
  @override
  Stream<String>? streamLogcat(String serial,
      {List<String> filters = const []}) {
    final existing = _logcatControllers[serial];
    if (existing != null) return existing.stream;
    final ctl = StreamController<String>.broadcast();
    _logcatControllers[serial] = ctl;
    Timer.periodic(const Duration(milliseconds: 750), (t) {
      if (ctl.isClosed) {
        t.cancel();
        return;
      }
      final line =
          '${DateTime.now().toIso8601String()} I/MockTag($serial): synthetic log entry';
      ctl.add(line);
    });
    return ctl.stream;
  }

  @override
  Future<void> stopLogcat(String serial) async {
    final ctl = _logcatControllers.remove(serial);
    await ctl?.close();
  }

  // Provide simple stubs for optional advanced operations
  @override
  Future<Map<String, String>> getProps(String serial) async => {
        'ro.build.version.release': '15',
        'ro.product.model': 'Internal Virtual Device',
        'ro.product.manufacturer': 'Internal',
      };
  @override
  Future<Uint8List?> screencap(String serial) async => null;
  @override
  Future<String> execOut(String serial, List<String> args) async =>
      shell(serial, args.join(' '));
}

class ADBBackendDevice {
  final String serial;
  final String state;
  ADBBackendDevice(this.serial, this.state);
}

class TransferProgress {
  final String operation; // push / pull
  final String localPath;
  final String remotePath;
  final int bytesTransferred;
  final int? totalBytes;
  final bool done;
  const TransferProgress({
    required this.operation,
    required this.localPath,
    required this.remotePath,
    required this.bytesTransferred,
    this.totalBytes,
    this.done = false,
  });
  double? get percent => (totalBytes != null && totalBytes! > 0)
      ? bytesTransferred / totalBytes!
      : null;
}

/// Implementation using the published `adb` package which shells out to the
/// installed adb binary. Assumes adb binary is available in PATH on host.
class ExternalAdbBackend implements ADBBackend {
  bool _initialized = false;
  final Map<String, Process> _logcatProcesses = {};
  final Map<String, StreamController<String>> _logcatControllers = {};

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
    for (final line in lines.skip(1)) {
      // skip header
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

  // Existing simple dispose removed; full implementation provided later

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

  @override
  Future<bool> installApk(String serial, String filePath) async {
    final res = await _run(['-s', serial, 'install', '-r', filePath]);
    if (res.exitCode != 0) return false;
    final out = (res.stdout as String).toLowerCase();
    return out.contains('success');
  }

  @override
  Future<bool> pushFile(
      String serial, String localPath, String remotePath) async {
    final res = await _run(['-s', serial, 'push', localPath, remotePath]);
    return res.exitCode == 0;
  }

  @override
  Stream<TransferProgress> pushFileWithProgress(
      String serial, String localPath, String remotePath) async* {
    final file = File(localPath);
    if (!await file.exists()) {
      yield TransferProgress(
          operation: 'push',
          localPath: localPath,
          remotePath: remotePath,
          bytesTransferred: 0,
          totalBytes: 0,
          done: true);
      return;
    }
    final total = await file.length();
    final proc = await Process.start(
        'adb', ['-s', serial, 'push', localPath, remotePath],
        runInShell: true);
    int lastBytes = 0;
    void handleLine(String line) {
      final match = RegExp(r'(\d+) bytes').firstMatch(line);
      if (match != null) {
        final b = int.tryParse(match.group(1)!);
        if (b != null && b >= lastBytes) {
          lastBytes = b > total ? total : b;
        }
      }
    }

    final stdoutLines = proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(handleLine);
    final stderrLines = proc.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(handleLine);
    while (true) {
      int? exit;
      try {
        exit = await proc.exitCode.timeout(const Duration(milliseconds: 150));
      } on TimeoutException {
        exit = null;
      }
      final done = exit is int;
      yield TransferProgress(
          operation: 'push',
          localPath: localPath,
          remotePath: remotePath,
          bytesTransferred: lastBytes,
          totalBytes: total,
          done: done);
      if (done) break;
      await Future.delayed(const Duration(milliseconds: 250));
    }
    await stdoutLines.cancel();
    await stderrLines.cancel();
  }

  @override
  Future<bool> pullFile(
      String serial, String remotePath, String localPath) async {
    final res = await _run(['-s', serial, 'pull', remotePath, localPath]);
    return res.exitCode == 0;
  }

  @override
  Stream<TransferProgress> pullFileWithProgress(
      String serial, String remotePath, String localPath) async* {
    final proc = await Process.start(
        'adb', ['-s', serial, 'pull', remotePath, localPath],
        runInShell: true);
    int transferred = 0;
    void handleLine(String line) {
      final match = RegExp(r'(\d+) bytes').firstMatch(line);
      if (match != null) {
        final b = int.tryParse(match.group(1)!);
        if (b != null && b >= transferred) transferred = b;
      }
    }

    final stdoutLines = proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(handleLine);
    final stderrLines = proc.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(handleLine);
    while (true) {
      int? exit;
      try {
        exit = await proc.exitCode.timeout(const Duration(milliseconds: 150));
      } on TimeoutException {
        exit = null;
      }
      final done = exit is int;
      yield TransferProgress(
          operation: 'pull',
          localPath: localPath,
          remotePath: remotePath,
          bytesTransferred: transferred,
          totalBytes: null,
          done: done);
      if (done) break;
      await Future.delayed(const Duration(milliseconds: 250));
    }
    await stdoutLines.cancel();
    await stderrLines.cancel();
  }

  @override
  Future<bool> forward(String serial, int localPort, String remoteSpec) async {
    final res =
        await _run(['-s', serial, 'forward', 'tcp:$localPort', remoteSpec]);
    return res.exitCode == 0;
  }

  @override
  Future<bool> removeForward(String serial, int localPort) async {
    final res =
        await _run(['-s', serial, 'forward', '--remove', 'tcp:$localPort']);
    return res.exitCode == 0;
  }

  @override
  Stream<String>? streamLogcat(String serial,
      {List<String> filters = const []}) {
    if (_logcatProcesses.containsKey(serial)) {
      return _logcatControllers[serial]!.stream;
    }
    final controller = StreamController<String>.broadcast();
    _logcatControllers[serial] = controller;
    // Start process async
    (() async {
      try {
        final args = ['-s', serial, 'logcat', '-v', 'time', ...filters];
        final proc = await Process.start('adb', args, runInShell: true);
        _logcatProcesses[serial] = proc;
        proc.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
          (line) => controller.add(line),
          onError: controller.addError,
          onDone: () {
            controller.close();
            _logcatProcesses.remove(serial);
            _logcatControllers.remove(serial);
          },
        );
        proc.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
              (line) => controller.add(line),
            );
      } catch (e) {
        controller.add('LOGCAT ERROR: $e');
        await controller.close();
        _logcatControllers.remove(serial);
      }
    })();
    return controller.stream;
  }

  @override
  Future<void> stopLogcat(String serial) async {
    final proc = _logcatProcesses.remove(serial);
    if (proc != null) {
      try {
        proc.kill(ProcessSignal.sigint);
      } catch (_) {}
    }
    final ctl = _logcatControllers.remove(serial);
    await ctl?.close();
  }

  @override
  Future<void> dispose() async {
    for (final s in _logcatProcesses.values) {
      try {
        s.kill(ProcessSignal.sigint);
      } catch (_) {}
    }
    for (final c in _logcatControllers.values) {
      await c.close();
    }
    _logcatProcesses.clear();
    _logcatControllers.clear();
  }

  // -------- Newly added advanced operations --------
  @override
  Future<Map<String, String>> getProps(String serial) async {
    final out = await shell(serial, 'getprop');
    final map = <String, String>{};
    final regex = RegExp(r'^\[(.+?)\]: \[(.*?)\]');
    for (final line in out.split('\n')) {
      final m = regex.firstMatch(line.trim());
      if (m != null) {
        map[m.group(1)!] = m.group(2)!;
      }
    }
    return map;
  }

  @override
  Future<bool> uninstallApk(String serial, String packageName) async {
    final res = await _run(['-s', serial, 'uninstall', packageName]);
    if (res.exitCode != 0) return false;
    final out = (res.stdout as String).toLowerCase();
    return out.contains('success');
  }

  @override
  Future<bool> reboot(String serial, {String? mode}) async {
    final args = ['-s', serial, 'reboot'];
    if (mode != null && mode.isNotEmpty) args.add(mode);
    final res = await _run(args);
    return res.exitCode == 0;
  }

  @override
  Future<List<String>> listForwards(String serial) async {
    final res = await _run(['-s', serial, 'forward', '--list']);
    if (res.exitCode != 0) return [];
    final lines = (res.stdout as String)
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    return lines.where((l) => l.startsWith(serial)).toList();
  }

  @override
  Future<bool> pair(String host, int pairingPort, String code) async {
    final target = '$host:$pairingPort';
    final res = await _run(['pair', target, code]);
    if (res.exitCode != 0) return false;
    final out = (res.stdout as String).toLowerCase();
    return out.contains('success') || out.contains('paired');
  }

  @override
  Future<Uint8List?> screencap(String serial) async {
    try {
      final result = await Process.run(
          'adb', ['-s', serial, 'exec-out', 'screencap', '-p'],
          stdoutEncoding: null);
      if (result.exitCode != 0) return null;
      final data = result.stdout;
      if (data is List<int>) {
        return Uint8List.fromList(data);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String> execOut(String serial, List<String> args) async {
    final res = await _run(['-s', serial, 'exec-out', ...args]);
    if (res.exitCode != 0) return (res.stderr as String).trim();
    return (res.stdout as String).trim();
  }
}
