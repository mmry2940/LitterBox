import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../adb_client.dart';
import '../webadb_server.dart';

enum WebAdbState { stopped, starting, running, error }

class WebAdbController extends ChangeNotifier {
  final ADBClientManager adb;
  WebAdbServer? _server;
  WebAdbState _state = WebAdbState.stopped;
  String? _lastError;
  int _port = 8587; // requested or bound port
  String? _authToken;
  Timer? _healthTimer;
  Map<String, dynamic>? _lastHealth;

  WebAdbController(this.adb);

  WebAdbState get state => _state;
  int get port => _server?.port ?? _port;
  String? get lastError => _lastError ?? _server?.lastError;
  Map<String, dynamic>? get lastHealth => _lastHealth;
  bool get running => _state == WebAdbState.running;

  Future<void> configure({int? port, String? token}) async {
    if (port != null) _port = port;
    _authToken = token?.isEmpty == true ? null : token;
    notifyListeners();
  }

  Future<bool> start() async {
    if (_state == WebAdbState.starting || _state == WebAdbState.running) {
      return running;
    }
    _setState(WebAdbState.starting);
    _lastError = null;
    _server = WebAdbServer(adb, port: _port, authToken: _authToken);
    final ok = await _server!.start();
    if (!ok) {
      if (_port != 0) {
        _lastError = _server!.lastError;
        _server = WebAdbServer(adb, port: 0, authToken: _authToken);
        final ok2 = await _server!.start();
        if (ok2) {
          _setState(WebAdbState.running);
          _beginHealthPolling();
          notifyListeners();
          return true;
        }
      }
      _lastError = _server!.lastError ?? 'Unknown start failure';
      _setState(WebAdbState.error);
      return false;
    }
    _setState(WebAdbState.running);
    _beginHealthPolling();
    return true;
  }

  Future<void> stop() async {
    _healthTimer?.cancel();
    _healthTimer = null;
    if (_server != null) {
      try {
        await _server!.stop();
      } catch (_) {}
    }
    _server = null;
    _setState(WebAdbState.stopped);
  }

  void _setState(WebAdbState s) {
    _state = s;
    notifyListeners();
  }

  void _beginHealthPolling() {
    _healthTimer?.cancel();
    _healthTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => fetchHealth());
    fetchHealth();
  }

  Future<void> fetchHealth() async {
    if (!running) return;
    try {
      final p = port;
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse('http://localhost:$p/health'));
      if (_authToken != null) {
        req.headers.set('Authorization', 'Bearer $_authToken');
      }
      final resp = await req.close();
      final body = await resp.transform(const Utf8Decoder()).join();
      if (resp.statusCode == 200) {
        _lastHealth = _decodeJson(body);
      } else {
        _lastHealth = {'error': 'HTTP ${resp.statusCode}'};
      }
    } catch (e) {
      _lastHealth = {'error': e.toString()};
    }
    notifyListeners();
  }

  Map<String, dynamic>? _decodeJson(String src) {
    try {
      return jsonDecode(src) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _healthTimer?.cancel();
    super.dispose();
  }
}
