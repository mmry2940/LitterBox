import 'dart:async';

/// Provides a single point to await network_tools initialization.
class NetworkToolsInitializer {
  static final Completer<bool> _completer = Completer<bool>();
  static bool _started = false;

  /// Mark initialization complete (called from main after configureNetworkTools).
  static void completeSuccess() {
    if (!_completer.isCompleted) _completer.complete(true);
  }

  /// Mark initialization failed but allow dependents to continue.
  static void completeFailure([Object? error]) {
    if (!_completer.isCompleted) _completer.complete(false);
  }

  /// Returns when initialization phase finished (success or failure).
  static Future<bool> ensureInitialized() {
    _started = true;
    return _completer.future;
  }

  static bool get isDone => _completer.isCompleted;
  static bool get started => _started;
}
