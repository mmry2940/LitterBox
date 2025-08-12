import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'adb_client.dart';

/// Minimal WebADB-like server exposing:
/// GET /devices -> JSON list
/// POST /connect {"host":"","port":5555}
/// POST /disconnect {"host":"","port":5555}
/// WS  /shell?serial=XYZ (send lines, receive console output events)
/// NOTE: This is a simplified bridge, not a spec-complete implementation.
class WebAdbServer {
  final ADBClientManager client; // uses current backend
  HttpServer? _http;
  int port;
  bool get running => _http != null;
  final List<WebSocket> _shellSockets = [];
  StreamSubscription<String>? _outputSub;

  WebAdbServer(this.client, {this.port = 8587});

  Future<bool> start() async {
    if (_http != null) return true;
    try {
      _http = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _wireOutputBroadcast();
      _http!.listen(_handleRequest, onError: (e) {
        // swallow errors
      });
      client.addOutput('🌐 WebADB server started on port $port');
      return true;
    } catch (e) {
      client.addOutput('❌ Failed to start WebADB server: $e');
      return false;
    }
  }

  Future<void> stop() async {
    await _outputSub?.cancel();
    _outputSub = null;
    for (final ws in _shellSockets) {
      try {
        await ws.close();
      } catch (_) {}
    }
    _shellSockets.clear();
    await _http?.close(force: true);
    _http = null;
    client.addOutput('🛑 WebADB server stopped');
  }

  void _wireOutputBroadcast() {
    _outputSub?.cancel();
    _outputSub = client.output.listen((line) {
      final msg = jsonEncode({'type': 'console', 'data': line});
      for (final ws in _shellSockets.toList()) {
        if (ws.closeCode == null) {
          try {
            ws.add(msg);
          } catch (_) {}
        }
      }
    });
  }

  Future<void> _handleRequest(HttpRequest req) async {
    // CORS
    req.response.headers.set('Access-Control-Allow-Origin', '*');
    req.response.headers.set('Access-Control-Allow-Headers', 'content-type');
    if (req.method == 'OPTIONS') {
      req.response.statusCode = 204;
      await req.response.close();
      return;
    }
    if (WebSocketTransformer.isUpgradeRequest(req)) {
      _handleWebSocket(req);
      return;
    }
    try {
      if (req.uri.path == '/devices' && req.method == 'GET') {
        final devices = await client.refreshBackendDevices();
        final jsonList =
            devices.map((d) => {'serial': d.serial, 'state': d.state}).toList();
        _json(req, {'devices': jsonList});
      } else if (req.uri.path == '/connect' && req.method == 'POST') {
        final body = await utf8.decodeStream(req);
        final map = jsonDecode(body) as Map<String, dynamic>;
        final host = map['host'] as String? ?? '';
        final port = map['port'] is int
            ? map['port']
            : int.tryParse('${map['port']}') ?? 5555;
        final ok = await client.connectWifi(host, port);
        _json(req, {'ok': ok});
      } else if (req.uri.path == '/disconnect' && req.method == 'POST') {
        await client.disconnect();
        _json(req, {'ok': true});
      } else {
        req.response.statusCode = 404;
        await req.response.close();
      }
    } catch (e) {
      _json(req, {'error': e.toString()}, status: 500);
    }
  }

  Future<void> _handleWebSocket(HttpRequest req) async {
    final serial = req.uri.queryParameters['serial'];
    final ws = await WebSocketTransformer.upgrade(req);
    _shellSockets.add(ws);
    client
        .addOutput('🔌 WebADB WS client connected (${serial ?? 'no-serial'})');
    ws.listen((data) async {
      try {
        final msg = jsonDecode(data);
        if (msg is Map && msg['type'] == 'shell' && msg['cmd'] is String) {
          final cmd = msg['cmd'] as String;
          await client.executeCommand(cmd);
        }
      } catch (_) {}
    }, onDone: () {
      _shellSockets.remove(ws);
      client.addOutput('🔌 WebADB WS client disconnected');
    }, onError: (_) {
      _shellSockets.remove(ws);
    });
  }

  void _json(HttpRequest req, Object obj, {int status = 200}) {
    final data = utf8.encode(jsonEncode(obj));
    req.response.statusCode = status;
    req.response.headers.contentType = ContentType.json;
    req.response.add(data);
    req.response.close();
  }
}
