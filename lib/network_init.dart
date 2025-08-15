import 'dart:async';

/// Provides a single point to await network_tools initialization.
class NetworkToolsInitializer {
  static final Completer<bool> _completer = Completer<bool>();
  static bool _started = false;
  static bool _isCompleted = false;
  static bool _result = false;

  /// Mark initialization complete (called from main after configureNetworkTools).
  static void completeSuccess() {
    if (!_isCompleted) {
      _result = true;
      _isCompleted = true;
      if (!_completer.isCompleted) _completer.complete(true);
    }
  }

  /// Mark initialization failed but allow dependents to continue.
  static void completeFailure([Object? error]) {
    if (!_isCompleted) {
      _result = false;
      _isCompleted = true;
      if (!_completer.isCompleted) _completer.complete(false);
    }
  }

  /// Returns when initialization phase finished (success or failure).
  static Future<bool> ensureInitialized() {
    _started = true;
    // If already completed, return cached result to avoid multiple listeners
    if (_isCompleted) {
      return Future.value(_result);
    }
    return _completer.future;
  }

  static bool get isDone => _isCompleted;
  static bool get started => _started;
}
