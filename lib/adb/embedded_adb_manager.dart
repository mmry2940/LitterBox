import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Manages extraction and execution of embedded adb / fastboot binaries.
/// Binaries should be placed under assets/adb/bin/<abi>/{adb,fastboot}
class EmbeddedAdbManager {
  static final EmbeddedAdbManager instance = EmbeddedAdbManager._();
  EmbeddedAdbManager._();

  String? _adbPath;
  String? _fastbootPath;
  bool _extracted = false;

  Future<String?> get adbPath async {
    if (!_extracted) await _extractIfNeeded();
    return _adbPath;
  }

  Future<String?> get fastbootPath async {
    if (!_extracted) await _extractIfNeeded();
    return _fastbootPath;
  }

  Future<void> _extractIfNeeded() async {
    if (_extracted) return;
    final abi = await _deviceAbi();
    final supportDir = await getApplicationSupportDirectory();
    final binDir = Directory('${supportDir.path}/adb_bin/$abi');
    if (!(await binDir.exists())) await binDir.create(recursive: true);

    Future<String> writeBinary(String name) async {
      final assetPath = 'assets/adb/bin/$abi/$name';
      try {
        final data = await rootBundle.load(assetPath);
        final file = File('${binDir.path}/$name');
        await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
        await _chmodExecutable(file);
        return file.path;
      } catch (e) {
        // Asset missing: caller can fallback to system adb.
        return '';
      }
    }

    _adbPath = await writeBinary('adb');
    _fastbootPath = await writeBinary('fastboot');
    _extracted = true;
  }

  Future<String> _deviceAbi() async {
    const channel = MethodChannel('embedded_adb/device');
    try {
      final abi = await channel.invokeMethod<String>('primaryAbi');
      return abi ?? _guessAbiFallback();
    } catch (_) {
      return _guessAbiFallback();
    }
  }

  String _guessAbiFallback() {
    if (Platform.isAndroid) {
      final arch = Platform.version.toLowerCase();
      if (arch.contains('arm64')) return 'arm64-v8a';
      if (arch.contains('arm')) return 'armeabi-v7a';
      if (arch.contains('x86_64')) return 'x86_64';
    }
    return 'arm64-v8a';
  }

  Future<void> _chmodExecutable(File f) async {
    if (!Platform.isAndroid && !Platform.isLinux && !Platform.isMacOS) return;
    try {
      await Process.run('chmod', ['755', f.path]);
    } catch (_) {}
  }

  Future<Process?> startAdbServer() async {
    final path = await adbPath;
    if (path == null || path.isEmpty) return null;
    return Process.start(path, ['start-server']);
  }

  Future<Process?> stopAdbServer() async {
    final path = await adbPath;
    if (path == null || path.isEmpty) return null;
    return Process.start(path, ['kill-server']);
  }

  Future<Process?> adbCommand(List<String> args) async {
    final path = await adbPath;
    if (path == null || path.isEmpty) return null;
    return Process.start(path, args);
  }

  Future<Process?> fastbootCommand(List<String> args) async {
    final path = await fastbootPath;
    if (path == null || path.isEmpty) return null;
    return Process.start(path, args);
  }
}
