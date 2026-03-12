import 'dart:async';
import 'dart:isolate';
import 'dart:io';
import 'dart:collection';

class _ScanConfig {
  final String subnet;
  final int firstHostId;
  final int lastHostId;
  final SendPort sendPort;
  _ScanConfig(this.subnet, this.firstHostId, this.lastHostId, this.sendPort);
}

/// Spawn an isolate that probes hosts concurrently.
/// Emits maps in two formats:
/// - {'type':'progress','percent':'42.5'}
/// - {'type':'host','ip':'x.x.x.x','responseMs':12,'hostName':'foo','openPorts':[22,80]}
Stream<Map<String, dynamic>> isolateSubnetScan(
  String subnet, {
  int firstHostId = 1,
  int lastHostId = 254,
  int maxConcurrentHosts = 64,
}) {
  final controller = StreamController<Map<String, dynamic>>();
  Isolate? iso;
  final receivePort = ReceivePort();
  receivePort.listen((message) {
    if (message is Map) {
      if (message['type'] == '_scan_done_') {
        controller.close();
        receivePort.close();
        iso?.kill(priority: Isolate.immediate);
      } else {
        controller.add(Map<String, dynamic>.from(message));
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

Future<Map<String, dynamic>> _probeHost(String ip) async {
  const candidatePorts = [22, 80, 443, 5555, 3389, 5900];
  const timeout = Duration(milliseconds: 120);
  final stopwatch = Stopwatch()..start();
  final List<int> openPorts = <int>[];
  var responded = false;

  Future<void> checkPort(int port) async {
    try {
      final socket = await Socket.connect(ip, port, timeout: timeout);
      socket.destroy();
      openPorts.add(port);
      responded = true;
    } catch (_) {
      // A host with all service ports closed often responds with
      // "connection refused". Treat that as alive so it still appears in scan.
      final lower = _.toString().toLowerCase();
      if (lower.contains('connection refused') ||
          lower.contains('errno = 111') ||
          lower.contains('errno = 61')) {
        responded = true;
      }
    }
  }

  await Future.wait(candidatePorts.map(checkPort));
  stopwatch.stop();
  if (openPorts.isEmpty && !responded) {
    return {'alive': false};
  }

  String? hostName;
  try {
    final reverse = await InternetAddress(ip)
        .reverse()
        .timeout(const Duration(milliseconds: 180));
    if (reverse.host.isNotEmpty && reverse.host != ip) {
      hostName = reverse.host;
    }
  } catch (_) {
    // Reverse DNS often fails on LANs; keep null.
  }

  return {
    'alive': true,
    'ip': ip,
    'responseMs': stopwatch.elapsedMilliseconds,
    'hostName': hostName,
    'openPorts': openPorts,
  };
}

void _scanEntry(_ScanConfig cfg) async {
  final send = cfg.sendPort;
  final total = (cfg.lastHostId - cfg.firstHostId + 1).clamp(0, 10000);
  int processed = 0;
  final queue = Queue<int>.from(
    List<int>.generate(total, (idx) => cfg.firstHostId + idx),
  );
  final maxWorkers = 64;
  final workerCount = total < maxWorkers ? total : maxWorkers;
  final List<Future<void>> workers = <Future<void>>[];

  Future<void> workerLoop() async {
    while (queue.isNotEmpty) {
      final hostId = queue.removeFirst();
      final ip = '${cfg.subnet}.$hostId';
      try {
        final result = await _probeHost(ip);
        if ((result['alive'] as bool?) ?? false) {
          send.send({
            'type': 'host',
            'ip': result['ip'],
            'responseMs': result['responseMs'],
            'hostName': result['hostName'],
            'openPorts': result['openPorts'],
          });
        }
      } catch (_) {
        // Continue scanning even if one host probe fails.
      }
      processed++;
      if (processed % 8 == 0 || processed == total) {
        final pct = (processed / total * 100).clamp(0, 100).toStringAsFixed(1);
        send.send({'type': 'progress', 'percent': pct});
      }
    }
  }

  for (int i = 0; i < workerCount; i++) {
    workers.add(workerLoop());
  }

  await Future.wait(workers);
  send.send({'type': '_scan_done_'});
}
