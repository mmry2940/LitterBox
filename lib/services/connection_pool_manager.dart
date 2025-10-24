import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../adb_client.dart';
import '../models/saved_adb_device.dart';

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
  closed,    // Normal operation
  open,      // Blocking requests
  halfOpen,  // Testing if service is back
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
        final isValid = result.exitCode == 0;
        
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
        final backoffDelay = Duration(seconds: (consecutiveFailures * 30).clamp(30, 300));
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
        await ssh.run('true').timeout(const Duration(seconds: 10)); // Minimal command
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
      
      final connectivityResult = await Connectivity().checkConnectivity();
      switch (connectivityResult.first) {
        case ConnectivityResult.wifi:
        case ConnectivityResult.ethernet:
        case ConnectivityResult.mobile:
          return NetworkState.connected;
        case ConnectivityResult.none:
          return NetworkState.disconnected;
        default:
          return NetworkState.unknown;
      }
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
  ConnectionPoolManager._internal();

  final Map<String, ManagedConnection> _connections = {};
  final Map<String, Timer> _reconnectionTimers = {};
  final StreamController<String> _reconnectionEvents =
      StreamController.broadcast();

  Stream<String> get reconnectionEvents => _reconnectionEvents.stream;

  /// Get or create SSH connection
  Future<SSHClient?> getSSHConnection(
    String host,
    int port,
    String username,
    String password, {
    bool enableAutoReconnect = true,
    Duration? timeout,
  }) async {
    final connectionId = 'ssh:$username@$host:$port';

    // Return existing healthy connection if available
    final existing = _connections[connectionId];
    if (existing != null &&
        existing.isHealthy &&
        existing.client is SSHClient) {
      existing.updateLastUsed();
      return existing.client as SSHClient;
    }

    try {
      // Create new SSH connection
      final socket = await SSHSocket.connect(
        host,
        port,
        timeout: timeout ?? const Duration(seconds: 10),
      );

      final client = SSHClient(
        socket,
        username: username,
        onPasswordRequest: () => password,
      );

      // Create managed connection
      final managedConnection = ManagedConnection<SSHClient>(
        connectionId: connectionId,
        client: client,
        metadata: {
          'host': host,
          'port': port,
          'username': username,
          'type': 'ssh',
        },
      );

      // Start health monitoring
      managedConnection.startHealthCheck(const Duration(seconds: 30));

      // Setup auto-reconnection if enabled
      if (enableAutoReconnect) {
        _setupAutoReconnection(connectionId, () async {
          return getSSHConnection(host, port, username, password,
              enableAutoReconnect: enableAutoReconnect, timeout: timeout);
        });
      }

      _connections[connectionId] = managedConnection;
      return client;
    } catch (e) {
      debugPrint('Failed to create SSH connection: $e');

      // Schedule retry if auto-reconnect is enabled
      if (enableAutoReconnect) {
        _scheduleReconnection(connectionId, () async {
          return getSSHConnection(host, port, username, password,
              enableAutoReconnect: enableAutoReconnect, timeout: timeout);
        });
      }

      return null;
    }
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

  /// Get connection statistics
  Map<String, dynamic> getConnectionStats() {
    return {
      'totalConnections': _connections.length,
      'healthyConnections':
          _connections.values.where((c) => c.isHealthy).length,
      'activeReconnections': _reconnectionTimers.length,
      'connections': _connections.entries
          .map((e) => {
                'id': e.key,
                'healthy': e.value.isHealthy,
                'lastUsed': e.value.lastUsed.toIso8601String(),
                'quality': e.value.quality?.qualityText ?? 'Unknown',
                'metadata': e.value.metadata,
              })
          .toList(),
    };
  }

  /// Dispose manager
  void dispose() {
    closeAllConnections();
    _reconnectionEvents.close();
  }
}
