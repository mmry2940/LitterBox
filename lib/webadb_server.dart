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
  final Map<WebSocket, String?> _shellSockets =
      {}; // socket -> serial (null means global)
  StreamSubscription<String>? _outputSub;
  String? authToken; // optional bearer / query token
  String? lastError; // store last startup/error message
  List<String> _localIPv4 = [];
  int? lastRequestedPort;
  bool fallbackUsed = false;
  bool _starting = false;

  WebAdbServer(this.client, {this.port = 8587, this.authToken});

  Future<bool> start({int maxFallbackPorts = 5}) async {
    if (_http != null) return true; // already running
    if (_starting) {
      lastError = 'Start already in progress';
      return false;
    }
    _starting = true;
    lastError = null;
    fallbackUsed = false;
    lastRequestedPort = port;
    int attemptPort = port;
    client.addOutput(
        '🧪 WebADB starting on base port $port (maxFallback=$maxFallbackPorts)');
    print('WEBADB: starting basePort=$port maxFallback=$maxFallbackPorts');
    // quick capability probe
    try {
      final test = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      await test.close();
    } catch (e) {
      lastError = 'Loopback bind failed: $e';
      client.addOutput('❌ Loopback probe failed: $e');
      _starting = false; // ensure flag cleared on early failure
      return false;
    }
    for (int attempt = 0; attempt <= maxFallbackPorts; attempt++) {
      client
          .addOutput('➡️  WebADB bind attempt ${attempt + 1} on $attemptPort');
      print('WEBADB: attempt ${attempt + 1} binding $attemptPort');
      try {
        _http = await HttpServer.bind(InternetAddress.anyIPv4, attemptPort);
        port = _http!.port; // update to actual bound port
        if (attempt > 0 || port != lastRequestedPort) fallbackUsed = true;
        _wireOutputBroadcast();
        _http!.listen(_handleRequest, onError: (e) {
          // swallow connection errors
        });
        await _gatherLocalIPs();
        client.addOutput(
            '🌐 WebADB server started on port $port (attempt ${attempt + 1})');
        print('WEBADB: started port=$port attempt=${attempt + 1}');
        _starting = false;
        return true;
      } catch (e) {
        lastError = e.toString();
        final isAddrInUse = e is SocketException &&
            (e.osError?.message.toLowerCase().contains('in use') ?? false);
        final needsShared = e is SocketException &&
            (e.osError?.message.toLowerCase().contains('shared flag') ?? false);
        client.addOutput('❌ WebADB start failed on $attemptPort: $e');
        print('WEBADB: fail attemptPort=$attemptPort error=$e');
        if (needsShared) {
          try {
            client.addOutput('🔁 Retrying with shared:true on $attemptPort');
            print('WEBADB: retry shared attemptPort=$attemptPort');
            _http = await HttpServer.bind(InternetAddress.anyIPv4, attemptPort,
                shared: true);
            port = _http!.port;
            if (attempt > 0 || port != lastRequestedPort) fallbackUsed = true;
            _wireOutputBroadcast();
            _http!.listen(_handleRequest, onError: (e) {});
            await _gatherLocalIPs();
            client.addOutput('🌐 WebADB server started (shared) on port $port');
            print('WEBADB: started shared port=$port');
            _starting = false;
            return true;
          } catch (se) {
            lastError = 'Shared bind failed: $se';
            client.addOutput('❌ Shared bind failed: $se');
            print('WEBADB: shared bind failed $se');
          }
        }
        if (!isAddrInUse || attempt == maxFallbackPorts) {
          // If we exhausted all retries due to address-in-use, try one last ephemeral port bind
          if (isAddrInUse && attempt == maxFallbackPorts) {
            try {
              client.addOutput('🔁 Trying ephemeral port (0) as last resort');
              print('WEBADB: trying ephemeral port 0');
              _http = await HttpServer.bind(InternetAddress.anyIPv4, 0);
              port = _http!.port;
              fallbackUsed = true;
              _wireOutputBroadcast();
              _http!.listen(_handleRequest, onError: (e) {});
              await _gatherLocalIPs();
              client.addOutput(
                  '🌐 WebADB server started on ephemeral port $port');
              print('WEBADB: started ephemeral port=$port');
              _starting = false;
              return true;
            } catch (ep) {
              lastError = 'Ephemeral bind failed: $ep';
              client.addOutput('❌ Ephemeral bind failed: $ep');
              print('WEBADB: ephemeral bind failed $ep');
            }
          }
          _starting = false;
          return false; // unrecoverable or exhausted including ephemeral attempt
        }
        attemptPort++; // try next port
      }
    }
    // If we reach here all attempts failed without triggering return
    if (_starting) _starting = false;
    if (lastError == null) lastError = 'Unknown bind failure after attempts';
    client.addOutput('❌ WebADB final failure: ${lastError}');
    print('WEBADB: final failure ${lastError}');
    return false;
  }

  Future<void> stop() async {
    await _outputSub?.cancel();
    _outputSub = null;
    for (final ws in _shellSockets.keys) {
      try {
        await ws.close();
      } catch (_) {}
    }
    _shellSockets.clear();
    await _http?.close(force: true);
    _http = null;
    client.addOutput('🛑 WebADB server stopped');
  }

  Future<void> _gatherLocalIPs() async {
    try {
      final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLinkLocal: false);
      final ips = <String>{};
      for (final ni in interfaces) {
        for (final addr in ni.addresses) {
          if (!addr.isLoopback) ips.add(addr.address);
        }
      }
      _localIPv4 = ips.toList()..sort();
    } catch (_) {
      _localIPv4 = [];
    }
  }

  List<String> get localIPv4 => List.unmodifiable(_localIPv4);
  bool get usedFallbackPort => fallbackUsed;

  void _wireOutputBroadcast() {
    _outputSub?.cancel();
    _outputSub = client.output.listen((line) {
      final msg = jsonEncode({'type': 'console', 'data': line});
      for (final ws in _shellSockets.keys.toList()) {
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
    req.response.headers.set('Access-Control-Allow-Headers',
        'content-type,authorization,x-webadb-token');
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
      // Basic token auth check (header Authorization: Bearer <token> OR x-webadb-token header OR ?token=)
      if (authToken != null) {
        final headerAuth = req.headers.value('authorization');
        final headerToken = req.headers.value('x-webadb-token');
        final qp = req.uri.queryParameters['token'];
        bool ok = false;
        if (headerAuth != null &&
            headerAuth.toLowerCase().startsWith('bearer ')) {
          ok = headerAuth.substring(7).trim() == authToken;
        }
        if (!ok && headerToken != null) ok = headerToken.trim() == authToken;
        if (!ok && qp != null) ok = qp == authToken;
        if (!ok) {
          _json(req, {'error': 'unauthorized'}, status: 401);
          return;
        }
      }

      if (req.uri.path == '/devices' && req.method == 'GET') {
        final devices = await client.refreshBackendDevices();
        final jsonList =
            devices.map((d) => {'serial': d.serial, 'state': d.state}).toList();
        _json(req, {'devices': jsonList});
      } else if (req.uri.path == '/health' && req.method == 'GET') {
        final devices = await client.refreshBackendDevices();
        _json(req, {
          'running': running,
          'port': port,
          'authRequired': authToken != null,
          'deviceCount': devices.length,
          'ips': localIPv4,
          'lastError': lastError
        });
      } else if (req.uri.path == '/props' && req.method == 'GET') {
        final serial = req.uri.queryParameters['serial'];
        if (serial == null || serial.isEmpty) {
          _json(req, {'error': 'missing serial'}, status: 400);
          return;
        }
        final props = await client.getDevicePropsFor(serial);
        _json(req, {'serial': serial, 'props': props});
      } else if (req.uri.path == '/screencap' && req.method == 'GET') {
        final serial = req.uri.queryParameters['serial'];
        if (serial == null || serial.isEmpty) {
          _json(req, {'error': 'missing serial'}, status: 400);
          return;
        }
        final png = await client.screencapForSerial(serial);
        if (png == null) {
          _json(req, {'error': 'failed'}, status: 500);
          return;
        }
        req.response.headers.contentType = ContentType('image', 'png');
        req.response.add(png);
        await req.response.close();
        return;
      } else if (req.uri.path == '/push' && req.method == 'POST') {
        // Expect multipart? For simplicity: JSON {serial, remote, data(base64)}
        final body = await utf8.decodeStream(req);
        final map = jsonDecode(body) as Map<String, dynamic>;
        final serial = map['serial'] as String?;
        final remote = map['remote'] as String?;
        final data = map['data'] as String?;
        final localTmp = 'push_tmp_${DateTime.now().microsecondsSinceEpoch}';
        if (serial == null || remote == null || data == null) {
          _json(req, {'error': 'missing fields'}, status: 400);
          return;
        }
        try {
          final bytes = base64.decode(data);
          final file = File(localTmp);
          await file.writeAsBytes(bytes, flush: true);
          final ok = await client.pushFileForSerial(serial, file.path, remote);
          try {
            await file.delete();
          } catch (_) {}
          _json(req, {'ok': ok});
        } catch (e) {
          _json(req, {'error': e.toString()}, status: 500);
        }
      } else if (req.uri.path == '/pull' && req.method == 'GET') {
        final serial = req.uri.queryParameters['serial'];
        final remote = req.uri.queryParameters['remote'];
        if (serial == null || remote == null) {
          _json(req, {'error': 'missing params'}, status: 400);
          return;
        }
        final content = await client.pullFileForSerial(serial, remote);
        _json(req, {
          'serial': serial,
          'remote': remote,
          'data': base64.encode(utf8.encode(content))
        });
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
      } else if (req.uri.path == '/webadb_test' && req.method == 'GET') {
        // Simple HTML test client
        final html = _testClientHtml();
        req.response.headers.contentType = ContentType.html;
        req.response.write(html);
        await req.response.close();
      } else {
        req.response.statusCode = 404;
        await req.response.close();
      }
    } catch (e) {
      _json(req, {'error': e.toString()}, status: 500);
    }
  }

  Future<void> _handleWebSocket(HttpRequest req) async {
    // Auth for WS if token required
    if (authToken != null) {
      final headerAuth = req.headers.value('authorization');
      final headerToken = req.headers.value('x-webadb-token');
      final qp = req.uri.queryParameters['token'];
      bool ok = false;
      if (headerAuth != null &&
          headerAuth.toLowerCase().startsWith('bearer ')) {
        ok = headerAuth.substring(7).trim() == authToken;
      }
      if (!ok && headerToken != null) ok = headerToken.trim() == authToken;
      if (!ok && qp != null) ok = qp == authToken;
      if (!ok) {
        req.response.statusCode = 401;
        await req.response.close();
        return;
      }
    }

    final serial = req.uri.queryParameters['serial'];
    final ws = await WebSocketTransformer.upgrade(req);
    _shellSockets[ws] = serial; // null => global
    client
        .addOutput('🔌 WebADB WS client connected (${serial ?? 'no-serial'})');
    ws.listen((data) async {
      try {
        final msg = jsonDecode(data);
        if (msg is Map && msg['type'] == 'shell' && msg['cmd'] is String) {
          final cmd = msg['cmd'] as String;
          final target = msg['serial'] as String? ?? serial;
          if (target != null && target.isNotEmpty) {
            final out = await client.shellForSerial(target, cmd);
            if (out.isNotEmpty) {
              try {
                ws.add(jsonEncode(
                    {'type': 'result', 'serial': target, 'data': out}));
              } catch (_) {}
            }
          } else {
            await client.executeCommand(cmd); // fallback to active device
          }
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

  String _testClientHtml() => '''<!doctype html>
<html><head><meta charset="utf-8"/><title>WebADB Test</title>
<style>body{font-family:system-ui,monospace;margin:16px;background:#111;color:#eee} pre{background:#222;padding:8px;max-height:300px;overflow:auto} input,button{margin:4px;} .ok{color:#4caf50}</style>
</head><body>
<h2>WebADB Test Client</h2>
<div>Token: <input id="token" placeholder="optional token" style="width:180px"/></div>
<div><button onclick="loadDevices()">List Devices</button> <span id=devCount></span></div>
<pre id="devices"></pre>
<div>Serial: <input id="serial" placeholder="device serial" style="width:200px"/></div>
<div><button onclick="getProps()">Get Props</button></div>
<pre id="props"></pre>
<div>Shell Cmd: <input id="cmd" style="width:300px" placeholder="e.g. getprop ro.product.model"/> <button onclick="sendCmd()">Send</button></div>
<pre id="log"></pre>
<script>
let ws;
function authHeaders(){ const t=document.getElementById('token').value.trim(); return t?{'Authorization':'Bearer '+t}:{}}
  function base(){const u=new URL(window.location.href); return u.protocol+'//'+u.hostname+':${port}'}
async function loadDevices(){
  const r=await fetch(base()+'/devices',{headers:authHeaders()});
  const j=await r.json();
  document.getElementById('devices').textContent=JSON.stringify(j,null,2);
  document.getElementById('devCount').textContent=j.devices.length+' device(s)';
  if(!ws){ openWs(); }
}
async function getProps(){
  const s=document.getElementById('serial').value.trim(); if(!s)return;
  const r=await fetch(base()+'/props?serial='+encodeURIComponent(s),{headers:authHeaders()});
  const j=await r.json(); document.getElementById('props').textContent=JSON.stringify(j,null,2);
}
function openWs(){
  const t=document.getElementById('token').value.trim();
  const url = 'ws://'+location.hostname+':${port}/shell'+(t?'?token='+encodeURIComponent(t):'');
  ws=new WebSocket(url);
  ws.onmessage=e=>{ const data=JSON.parse(e.data); const log=document.getElementById('log'); log.textContent += JSON.stringify(data)+"\n"; log.scrollTop=log.scrollHeight; };
  ws.onopen=()=>{ const log=document.getElementById('log'); log.textContent+='[ws opened]\n'; };
  ws.onclose=()=>{ const log=document.getElementById('log'); log.textContent+='[ws closed]\n'; };
}
function sendCmd(){ if(!ws || ws.readyState!==1) return; const cmd=document.getElementById('cmd').value; const serial=document.getElementById('serial').value.trim(); ws.send(JSON.stringify({type:'shell',cmd:cmd,serial:serial||undefined})); }
</script>
</body></html>''';
}
