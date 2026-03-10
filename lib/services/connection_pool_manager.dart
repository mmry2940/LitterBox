import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../adb_client.dart';
import '../models/saved_adb_device.dart';

ConnectivityResult? _coerceConnectivityResult(dynamic value) {
  if (value is ConnectivityResult) return value;
  if (value is List && value.isNotEmpty) {
    return _coerceConnectivityResult(value.first);
  }
  if (value is String) {
    switch (value.toLowerCase()) {
      case 'wifi':
        return ConnectivityResult.wifi;
      case 'ethernet':
        return ConnectivityResult.ethernet;
      case 'mobile':
        return ConnectivityResult.mobile;
      case 'none':
        return ConnectivityResult.none;
      case 'bluetooth':
        return ConnectivityResult.bluetooth;
      case 'vpn':
        return ConnectivityResult.vpn;
      case 'other':
        return ConnectivityResult.other;
    }
  }
  return null;
}

NetworkState _networkStateFromConnectivity(ConnectivityResult? result) {
  switch (result) {
    case ConnectivityResult.wifi:
    case ConnectivityResult.ethernet:
    case ConnectivityResult.mobile:
      return NetworkState.connected;
    case ConnectivityResult.none:
      return NetworkState.disconnected;
    default:
      return NetworkState.unknown;
  }
}

/// Quality metrics for a connection
class ConnectionQuality {
  final int latencyMs;
  final double bandwidthMbps;
  final double packetLoss;
  final DateTime lastMeasured;
  final ConnectionHealthStatus status;

  ConnectionQuality({
    required this.latencyMs,
    required this.bandwidthMbps,
    required this.packetLoss,
    required this.lastMeasured,
    required this.status,
  });

  String get qualityText {
    switch (status) {
      case ConnectionHealthStatus.excellent:
        return 'Excellent';
      case ConnectionHealthStatus.good:
        return 'Good';
      case ConnectionHealthStatus.fair:
        return 'Fair';
      case ConnectionHealthStatus.poor:
        return 'Poor';
      case ConnectionHealthStatus.critical:
        return 'Critical';
    }
  }

  Color get qualityColor {
    switch (status) {
      case ConnectionHealthStatus.excellent:
        return const Color(0xFF4CAF50);
      case ConnectionHealthStatus.good:
        return const Color(0xFF8BC34A);
      case ConnectionHealthStatus.fair:
        return const Color(0xFFFFC107);
      case ConnectionHealthStatus.poor:
        return const Color(0xFFFF9800);
      case ConnectionHealthStatus.critical:
        return const Color(0xFFF44336);
    }
  }
}

enum ConnectionHealthStatus {
  excellent,
  good,
  fair,
  poor,
  critical,
}

enum CircuitBreakerState {
  closed, // Normal operation
  open, // Blocking requests
  halfOpen, // Testing if service is back
}

enum NetworkState {
  connected,
  disconnected,
  limited,
  unknown,
}

/// Circuit breaker for connection failure handling
class ConnectionCircuitBreaker {
  final String connectionId;
  final int failureThreshold;
  final Duration timeout;
  final Duration retryAfter;

  CircuitBreakerState _state = CircuitBreakerState.closed;
  int _failureCount = 0;
  DateTime? _lastFailureTime;
  DateTime? _nextRetryTime;

  ConnectionCircuitBreaker({
    required this.connectionId,
    this.failureThreshold = 5,
    this.timeout = const Duration(seconds: 30),
    this.retryAfter = const Duration(minutes: 2),
  });

  CircuitBreakerState get state => _state;
  int get failureCount => _failureCount;

  bool canAttemptConnection() {
    switch (_state) {
      case CircuitBreakerState.closed:
        return true;
      case CircuitBreakerState.open:
        if (_nextRetryTime != null && DateTime.now().isAfter(_nextRetryTime!)) {
          _state = CircuitBreakerState.halfOpen;
          return true;
        }
        return false;
      case CircuitBreakerState.halfOpen:
        return true;
    }
  }

  void recordSuccess() {
    _failureCount = 0;
    _state = CircuitBreakerState.closed;
    _lastFailureTime = null;
    _nextRetryTime = null;
  }

  void recordFailure() {
    _failureCount++;
    _lastFailureTime = DateTime.now();

    if (_failureCount >= failureThreshold) {
      _state = CircuitBreakerState.open;
      _nextRetryTime = DateTime.now().add(retryAfter);
    }
  }

  void reset() {
    _failureCount = 0;
    _state = CircuitBreakerState.closed;
    _lastFailureTime = null;
    _nextRetryTime = null;
  }
}

/// Managed connection wrapper
class ManagedConnection<T> {
  final String connectionId;
  final T client;
  final DateTime createdAt;
  final Map<String, dynamic> metadata;

  DateTime lastUsed;
  bool isHealthy;
  ConnectionQuality? quality;
  Timer? _heartbeatTimer;
  Timer? _qualityTimer;
  Timer? _keepAliveTimer;

  // Enhanced stability features
  final ConnectionCircuitBreaker circuitBreaker;
  Duration adaptiveTimeout;
  int consecutiveFailures = 0;
  DateTime? lastValidationTime;
  bool isValidated = false;

  // Network state monitoring
  NetworkState lastKnownNetworkState = NetworkState.unknown;

  final StreamController<ConnectionQuality> _qualityController =
      StreamController<ConnectionQuality>.broadcast();
  final StreamController<String> _statusController =
      StreamController<String>.broadcast();

  ManagedConnection({
    required this.connectionId,
    required this.client,
    required this.metadata,
    Duration? initialTimeout,
  })  : createdAt = DateTime.now(),
        lastUsed = DateTime.now(),
        isHealthy = true,
        circuitBreaker = ConnectionCircuitBreaker(connectionId: connectionId),
        adaptiveTimeout = initialTimeout ?? const Duration(seconds: 30);

  Stream<ConnectionQuality> get qualityUpdates => _qualityController.stream;
  Stream<String> get statusUpdates => _statusController.stream;

  void updateLastUsed() {
    lastUsed = DateTime.now();
  }

  void updateQuality(ConnectionQuality quality) {
    this.quality = quality;
    _qualityController.add(quality);

    // Update adaptive timeout based on quality
    _updateAdaptiveTimeout(quality);
  }

  /// Validate connection before use
  Future<bool> validateConnection() async {
    if (!circuitBreaker.canAttemptConnection()) {
      _statusController.add('Connection blocked by circuit breaker');
      return false;
    }

    // Skip validation if recently validated and healthy
    if (lastValidationTime != null &&
        DateTime.now().difference(lastValidationTime!).inSeconds < 30 &&
        isValidated &&
        isHealthy) {
      return true;
    }

    try {
      if (client is SSHClient) {
        final ssh = client as SSHClient;
        final result = await ssh.run('echo "validation"').timeout(adaptiveTimeout);
        final isValid = result.isNotEmpty;

        lastValidationTime = DateTime.now();
        isValidated = isValid;
        isHealthy = isValid;

        if (isValid) {
          circuitBreaker.recordSuccess();
          consecutiveFailures = 0;
        } else {
          circuitBreaker.recordFailure();
          consecutiveFailures++;
        }

        return isValid;
      } else if (client is ADBClientManager) {
        final adb = client as ADBClientManager;
        final isValid = adb.currentState == ADBConnectionState.connected;

        lastValidationTime = DateTime.now();
        isValidated = isValid;
        isHealthy = isValid;

        if (isValid) {
          circuitBreaker.recordSuccess();
          consecutiveFailures = 0;
        } else {
          circuitBreaker.recordFailure();
          consecutiveFailures++;
        }

        return isValid;
      }
    } catch (e) {
      _statusController.add('Validation failed: $e');
      circuitBreaker.recordFailure();
      consecutiveFailures++;
      isHealthy = false;
      isValidated = false;
      return false;
    }

    return false;
  }

  /// Update adaptive timeout based on connection quality
  void _updateAdaptiveTimeout(ConnectionQuality quality) {
    switch (quality.status) {
      case ConnectionHealthStatus.excellent:
        adaptiveTimeout = const Duration(seconds: 10);
        break;
      case ConnectionHealthStatus.good:
        adaptiveTimeout = const Duration(seconds: 20);
        break;
      case ConnectionHealthStatus.fair:
        adaptiveTimeout = const Duration(seconds: 30);
        break;
      case ConnectionHealthStatus.poor:
        adaptiveTimeout = const Duration(seconds: 45);
        break;
      case ConnectionHealthStatus.critical:
        adaptiveTimeout = const Duration(seconds: 60);
        break;
    }
  }

  void startHealthCheck(Duration interval) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(interval, (_) => _performHealthCheck());

    _qualityTimer?.cancel();
    _qualityTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _measureQuality(),
    );

    // Start keep-alive timer for idle connections
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _performKeepAlive(),
    );

    _statusController.add('Health monitoring started');
  }

  void stopHealthCheck() {
    _heartbeatTimer?.cancel();
    _qualityTimer?.cancel();
    _keepAliveTimer?.cancel();
    _heartbeatTimer = null;
    _qualityTimer = null;
    _keepAliveTimer = null;

    _statusController.add('Health monitoring stopped');
  }

  Future<void> _performHealthCheck() async {
    try {
      // Check network state first
      final networkState = await _getNetworkState();
      if (networkState == NetworkState.disconnected) {
        isHealthy = false;
        lastKnownNetworkState = networkState;
        _statusController.add('Network disconnected');
        return;
      }

      if (client is SSHClient) {
        final ssh = client as SSHClient;
        await ssh.run('echo "health_check"').timeout(adaptiveTimeout);
        isHealthy = true;
        circuitBreaker.recordSuccess();
        _statusController.add('Health check passed');
      } else if (client is ADBClientManager) {
        final adb = client as ADBClientManager;
        isHealthy = adb.currentState == ADBConnectionState.connected;
        if (isHealthy) {
          circuitBreaker.recordSuccess();
          _statusController.add('ADB connection healthy');
        } else {
          circuitBreaker.recordFailure();
          _statusController.add('ADB connection unhealthy');
        }
      }

      lastKnownNetworkState = networkState;
    } catch (e) {
      isHealthy = false;
      circuitBreaker.recordFailure();
      consecutiveFailures++;
      _statusController.add('Health check failed: $e');

      // Adaptive backoff for failed health checks
      if (consecutiveFailures > 3) {
        _heartbeatTimer?.cancel();
        final backoffDelay =
            Duration(seconds: (consecutiveFailures * 30).clamp(30, 300));
        _heartbeatTimer = Timer(backoffDelay, () {
          startHealthCheck(const Duration(seconds: 30));
        });
      }
    }
  }

  Future<void> _measureQuality() async {
    try {
      if (client is SSHClient) {
        final ssh = client as SSHClient;

        // Measure latency with small command
        final latencyStart = DateTime.now();
        await ssh.run('echo "ping"');
        final latencyMs =
            DateTime.now().difference(latencyStart).inMilliseconds;

        // Measure bandwidth (simplified)
        final bandwidthStart = DateTime.now();
        await ssh.run('dd if=/dev/zero bs=1024 count=100 2>/dev/null | wc -c');
        final bandwidthTime =
            DateTime.now().difference(bandwidthStart).inMilliseconds;
        final bandwidthMbps =
            (100 * 1024 * 8) / (bandwidthTime * 1000.0); // Rough calculation

        final status =
            _calculateHealthStatus(latencyMs.toDouble(), bandwidthMbps, 0.0);

        updateQuality(ConnectionQuality(
          latencyMs: latencyMs,
          bandwidthMbps: bandwidthMbps,
          packetLoss: 0.0, // Simplified for SSH
          lastMeasured: DateTime.now(),
          status: status,
        ));
      }
    } catch (e) {
      // On error, mark as poor quality
      updateQuality(ConnectionQuality(
        latencyMs: 9999,
        bandwidthMbps: 0.0,
        packetLoss: 100.0,
        lastMeasured: DateTime.now(),
        status: ConnectionHealthStatus.critical,
      ));
    }
  }

  ConnectionHealthStatus _calculateHealthStatus(
      double latency, double bandwidth, double packetLoss) {
    if (latency < 50 && bandwidth > 10 && packetLoss < 1) {
      return ConnectionHealthStatus.excellent;
    } else if (latency < 150 && bandwidth > 5 && packetLoss < 3) {
      return ConnectionHealthStatus.good;
    } else if (latency < 300 && bandwidth > 1 && packetLoss < 10) {
      return ConnectionHealthStatus.fair;
    } else if (latency < 1000 && packetLoss < 25) {
      return ConnectionHealthStatus.poor;
    }
    return ConnectionHealthStatus.critical;
  }

  /// Perform keep-alive to prevent idle timeouts
  Future<void> _performKeepAlive() async {
    // Only send keep-alive if connection hasn't been used recently
    final timeSinceLastUse = DateTime.now().difference(lastUsed);
    if (timeSinceLastUse.inMinutes < 5) {
      return; // Connection is actively used, no need for keep-alive
    }

    try {
      if (client is SSHClient) {
        final ssh = client as SSHClient;
        await ssh
            .run('true')
            .timeout(const Duration(seconds: 10)); // Minimal command
        _statusController.add('Keep-alive sent');
      }
    } catch (e) {
      _statusController.add('Keep-alive failed: $e');
      isHealthy = false;
    }
  }

  /// Get current network state
  Future<NetworkState> _getNetworkState() async {
    try {
      if (kIsWeb) return NetworkState.connected; // Assume connected on web

      final connectivityData = await Connectivity().checkConnectivity();
      final result = _coerceConnectivityResult(connectivityData);
      return _networkStateFromConnectivity(result);
    } catch (e) {
      return NetworkState.unknown;
    }
  }

  void dispose() {
    stopHealthCheck();
    _qualityController.close();
    _statusController.close();

    try {
      if (client is SSHClient) {
        (client as SSHClient).close();
      }
    } catch (e) {
      debugPrint('Error disposing connection: $e');
    }
  }
}

/// Connection pool manager with auto-reconnection and quality monitoring
class ConnectionPoolManager {
  static final ConnectionPoolManager _instance =
      ConnectionPoolManager._internal();
  factory ConnectionPoolManager() => _instance;

  final Map<String, ManagedConnection> _connections = {};
  final Map<String, Timer> _reconnectionTimers = {};
  final Map<String, ConnectionCircuitBreaker> _circuitBreakers = {};
  final StreamController<String> _reconnectionEvents =
      StreamController.broadcast();
  final StreamController<String> _networkEvents = StreamController.broadcast();

  StreamSubscription<dynamic>? _connectivitySubscription;
  NetworkState _currentNetworkState = NetworkState.unknown;
  Timer? _networkMonitorTimer;

  Stream<String> get reconnectionEvents => _reconnectionEvents.stream;
  Stream<String> get networkEvents => _networkEvents.stream;

  ConnectionPoolManager._internal() {
    _initializeNetworkMonitoring();
  }

  void _initializeNetworkMonitoring() {
    if (kIsWeb) return;

    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((results) {
      final first = _coerceConnectivityResult(results);
      if (first != null) {
        _handleNetworkChange(first);
      }
    }, onError: (error) {
      _networkEvents.add('Connectivity stream error: $error');
      _currentNetworkState = NetworkState.unknown;
    });

    // Periodic network quality check
    _networkMonitorTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _checkNetworkQuality();
    });
  }

  void _handleNetworkChange(ConnectivityResult result) {
    final newState = _mapConnectivityToNetworkState(result);
    if (newState != _currentNetworkState) {
      _networkEvents.add(
          'Network state changed: ${_currentNetworkState.name} -> ${newState.name}');
      _currentNetworkState = newState;

      if (newState == NetworkState.disconnected) {
        _handleNetworkDisconnection();
      } else if (_currentNetworkState == NetworkState.disconnected &&
          newState == NetworkState.connected) {
        _handleNetworkReconnection();
      }
    }
  }

  NetworkState _mapConnectivityToNetworkState(ConnectivityResult result) {
    return _networkStateFromConnectivity(result);
  }

  void _handleNetworkDisconnection() {
    _networkEvents.add('Network disconnected - pausing connection attempts');
    for (final connection in _connections.values) {
      connection.isHealthy = false;
    }
  }

  void _handleNetworkReconnection() {
    _networkEvents.add('Network reconnected - validating connections');
    for (final connection in _connections.values) {
      connection.validateConnection();
    }
  }

  Future<void> _checkNetworkQuality() async {
    if (_currentNetworkState == NetworkState.disconnected) return;

    try {
      // Simple network latency test
      final stopwatch = Stopwatch()..start();
      await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));
      stopwatch.stop();

      final latency = stopwatch.elapsedMilliseconds;
      if (latency > 5000) {
        _networkEvents.add('High network latency detected: ${latency}ms');
      }
    } catch (e) {
      _networkEvents.add('Network quality check failed: $e');
    }
  }

  /// Get or create SSH connection with enhanced stability
  Future<SSHClient?> getSSHConnection(
    String host,
    int port,
    String username,
    String password, {
    bool enableAutoReconnect = true,
    Duration? timeout,
    int maxRetries = 3,
  }) async {
    final connectionId = 'ssh:$username@$host:$port';

    // Check network state first
    if (_currentNetworkState == NetworkState.disconnected) {
      _reconnectionEvents.add('Cannot connect - network is disconnected');
      return null;
    }

    // Check circuit breaker
    final circuitBreaker = _circuitBreakers[connectionId] ??=
        ConnectionCircuitBreaker(connectionId: connectionId);

    if (!circuitBreaker.canAttemptConnection()) {
      _reconnectionEvents
          .add('Connection blocked by circuit breaker: $connectionId');
      return null;
    }

    // Return existing connection if valid
    final existing = _connections[connectionId];
    if (existing != null && existing.client is SSHClient) {
      final isValid = await existing.validateConnection();
      if (isValid) {
        existing.updateLastUsed();
        return existing.client as SSHClient;
      } else {
        // Remove invalid connection
        _connections.remove(connectionId);
        existing.dispose();
      }
    }

    // Retry logic with exponential backoff
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        _reconnectionEvents
            .add('Connecting to $connectionId (attempt $attempt/$maxRetries)');

        // Adaptive timeout based on attempt
        final adaptiveTimeout =
            timeout ?? Duration(seconds: 10 + (attempt * 5));

        final socket = await SSHSocket.connect(
          host,
          port,
          timeout: adaptiveTimeout,
        );

        final client = SSHClient(
          socket,
          username: username,
          onPasswordRequest: () => password,
        );

        // Test the connection immediately
        await client
            .run('echo "connection_test"')
            .timeout(const Duration(seconds: 5));

        // Create managed connection
        final managedConnection = ManagedConnection<SSHClient>(
          connectionId: connectionId,
          client: client,
          metadata: {
            'host': host,
            'port': port,
            'username': username,
            'type': 'ssh',
            'created': DateTime.now().toIso8601String(),
            'maxRetries': maxRetries,
          },
          initialTimeout: adaptiveTimeout,
        );

        // Start health monitoring
        managedConnection.startHealthCheck(const Duration(seconds: 30));

        // Setup auto-reconnection if enabled
        if (enableAutoReconnect) {
          _setupAutoReconnection(connectionId, () async {
            return getSSHConnection(host, port, username, password,
                enableAutoReconnect: enableAutoReconnect,
                timeout: timeout,
                maxRetries: maxRetries);
          });
        }

        _connections[connectionId] = managedConnection;
        circuitBreaker.recordSuccess();
        _reconnectionEvents.add('Successfully connected to $connectionId');

        return client;
      } catch (e) {
        _reconnectionEvents
            .add('Connection attempt $attempt failed for $connectionId: $e');
        circuitBreaker.recordFailure();

        if (attempt < maxRetries) {
          // Wait before retry with exponential backoff
          final delayMs = (100 * (1 << (attempt - 1))).clamp(100, 2000);
          await Future.delayed(Duration(milliseconds: delayMs));
        }
      }
    }

    // All attempts failed
    _reconnectionEvents.add('All connection attempts failed for $connectionId');

    // Schedule retry if auto-reconnect is enabled
    if (enableAutoReconnect) {
      _scheduleReconnection(connectionId, () async {
        return getSSHConnection(host, port, username, password,
            enableAutoReconnect: enableAutoReconnect,
            timeout: timeout,
            maxRetries: maxRetries);
      });
    }

    return null;
  }

  /// Get or create ADB connection
  Future<ADBClientManager?> getADBConnection(
    SavedADBDevice device, {
    bool enableAutoReconnect = true,
  }) async {
    final connectionId = 'adb:${device.host}:${device.port}';

    // Return existing healthy connection if available
    final existing = _connections[connectionId];
    if (existing != null &&
        existing.isHealthy &&
        existing.client is ADBClientManager) {
      existing.updateLastUsed();
      return existing.client as ADBClientManager;
    }

    try {
      final adbClient = ADBClientManager()..enableFlutterAdbBackend();

      bool connected = false;
      switch (device.connectionType) {
        case ADBConnectionType.wifi:
        case ADBConnectionType.custom:
          connected = await adbClient.connectWifi(device.host, device.port);
          break;
        case ADBConnectionType.usb:
          connected = await adbClient.connectUSB();
          break;
        case ADBConnectionType.pairing:
          // Handle pairing logic
          break;
      }

      if (!connected) {
        throw Exception('Failed to establish ADB connection');
      }

      // Create managed connection
      final managedConnection = ManagedConnection<ADBClientManager>(
        connectionId: connectionId,
        client: adbClient,
        metadata: {
          'device': device.toJson(),
          'type': 'adb',
        },
      );

      // Start health monitoring
      managedConnection.startHealthCheck(const Duration(seconds: 20));

      // Setup auto-reconnection if enabled
      if (enableAutoReconnect) {
        _setupAutoReconnection(connectionId, () async {
          return getADBConnection(device,
              enableAutoReconnect: enableAutoReconnect);
        });
      }

      _connections[connectionId] = managedConnection;
      return adbClient;
    } catch (e) {
      debugPrint('Failed to create ADB connection: $e');

      // Schedule retry if auto-reconnect is enabled
      if (enableAutoReconnect) {
        _scheduleReconnection(connectionId, () async {
          return getADBConnection(device,
              enableAutoReconnect: enableAutoReconnect);
        });
      }

      return null;
    }
  }

  /// Get connection quality metrics
  ConnectionQuality? getConnectionQuality(String connectionId) {
    return _connections[connectionId]?.quality;
  }

  /// Get quality stream for a connection
  Stream<ConnectionQuality>? getQualityStream(String connectionId) {
    return _connections[connectionId]?.qualityUpdates;
  }

  /// Setup auto-reconnection for a connection
  void _setupAutoReconnection(
      String connectionId, Future<dynamic> Function() reconnectFn) {
    // Monitor connection health
    _connections[connectionId]?.qualityUpdates.listen((quality) {
      if (quality.status == ConnectionHealthStatus.critical) {
        _scheduleReconnection(connectionId, reconnectFn);
      }
    });
  }

  /// Schedule reconnection attempt
  void _scheduleReconnection(
      String connectionId, Future<dynamic> Function() reconnectFn) {
    // Cancel existing timer
    _reconnectionTimers[connectionId]?.cancel();

    // Schedule exponential backoff retry
    var retryCount = 0;
    void attemptReconnection() {
      _reconnectionTimers[connectionId] = Timer(
        Duration(
            seconds: (1 << retryCount).clamp(
                1, 60)), // Exponential backoff: 1s, 2s, 4s, 8s, ..., max 60s
        () async {
          try {
            _reconnectionEvents.add(
                'Attempting to reconnect $connectionId (attempt ${retryCount + 1})');

            final result = await reconnectFn();
            if (result != null) {
              _reconnectionEvents.add('Successfully reconnected $connectionId');
              _reconnectionTimers.remove(connectionId);
            } else {
              retryCount++;
              if (retryCount < 10) {
                // Max 10 retry attempts
                attemptReconnection();
              } else {
                _reconnectionEvents
                    .add('Failed to reconnect $connectionId after 10 attempts');
                _reconnectionTimers.remove(connectionId);
              }
            }
          } catch (e) {
            retryCount++;
            if (retryCount < 10) {
              attemptReconnection();
            } else {
              _reconnectionEvents.add('Failed to reconnect $connectionId: $e');
              _reconnectionTimers.remove(connectionId);
            }
          }
        },
      );
    }

    attemptReconnection();
  }

  /// Close a specific connection
  void closeConnection(String connectionId) {
    final connection = _connections.remove(connectionId);
    _reconnectionTimers[connectionId]?.cancel();
    _reconnectionTimers.remove(connectionId);
    connection?.dispose();
  }

  /// Close all connections
  void closeAllConnections() {
    for (final connection in _connections.values) {
      connection.dispose();
    }
    _connections.clear();

    for (final timer in _reconnectionTimers.values) {
      timer.cancel();
    }
    _reconnectionTimers.clear();
  }

  /// Get connection statistics with enhanced information
  Map<String, dynamic> getConnectionStats() {
    final now = DateTime.now();
    final connections = _connections.entries.map((e) {
      final connection = e.value;
      final timeSinceLastUse = now.difference(connection.lastUsed);
      final circuitBreaker = _circuitBreakers[e.key];

      return {
        'id': e.key,
        'healthy': connection.isHealthy,
        'validated': connection.isValidated,
        'lastUsed': connection.lastUsed.toIso8601String(),
        'timeSinceLastUse':
            '${timeSinceLastUse.inMinutes}m ${timeSinceLastUse.inSeconds % 60}s',
        'quality': connection.quality?.qualityText ?? 'Unknown',
        'latency': connection.quality?.latencyMs,
        'adaptiveTimeout': connection.adaptiveTimeout.inSeconds,
        'consecutiveFailures': connection.consecutiveFailures,
        'circuitBreakerState': circuitBreaker?.state.name ?? 'unknown',
        'circuitBreakerFailures': circuitBreaker?.failureCount ?? 0,
        'metadata': connection.metadata,
      };
    }).toList();

    // Sort connections by priority (healthy, recently used, good quality)
    connections.sort((a, b) {
      // Prioritize healthy connections
      if (a['healthy'] != b['healthy']) {
        return (b['healthy'] as bool) ? 1 : -1;
      }

      // Then by recent usage
      final aLastUsed = DateTime.parse(a['lastUsed'] as String);
      final bLastUsed = DateTime.parse(b['lastUsed'] as String);
      return bLastUsed.compareTo(aLastUsed);
    });

    return {
      'totalConnections': _connections.length,
      'healthyConnections':
          _connections.values.where((c) => c.isHealthy).length,
      'validatedConnections':
          _connections.values.where((c) => c.isValidated).length,
      'activeReconnections': _reconnectionTimers.length,
      'networkState': _currentNetworkState.name,
      'circuitBreakersOpen': _circuitBreakers.values
          .where((cb) => cb.state == CircuitBreakerState.open)
          .length,
      'connections': connections,
    };
  }

  /// Force connection validation for all connections
  Future<void> validateAllConnections() async {
    _networkEvents.add('Validating all connections');

    final validationTasks = _connections.values.map((connection) async {
      try {
        await connection.validateConnection();
      } catch (e) {
        _reconnectionEvents
            .add('Validation failed for ${connection.connectionId}: $e');
      }
    });

    await Future.wait(validationTasks);
    _networkEvents.add('Connection validation completed');
  }

  /// Clean up stale connections
  void cleanupStaleConnections(
      {Duration maxIdleTime = const Duration(hours: 1)}) {
    final now = DateTime.now();
    final staleConnections = <String>[];

    for (final entry in _connections.entries) {
      final connection = entry.value;
      final timeSinceLastUse = now.difference(connection.lastUsed);

      if (timeSinceLastUse > maxIdleTime && !connection.isHealthy) {
        staleConnections.add(entry.key);
      }
    }

    for (final connectionId in staleConnections) {
      _reconnectionEvents.add('Cleaning up stale connection: $connectionId');
      closeConnection(connectionId);
    }
  }

  /// Dispose manager
  void dispose() {
    closeAllConnections();
    _connectivitySubscription?.cancel();
    _networkMonitorTimer?.cancel();
    _reconnectionEvents.close();
    _networkEvents.close();
  }
}
