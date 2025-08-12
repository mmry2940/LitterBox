import 'dart:async';
import 'dart:isolate';
import 'dart:io';

class _ScanConfig {
  final String subnet;
  final int firstHostId;
  final int lastHostId;
  final SendPort sendPort;
  _ScanConfig(this.subnet, this.firstHostId, this.lastHostId, this.sendPort);
}

/// Spawn an isolate that attempts lightweight TCP connects to detect live hosts.
/// Emits discovered host IPs and progress events as 'progress:<percent>'.
Stream<String> isolateSubnetScan(
  String subnet, {
  int firstHostId = 1,
  int lastHostId = 254,
  Duration perHostTimeout = const Duration(milliseconds: 120),
}) {
  final controller = StreamController<String>();
  Isolate? iso;
  final receivePort = ReceivePort();
  receivePort.listen((message) {
    if (message is String) {
      if (message == '_scan_done_') {
        controller.close();
        receivePort.close();
        iso?.kill(priority: Isolate.immediate);
      } else {
        controller.add(message);
      }
    }
  });
  Isolate.spawn<_ScanConfig>(_scanEntry,
          _ScanConfig(subnet, firstHostId, lastHostId, receivePort.sendPort))
      .then((value) => iso = value)
      .catchError((e, st) {
    controller.addError(e, st);
    controller.close();
    receivePort.close();
    throw e; // propagate
  });
  controller.onCancel = () {
    try {
      receivePort.close();
      iso?.kill(priority: Isolate.immediate);
    } catch (_) {}
  };
  return controller.stream;
}

Future<bool> _quickConnect(String ip) async {
  final ports = [22, 80, 443];
  for (final port in ports) {
    try {
      final socket = await Socket.connect(ip, port,
          timeout: const Duration(milliseconds: 80));
      socket.destroy();
      return true;
    } catch (_) {}
  }
  return false;
}

void _scanEntry(_ScanConfig cfg) async {
  final send = cfg.sendPort;
  final total = (cfg.lastHostId - cfg.firstHostId + 1).clamp(0, 10000);
  int processed = 0;
  for (int host = cfg.firstHostId; host <= cfg.lastHostId; host++) {
    final ip = '${cfg.subnet}.$host';
    try {
      final alive = await _quickConnect(ip);
      if (alive) {
        send.send(ip);
      }
    } catch (_) {}
    processed++;
    if (processed % 8 == 0 || processed == total) {
      final pct = (processed / total * 100).clamp(0, 100).toStringAsFixed(1);
      send.send('progress:$pct');
    }
  }
  send.send('_scan_done_');
}
