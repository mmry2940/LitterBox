import 'dart:async';
import 'package:multicast_dns/multicast_dns.dart';
import 'dart:io' show Socket;

class AdbMdnsServiceInfo {
  final String host; // target hostname
  final String? ip; // resolved IPv4 if available
  final String? ipv6; // resolved IPv6 if available
  final int port;
  final Map<String, String> txt; // parsed TXT key/values
  final DateTime discoveredAt;
  bool? reachable; // set after a reachability probe
  AdbMdnsServiceInfo(
      this.host, this.ip, this.ipv6, this.port, this.txt, this.discoveredAt,
      {this.reachable});

  Map<String, dynamic> toJson() => {
        'host': host,
        'ip': ip,
        'ipv6': ipv6,
        'port': port,
        'txt': txt,
        'reachable': reachable,
        'ts': discoveredAt.millisecondsSinceEpoch,
      };
  static AdbMdnsServiceInfo fromJson(Map<String, dynamic> j) =>
      AdbMdnsServiceInfo(
        j['host'] as String,
        j['ip'] as String?,
        j['ipv6'] as String?,
        j['port'] as int,
        (j['txt'] as Map).cast<String, String>(),
        DateTime.fromMillisecondsSinceEpoch(j['ts'] as int),
        reachable: j['reachable'] as bool?,
      );
}

/// Robust mDNS discovery for ADB over Wi‑Fi (_adb._tcp.local)
/// Features:
///  - Correct use of ResourceRecordQuery constructs (PTR -> SRV -> TXT)
///  - Debounced emission (avoid spamming when multiple records arrive)
///  - In‑memory cache with TTL (default 60s) to avoid duplicate UI churn
///  - Periodic retry timer when no services found
///  - Single-flight lookups (subsequent discover() calls wait for active scan)
class AdbMdnsDiscovery {
  final MDnsClient _client = MDnsClient();
  bool _running = false;
  bool _scanning = false;
  final Map<String, AdbMdnsServiceInfo> _cache = {}; // key = host:port
  final Duration ttl;
  Timer? _retryTimer;
  final Duration retryInterval;
  final StreamController<List<AdbMdnsServiceInfo>> _controller =
      StreamController.broadcast();
  Timer? _debounceTimer;

  AdbMdnsDiscovery(
      {this.ttl = const Duration(seconds: 60),
      this.retryInterval = const Duration(seconds: 20)});

  Stream<List<AdbMdnsServiceInfo>> get stream => _controller.stream;

  Future<void> start() async {
    if (_running) return;
    await _client.start();
    _running = true;
    _scheduleRetry();
    unawaited(scanOnce());
  }

  Future<void> stop() async {
    _retryTimer?.cancel();
    _retryTimer = null;
    _debounceTimer?.cancel();
    if (!_running) return;
    _client.stop();
    _running = false;
  }

  void dispose() {
    stop();
    _controller.close();
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(retryInterval, (_) {
      // Refresh cache entries (drop expired) and rescan if stale / empty
      _purgeExpired();
      if (_cache.isEmpty) {
        unawaited(scanOnce());
      }
    });
  }

  void _purgeExpired() {
    final now = DateTime.now();
    final toRemove = <String>[];
    _cache.forEach((k, v) {
      if (now.difference(v.discoveredAt) > ttl) toRemove.add(k);
    });
    for (final k in toRemove) {
      _cache.remove(k);
    }
  }

  Future<void> scanOnce(
      {Duration overallTimeout = const Duration(seconds: 5)}) async {
    if (_scanning) return; // single flight
    if (!_running) await start();
    _scanning = true;
    final discovered = <AdbMdnsServiceInfo>[];
    try {
      final ptrQuery = ResourceRecordQuery.serverPointer('_adb._tcp.local');
      final ptrResponses = _client
          .lookup<PtrResourceRecord>(ptrQuery)
          .timeout(overallTimeout, onTimeout: (sink) {
        sink.close();
      });

      await for (final ptr in ptrResponses) {
        final serviceName = ptr.domainName; // e.g. <instance>._adb._tcp.local
        final srvQuery = ResourceRecordQuery.service(serviceName);
        await for (final srv in _client.lookup<SrvResourceRecord>(srvQuery)) {
          final txtQuery = ResourceRecordQuery.text(serviceName);
          final txtMap = <String, String>{};
          try {
            await for (final txt
                in _client.lookup<TxtResourceRecord>(txtQuery)) {
              // Each record's text is a list of raw key=value strings (in modern versions) or joined
              final List<String> pairs = txt.text.split('\n');
              for (final p in pairs) {
                if (p.isEmpty) continue;
                final idx = p.indexOf('=');
                if (idx > 0) {
                  txtMap[p.substring(0, idx)] = p.substring(idx + 1);
                }
              }
            }
          } catch (_) {
            // Ignore TXT failures
          }
          // Attempt A/AAAA lookup for target to get IP (best-effort)
          String? ipv4;
          String? ipv6;
          // IPv4 lookup
          try {
            final aQuery = ResourceRecordQuery.addressIPv4(srv.target);
            await for (final IPAddressResourceRecord a in _client
                .lookup<IPAddressResourceRecord>(aQuery)
                .timeout(const Duration(milliseconds: 800), onTimeout: (sink) {
              sink.close();
            })) {
              ipv4 = a.address.address;
              break;
            }
          } catch (_) {}
          // IPv6 lookup only if IPv4 absent (or we still want IPv6 anyway)
          try {
            final aaaaQuery = ResourceRecordQuery.addressIPv6(srv.target);
            await for (final IPAddressResourceRecord aaaa in _client
                .lookup<IPAddressResourceRecord>(aaaaQuery)
                .timeout(const Duration(milliseconds: 800), onTimeout: (sink) {
              sink.close();
            })) {
              ipv6 = aaaa.address.address;
              break;
            }
          } catch (_) {}
          final info = AdbMdnsServiceInfo(
              srv.target, ipv4, ipv6, srv.port, txtMap, DateTime.now());
          // Reachability probe (best effort)
          try {
            final targetIp = info.ip ?? info.ipv6 ?? info.host;
            final socket = await Socket.connect(targetIp, info.port,
                timeout: const Duration(milliseconds: 600));
            await socket.close();
            info.reachable = true;
          } catch (_) {
            info.reachable = false;
          }
          final key = '${info.host}:${info.port}';
          _cache[key] = info;
          discovered.add(info);
          _debouncedEmit();
        }
      }
    } catch (_) {
      // swallow and allow retry
    } finally {
      _scanning = false;
      if (discovered.isEmpty) {
        // Emit current cache (purged) so UI can show stale/empty state
        _purgeExpired();
        _debouncedEmit(force: true);
      }
    }
  }

  void _debouncedEmit({bool force = false}) {
    if (force) {
      if (!_controller.isClosed) {
        _controller.add(
            _cache.values.toList()..sort((a, b) => a.host.compareTo(b.host)));
      }
      return;
    }
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      if (_controller.isClosed) return;
      _controller.add(
          _cache.values.toList()..sort((a, b) => a.host.compareTo(b.host)));
    });
  }

  List<AdbMdnsServiceInfo> currentCache() => _cache.values.toList()
    ..sort((a, b) => b.discoveredAt.compareTo(a.discoveredAt));
}
