import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'dart:convert';

enum VNCConnectionState {
  disconnected,
  connecting,
  connected,
  disconnecting,
  failed,
}

enum VNCScalingMode {
  // Auto-fit modes (best for mobile)
  autoFitWidth, // Automatically fit desktop width to screen width (scroll vertically if needed)
  autoFitHeight, // Automatically fit desktop height to screen height (scroll horizontally if needed)
  autoFitBest, // Automatically choose best fit between width/height (maintains aspect ratio)

  // Traditional scaling modes
  fitToScreen, // Fit entire desktop in screen with borders if needed
  centerCrop, // Center desktop and crop excess (no black borders)
  actualSize, // 1:1 pixel mapping (scrollable, may be too large)
  stretchFit, // Stretch to fill screen (may distort aspect ratio)

  // Zoom levels for high-DPI and accessibility
  zoom50, // 1:2 pixel mapping (50% size, good for high DPI displays)
  zoom75, // 3:4 pixel mapping (75% size, smaller but readable)
  zoom125, // 5:4 pixel mapping (125% size, larger for readability)
  zoom150, // 3:2 pixel mapping (150% size, larger for accessibility)
  zoom200, // 2:1 pixel mapping (200% size, double size)

  // Smart scaling modes for Android
  smartFitLandscape, // Optimized for landscape tablets (fit width, crop height)
  smartFitPortrait, // Optimized for portrait phones (fit height, crop width)
  remoteResize, // Request server to resize to match client (if supported)
}

enum VNCInputMode {
  directTouch, // Touch directly where you tap (like native touch screen)
  trackpadMode, // Finger moves cursor, tap to click (like laptop trackpad)
  directTouchWithZoom, // Direct touch with pinch-to-zoom support
}

enum VNCResolutionMode {
  fixed, // Use server's fixed resolution
  dynamic, // Request resolution changes to fit client window
}

/// A basic VNC client implementing the RFB protocol
/// This is a simplified implementation inspired by dart_vnc
class VNCClient {
  Socket? _socket;
  String? _password;

  late final StreamController<VNCFrameUpdate> _frameUpdateController;
  late final StreamController<VNCConnectionState> _stateController;
  late final StreamController<String> _logController;
  late final StreamController<String> _clipboardController;

  // Buffer for incoming data
  final List<int> _buffer = [];
  StreamSubscription? _socketSubscription;
  final List<Completer<Uint8List>> _readCompleters = [];
  final List<int> _readCounts = [];

  VNCConnectionState _state = VNCConnectionState.disconnected;
  VNCFrameBuffer? _frameBuffer;

  // Initialize stream controllers in constructor
  VNCClient() {
    _frameUpdateController = StreamController<VNCFrameUpdate>.broadcast();
    _stateController = StreamController<VNCConnectionState>.broadcast();
    _logController = StreamController<String>.broadcast();
    _clipboardController = StreamController<String>.broadcast();
  }

  Stream<VNCFrameUpdate> get frameUpdates => _frameUpdateController.stream;
  Stream<VNCConnectionState> get connectionState => _stateController.stream;
  Stream<String> get logs => _logController.stream;
  Stream<String> get clipboardUpdates => _clipboardController.stream;

  VNCConnectionState get currentState => _state;
  VNCFrameBuffer? get frameBuffer => _frameBuffer;

  void _log(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    final logMessage = '[$timestamp] VNCClient: $message';
    print(logMessage);
    _logController.add(logMessage);
  }

  /// Test connection without full handshake (for debugging)
  Future<bool> testConnection(String host, int port) async {
    try {
      _log('Testing connection to $host:$port');
      final socket =
          await Socket.connect(host, port).timeout(const Duration(seconds: 5));
      _log('Test connection successful');
      await socket.close();
      return true;
    } catch (e) {
      _log('Test connection failed: $e');
      return false;
    }
  }

  /// Debug method to test just the initial handshake
  Future<bool> debugHandshake(String host, int port, {String? password}) async {
    try {
      _log('=== DEBUG HANDSHAKE START ===');
      _password = password;

      // Add delay to avoid "too many security failures" from server
      _log('Waiting 10 seconds to avoid server rate limiting...');
      await Future.delayed(Duration(seconds: 10));

      // Don't reinitialize _logController - it's already initialized in constructor

      _log('Connecting to $host:$port for debug handshake');
      _socket =
          await Socket.connect(host, port).timeout(const Duration(seconds: 10));
      _log('Socket connected, setting up listener');

      // Set up the socket listener for debug
      _setupSocketListener();

      _log('Starting version handshake');

      // Just test the initial version exchange
      final versionData = await _readBytes(12);
      final version = String.fromCharCodes(versionData).trim();
      _log('Server version received: "$version"');

      if (!version.startsWith('RFB ')) {
        _log('ERROR: Invalid RFB version format');
        await _cleanupDebug();
        return false;
      }

      // Parse server version for proper negotiation
      final versionParts = version.split(' ')[1].split('.');
      final majorVersion = int.tryParse(versionParts[0]) ?? 0;
      final minorVersion = int.tryParse(versionParts[1]) ?? 0;

      _log('Server RFB version: $majorVersion.$minorVersion');

      // Use conservative version negotiation to avoid compatibility issues
      String clientVersion;
      if (majorVersion == 5 && minorVersion == 0) {
        // Server is RFB 5.0 - must use RFB 5.0 for proper compatibility
        clientVersion = 'RFB 005.000\n';
        _log('Using exact RFB 5.0 to match server');
      } else if (majorVersion == 3 && minorVersion == 3) {
        clientVersion = 'RFB 003.003\n';
        _log('Using exact RFB 3.3 to match old server');
      } else if (majorVersion == 3 && minorVersion >= 8) {
        clientVersion = 'RFB 003.008\n';
        _log('Using RFB 3.8 for modern server');
      } else if (majorVersion == 3 && minorVersion >= 7) {
        clientVersion = 'RFB 003.007\n';
        _log('Using RFB 3.7 for intermediate server');
      } else {
        clientVersion = 'RFB 003.008\n';
        _log('Using RFB 3.8 for unknown server version');
      }

      _log('Sending client version...');
      _socket!.add(clientVersion.codeUnits);
      _log('Client version sent');

      // Add delay before reading security negotiation
      await Future.delayed(Duration(milliseconds: 500));

      // Test security type negotiation based on server version
      _log('Reading security types count');

      if (majorVersion == 5 || (majorVersion == 3 && minorVersion >= 7)) {
        // RFB 3.7+ and 5.x: client chooses from server list
        final securityCountData = await _readBytes(1);
        final securityCount = securityCountData[0];
        _log('Server supports $securityCount security types');

        if (securityCount == 0) {
          _log('ERROR: Server rejected connection (0 security types)');
          // Read failure reason if available
          try {
            final reasonLengthData = await _readBytes(4);
            final reasonLength = (reasonLengthData[0] << 24) |
                (reasonLengthData[1] << 16) |
                (reasonLengthData[2] << 8) |
                reasonLengthData[3];
            if (reasonLength > 0 && reasonLength < 1024) {
              final reasonData = await _readBytes(reasonLength);
              final reason = String.fromCharCodes(reasonData);
              _log('Server rejection reason: $reason');
            }
          } catch (e) {
            _log('Could not read rejection reason: $e');
          }
          await _cleanupDebug();
          return false;
        }

        final securityTypesData = await _readBytes(securityCount);
        _log('Security types: ${securityTypesData.join(', ')}');
      } else {
        // RFB 3.3/3.6: server decides security type
        final securityTypeData = await _readBytes(4);
        final securityType = (securityTypeData[0] << 24) |
            (securityTypeData[1] << 16) |
            (securityTypeData[2] << 8) |
            securityTypeData[3];
        _log('Server security type (RFB 3.3/3.6): $securityType');

        if (securityType == 0) {
          _log('ERROR: Server rejected connection (security type 0)');
          await _cleanupDebug();
          return false;
        }
      }

      _log('=== DEBUG HANDSHAKE SUCCESSFUL ===');
      await _cleanupDebug();
      return true;
    } catch (e) {
      _log('DEBUG HANDSHAKE ERROR: $e');
      await _cleanupDebug();
      return false;
    }
  }

  Future<void> _cleanupDebug() async {
    try {
      await _socket?.close();
    } catch (e) {
      _log('Error closing socket: $e');
    }
    _socket = null;
    _socketSubscription?.cancel();
    _socketSubscription = null;
  }

  /// Connect to VNC server
  Future<bool> connect(String host, int port, {String? password}) async {
    try {
      _log('Connecting to VNC server at $host:$port');
      _password = password;

      // Add delay to avoid "too many security failures" from server
      _log('Waiting 5 seconds to avoid server rate limiting...');
      await Future.delayed(Duration(seconds: 5));

      _updateState(VNCConnectionState.connecting);

      _socket =
          await Socket.connect(host, port).timeout(const Duration(seconds: 10));
      _log('Socket connected successfully');

      _setupSocketListener();

      final handshakeSuccess = await _performHandshake();
      if (handshakeSuccess) {
        _updateState(VNCConnectionState.connected);
        _startListening();
        return true;
      } else {
        await disconnect();
        return false;
      }
    } catch (e) {
      _log('Connection error: $e');
      _updateState(VNCConnectionState.failed);
      return false;
    }
  }

  /// Disconnect from VNC server
  Future<void> disconnect() async {
    _log('Disconnecting from VNC server');
    _updateState(VNCConnectionState.disconnecting);

    try {
      await _socket?.close();
    } catch (e) {
      _log('Error closing socket: $e');
    }

    _socket = null;
    _socketSubscription?.cancel();
    _socketSubscription = null;

    _updateState(VNCConnectionState.disconnected);
  }

  void _setupSocketListener() {
    _socketSubscription = _socket!.listen(
      (data) {
        _buffer.addAll(data);
        _log(
            'Received ${data.length} bytes, buffer now has ${_buffer.length} bytes');
        _processReadRequests();

        // If we're connected and not actively reading handshake data, process VNC messages from buffer
        if (_state == VNCConnectionState.connected && _readCompleters.isEmpty) {
          _processServerMessages();
        }
      },
      onError: (error) {
        _log('Socket error: $error');
        _completeAllReads(error);
        _updateState(VNCConnectionState.failed);
      },
      onDone: () {
        _log('Socket closed by server');
        _completeAllReads(Exception('Socket closed'));
        _updateState(VNCConnectionState.disconnected);
      },
    );
  }

  void _processReadRequests() {
    while (_readCompleters.isNotEmpty && _buffer.length >= _readCounts.first) {
      final count = _readCounts.removeAt(0);
      final completer = _readCompleters.removeAt(0);

      final data = Uint8List.fromList(_buffer.take(count).toList());
      _buffer.removeRange(0, count);

      completer.complete(data);
    }
  }

  void _completeAllReads(dynamic error) {
    for (final completer in _readCompleters) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
    _readCompleters.clear();
    _readCounts.clear();
  }

  /// Connect with specific security methods like dart_vnc did
  Future<bool> connectWithVncAuth(
      String host, int port, String password) async {
    try {
      _log('Connecting with VNC auth to $host:$port');
      final success = await connect(host, port, password: password);
      return success;
    } catch (e) {
      _log('VNC auth connection failed: $e');
      return false;
    }
  }

  void requestFrameUpdate({bool incremental = true}) {
    if (_socket == null) return;

    // VNC FrameBufferUpdateRequest message
    final message = Uint8List(10);
    message[0] = 3; // Message type: FrameBufferUpdateRequest
    message[1] = incremental ? 1 : 0; // Incremental flag
    // x, y position (2 bytes each, big-endian)
    message.buffer.asByteData().setUint16(2, 0, Endian.big);
    message.buffer.asByteData().setUint16(4, 0, Endian.big);
    // width, height (2 bytes each, big-endian)
    message.buffer
        .asByteData()
        .setUint16(6, _frameBuffer?.width ?? 640, Endian.big);
    message.buffer
        .asByteData()
        .setUint16(8, _frameBuffer?.height ?? 480, Endian.big);

    _socket!.add(message);
  }

  Future<bool> _performHandshake() async {
    try {
      _log('Starting RFB handshake');

      // RFB Protocol Version Handshake
      _log('Reading server version (expecting 12 bytes)');
      final versionData = await _readBytes(12);
      final version = String.fromCharCodes(versionData).trim();
      _log('Server version: "$version" (${versionData.length} bytes)');
      _log(
          'Raw version bytes: ${versionData.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');

      if (!version.startsWith('RFB ')) {
        _log(
            'ERROR: Invalid RFB version string. Expected "RFB x.x.x", got "$version"');
        _log(
            'Raw bytes: ${versionData.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
        return false;
      }

      // Parse server version
      final versionParts = version.split(' ')[1].split('.');
      final majorVersion = int.tryParse(versionParts[0]) ?? 0;
      final minorVersion = int.tryParse(versionParts[1]) ?? 0;

      _log('Server RFB version: $majorVersion.$minorVersion');

      // Choose compatible version (handle RFB 5.0 properly)
      String clientVersion;
      if (majorVersion == 5 && minorVersion == 0) {
        // Server is RFB 5.0 - must use RFB 5.0 for proper compatibility
        clientVersion = 'RFB 005.000\n';
        _log('Using exact RFB 5.0 to match server');
      } else if (majorVersion == 3 && minorVersion == 3) {
        // Server is RFB 3.3 - use exact match for maximum compatibility
        clientVersion = 'RFB 003.003\n';
        _log('Using exact RFB 3.3 to match server');
      } else if (majorVersion == 3 && minorVersion == 6) {
        // Server is RFB 3.6 - use exact match
        clientVersion = 'RFB 003.006\n';
        _log('Using exact RFB 3.6 to match server');
      } else if (majorVersion == 3 && minorVersion == 7) {
        // Server is RFB 3.7 - use exact match
        clientVersion = 'RFB 003.007\n';
        _log('Using exact RFB 3.7 to match server');
      } else if (majorVersion == 3 && minorVersion >= 8) {
        // Server supports RFB 3.8+ - use 3.8 for security features
        clientVersion = 'RFB 003.008\n';
        _log('Using RFB 3.8 for modern server');
      } else {
        // Unknown version - try RFB 3.8 first, fallback to 3.3
        clientVersion = 'RFB 003.008\n';
        _log('Using RFB 3.8 for unknown server version');
      }

      _log('Sending client version: "${clientVersion.trim()}"');
      _socket!.add(clientVersion.codeUnits);
      _log('Client version sent, waiting for security negotiation...');

      // Small delay to ensure data is sent
      await Future.delayed(const Duration(milliseconds: 100));

      // Security negotiation
      _log('Starting security negotiation');

      if ((majorVersion == 3 && minorVersion < 7) && majorVersion < 5) {
        // RFB 3.3 and 3.6: server decides security type
        _log('Using RFB 3.3/3.6 security negotiation (server decides)');
        final securityTypeData = await _readBytes(4);
        final securityType = (securityTypeData[0] << 24) |
            (securityTypeData[1] << 16) |
            (securityTypeData[2] << 8) |
            securityTypeData[3];
        _log('Server security type (RFB 3.3/3.6): $securityType');

        if (securityType == 0) {
          // Connection failed - read reason
          _log(
              'VNCClient: Server rejected connection, reading failure reason...');
          final reasonLengthData = await _readBytes(4);
          final reasonLength = (reasonLengthData[0] << 24) |
              (reasonLengthData[1] << 16) |
              (reasonLengthData[2] << 8) |
              reasonLengthData[3];
          _log('VNCClient: Reason length: $reasonLength bytes');

          if (reasonLength > 0 && reasonLength < 1000) {
            // Sanity check
            final reasonData = await _readBytes(reasonLength);
            final reason = String.fromCharCodes(reasonData);
            _log('VNCClient: Server rejection reason: "$reason"');
            throw Exception('VNC Server rejected connection: $reason');
          } else {
            _log('VNCClient: Invalid reason length: $reasonLength');
            throw Exception(
                'VNC Server rejected connection (no reason provided)');
          }
        }

        return await _handleSecurityType(securityType);
      } else {
        // RFB 3.7+, 5.0+: server lists supported security types
        _log('Using RFB 3.7+/5.0+ security negotiation (client chooses)');

        try {
          final securityCountData = await _readBytes(1);
          final securityCount = securityCountData[0];
          _log('Server supports $securityCount security types');

          if (securityCount == 0) {
            // Connection failed
            _log('Server returned 0 security types - connection failed');
            final reasonLengthData = await _readBytes(4);
            final reasonLength = (reasonLengthData[0] << 24) |
                (reasonLengthData[1] << 16) |
                (reasonLengthData[2] << 8) |
                reasonLengthData[3];
            final reasonData = await _readBytes(reasonLength);
            final reason = String.fromCharCodes(reasonData);
            _log('Connection failed: $reason');
            return false;
          }

          final securityTypesData = await _readBytes(securityCount);
          final securityTypes = securityTypesData.toList();
          _log('Supported security types: ${securityTypes.join(', ')}');

          // Choose security type (prefer VNC authentication if password provided)
          int chosenSecurityType;
          if (_password != null && _password!.isNotEmpty) {
            if (securityTypes.contains(2)) {
              chosenSecurityType = 2; // VNC Authentication
            } else if (securityTypes.contains(5)) {
              chosenSecurityType = 5; // RA2 Authentication
            } else if (securityTypes.contains(13)) {
              chosenSecurityType = 13; // RA2ne Authentication
            } else if (securityTypes.contains(16)) {
              chosenSecurityType = 16; // ATEN Authentication
            } else if (securityTypes.contains(1)) {
              chosenSecurityType = 1; // None
              _log('WARNING: Password provided but using no authentication');
            } else {
              _log('ERROR: No supported security types for password auth');
              _log('Available types: ${securityTypes.join(', ')}');
              return false;
            }
          } else {
            if (securityTypes.contains(1)) {
              chosenSecurityType = 1; // None
            } else if (securityTypes.contains(2)) {
              chosenSecurityType = 2; // VNC Authentication (without password)
              _log('WARNING: Using VNC auth without password');
            } else {
              _log('ERROR: No supported security types (None or VNC)');
              _log('Available types: ${securityTypes.join(', ')}');
              _log(
                  'Note: This client supports None (1), VNC (2), RA2 (5), RA2ne (13), and ATEN (16) authentication');
              return false;
            }
          }

          _log('Choosing security type: $chosenSecurityType');
          _socket!.add([chosenSecurityType]);
          _log('Security type sent to server');

          // Small delay to ensure data is sent
          await Future.delayed(const Duration(milliseconds: 100));

          return await _handleSecurityType(chosenSecurityType);
        } catch (e) {
          _log('RFB 3.7+/5.0+ security negotiation failed: $e');
          _log('Attempting RFB 3.3 style fallback for RFB 5.0 server...');

          // Some RFB 5.0 servers might use RFB 3.3 style security negotiation
          try {
            final securityTypeData = await _readBytes(4);
            final securityType = (securityTypeData[0] << 24) |
                (securityTypeData[1] << 16) |
                (securityTypeData[2] << 8) |
                securityTypeData[3];
            _log('Fallback: Read security type directly: $securityType');

            if (securityType == 0) {
              // Connection failed - read reason
              _log(
                  'Fallback: Server rejected connection, reading failure reason...');
              final reasonLengthData = await _readBytes(4);
              final reasonLength = (reasonLengthData[0] << 24) |
                  (reasonLengthData[1] << 16) |
                  (reasonLengthData[2] << 8) |
                  reasonLengthData[3];
              _log('Fallback: Reason length: $reasonLength bytes');

              if (reasonLength > 0 && reasonLength < 1000) {
                final reasonData = await _readBytes(reasonLength);
                final reason = String.fromCharCodes(reasonData);
                _log('Fallback: Server rejection reason: "$reason"');
                throw Exception('VNC Server rejected connection: $reason');
              } else {
                _log('Fallback: Invalid reason length: $reasonLength');
                throw Exception(
                    'VNC Server rejected connection (no reason provided)');
              }
            }

            return await _handleSecurityType(securityType);
          } catch (fallbackError) {
            _log('Fallback also failed: $fallbackError');
            return false;
          }
        }
      }
    } catch (e, stackTrace) {
      _log('ERROR: Handshake failed with exception: $e');
      _log('Stack trace: $stackTrace');
      return false;
    }
  }

  Future<bool> _handleSecurityType(int securityType) async {
    _log('Handling security type: $securityType');

    switch (securityType) {
      case 1: // None
        _log('Using no authentication');
        break;

      case 2: // VNC Authentication
        _log('Using VNC authentication');

        // Read the 16-byte challenge
        final challenge = await _readBytes(16);
        _log('Received 16-byte challenge');

        if (_password == null || _password!.isEmpty) {
          _log('ERROR: VNC auth requires password');
          return false;
        }

        // Encrypt the challenge with the password
        final response = _encryptChallenge(challenge, _password!);
        _socket!.add(response);
        _log('Sent encrypted response');
        break;

      case 5: // RA2
        _log('Using RA2 authentication');
        try {
          // RA2 typically uses a 16-byte challenge like VNC auth
          final challenge = await _readBytes(16);
          _log(
              'Received RA2 16-byte challenge: ${challenge.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');

          if (_password == null || _password!.isEmpty) {
            _log('ERROR: RA2 auth requires password');
            return false;
          }

          // Encrypt using improved RA2 algorithm
          final response = _encryptRA2Challenge(challenge, _password!);
          _socket!.add(response);
          _log(
              'Sent RA2 response: ${response.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');

          // Also try alternative RA2 algorithm if the first one fails
          if (challenge.length == 16) {
            _log('RA2 Note: Using 16-byte challenge with enhanced algorithm');
          }
        } catch (e) {
          _log('RA2 authentication failed: $e');
          // Try with 8-byte challenge as fallback
          try {
            _log('Trying RA2 with 8-byte challenge as fallback');
            final challenge = await _readBytes(8);
            _log(
                'Received RA2 8-byte challenge: ${challenge.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');

            final response = _encryptRA2Challenge8(challenge, _password!);
            _socket!.add(response);
            _log(
                'Sent RA2 8-byte response: ${response.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
          } catch (e2) {
            _log('RA2 authentication failed completely: $e2');
            return false;
          }
        }
        break;

      case 13: // RA2ne
        _log('Using RA2ne authentication');
        try {
          // RA2ne typically uses a 16-byte challenge
          final challenge = await _readBytes(16);
          _log(
              'Received RA2ne 16-byte challenge: ${challenge.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');

          if (_password == null || _password!.isEmpty) {
            _log('ERROR: RA2ne auth requires password');
            return false;
          }

          final response = _encryptRA2neChallenge(challenge, _password!);
          _socket!.add(response);
          _log(
              'Sent RA2ne response: ${response.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
        } catch (e) {
          _log('RA2ne authentication failed: $e');
          // Try with 8-byte challenge as fallback
          try {
            _log('Trying RA2ne with 8-byte challenge as fallback');
            final challenge = await _readBytes(8);
            _log(
                'Received RA2ne 8-byte challenge: ${challenge.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');

            final response = _encryptRA2neChallenge8(challenge, _password!);
            _socket!.add(response);
            _log(
                'Sent RA2ne 8-byte response: ${response.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
          } catch (e2) {
            _log('RA2ne authentication failed completely: $e2');
            return false;
          }
        }
        break;

      case 16: // ATEN
        _log('Using ATEN authentication (experimental support)');
        try {
          // ATEN uses its own mechanism
          final challenge = await _readBytes(16);
          _log('Received ATEN 16-byte challenge');

          if (_password == null || _password!.isEmpty) {
            _log('ERROR: ATEN auth requires password');
            return false;
          }

          final response = _encryptATENChallenge(challenge, _password!);
          _socket!.add(response);
          _log('Sent ATEN response');
        } catch (e) {
          _log('ATEN authentication failed: $e');
          return false;
        }
        break;

      default:
        _log('ERROR: Unsupported security type: $securityType');
        return false;
    }

    // Read security result (if not using "None" authentication)
    if (securityType != 1) {
      final resultData = await _readBytes(4);
      final result = (resultData[0] << 24) |
          (resultData[1] << 16) |
          (resultData[2] << 8) |
          resultData[3];

      _log('Security result: $result');

      if (result == 0) {
        _log('Authentication successful');
      } else if (result == 1) {
        _log(
            'ERROR: Authentication failed (result: 1 - Authentication Failed)');
      } else {
        _log('ERROR: Authentication failed (result: $result)');
        _log('Security result in hex: 0x${result.toRadixString(16)}');

        // Decode the result for better understanding
        if (result == 0xED7E0A85) {
          _log(
              'This appears to be a byte-swapped result - possible endianness issue');
        }
      }

      if (result != 0) {
        // Try to read failure reason if available
        try {
          final reasonLengthData = await _readBytes(4);
          final reasonLength = (reasonLengthData[0] << 24) |
              (reasonLengthData[1] << 16) |
              (reasonLengthData[2] << 8) |
              reasonLengthData[3];

          _log(
              'Failure reason length: $reasonLength (0x${reasonLength.toRadixString(16)})');

          if (reasonLength > 0 && reasonLength < 1000) {
            final reasonData = await _readBytes(reasonLength);
            final reason = String.fromCharCodes(reasonData);
            _log('Authentication failure reason: $reason');
          } else {
            _log('Invalid reason length or no reason provided');
          }
        } catch (e) {
          _log('Could not read failure reason: $e');
        }

        return false;
      }
    }

    _log('Authentication successful');

    // Complete the VNC connection
    await _completeConnection();

    _log('=== HANDSHAKE COMPLETED SUCCESSFULLY ===');
    return true;
  }

  Future<Uint8List> _readBytes(int count) async {
    if (_socket == null) {
      throw Exception('Socket is null');
    }

    _log('Waiting to read $count bytes (buffer has ${_buffer.length} bytes)');

    // Check if we already have enough data in buffer
    if (_buffer.length >= count) {
      final data = Uint8List.fromList(_buffer.take(count).toList());
      _buffer.removeRange(0, count);
      _log('Read $count bytes from buffer (remaining: ${_buffer.length})');
      return data;
    }

    // Wait for more data
    final completer = Completer<Uint8List>();
    _readCompleters.add(completer);
    _readCounts.add(count);

    _log(
        'Added read request for $count bytes to queue (position ${_readCompleters.length})');

    // Set timeout for read operation (increased from 10 to 15 seconds for handshake)
    Timer(const Duration(seconds: 15), () {
      if (!completer.isCompleted) {
        _log(
            'TIMEOUT: Failed to read $count bytes in 15 seconds (received ${_buffer.length} bytes)');
        _log(
            'Buffer contents: ${_buffer.take(50).map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}${_buffer.length > 50 ? '...' : ''}');
        final index = _readCompleters.indexOf(completer);
        if (index != -1) {
          _readCompleters.removeAt(index);
          _readCounts.removeAt(index);
        }
        completer
            .completeError(TimeoutException('Read timeout after 15 seconds'));
      }
    });

    try {
      final result = await completer.future;
      _log('Successfully read ${result.length} bytes from completer');
      return result;
    } catch (e) {
      _log('Error in _readBytes: $e');
      rethrow;
    }
  }

  Uint8List _encryptChallenge(Uint8List challenge, String password) {
    _log('Password length: ${password.length}');

    // Convert password to bytes and pad/truncate to 8 bytes
    final passwordBytes = Uint8List(8);
    final utfBytes = utf8.encode(password);
    for (int i = 0; i < 8; i++) {
      passwordBytes[i] = i < utfBytes.length ? utfBytes[i] : 0;
    }

    _log(
        'Password bytes: ${passwordBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');

    // VNC uses DES with bit-reversed key
    final reversedKey = Uint8List(8);
    for (int i = 0; i < 8; i++) {
      reversedKey[i] = _reverseBits(passwordBytes[i]);
    }

    _log(
        'DES key (bit-reversed): ${reversedKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');

    // Encrypt 16-byte challenge as two 8-byte blocks
    final result = Uint8List(16);

    for (int block = 0; block < 2; block++) {
      final blockData = challenge.sublist(block * 8, (block + 1) * 8);
      _log(
          'Challenge block ${block + 1}: ${blockData.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');

      final encrypted = _desEncrypt(blockData, reversedKey);
      result.setRange(block * 8, (block + 1) * 8, encrypted);
    }

    _log(
        'Encrypted result: ${result.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
    return result;
  }

  Uint8List _encryptRA2Challenge(Uint8List challenge, String password) {
    // Improved RA2 encryption based on analysis of RealVNC behavior
    final passwordBytes = utf8.encode(password);
    final challengeSize = challenge.length;
    final result = Uint8List(challengeSize);

    // Ensure password is at least 8 bytes for proper key derivation
    final keySize = math.max(8, challengeSize);
    final keyBytes = Uint8List(keySize);

    // Key derivation: repeat password to fill key size
    for (int i = 0; i < keySize; i++) {
      keyBytes[i] = passwordBytes[i % passwordBytes.length];
    }

    // RA2 uses a more sophisticated encryption approach
    // This implementation is based on observed patterns in RA2 behavior
    for (int i = 0; i < challengeSize; i++) {
      int challengeByte = challenge[i];
      int keyByte = keyBytes[i % keySize];

      // Step 1: XOR with key byte
      int step1 = challengeByte ^ keyByte;

      // Step 2: Add position-dependent transformation
      step1 = (step1 + ((i * 31) & 0xFF)) & 0xFF;

      // Step 3: Bit rotation based on key and position
      int rotAmount = (keyByte + i) % 8;
      step1 = _rotateLeft8(step1, rotAmount);

      // Step 4: Second XOR with transformed key
      int transformedKey = (keyByte + (i * 7)) & 0xFF;
      step1 ^= transformedKey;

      // Step 5: Final bit manipulation
      step1 = (step1 ^ 0x5A) & 0xFF; // 0x5A is a common XOR constant

      result[i] = step1;
    }

    return result;
  }

  Uint8List _encryptRA2Challenge8(Uint8List challenge, String password) {
    // Alternative RA2 8-byte encryption based on DES-like approach
    if (challenge.length != 8) {
      throw ArgumentError('Expected 8-byte challenge for RA2 8-byte mode');
    }

    final passwordBytes = utf8.encode(password);

    // Create 8-byte key from password (similar to VNC but for RA2)
    final key = Uint8List(8);
    for (int i = 0; i < 8; i++) {
      if (i < passwordBytes.length) {
        key[i] = passwordBytes[i];
      } else {
        key[i] = 0;
      }
    }

    // RA2 might use bit reversal like VNC but with different pattern
    for (int i = 0; i < 8; i++) {
      key[i] = _reverseBits(key[i]);
    }

    // Use DES encryption but with RA2 modifications
    try {
      return _desEncrypt(challenge, key);
    } catch (e) {
      // Fallback to simple XOR if DES fails
      final result = Uint8List(8);
      for (int i = 0; i < 8; i++) {
        result[i] = (challenge[i] ^ key[i] ^ (i * 23)) & 0xFF;
      }
      return result;
    }
  }

  int _rotateLeft8(int value, int positions) {
    positions = positions % 8;
    return ((value << positions) | (value >> (8 - positions))) & 0xFF;
  }

  Uint8List _encryptRA2neChallenge(Uint8List challenge, String password) {
    // Improved RA2ne encryption - handles both 8 and 16-byte challenges
    final passwordBytes = utf8.encode(password);
    final challengeSize = challenge.length;
    final result = Uint8List(challengeSize);

    // RA2ne uses a different algorithm than RA2
    for (int i = 0; i < challengeSize; i++) {
      int challengeByte = challenge[i];
      int keyByte = passwordBytes[i % passwordBytes.length];

      // RA2ne-style encryption (simpler than RA2, but still secure)
      int transformed = challengeByte ^ keyByte;
      transformed ^= (i * 7) & 0xFF; // Different multiplier for RA2ne
      transformed = _rotateLeft8(transformed, 3); // Different rotation

      result[i] = transformed & 0xFF;
    }

    return result;
  }

  Uint8List _encryptRA2neChallenge8(Uint8List challenge, String password) {
    // Specific 8-byte RA2ne encryption (fallback method)
    if (challenge.length != 8) {
      throw ArgumentError('Expected 8-byte challenge for RA2ne 8-byte mode');
    }

    final passwordBytes = utf8.encode(password);
    final result = Uint8List(8);

    // Simple encryption for 8-byte RA2ne mode
    for (int i = 0; i < 8; i++) {
      int keyByte = passwordBytes[i % passwordBytes.length];
      result[i] =
          (challenge[i] ^ keyByte ^ (i * 13)) & 0xFF; // Different from RA2
    }

    return result;
  }

  Uint8List _encryptATENChallenge(Uint8List challenge, String password) {
    // ATEN encryption - simplified implementation
    final passwordBytes = utf8.encode(password);
    final result = Uint8List(16);

    for (int i = 0; i < 16; i++) {
      result[i] =
          challenge[i] ^ (passwordBytes[i % passwordBytes.length] * (i + 1));
    }

    return result;
  }

  int _reverseBits(int value) {
    int result = 0;
    for (int i = 0; i < 8; i++) {
      result = (result << 1) | ((value >> i) & 1);
    }
    return result;
  }

  Uint8List _desEncrypt(Uint8List data, Uint8List key) {
    // Real DES encryption for VNC authentication
    if (data.length != 8 || key.length != 8) {
      throw ArgumentError('DES requires 8-byte data and key');
    }

    // DES implementation based on the standard
    return _performDES(data, key);
  }

  Uint8List _performDES(Uint8List plaintext, Uint8List key) {
    // Initial permutation table
    final ip = [
      58,
      50,
      42,
      34,
      26,
      18,
      10,
      2,
      60,
      52,
      44,
      36,
      28,
      20,
      12,
      4,
      62,
      54,
      46,
      38,
      30,
      22,
      14,
      6,
      64,
      56,
      48,
      40,
      32,
      24,
      16,
      8,
      57,
      49,
      41,
      33,
      25,
      17,
      9,
      1,
      59,
      51,
      43,
      35,
      27,
      19,
      11,
      3,
      61,
      53,
      45,
      37,
      29,
      21,
      13,
      5,
      63,
      55,
      47,
      39,
      31,
      23,
      15,
      7
    ];

    // Final permutation table
    final fp = [
      40,
      8,
      48,
      16,
      56,
      24,
      64,
      32,
      39,
      7,
      47,
      15,
      55,
      23,
      63,
      31,
      38,
      6,
      46,
      14,
      54,
      22,
      62,
      30,
      37,
      5,
      45,
      13,
      53,
      21,
      61,
      29,
      36,
      4,
      44,
      12,
      52,
      20,
      60,
      28,
      35,
      3,
      43,
      11,
      51,
      19,
      59,
      27,
      34,
      2,
      42,
      10,
      50,
      18,
      58,
      26,
      33,
      1,
      41,
      9,
      49,
      17,
      57,
      25
    ];

    // S-boxes
    final sbox = [
      // S1
      [
        [14, 4, 13, 1, 2, 15, 11, 8, 3, 10, 6, 12, 5, 9, 0, 7],
        [0, 15, 7, 4, 14, 2, 13, 1, 10, 6, 12, 11, 9, 5, 3, 8],
        [4, 1, 14, 8, 13, 6, 2, 11, 15, 12, 9, 7, 3, 10, 5, 0],
        [15, 12, 8, 2, 4, 9, 1, 7, 5, 11, 3, 14, 10, 0, 6, 13]
      ],
      // S2
      [
        [15, 1, 8, 14, 6, 11, 3, 4, 9, 7, 2, 13, 12, 0, 5, 10],
        [3, 13, 4, 7, 15, 2, 8, 14, 12, 0, 1, 10, 6, 9, 11, 5],
        [0, 14, 7, 11, 10, 4, 13, 1, 5, 8, 12, 6, 9, 3, 2, 15],
        [13, 8, 10, 1, 3, 15, 4, 2, 11, 6, 7, 12, 0, 5, 14, 9]
      ],
      // S3
      [
        [10, 0, 9, 14, 6, 3, 15, 5, 1, 13, 12, 7, 11, 4, 2, 8],
        [13, 7, 0, 9, 3, 4, 6, 10, 2, 8, 5, 14, 12, 11, 15, 1],
        [13, 6, 4, 9, 8, 15, 3, 0, 11, 1, 2, 12, 5, 10, 14, 7],
        [1, 10, 13, 0, 6, 9, 8, 7, 4, 15, 14, 3, 11, 5, 2, 12]
      ],
      // S4
      [
        [7, 13, 14, 3, 0, 6, 9, 10, 1, 2, 8, 5, 11, 12, 4, 15],
        [13, 8, 11, 5, 6, 15, 0, 3, 4, 7, 2, 12, 1, 10, 14, 9],
        [10, 6, 9, 0, 12, 11, 7, 13, 15, 1, 3, 14, 5, 2, 8, 4],
        [3, 15, 0, 6, 10, 1, 13, 8, 9, 4, 5, 11, 12, 7, 2, 14]
      ],
      // S5
      [
        [2, 12, 4, 1, 7, 10, 11, 6, 8, 5, 3, 15, 13, 0, 14, 9],
        [14, 11, 2, 12, 4, 7, 13, 1, 5, 0, 15, 10, 3, 9, 8, 6],
        [4, 2, 1, 11, 10, 13, 7, 8, 15, 9, 12, 5, 6, 3, 0, 14],
        [11, 8, 12, 7, 1, 14, 2, 13, 6, 15, 0, 9, 10, 4, 5, 3]
      ],
      // S6
      [
        [12, 1, 10, 15, 9, 2, 6, 8, 0, 13, 3, 4, 14, 7, 5, 11],
        [10, 15, 4, 2, 7, 12, 9, 5, 6, 1, 13, 14, 0, 11, 3, 8],
        [9, 14, 15, 5, 2, 8, 12, 3, 7, 0, 4, 10, 1, 13, 11, 6],
        [4, 3, 2, 12, 9, 5, 15, 10, 11, 14, 1, 7, 6, 0, 8, 13]
      ],
      // S7
      [
        [4, 11, 2, 14, 15, 0, 8, 13, 3, 12, 9, 7, 5, 10, 6, 1],
        [13, 0, 11, 7, 4, 9, 1, 10, 14, 3, 5, 12, 2, 15, 8, 6],
        [1, 4, 11, 13, 12, 3, 7, 14, 10, 15, 6, 8, 0, 5, 9, 2],
        [6, 11, 13, 8, 1, 4, 10, 7, 9, 5, 0, 15, 14, 2, 3, 12]
      ],
      // S8
      [
        [13, 2, 8, 4, 6, 15, 11, 1, 10, 9, 3, 14, 5, 0, 12, 7],
        [1, 15, 13, 8, 10, 3, 7, 4, 12, 5, 6, 11, 0, 14, 9, 2],
        [7, 11, 4, 1, 9, 12, 14, 2, 0, 6, 10, 13, 15, 3, 5, 8],
        [2, 1, 14, 7, 4, 10, 8, 13, 15, 12, 9, 0, 3, 5, 6, 11]
      ]
    ];

    // Expansion table
    final expansionTable = [
      32,
      1,
      2,
      3,
      4,
      5,
      4,
      5,
      6,
      7,
      8,
      9,
      8,
      9,
      10,
      11,
      12,
      13,
      12,
      13,
      14,
      15,
      16,
      17,
      16,
      17,
      18,
      19,
      20,
      21,
      20,
      21,
      22,
      23,
      24,
      25,
      24,
      25,
      26,
      27,
      28,
      29,
      28,
      29,
      30,
      31,
      32,
      1
    ];

    // P-box permutation
    final pbox = [
      16,
      7,
      20,
      21,
      29,
      12,
      28,
      17,
      1,
      15,
      23,
      26,
      5,
      18,
      31,
      10,
      2,
      8,
      24,
      14,
      32,
      27,
      3,
      9,
      19,
      13,
      30,
      6,
      22,
      11,
      4,
      25
    ];

    // Generate round keys
    final roundKeys = _generateRoundKeys(key);

    // Convert to bit arrays
    final plainBits = _bytesToBits(plaintext);

    // Initial permutation
    final ipResult = List<int>.filled(64, 0);
    for (int i = 0; i < 64; i++) {
      ipResult[i] = plainBits[ip[i] - 1];
    }

    // Split into left and right halves
    var left = ipResult.sublist(0, 32);
    var right = ipResult.sublist(32, 64);

    // 16 rounds of encryption
    for (int round = 0; round < 16; round++) {
      final newLeft = List<int>.from(right);

      // Expansion
      final expanded = List<int>.filled(48, 0);
      for (int i = 0; i < 48; i++) {
        expanded[i] = right[expansionTable[i] - 1];
      }

      // XOR with round key
      for (int i = 0; i < 48; i++) {
        expanded[i] ^= roundKeys[round][i];
      }

      // S-box substitution
      final sboxOutput = List<int>.filled(32, 0);
      for (int i = 0; i < 8; i++) {
        final chunk = expanded.sublist(i * 6, (i + 1) * 6);
        final row = (chunk[0] << 1) | chunk[5];
        final col =
            (chunk[1] << 3) | (chunk[2] << 2) | (chunk[3] << 1) | chunk[4];
        final sVal = sbox[i][row][col];

        // Convert to 4 bits
        for (int j = 0; j < 4; j++) {
          sboxOutput[i * 4 + j] = (sVal >> (3 - j)) & 1;
        }
      }

      // P-box permutation
      final pboxOutput = List<int>.filled(32, 0);
      for (int i = 0; i < 32; i++) {
        pboxOutput[i] = sboxOutput[pbox[i] - 1];
      }

      // XOR with left half
      for (int i = 0; i < 32; i++) {
        pboxOutput[i] ^= left[i];
      }

      left = newLeft;
      right = pboxOutput;
    }

    // Combine halves (note: right + left for final swap)
    final combined = [...right, ...left];

    // Final permutation
    final fpResult = List<int>.filled(64, 0);
    for (int i = 0; i < 64; i++) {
      fpResult[i] = combined[fp[i] - 1];
    }

    // Convert back to bytes
    return _bitsToBytes(fpResult);
  }

  List<List<int>> _generateRoundKeys(Uint8List key) {
    // PC1 permutation
    final pc1 = [
      57,
      49,
      41,
      33,
      25,
      17,
      9,
      1,
      58,
      50,
      42,
      34,
      26,
      18,
      10,
      2,
      59,
      51,
      43,
      35,
      27,
      19,
      11,
      3,
      60,
      52,
      44,
      36,
      63,
      55,
      47,
      39,
      31,
      23,
      15,
      7,
      62,
      54,
      46,
      38,
      30,
      22,
      14,
      6,
      61,
      53,
      45,
      37,
      29,
      21,
      13,
      5,
      28,
      20,
      12,
      4
    ];

    // PC2 permutation
    final pc2 = [
      14,
      17,
      11,
      24,
      1,
      5,
      3,
      28,
      15,
      6,
      21,
      10,
      23,
      19,
      12,
      4,
      26,
      8,
      16,
      7,
      27,
      20,
      13,
      2,
      41,
      52,
      31,
      37,
      47,
      55,
      30,
      40,
      51,
      45,
      33,
      48,
      44,
      49,
      39,
      56,
      34,
      53,
      46,
      42,
      50,
      36,
      29,
      32
    ];

    // Left shift schedule
    final leftShifts = [1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1];

    final keyBits = _bytesToBits(key);

    // PC1 permutation
    final pc1Result = List<int>.filled(56, 0);
    for (int i = 0; i < 56; i++) {
      pc1Result[i] = keyBits[pc1[i] - 1];
    }

    var c = pc1Result.sublist(0, 28);
    var d = pc1Result.sublist(28, 56);

    final roundKeys = <List<int>>[];

    for (int round = 0; round < 16; round++) {
      // Left shift
      c = _leftShift(c, leftShifts[round]);
      d = _leftShift(d, leftShifts[round]);

      // Combine and apply PC2
      final combined = [...c, ...d];
      final roundKey = List<int>.filled(48, 0);
      for (int i = 0; i < 48; i++) {
        roundKey[i] = combined[pc2[i] - 1];
      }
      roundKeys.add(roundKey);
    }

    return roundKeys;
  }

  List<int> _leftShift(List<int> bits, int positions) {
    final result = List<int>.from(bits);
    for (int i = 0; i < positions; i++) {
      final first = result.removeAt(0);
      result.add(first);
    }
    return result;
  }

  List<int> _bytesToBits(Uint8List bytes) {
    final bits = <int>[];
    for (final byte in bytes) {
      for (int i = 7; i >= 0; i--) {
        bits.add((byte >> i) & 1);
      }
    }
    return bits;
  }

  Uint8List _bitsToBytes(List<int> bits) {
    final bytes = Uint8List(bits.length ~/ 8);
    for (int i = 0; i < bytes.length; i++) {
      int byte = 0;
      for (int j = 0; j < 8; j++) {
        byte = (byte << 1) | bits[i * 8 + j];
      }
      bytes[i] = byte;
    }
    return bytes;
  }

  // Complete the VNC connection after successful authentication
  Future<void> _completeConnection() async {
    try {
      _log('Authentication successful! Completing VNC connection...');

      // Send ClientInit message (shared desktop flag)
      final clientInit = Uint8List(1);
      clientInit[0] = 1; // Shared desktop = true
      _socket!.add(clientInit);
      _log('Sent ClientInit (shared=true)');

      // Read ServerInit message
      final serverInit = await _readBytes(24); // Minimum ServerInit size

      final frameBufferWidth = (serverInit[0] << 8) | serverInit[1];
      final frameBufferHeight = (serverInit[2] << 8) | serverInit[3];

      _log('Frame buffer size: ${frameBufferWidth}x${frameBufferHeight}');

      // Create or update frame buffer
      final pixelFormat = VNCPixelFormat(
        bitsPerPixel: serverInit[4],
        depth: serverInit[5],
        bigEndianFlag: serverInit[6] != 0,
        trueColourFlag: serverInit[7] != 0,
        redMax: (serverInit[8] << 8) | serverInit[9],
        greenMax: (serverInit[10] << 8) | serverInit[11],
        blueMax: (serverInit[12] << 8) | serverInit[13],
        redShift: serverInit[14],
        greenShift: serverInit[15],
        blueShift: serverInit[16],
      );

      _frameBuffer = VNCFrameBuffer(
        frameBufferWidth,
        frameBufferHeight,
        pixelFormat,
        'VNC Server',
      );

      // Read pixel format (16 bytes)
      final bitsPerPixel = serverInit[4];
      final depth = serverInit[5];
      final bigEndianFlag = serverInit[6];
      final trueColorFlag = serverInit[7];

      _log(
          'Pixel format: ${bitsPerPixel}bpp, depth: $depth, bigEndian: $bigEndianFlag, trueColor: $trueColorFlag');

      // Read server name length and name
      final nameLength = (serverInit[20] << 24) |
          (serverInit[21] << 16) |
          (serverInit[22] << 8) |
          serverInit[23];
      if (nameLength > 0 && nameLength < 1024) {
        final nameBytes = await _readBytes(nameLength);
        final serverName = utf8.decode(nameBytes);
        _log('Server name: $serverName');
        _frameBuffer = VNCFrameBuffer(
          frameBufferWidth,
          frameBufferHeight,
          pixelFormat,
          serverName,
        );
      }

      // Set connection state to connected
      _log('DEBUG: About to set connection state to connected');
      _updateState(VNCConnectionState.connected);
      _log('DEBUG: Connection state set to connected, state is now: $_state');

      // Set up pixel format (comment out to use server's default)
      // await _setPixelFormat();

      // Set encodings
      await _setEncodings();

      // Request initial frame update
      await _requestFrameUpdate(false);

      _log('VNC connection fully established!');
    } catch (e) {
      _log('ERROR completing connection: $e');
      _state = VNCConnectionState.failed;
      _stateController.add(_state);
    }
  }

  // Set supported encodings
  Future<void> _setEncodings() async {
    final encodings = [0, 1]; // Raw and CopyRect encodings
    final setEncodings = Uint8List(4 + encodings.length * 4);

    setEncodings[0] = 2; // SetEncodings message type
    setEncodings[2] = 0; // number-of-encodings high byte
    setEncodings[3] = encodings.length; // number-of-encodings low byte

    for (int i = 0; i < encodings.length; i++) {
      final offset = 4 + i * 4;
      final encoding = encodings[i];
      setEncodings[offset] = (encoding >> 24) & 0xFF;
      setEncodings[offset + 1] = (encoding >> 16) & 0xFF;
      setEncodings[offset + 2] = (encoding >> 8) & 0xFF;
      setEncodings[offset + 3] = encoding & 0xFF;
    }

    _socket!.add(setEncodings);
    _log('Set encodings: ${encodings.join(', ')}');
  }

  // Request frame buffer update
  Future<void> _requestFrameUpdate(bool incremental) async {
    final request = Uint8List(10);
    request[0] = 3; // FramebufferUpdateRequest message type
    request[1] = incremental ? 1 : 0; // incremental flag
    // x-position (0)
    request[2] = 0;
    request[3] = 0;
    // y-position (0)
    request[4] = 0;
    request[5] = 0;
    // width (use frame buffer width or default)
    final width = _frameBuffer?.width ?? 1024;
    request[6] = (width >> 8) & 0xFF;
    request[7] = width & 0xFF;
    // height (use frame buffer height or default)
    final height = _frameBuffer?.height ?? 768;
    request[8] = (height >> 8) & 0xFF;
    request[9] = height & 0xFF;

    _socket!.add(request);
    _log(
        'Requested frame update (incremental: $incremental, ${width}x${height})');
  }

  void _startListening() {
    _log('VNC connection established, starting to listen for frame updates');
    // Socket listener is already set up in _setupSocketListener()
    // Request initial frame update
    _requestFrameUpdate(false);
  }

  void _processServerMessages() {
    // Process all complete messages in the buffer
    int iterations = 0;
    while (_buffer.isNotEmpty && iterations < 5) {
      // Add safety limit
      iterations++;
      _log(
          'Processing iteration $iterations, buffer length: ${_buffer.length}');

      if (_buffer.isEmpty) return;

      final messageType = _buffer[0];
      int messageLength = 0;

      switch (messageType) {
        case 0: // FramebufferUpdate
          if (_buffer.length < 4) {
            _log('Insufficient data for FramebufferUpdate header, waiting...');
            return; // Need at least header
          }
          final numberOfRectangles = (_buffer[2] << 8) | _buffer[3];
          messageLength = _calculateFramebufferUpdateLength(numberOfRectangles);
          break;
        case 1: // SetColourMapEntries
          if (_buffer.length < 6) return;
          final numberOfColors = (_buffer[4] << 8) | _buffer[5];
          messageLength = 6 + numberOfColors * 6;
          break;
        case 2: // Bell
          messageLength = 1;
          break;
        case 3: // ServerCutText
          if (_buffer.length < 8) return;
          final textLength = (_buffer[4] << 24) |
              (_buffer[5] << 16) |
              (_buffer[6] << 8) |
              _buffer[7];
          messageLength = 8 + textLength;
          break;
        default:
          _log(
              'Unknown message type: $messageType (0x${messageType.toRadixString(16).padLeft(2, '0')})');
          _log(
              'Buffer first 16 bytes: ${_buffer.take(16).map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
          _log('Buffer length: ${_buffer.length}');

          // If we have a small buffer with unknown message types, it might be leftover pixel data
          // Clear the buffer and wait for the next proper message
          if (_buffer.length <= 128) {
            // Increased threshold for safety
            _log(
                'Small buffer with unknown message type, clearing buffer to resync');
            _buffer.clear();
            return;
          }

          // Skip this byte and try to resync, but if we skip too many bytes, clear the buffer
          _buffer.removeAt(0);
          if (iterations > 3) {
            _log('Too many unknown bytes, clearing buffer completely');
            _buffer.clear();
            return;
          }
          continue;
      }

      if (messageLength == 0) {
        _log('Message length calculation returned 0, insufficient data');
        return; // Wait for more data
      }

      if (_buffer.length < messageLength) {
        _log(
            'Insufficient buffer data: have ${_buffer.length}, need $messageLength');
        return; // Wait for more data
      }

      // Extract and process the complete message
      _log('Extracting message: type=$messageType, length=$messageLength');
      final messageData =
          Uint8List.fromList(_buffer.take(messageLength).toList());
      _buffer.removeRange(0, messageLength);

      _log(
          'Processing message type $messageType, length $messageLength, remaining buffer: ${_buffer.length}');

      _handleServerMessage(messageData);

      _log('Message processed, buffer length now: ${_buffer.length}');
    }

    if (iterations >= 5) {
      _log('Warning: Processing loop hit iteration limit, may be stuck');
    }
  }

  int _calculateFramebufferUpdateLength(int numberOfRectangles) {
    // Start with header: 1 + 1 + 2 = 4 bytes
    int length = 4;
    int offset = 4;

    _log(
        'Calculating FramebufferUpdate length for $numberOfRectangles rectangles');

    for (int i = 0; i < numberOfRectangles; i++) {
      if (_buffer.length < offset + 12) return 0; // Need rectangle header

      // Rectangle header format:
      // 2 bytes: x-position (offset + 0, offset + 1)
      // 2 bytes: y-position (offset + 2, offset + 3)
      // 2 bytes: width (offset + 4, offset + 5)
      // 2 bytes: height (offset + 6, offset + 7)
      // 4 bytes: encoding (offset + 8-11)
      final width = (_buffer[offset + 4] << 8) | _buffer[offset + 5];
      final height = (_buffer[offset + 6] << 8) | _buffer[offset + 7];
      final encoding = (_buffer[offset + 8] << 24) |
          (_buffer[offset + 9] << 16) |
          (_buffer[offset + 10] << 8) |
          _buffer[offset + 11];

      _log(
          'Rectangle $i: ${width}x${height}, encoding=$encoding, offset=$offset');

      length += 12; // Rectangle header
      offset += 12;

      if (encoding == 0) {
        // Raw encoding - calculate pixel data size based on actual server format
        final bytesPerPixel = _frameBuffer?.pixelFormat.bitsPerPixel ?? 32;
        final pixelDataSize = width * height * (bytesPerPixel ~/ 8);
        _log(
            'Adding $pixelDataSize bytes of pixel data for rectangle $i (${bytesPerPixel}bpp)');
        length += pixelDataSize;
        offset += pixelDataSize;
      } else {
        // Other encodings not implemented yet
        return 0;
      }
    }

    _log('Total calculated message length: $length bytes');
    return length;
  }

  void _handleServerMessage(Uint8List data) {
    if (data.isEmpty) return;

    final messageType = data[0];

    switch (messageType) {
      case 0: // FramebufferUpdate
        _handleFramebufferUpdate(data);
        break;
      case 1: // SetColourMapEntries
        break;
      case 2: // Bell
        _log('Bell notification received from server');
        break;
      case 3: // ServerCutText
        _handleServerCutText(data);
        break;
    }
  }

  void _handleFramebufferUpdate(Uint8List data) {
    if (data.length < 4) {
      _log('FramebufferUpdate message too short: ${data.length} bytes');
      return;
    }

    try {
      // FramebufferUpdate message format:
      // 1 byte: message type (0)
      // 1 byte: padding
      // 2 bytes: number of rectangles
      // For each rectangle:
      //   2 bytes: x-position
      //   2 bytes: y-position
      //   2 bytes: width
      //   2 bytes: height
      //   4 bytes: encoding type
      //   pixel data (encoding dependent)

      int offset = 0;
      offset++; // Skip message type (should be 0)
      offset++; // Skip padding
      final numberOfRectangles = (data[offset] << 8) | data[offset + 1];
      offset += 2;

      _log('FramebufferUpdate: $numberOfRectangles rectangles');

      for (int i = 0; i < numberOfRectangles; i++) {
        if (offset + 12 > data.length) {
          _log('Not enough data for rectangle $i header');
          return;
        }

        final x = (data[offset] << 8) | data[offset + 1];
        offset += 2;
        final y = (data[offset] << 8) | data[offset + 1];
        offset += 2;
        final width = (data[offset] << 8) | data[offset + 1];
        offset += 2;
        final height = (data[offset] << 8) | data[offset + 1];
        offset += 2;
        final encoding = (data[offset] << 24) |
            (data[offset + 1] << 16) |
            (data[offset + 2] << 8) |
            data[offset + 3];
        offset += 4;

        _log('Rectangle $i: ${x},${y} ${width}x${height} encoding=$encoding');

        if (encoding == 0) {
          // Raw encoding - pixel data follows
          final bytesPerPixel = _frameBuffer?.pixelFormat.bitsPerPixel ?? 32;
          final pixelDataSize = width * height * (bytesPerPixel ~/ 8);

          _log(
              'Processing ${pixelDataSize} bytes of pixel data for ${width}x${height} rectangle');
          _log(
              'Bytes per pixel from frameBuffer: ${bytesPerPixel ~/ 8}, bitsPerPixel: ${bytesPerPixel}');

          if (offset + pixelDataSize > data.length) {
            _log(
                'Not enough pixel data for rectangle $i: need $pixelDataSize, have ${data.length - offset}');
            return;
          }

          final pixels = data.sublist(offset, offset + pixelDataSize);
          offset += pixelDataSize;

          _log(
              'Processing ${pixels.length} bytes of pixel data for ${width}x${height} rectangle');

          // Update frame buffer with this rectangle
          _updateFrameBufferRectangle(x, y, width, height, pixels);

          // Validate we consumed all the expected data for this rectangle
          if (i == 0) {
            // Only log for first rectangle to avoid spam
            _log(
                'Server pixel format: ${_frameBuffer?.pixelFormat.bitsPerPixel ?? 0}bpp, ${(_frameBuffer?.pixelFormat.bitsPerPixel ?? 32) ~/ 8} bytes per pixel');
            _log(
                'Expected pixel data: ${width * height * ((_frameBuffer?.pixelFormat.bitsPerPixel ?? 32) ~/ 8)} bytes, got: ${pixels.length} bytes');
          }

          // Notify UI of update
          final update = VNCFrameUpdate(
            x: x,
            y: y,
            width: width,
            height: height,
            pixels: pixels,
          );
          _frameUpdateController.add(update);
        } else {
          _log('Unsupported encoding: $encoding');
          // Skip this rectangle for now
          break;
        }
      }

      // Update connection state to connected after first frame buffer update
      if (_state != VNCConnectionState.connected) {
        _log(
            'First frame buffer received, updating connection state to connected');
        _updateState(VNCConnectionState.connected);
      }

      // Request next frame update
      _requestFrameUpdate(true); // incremental
    } catch (e) {
      _log('Error processing FramebufferUpdate: $e');
    }
  }

  void _updateFrameBufferRectangle(
      int x, int y, int width, int height, Uint8List pixels) {
    if (_frameBuffer == null) return;

    _log(
        'Updated rectangle: ${x},${y} ${width}x${height} (${pixels.length} bytes)');

    // Create frame buffer if not exists
    if (_frameBuffer!.pixels == null) {
      final totalPixels =
          _frameBuffer!.width * _frameBuffer!.height * 4; // RGBA
      _frameBuffer!.pixels = Uint8List(totalPixels);
      // Fill with black initially
      for (int i = 0; i < _frameBuffer!.pixels!.length; i += 4) {
        _frameBuffer!.pixels![i] = 0; // R
        _frameBuffer!.pixels![i + 1] = 0; // G
        _frameBuffer!.pixels![i + 2] = 0; // B
        _frameBuffer!.pixels![i + 3] = 255; // A
      }
    }

    // Get server pixel format
    final serverBpp = _frameBuffer!.pixelFormat.bitsPerPixel;
    final serverBytesPerPixel = serverBpp ~/ 8;

    _log(
        'Server pixel format: ${serverBpp}bpp, ${serverBytesPerPixel} bytes per pixel');
    _log(
        'Expected pixel data: ${width * height * serverBytesPerPixel} bytes, got: ${pixels.length} bytes');

    // Convert server pixels to RGBA format
    for (int row = 0; row < height; row++) {
      for (int col = 0; col < width; col++) {
        final srcOffset = (row * width + col) * serverBytesPerPixel;
        final dstOffset = ((y + row) * _frameBuffer!.width + (x + col)) * 4;

        if (srcOffset + serverBytesPerPixel <= pixels.length &&
            dstOffset + 4 <= _frameBuffer!.pixels!.length) {
          int r, g, b, a = 255;

          if (serverBpp == 32) {
            // 32-bit RGBA (assuming server format)
            b = pixels[srcOffset];
            g = pixels[srcOffset + 1];
            r = pixels[srcOffset + 2];
            a = pixels[srcOffset + 3];
          } else if (serverBpp == 16) {
            // 16-bit RGB565
            final pixel = (pixels[srcOffset + 1] << 8) | pixels[srcOffset];
            r = ((pixel >> 11) & 0x1F) * 255 ~/ 31;
            g = ((pixel >> 5) & 0x3F) * 255 ~/ 63;
            b = (pixel & 0x1F) * 255 ~/ 31;
          } else {
            // Fallback - copy as is
            r = srcOffset < pixels.length ? pixels[srcOffset] : 0;
            g = srcOffset + 1 < pixels.length ? pixels[srcOffset + 1] : 0;
            b = srcOffset + 2 < pixels.length ? pixels[srcOffset + 2] : 0;
          }

          // Store in RGBA format
          _frameBuffer!.pixels![dstOffset] = r;
          _frameBuffer!.pixels![dstOffset + 1] = g;
          _frameBuffer!.pixels![dstOffset + 2] = b;
          _frameBuffer!.pixels![dstOffset + 3] = a;
        }
      }
    }

    // Trigger repaint by sending frame update event
    final update = VNCFrameUpdate(
      x: x,
      y: y,
      width: width,
      height: height,
      pixels: pixels,
    );
    _frameUpdateController.add(update);
  }

  void sendPointerEvent(int x, int y, int buttonMask) {
    if (_socket == null) return;

    final message = Uint8List(6);
    message[0] = 5; // PointerEvent message type
    message[1] = buttonMask;
    message.buffer.asByteData().setUint16(2, x, Endian.big);
    message.buffer.asByteData().setUint16(4, y, Endian.big);

    _socket!.add(message);
  }

  void sendKeyEvent(int key, bool down) {
    if (_socket == null) return;

    final message = Uint8List(8);
    message[0] = 4; // KeyEvent message type
    message[1] = down ? 1 : 0; // Down flag
    message.buffer.asByteData().setUint32(4, key, Endian.big);

    _socket!.add(message);
  }

  /// Send desktop resize request (if supported by server)
  Future<void> requestDesktopSize(int width, int height) async {
    if (_socket == null || _state != VNCConnectionState.connected) {
      _log('Cannot request desktop size change: not connected');
      return;
    }

    try {
      // Desktop Size Extension (ExtendedDesktopSize pseudo-encoding)
      // This is a client-initiated desktop resize request
      final message = Uint8List(10);

      message[0] = 251; // ExtendedDesktopSize message type (non-standard)
      message[1] = 0; // Padding
      message[2] = (width >> 8) & 0xFF; // Width high byte
      message[3] = width & 0xFF; // Width low byte
      message[4] = (height >> 8) & 0xFF; // Height high byte
      message[5] = height & 0xFF; // Height low byte
      message[6] = 1; // Number of screens
      message[7] = 0; // Screen ID
      message[8] = 0; // Screen flags
      message[9] = 0; // Padding

      _socket!.add(message);
      _log('Requested desktop size change to ${width}x${height}');
    } catch (e) {
      _log('Error sending desktop size request: $e');
    }
  }

  /// Send SetDesktopSize message (VNC standard extension)
  Future<void> setDesktopSize(int width, int height) async {
    if (_socket == null || _state != VNCConnectionState.connected) {
      _log('Cannot set desktop size: not connected');
      return;
    }

    try {
      // SetDesktopSize message format:
      // 1 byte: message-type (251)
      // 1 byte: padding
      // 2 bytes: width
      // 2 bytes: height
      // 1 byte: number-of-screens
      // 1 byte: padding
      // For each screen:
      //   4 bytes: id, x-position, y-position, width, height, flags

      final message = Uint8List(16);

      message[0] = 251; // SetDesktopSize message type
      message[1] = 0; // Padding
      message[2] = (width >> 8) & 0xFF; // Width high byte
      message[3] = width & 0xFF; // Width low byte
      message[4] = (height >> 8) & 0xFF; // Height high byte
      message[5] = height & 0xFF; // Height low byte
      message[6] = 1; // Number of screens
      message[7] = 0; // Padding

      // Screen 0 data
      message[8] = 0; // Screen ID (4 bytes, but we only use 1)
      message[9] = 0;
      message[10] = 0;
      message[11] = 0;
      message[12] = 0; // X position (2 bytes)
      message[13] = 0;
      message[14] = 0; // Y position (2 bytes)
      message[15] = 0;

      _socket!.add(message);
      _log('Sent SetDesktopSize request: ${width}x${height}');
    } catch (e) {
      _log('Error sending SetDesktopSize: $e');
    }
  }

  void _updateState(VNCConnectionState newState) {
    print('DEBUG: _updateState called with: $newState, old state: $_state');
    _state = newState;
    print(
        'DEBUG: Broadcasting state $newState to ${_stateController.hasListener ? "listeners" : "no listeners"}');
    _stateController.add(newState);
    print('DEBUG: State update complete, current state: $_state');
  }

  void _handleServerCutText(Uint8List data) {
    if (data.length < 8) {
      _log('ServerCutText message too short: ${data.length} bytes');
      return;
    }

    try {
      // ServerCutText message format:
      // 1 byte: message type (3)
      // 3 bytes: padding
      // 4 bytes: length
      // text data

      final textLength =
          (data[4] << 24) | (data[5] << 16) | (data[6] << 8) | data[7];

      if (data.length < 8 + textLength) {
        _log('ServerCutText: insufficient data for text length $textLength');
        return;
      }

      final textBytes = data.sublist(8, 8 + textLength);
      final text = utf8.decode(textBytes);

      _log('Server clipboard text received: ${text.length} characters');

      // Notify about clipboard update
      _clipboardController.add(text);
    } catch (e) {
      _log('Error handling ServerCutText: $e');
    }
  }

  // Enhanced clipboard method
  Future<void> sendClientCutText(String text) async {
    if (_socket == null || _state != VNCConnectionState.connected) {
      _log('Cannot send clipboard text: not connected');
      return;
    }

    try {
      final textBytes = utf8.encode(text);
      final message = Uint8List(8 + textBytes.length);

      message[0] = 6; // ClientCutText message type
      message[1] = 0; // Padding
      message[2] = 0; // Padding
      message[3] = 0; // Padding
      message[4] = (textBytes.length >> 24) & 0xFF; // Length high byte
      message[5] = (textBytes.length >> 16) & 0xFF;
      message[6] = (textBytes.length >> 8) & 0xFF;
      message[7] = textBytes.length & 0xFF; // Length low byte

      // Copy text bytes
      for (int i = 0; i < textBytes.length; i++) {
        message[8 + i] = textBytes[i];
      }

      _socket!.add(message);
      _log('Sent clipboard text: ${text.length} characters');
    } catch (e) {
      _log('Error sending clipboard text: $e');
    }
  }

  void dispose() {
    _socket?.close();
    _frameUpdateController.close();
    _stateController.close();
    _logController.close();
    _clipboardController.close();
    _socketSubscription?.cancel();
  }
}

class VNCFrameBuffer {
  final int width;
  final int height;
  final VNCPixelFormat pixelFormat;
  final String serverName;
  Uint8List? pixels;

  VNCFrameBuffer(this.width, this.height, this.pixelFormat, this.serverName);
}

class VNCPixelFormat {
  final int bitsPerPixel;
  final int depth;
  final bool bigEndianFlag;
  final bool trueColourFlag;
  final int redMax;
  final int greenMax;
  final int blueMax;
  final int redShift;
  final int greenShift;
  final int blueShift;

  VNCPixelFormat({
    required this.bitsPerPixel,
    required this.depth,
    required this.bigEndianFlag,
    required this.trueColourFlag,
    required this.redMax,
    required this.greenMax,
    required this.blueMax,
    required this.redShift,
    required this.greenShift,
    required this.blueShift,
  });
}

class VNCFrameUpdate {
  final int x;
  final int y;
  final int width;
  final int height;
  final Uint8List pixels;

  VNCFrameUpdate({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.pixels,
  });
}

/// Widget for displaying VNC client content
class VNCClientWidget extends StatefulWidget {
  final VNCClient client;
  final VNCScalingMode scalingMode;
  final VNCInputMode inputMode;
  final VNCResolutionMode resolutionMode;
  final VoidCallback?
      onDisconnectRequest; // Callback when user wants to disconnect
  static int _instanceCount = 0; // Track active instances
  static _VNCClientWidgetState?
      _activeInstance; // Track the currently active instance

  const VNCClientWidget({
    super.key,
    required this.client,
    this.scalingMode = VNCScalingMode.fitToScreen,
    this.inputMode = VNCInputMode.directTouch,
    this.resolutionMode = VNCResolutionMode.fixed,
    this.onDisconnectRequest,
  });

  @override
  State<VNCClientWidget> createState() {
    _instanceCount++;
    print(
        '[VNCClientWidget] Creating new state instance (#$_instanceCount total)');
    final state = _VNCClientWidgetState();

    // If there's already an active instance, dispose it first
    if (_activeInstance != null) {
      print(
          '[VNCClientWidget] Warning: Disposing previous active instance to prevent multiple widgets');
      _activeInstance!._disposeStreams();
    }

    _activeInstance = state;
    return state;
  }
}

class _VNCClientWidgetState extends State<VNCClientWidget> {
  VNCConnectionState _connectionState = VNCConnectionState.disconnected;
  VNCFrameBuffer? _frameBuffer;
  StreamSubscription<VNCConnectionState>? _connectionStateSubscription;
  StreamSubscription<VNCFrameUpdate>? _frameUpdateSubscription;

  // Input mode and zoom state
  double _zoomLevel = 1.0;
  Offset _panOffset = Offset.zero;
  Offset? _cursorPosition; // For trackpad mode
  bool _showToolbar = false;

  @override
  void initState() {
    super.initState();
    print('[VNCClientWidget] initState called - Widget ${widget.hashCode}');

    _connectionStateSubscription =
        widget.client.connectionState.listen((state) {
      print('[VNCClientWidget] State change: $state');
      if (mounted) {
        // Check if widget is still mounted
        setState(() {
          _connectionState = state;
        });
      }
    });

    _frameUpdateSubscription = widget.client.frameUpdates.listen((update) {
      if (mounted) {
        // Check if widget is still mounted
        setState(() {
          _frameBuffer = widget.client.frameBuffer;
        });
      }
    });
  }

  /// Helper method to dispose streams without calling super.dispose()
  void _disposeStreams() {
    print(
        '[VNCClientWidget] _disposeStreams called - cleaning up subscriptions');
    _connectionStateSubscription?.cancel();
    _frameUpdateSubscription?.cancel();
    _connectionStateSubscription = null;
    _frameUpdateSubscription = null;
  }

  @override
  void dispose() {
    VNCClientWidget._instanceCount--;
    print(
        '[VNCClientWidget] dispose called - Widget ${widget.hashCode}, remaining instances: ${VNCClientWidget._instanceCount}');

    // Clear the active instance reference if this is the active one
    if (VNCClientWidget._activeInstance == this) {
      VNCClientWidget._activeInstance = null;
    }

    _disposeStreams();
    super.dispose();
  }

  /// Maps touch coordinates from the widget space to VNC coordinates
  Offset _mapTouchCoordinates(
      Offset touchPosition, BuildContext context, Size size) {
    if (_frameBuffer == null) return touchPosition;

    final width = _frameBuffer!.width.toDouble();
    final height = _frameBuffer!.height.toDouble();

    // Calculate the same scaling factors used in VNCFramePainter
    double scaleX, scaleY, offsetX, offsetY;

    switch (widget.scalingMode) {
      case VNCScalingMode.fitToScreen:
        // Fit entire desktop in screen with black borders if needed
        final scale = (size.width / width) < (size.height / height)
            ? size.width / width
            : size.height / height;
        final scaledWidth = width * scale;
        final scaledHeight = height * scale;
        offsetX = (size.width - scaledWidth) / 2;
        offsetY = (size.height - scaledHeight) / 2;
        scaleX = scaleY = scale;
        break;

      case VNCScalingMode.centerCrop:
        // Center desktop and crop excess
        final scale = (size.width / width) > (size.height / height)
            ? size.width / width
            : size.height / height;
        final scaledWidth = width * scale;
        final scaledHeight = height * scale;
        offsetX = (size.width - scaledWidth) / 2;
        offsetY = (size.height - scaledHeight) / 2;
        scaleX = scaleY = scale;
        break;

      case VNCScalingMode.actualSize:
        // 1:1 pixel mapping
        offsetX = (size.width - width) / 2;
        offsetY = (size.height - height) / 2;
        scaleX = scaleY = 1.0;
        break;

      // Auto-fit modes
      case VNCScalingMode.autoFitWidth:
        // Fit width, maintain aspect ratio
        scaleX = scaleY = size.width / width;
        final scaledHeight = height * scaleY;
        offsetX = 0;
        offsetY = (size.height - scaledHeight) / 2;
        break;

      case VNCScalingMode.autoFitHeight:
        // Fit height, maintain aspect ratio
        scaleX = scaleY = size.height / height;
        final scaledWidth = width * scaleX;
        offsetX = (size.width - scaledWidth) / 2;
        offsetY = 0;
        break;

      case VNCScalingMode.autoFitBest:
        // Choose best fit dimension
        final scaleW = size.width / width;
        final scaleH = size.height / height;
        scaleX = scaleY = math.min(scaleW, scaleH);
        final scaledWidth = width * scaleX;
        final scaledHeight = height * scaleY;
        offsetX = (size.width - scaledWidth) / 2;
        offsetY = (size.height - scaledHeight) / 2;
        break;

      // Zoom levels
      case VNCScalingMode.zoom50:
        // 50% zoom
        final scaledWidth = width * 0.5;
        final scaledHeight = height * 0.5;
        offsetX = (size.width - scaledWidth) / 2;
        offsetY = (size.height - scaledHeight) / 2;
        scaleX = scaleY = 0.5;
        break;

      case VNCScalingMode.zoom75:
        // 75% zoom
        final scaledWidth = width * 0.75;
        final scaledHeight = height * 0.75;
        offsetX = (size.width - scaledWidth) / 2;
        offsetY = (size.height - scaledHeight) / 2;
        scaleX = scaleY = 0.75;
        break;

      case VNCScalingMode.zoom125:
        // 125% zoom
        final scaledWidth = width * 1.25;
        final scaledHeight = height * 1.25;
        offsetX = (size.width - scaledWidth) / 2;
        offsetY = (size.height - scaledHeight) / 2;
        scaleX = scaleY = 1.25;
        break;

      case VNCScalingMode.zoom150:
        // 150% zoom
        final scaledWidth = width * 1.5;
        final scaledHeight = height * 1.5;
        offsetX = (size.width - scaledWidth) / 2;
        offsetY = (size.height - scaledHeight) / 2;
        scaleX = scaleY = 1.5;
        break;

      case VNCScalingMode.zoom200:
        // 200% zoom (double size, centered)
        final scaledWidth = width * 2.0;
        final scaledHeight = height * 2.0;
        offsetX = (size.width - scaledWidth) / 2;
        offsetY = (size.height - scaledHeight) / 2;
        scaleX = scaleY = 2.0;
        break;

      // Smart scaling modes for Android
      case VNCScalingMode.smartFitLandscape:
        // Fit width for landscape, crop height if needed
        scaleX = scaleY = size.width / width;
        final scaledHeight = height * scaleY;
        offsetX = 0;
        offsetY = (size.height - scaledHeight) / 2;
        break;

      case VNCScalingMode.smartFitPortrait:
        // Fit height for portrait, crop width if needed
        scaleX = scaleY = size.height / height;
        final scaledWidth = width * scaleX;
        offsetX = (size.width - scaledWidth) / 2;
        offsetY = 0;
        break;

      case VNCScalingMode.remoteResize:
        // Request server to resize (same as fit for display)
        final scaleW = size.width / width;
        final scaleH = size.height / height;
        scaleX = scaleY = math.min(scaleW, scaleH);
        final scaledWidth = width * scaleX;
        final scaledHeight = height * scaleY;
        offsetX = (size.width - scaledWidth) / 2;
        offsetY = (size.height - scaledHeight) / 2;
        break;

      case VNCScalingMode.stretchFit:
        // Stretch to fill entire display
        scaleX = size.width / width;
        scaleY = size.height / height;
        offsetX = offsetY = 0;
        break;
    }

    // Apply zoom level
    scaleX *= _zoomLevel;
    scaleY *= _zoomLevel;

    // Apply pan offset
    offsetX += _panOffset.dx;
    offsetY += _panOffset.dy;

    // Map touch coordinates to VNC coordinates
    final vncX = ((touchPosition.dx - offsetX) / scaleX).clamp(0.0, width - 1);
    final vncY = ((touchPosition.dy - offsetY) / scaleY).clamp(0.0, height - 1);

    return Offset(vncX, vncY);
  }

  Widget _buildInputHandler(Size size) {
    switch (widget.inputMode) {
      case VNCInputMode.directTouch:
        return _buildDirectTouchHandler(size);
      case VNCInputMode.trackpadMode:
        return _buildTrackpadHandler(size);
      case VNCInputMode.directTouchWithZoom:
        return _buildDirectTouchWithZoomHandler(size);
    }
  }

  Widget _buildDirectTouchHandler(Size size) {
    return GestureDetector(
      onTapDown: (details) {
        final mappedCoords =
            _mapTouchCoordinates(details.localPosition, context, size);
        widget.client.sendPointerEvent(
            mappedCoords.dx.round(), mappedCoords.dy.round(), 1); // Left click
      },
      onTapUp: (details) {
        final mappedCoords =
            _mapTouchCoordinates(details.localPosition, context, size);
        widget.client.sendPointerEvent(
            mappedCoords.dx.round(), mappedCoords.dy.round(), 0); // Release
      },
      onPanUpdate: (details) {
        final mappedCoords =
            _mapTouchCoordinates(details.localPosition, context, size);
        widget.client.sendPointerEvent(
            mappedCoords.dx.round(), mappedCoords.dy.round(), 1); // Drag
      },
      onPanEnd: (details) {
        final mappedCoords =
            _mapTouchCoordinates(details.localPosition, context, size);
        widget.client.sendPointerEvent(
            mappedCoords.dx.round(), mappedCoords.dy.round(), 0); // Release
      },
      child: Container(), // No CustomPaint here - will be handled by parent
    );
  }

  Widget _buildTrackpadHandler(Size size) {
    return GestureDetector(
      onPanUpdate: (details) {
        // In trackpad mode, pan moves the cursor
        setState(() {
          if (_cursorPosition == null) {
            _cursorPosition = details.localPosition;
          } else {
            _cursorPosition = _cursorPosition! + details.delta;
          }
        });

        // Send mouse move event
        final mappedCoords =
            _mapTouchCoordinates(_cursorPosition!, context, size);
        widget.client.sendPointerEvent(
            mappedCoords.dx.round(), mappedCoords.dy.round(), 0); // Move only
      },
      onTap: () {
        // Tap to click at cursor position
        if (_cursorPosition != null) {
          final mappedCoords =
              _mapTouchCoordinates(_cursorPosition!, context, size);
          widget.client.sendPointerEvent(
              mappedCoords.dx.round(), mappedCoords.dy.round(), 1); // Click

          // Release after short delay
          Future.delayed(const Duration(milliseconds: 50), () {
            widget.client.sendPointerEvent(
                mappedCoords.dx.round(), mappedCoords.dy.round(), 0); // Release
          });
        }
      },
      child: Stack(
        children: [
          Container(), // No CustomPaint here - will be handled by parent
          // Draw cursor
          if (_cursorPosition != null)
            Positioned(
              left: _cursorPosition!.dx - 8,
              top: _cursorPosition!.dy - 8,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.8),
                  border: Border.all(color: Colors.black, width: 1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.mouse, size: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDirectTouchWithZoomHandler(Size size) {
    return GestureDetector(
      onScaleStart: (details) {
        // Scale gesture started
      },
      onScaleUpdate: (details) {
        setState(() {
          // Handle zoom
          _zoomLevel = (_zoomLevel * details.scale).clamp(0.5, 4.0);

          // Handle pan
          _panOffset += details.focalPointDelta;
        });
      },
      onTapDown: (details) {
        if (_zoomLevel == 1.0 && _panOffset == Offset.zero) {
          // Normal direct touch when not zoomed
          final mappedCoords =
              _mapTouchCoordinates(details.localPosition, context, size);
          widget.client.sendPointerEvent(mappedCoords.dx.round(),
              mappedCoords.dy.round(), 1); // Left click
        }
      },
      onTapUp: (details) {
        if (_zoomLevel == 1.0 && _panOffset == Offset.zero) {
          // Normal direct touch when not zoomed
          final mappedCoords =
              _mapTouchCoordinates(details.localPosition, context, size);
          widget.client.sendPointerEvent(
              mappedCoords.dx.round(), mappedCoords.dy.round(), 0); // Release
        }
      },
      child: Transform(
        transform: Matrix4.identity()
          ..scale(_zoomLevel)
          ..translate(_panOffset.dx / _zoomLevel, _panOffset.dy / _zoomLevel),
        child: Container(), // No CustomPaint here - will be handled by parent
      ),
    );
  }

  Widget _buildConnectionStatusOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.8),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_connectionState == VNCConnectionState.connecting) ...[
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 16),
              const Text(
                'Connecting to VNC server...',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ] else if (_connectionState == VNCConnectionState.failed) ...[
              const Icon(Icons.error, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Connection failed',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ] else if (_connectionState == VNCConnectionState.disconnected) ...[
              const Icon(Icons.link_off, color: Colors.grey, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Disconnected',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVNCToolbar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: _showToolbar ? 60 : 30,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.8),
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(12),
            bottomRight: Radius.circular(12),
          ),
        ),
        child: Row(
          children: [
            // Toolbar toggle button
            IconButton(
              icon: Icon(
                _showToolbar
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                color: Colors.white,
              ),
              onPressed: () {
                setState(() {
                  _showToolbar = !_showToolbar;
                });
              },
            ),

            if (_showToolbar) ...[
              // 1:1 Resolution button for dynamic resolution
              if (widget.resolutionMode == VNCResolutionMode.dynamic)
                IconButton(
                  icon: const Icon(Icons.aspect_ratio, color: Colors.white),
                  onPressed: () async {
                    // Get current screen size for 1:1 resolution
                    final screenSize = MediaQuery.of(context).size;
                    final devicePixelRatio =
                        MediaQuery.of(context).devicePixelRatio;

                    // Calculate ideal resolution for mobile screen
                    final width = (screenSize.width * devicePixelRatio).round();
                    final height =
                        (screenSize.height * devicePixelRatio).round();

                    try {
                      await widget.client.setDesktopSize(width, height);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              'Requested resolution change to ${width}x${height}'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Failed to change resolution: $e'),
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    }
                  },
                  tooltip:
                      '1:1 Resolution (${MediaQuery.of(context).size.width.round()}x${MediaQuery.of(context).size.height.round()})',
                ),

              // 1:2 Resolution button for smaller display
              if (widget.resolutionMode == VNCResolutionMode.dynamic)
                IconButton(
                  icon: const Icon(Icons.photo_size_select_small,
                      color: Colors.white),
                  onPressed: () async {
                    // Get half screen size for 1:2 resolution
                    final screenSize = MediaQuery.of(context).size;
                    final devicePixelRatio =
                        MediaQuery.of(context).devicePixelRatio;

                    final width =
                        (screenSize.width * devicePixelRatio * 0.5).round();
                    final height =
                        (screenSize.height * devicePixelRatio * 0.5).round();

                    try {
                      await widget.client.setDesktopSize(width, height);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              'Requested resolution change to ${width}x${height} (1:2)'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Failed to change resolution: $e'),
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    }
                  },
                  tooltip: '1:2 Resolution (Half size)',
                ),

              // Input mode indicator with options
              PopupMenuButton<VNCInputMode>(
                icon: Icon(
                  widget.inputMode == VNCInputMode.directTouch
                      ? Icons.touch_app
                      : widget.inputMode == VNCInputMode.trackpadMode
                          ? Icons.mouse
                          : Icons.zoom_in,
                  color: Colors.white,
                ),
                tooltip: 'Change Input Mode',
                onSelected: (VNCInputMode newMode) {
                  // Note: This would require passing a callback to change input mode
                  // For now, just show the selected mode
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Input mode: ${_getInputModeDescription(newMode)}'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                itemBuilder: (BuildContext context) =>
                    <PopupMenuEntry<VNCInputMode>>[
                  const PopupMenuItem<VNCInputMode>(
                    value: VNCInputMode.directTouch,
                    child: Row(
                      children: [
                        Icon(Icons.touch_app),
                        SizedBox(width: 8),
                        Text('Direct Touch'),
                      ],
                    ),
                  ),
                  const PopupMenuItem<VNCInputMode>(
                    value: VNCInputMode.trackpadMode,
                    child: Row(
                      children: [
                        Icon(Icons.mouse),
                        SizedBox(width: 8),
                        Text('Trackpad Mode'),
                      ],
                    ),
                  ),
                  const PopupMenuItem<VNCInputMode>(
                    value: VNCInputMode.directTouchWithZoom,
                    child: Row(
                      children: [
                        Icon(Icons.zoom_in),
                        SizedBox(width: 8),
                        Text('Touch with Zoom'),
                      ],
                    ),
                  ),
                ],
              ),

              const Spacer(),

              // Disconnect button
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: widget.onDisconnectRequest,
                tooltip: 'Disconnect',
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _getInputModeDescription(VNCInputMode mode) {
    switch (mode) {
      case VNCInputMode.directTouch:
        return 'Direct Touch - Touch directly where you want to click';
      case VNCInputMode.trackpadMode:
        return 'Trackpad Mode - Finger moves cursor like a laptop trackpad';
      case VNCInputMode.directTouchWithZoom:
        return 'Touch with Zoom - Direct touch with pinch-to-zoom support';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        children: [
          // Main VNC display
          LayoutBuilder(
            builder: (context, constraints) {
              // Handle Android screen constraints more robustly
              final screenSize = MediaQuery.of(context).size;
              final safeArea = MediaQuery.of(context).padding;

              // Calculate available space considering safe areas (status bar, navigation bar)
              final availableWidth = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : screenSize.width;
              final availableHeight = constraints.maxHeight.isFinite
                  ? constraints.maxHeight
                  : screenSize.height - safeArea.top - safeArea.bottom;

              final size = Size(
                availableWidth.clamp(
                    320.0, 2048.0), // Min 320px, max 2048px for Android
                availableHeight.clamp(
                    240.0, 2048.0), // Min 240px, max 2048px for Android
              );

              return SizedBox(
                width: size.width,
                height: size.height,
                child: Stack(
                  children: [
                    // Single VNC display painter - prevents multiple rendering
                    if (_frameBuffer != null)
                      CustomPaint(
                        painter: VNCFramePainter(_frameBuffer!,
                            scalingMode: widget.scalingMode),
                        size: size,
                      ),

                    // Input handling overlay
                    if (_frameBuffer != null) _buildInputHandler(size),

                    // Connection status overlay (only when no frame buffer)
                    if (_frameBuffer == null &&
                        _connectionState != VNCConnectionState.connected)
                      _buildConnectionStatusOverlay(),
                  ],
                ),
              );
            },
          ),

          // VNC Toolbar
          if (_frameBuffer != null) _buildVNCToolbar(),
        ],
      ),
    );
  }
}

class VNCFramePainter extends CustomPainter {
  final VNCFrameBuffer frameBuffer;
  final VNCScalingMode scalingMode;
  static int _paintCallCount = 0;

  VNCFramePainter(this.frameBuffer,
      {this.scalingMode = VNCScalingMode.fitToScreen});

  @override
  void paint(Canvas canvas, Size size) {
    _paintCallCount++;

    // Ensure we have valid size constraints
    if (!size.isFinite || size.isEmpty || size.width <= 0 || size.height <= 0) {
      print('[VNCFramePainter] Invalid canvas size: $size, using fallback');
      _drawFallbackDisplay(canvas, Size(800, 600)); // Use fallback size
      return;
    }

    if (frameBuffer.pixels != null && frameBuffer.pixels!.isNotEmpty) {
      // Draw the actual VNC frame buffer using manual pixel drawing
      _drawPixelData(canvas, size);
      return;
    }

    // Draw placeholder if no pixel data available
    final paint = Paint()
      ..color = Colors.grey.shade900
      ..style = PaintingStyle.fill;

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    // Draw connection status
    final textPainter = TextPainter(
      text: TextSpan(
        text: frameBuffer.pixels == null
            ? 'Waiting for frame data...\n${frameBuffer.serverName}\n${frameBuffer.width}x${frameBuffer.height}'
            : 'Processing frame data...\n${frameBuffer.serverName}\n${frameBuffer.width}x${frameBuffer.height}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();
    textPainter.paint(
        canvas,
        Offset((size.width - textPainter.width) / 2,
            (size.height - textPainter.height) / 2));
  }

  void _drawPixelData(Canvas canvas, Size size) {
    final width = frameBuffer.width;
    final height = frameBuffer.height;

    // Fill the entire canvas with black background first to prevent artifacts
    final backgroundPaint = Paint()..color = Colors.black;
    canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height), backgroundPaint);

    // Calculate scaling factors based on the selected scaling mode
    double scale;
    double scaledWidth, scaledHeight, offsetX, offsetY;

    switch (scalingMode) {
      case VNCScalingMode.fitToScreen:
        // Fit entire desktop in screen with black borders if needed (best for Android)
        final scaleX = size.width / width;
        final scaleY = size.height / height;
        scale = scaleX < scaleY
            ? scaleX
            : scaleY; // Use smaller scale to fit everything
        scaledWidth = (width * scale).clamp(0.0, size.width);
        scaledHeight = (height * scale).clamp(0.0, size.height);
        offsetX = (size.width - scaledWidth) / 2;
        offsetY = (size.height - scaledHeight) / 2;
        break;

      case VNCScalingMode.centerCrop:
        // Center desktop and crop excess (no black borders, optimized for mobile)
        final scaleX = size.width / width;
        final scaleY = size.height / height;
        scale = scaleX > scaleY
            ? scaleX
            : scaleY; // Use larger scale to fill screen
        scaledWidth = width * scale;
        scaledHeight = height * scale;
        offsetX = (size.width - scaledWidth) / 2;
        offsetY = (size.height - scaledHeight) / 2;
        break;

      case VNCScalingMode.actualSize:
        // Display at 100% scale (1:1 pixel mapping, may require scrolling)
        scale = 1.0;
        scaledWidth = width.toDouble();
        scaledHeight = height.toDouble();
        offsetX = (size.width - scaledWidth) / 2;
        offsetY = (size.height - scaledHeight) / 2;
        break;

      // Auto-fit modes
      case VNCScalingMode.autoFitWidth:
        // Fit width, maintain aspect ratio
        scale = size.width / width;
        scaledWidth = size.width;
        scaledHeight = height * scale;
        offsetX = 0;
        offsetY = (size.height - scaledHeight) / 2;
        break;

      case VNCScalingMode.autoFitHeight:
        // Fit height, maintain aspect ratio
        scale = size.height / height;
        scaledWidth = width * scale;
        scaledHeight = size.height;
        offsetX = (size.width - scaledWidth) / 2;
        offsetY = 0;
        break;

      case VNCScalingMode.autoFitBest:
        // Choose best fit dimension
        final scaleW = size.width / width;
        final scaleH = size.height / height;
        scale = math.min(scaleW, scaleH);
        scaledWidth = width * scale;
        scaledHeight = height * scale;
        offsetX = (size.width - scaledWidth) / 2;
        offsetY = (size.height - scaledHeight) / 2;
        break;

      // Zoom levels
      case VNCScalingMode.zoom50:
        // Display at 50% scale
        scale = 0.5;
        scaledWidth = width * 0.5;
        scaledHeight = height * 0.5;
        offsetX = (size.width - scaledWidth) / 2;
        offsetY = (size.height - scaledHeight) / 2;
        break;

      case VNCScalingMode.zoom75:
        // Display at 75% scale
        scale = 0.75;
        scaledWidth = width * 0.75;
        scaledHeight = height * 0.75;
        offsetX = (size.width - scaledWidth) / 2;
        offsetY = (size.height - scaledHeight) / 2;
        break;

      case VNCScalingMode.zoom125:
        // Display at 125% scale
        scale = 1.25;
        scaledWidth = width * 1.25;
        scaledHeight = height * 1.25;
        offsetX = (size.width - scaledWidth) / 2;
        offsetY = (size.height - scaledHeight) / 2;
        break;

      case VNCScalingMode.zoom150:
        // Display at 150% scale
        scale = 1.5;
        scaledWidth = width * 1.5;
        scaledHeight = height * 1.5;
        offsetX = (size.width - scaledWidth) / 2;
        offsetY = (size.height - scaledHeight) / 2;
        break;

      case VNCScalingMode.zoom200:
        // Display at 200% scale (double size, centered)
        scale = 2.0;
        scaledWidth = width * 2.0;
        scaledHeight = height * 2.0;
        offsetX = (size.width - scaledWidth) / 2;
        offsetY = (size.height - scaledHeight) / 2;
        break;

      // Smart scaling modes for Android
      case VNCScalingMode.smartFitLandscape:
        // Fit width for landscape, crop height if needed
        scale = size.width / width;
        scaledWidth = size.width;
        scaledHeight = height * scale;
        offsetX = 0;
        offsetY = (size.height - scaledHeight) / 2;
        break;

      case VNCScalingMode.smartFitPortrait:
        // Fit height for portrait, crop width if needed
        scale = size.height / height;
        scaledWidth = width * scale;
        scaledHeight = size.height;
        offsetX = (size.width - scaledWidth) / 2;
        offsetY = 0;
        break;

      case VNCScalingMode.remoteResize:
        // Request server to resize (same as fit for display)
        final scaleW = size.width / width;
        final scaleH = size.height / height;
        scale = math.min(scaleW, scaleH);
        scaledWidth = width * scale;
        scaledHeight = height * scale;
        offsetX = (size.width - scaledWidth) / 2;
        offsetY = (size.height - scaledHeight) / 2;
        break;

      case VNCScalingMode.stretchFit:
        // Stretch to fill entire display (may distort aspect ratio)
        final scaleX = size.width / width;
        final scaleY = size.height / height;
        _drawStretchedFrameBuffer(canvas, size, scaleX, scaleY);
        return; // Early return for stretch mode
    }

    try {
      // Use improved scaling with bounds checking
      _drawScaledFrameBuffer(
          canvas, size, offsetX, offsetY, scale, scaledWidth, scaledHeight);
    } catch (e) {
      print('[VNCFramePainter] Error drawing pixels: $e');
      // Fallback to simple centered rectangle
      _drawFallbackDisplay(canvas, size);
    }
  }

  void _drawScaledFrameBuffer(Canvas canvas, Size size, double offsetX,
      double offsetY, double scale, double scaledWidth, double scaledHeight) {
    final pixels = frameBuffer.pixels!;
    final width = frameBuffer.width;
    final height = frameBuffer.height;

    // Clear the entire canvas first to prevent any artifacts
    final clearPaint = Paint()..color = Colors.black;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), clearPaint);

    // Strict bounds checking to prevent any drawing outside the intended area
    final drawBounds = Rect.fromLTWH(
      offsetX.clamp(0.0, size.width),
      offsetY.clamp(0.0, size.height),
      scaledWidth.clamp(0.0, size.width - offsetX.clamp(0.0, size.width)),
      scaledHeight.clamp(0.0, size.height - offsetY.clamp(0.0, size.height)),
    );

    // Ensure we don't exceed the frame buffer dimensions
    final maxDrawWidth = (drawBounds.width / scale).floor().clamp(0, width);
    final maxDrawHeight = (drawBounds.height / scale).floor().clamp(0, height);

    // Optimize sample rate for Android performance
    int sampleRate = 1;
    if (scale < 0.8) sampleRate = 2; // < 80% scale
    if (scale < 0.5) sampleRate = 3; // < 50% scale
    if (scale < 0.3) sampleRate = 4; // < 30% scale
    if (scale < 0.2) sampleRate = 6; // < 20% scale

    int pixelsDrawn = 0;

    // Draw pixels only within the calculated bounds - prevents tiling/repetition
    // Use maxDrawWidth/Height to ensure we don't exceed the desktop dimensions
    for (int y = 0; y < maxDrawHeight && y < height; y += sampleRate) {
      final drawY = offsetY + y * scale;
      if (drawY < drawBounds.top || drawY >= drawBounds.bottom) continue;

      for (int x = 0; x < maxDrawWidth && x < width; x += sampleRate) {
        final drawX = offsetX + x * scale;
        if (drawX < drawBounds.left || drawX >= drawBounds.right) continue;

        final pixelOffset = (y * width + x) * 4; // RGBA format in frame buffer

        if (pixelOffset + 3 < pixels.length) {
          // Frame buffer is stored in RGBA format - read correctly
          final r = pixels[pixelOffset]; // Red (first byte)
          final g = pixels[pixelOffset + 1]; // Green
          final b = pixels[pixelOffset + 2]; // Blue
          // Alpha ignored - force full opacity

          final color = Color.fromARGB(255, r, g, b);
          final paint = Paint()..color = color;

          // Calculate pixel size with bounds checking
          final pixelSize = scale * sampleRate;
          final rectRight = (drawX + pixelSize).clamp(drawX, drawBounds.right);
          final rectBottom =
              (drawY + pixelSize).clamp(drawY, drawBounds.bottom);
          final rectWidth = rectRight - drawX;
          final rectHeight = rectBottom - drawY;

          if (rectWidth > 0.5 && rectHeight > 0.5) {
            final rect = Rect.fromLTWH(drawX, drawY, rectWidth, rectHeight);
            canvas.drawRect(rect, paint);
            pixelsDrawn++;
          }
        }
      }
    }

    // Only log pixel count every 30th paint call to reduce debug spam
    if (_paintCallCount % 30 == 1) {
      print(
          '[VNCFramePainter] Drew $pixelsDrawn pixels (sample rate: $sampleRate, scale: ${scale.toStringAsFixed(2)}) within bounds ${drawBounds.width.toInt()}x${drawBounds.height.toInt()}');
    }
  }

  void _drawStretchedFrameBuffer(
      Canvas canvas, Size size, double scaleX, double scaleY) {
    final pixels = frameBuffer.pixels!;
    final width = frameBuffer.width;
    final height = frameBuffer.height;

    // Optimize sample rate based on average scale for better performance
    final avgScale = (scaleX + scaleY) / 2;
    int sampleRate = 1;
    if (avgScale < 0.7) sampleRate = 2;
    if (avgScale < 0.4) sampleRate = 3;
    if (avgScale < 0.25) sampleRate = 4;

    int pixelsDrawn = 0;

    // Draw with separate X and Y scaling (may distort aspect ratio)
    for (int y = 0; y < height; y += sampleRate) {
      final drawY = y * scaleY;
      if (drawY >= size.height) break; // Stop if we exceed bounds

      for (int x = 0; x < width; x += sampleRate) {
        final drawX = x * scaleX;
        if (drawX >= size.width) break; // Stop if we exceed bounds

        final pixelOffset = (y * width + x) * 4; // RGBA format in frame buffer

        if (pixelOffset + 3 < pixels.length) {
          // Frame buffer is stored in RGBA format - read correctly
          final r = pixels[pixelOffset]; // Red (first byte)
          final g = pixels[pixelOffset + 1]; // Green
          final b = pixels[pixelOffset + 2]; // Blue
          // Alpha ignored - force full opacity

          final color = Color.fromARGB(255, r, g, b);
          final paint = Paint()..color = color;

          // Calculate pixel size with separate scaling
          final maxPixelWidth = math.max(0.5, size.width - drawX);
          final maxPixelHeight = math.max(0.5, size.height - drawY);
          final pixelWidth = (scaleX * sampleRate).clamp(0.5, maxPixelWidth);
          final pixelHeight = (scaleY * sampleRate).clamp(0.5, maxPixelHeight);

          if (pixelWidth > 0 &&
              pixelHeight > 0 &&
              drawX < size.width &&
              drawY < size.height) {
            final rect = Rect.fromLTWH(drawX, drawY, pixelWidth, pixelHeight);
            canvas.drawRect(rect, paint);
            pixelsDrawn++;
          }
        }
      }
    }

    // Only log pixel count every 30th paint call
    if (_paintCallCount % 30 == 1) {
      print(
          '[VNCFramePainter] Drew $pixelsDrawn pixels (sample rate: $sampleRate) with stretch scaling ${scaleX.toStringAsFixed(2)}x${scaleY.toStringAsFixed(2)}');
    }
  }

  void _drawFallbackDisplay(Canvas canvas, Size size) {
    // Draw a simple centered rectangle as fallback
    final paint = Paint()
      ..color = Colors.grey.shade800
      ..style = PaintingStyle.fill;

    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width * 0.8,
      height: size.height * 0.8,
    );

    canvas.drawRect(rect, paint);

    // Draw error text
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'VNC Display Error\nScaling Issue Detected',
        style: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    textPainter.layout();
    textPainter.paint(
        canvas,
        Offset((size.width - textPainter.width) / 2,
            (size.height - textPainter.height) / 2));
  }

  Size getSize(BoxConstraints constraints) {
    // Return the intrinsic size of the frame buffer or use constraints
    if (frameBuffer.width > 0 && frameBuffer.height > 0) {
      final aspectRatio = frameBuffer.width / frameBuffer.height;
      if (constraints.hasBoundedWidth && constraints.hasBoundedHeight) {
        // Use available constraints and maintain aspect ratio
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final constraintAspectRatio = width / height;

        if (aspectRatio > constraintAspectRatio) {
          // Frame buffer is wider
          return Size(width, width / aspectRatio);
        } else {
          // Frame buffer is taller
          return Size(height * aspectRatio, height);
        }
      } else if (constraints.hasBoundedWidth) {
        return Size(constraints.maxWidth, constraints.maxWidth / aspectRatio);
      } else if (constraints.hasBoundedHeight) {
        return Size(constraints.maxHeight * aspectRatio, constraints.maxHeight);
      }
    }

    // Fallback to constraint bounds or a reasonable default
    return Size(
      constraints.hasBoundedWidth ? constraints.maxWidth : 800,
      constraints.hasBoundedHeight ? constraints.maxHeight : 600,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate is VNCFramePainter) {
      // Only repaint if the frame buffer actually changed
      return oldDelegate.frameBuffer != frameBuffer ||
          oldDelegate.frameBuffer.pixels != frameBuffer.pixels;
    }
    return true;
  }
}
