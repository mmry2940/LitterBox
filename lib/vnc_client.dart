import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'dart:convert';

/// A basic VNC client implementing the RFB protocol
/// This is a simplified implementation inspired by dart_vnc
class VNCClient {
  Socket? _socket;
  String? _password;

  late final StreamController<VNCFrameUpdate> _frameUpdateController;
  late final StreamController<VNCConnectionState> _stateController;
  late final StreamController<String> _logController;

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
  }

  Stream<VNCFrameUpdate> get frameUpdates => _frameUpdateController.stream;
  Stream<VNCConnectionState> get connectionState => _stateController.stream;
  Stream<String> get logs => _logController.stream;

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

      _logController = StreamController<String>.broadcast();

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

      _log('Sending client version...');
      const clientVersion = 'RFB 003.008\n';
      _socket!.add(clientVersion.codeUnits);
      _log('Client version sent');

      // Test security type negotiation
      _log('Reading security types count');
      final securityCountData = await _readBytes(1);
      final securityCount = securityCountData[0];
      _log('Server supports $securityCount security types');

      if (securityCount == 0) {
        _log('ERROR: Server rejected connection (0 security types)');
        await _cleanupDebug();
        return false;
      }

      final securityTypesData = await _readBytes(securityCount);
      _log('Security types: ${securityTypesData.join(', ')}');

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

      // Choose compatible version (prefer 3.8, fallback to 3.3)
      String clientVersion;
      if (majorVersion >= 5) {
        // RFB 5.x servers - use 3.8 for best compatibility
        clientVersion = 'RFB 003.008\n';
      } else if (majorVersion == 3 && minorVersion >= 8) {
        // RFB 3.8+ servers
        clientVersion = 'RFB 003.008\n';
      } else if (majorVersion == 3 && minorVersion >= 7) {
        // RFB 3.7 servers
        clientVersion = 'RFB 003.007\n';
      } else {
        // Fallback to RFB 3.3 for older servers
        clientVersion = 'RFB 003.003\n';
      }

      _log('Sending client version: "${clientVersion.trim()}"');
      _socket!.add(clientVersion.codeUnits);

      // Security negotiation
      _log('Starting security negotiation');

      if (majorVersion == 3 && minorVersion < 7) {
        // RFB 3.3 and 3.6: server decides security type
        final securityTypeData = await _readBytes(4);
        final securityType = (securityTypeData[0] << 24) |
            (securityTypeData[1] << 16) |
            (securityTypeData[2] << 8) |
            securityTypeData[3];
        _log('Server security type (RFB 3.3/3.6): $securityType');

        if (securityType == 0) {
          // Connection failed
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

        return await _handleSecurityType(securityType);
      } else {
        // RFB 3.7+: server lists supported security types
        final securityCountData = await _readBytes(1);
        final securityCount = securityCountData[0];
        _log('Server supports $securityCount security types');

        if (securityCount == 0) {
          // Connection failed
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
          } else if (securityTypes.contains(1)) {
            chosenSecurityType = 1; // None
            _log('WARNING: Password provided but using no authentication');
          } else if (securityTypes.contains(5)) {
            chosenSecurityType = 5; // RA2
          } else if (securityTypes.contains(13)) {
            chosenSecurityType = 13; // RA2ne
          } else if (securityTypes.contains(16)) {
            chosenSecurityType = 16; // ATEN
          } else {
            _log('ERROR: No supported security types for password auth');
            return false;
          }
        } else {
          if (securityTypes.contains(1)) {
            chosenSecurityType = 1; // None
          } else if (securityTypes.contains(2)) {
            chosenSecurityType = 2; // VNC Authentication (without password)
            _log('WARNING: Using VNC auth without password');
          } else {
            _log('ERROR: No supported security types');
            return false;
          }
        }

        _log('Choosing security type: $chosenSecurityType');
        _socket!.add([chosenSecurityType]);

        return await _handleSecurityType(chosenSecurityType);
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
        _log('Using RA2 authentication (experimental support)');
        try {
          // RA2 uses a different challenge-response mechanism
          final challenge = await _readBytes(8);
          _log('Received RA2 8-byte challenge');

          if (_password == null || _password!.isEmpty) {
            _log('ERROR: RA2 auth requires password');
            return false;
          }

          // For RA2, we'll try a simplified response
          final response = _encryptRA2Challenge(challenge, _password!);
          _socket!.add(response);
          _log('Sent RA2 response');
        } catch (e) {
          _log('RA2 authentication failed: $e');
          return false;
        }
        break;

      case 13: // RA2ne
        _log('Using RA2ne authentication (experimental support)');
        try {
          // Similar to RA2 but different encryption
          final challenge = await _readBytes(8);
          _log('Received RA2ne 8-byte challenge');

          if (_password == null || _password!.isEmpty) {
            _log('ERROR: RA2ne auth requires password');
            return false;
          }

          final response = _encryptRA2neChallenge(challenge, _password!);
          _socket!.add(response);
          _log('Sent RA2ne response');
        } catch (e) {
          _log('RA2ne authentication failed: $e');
          return false;
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

      if (result != 0) {
        _log('ERROR: Authentication failed (result: $result)');

        // Try to read failure reason if available
        try {
          final reasonLengthData = await _readBytes(4);
          final reasonLength = (reasonLengthData[0] << 24) |
              (reasonLengthData[1] << 16) |
              (reasonLengthData[2] << 8) |
              reasonLengthData[3];

          if (reasonLength > 0 && reasonLength < 1000) {
            final reasonData = await _readBytes(reasonLength);
            final reason = String.fromCharCodes(reasonData);
            _log('Authentication failure reason: $reason');
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
      _log('Read $count bytes from buffer');
      return data;
    }

    // Wait for more data
    final completer = Completer<Uint8List>();
    _readCompleters.add(completer);
    _readCounts.add(count);

    // Set timeout for read operation
    Timer(const Duration(seconds: 10), () {
      if (!completer.isCompleted) {
        _log('Timeout reading $count bytes (received ${_buffer.length} bytes)');
        final index = _readCompleters.indexOf(completer);
        if (index != -1) {
          _readCompleters.removeAt(index);
          _readCounts.removeAt(index);
        }
        completer.completeError(TimeoutException('Read timeout'));
      }
    });

    return completer.future;
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
    // RA2 encryption - simplified implementation
    final passwordBytes = utf8.encode(password);
    final result = Uint8List(8);

    for (int i = 0; i < 8; i++) {
      result[i] = challenge[i] ^ (passwordBytes[i % passwordBytes.length] + i);
    }

    return result;
  }

  Uint8List _encryptRA2neChallenge(Uint8List challenge, String password) {
    // RA2ne encryption - simplified implementation
    final passwordBytes = utf8.encode(password);
    final result = Uint8List(8);

    for (int i = 0; i < 8; i++) {
      result[i] = challenge[i] ^ passwordBytes[i % passwordBytes.length];
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

      // Set up pixel format (use 16-bit RGB565 for performance)
      await _setPixelFormat();

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

  // Set pixel format to 16-bit RGB565
  Future<void> _setPixelFormat() async {
    final setPixelFormat = Uint8List(20);
    setPixelFormat[0] = 0; // SetPixelFormat message type

    // Pixel format (16-bit RGB565)
    setPixelFormat[4] = 16; // bits-per-pixel
    setPixelFormat[5] = 16; // depth
    setPixelFormat[6] = 0; // big-endian-flag
    setPixelFormat[7] = 1; // true-color-flag
    setPixelFormat[8] = 0; // red-max high byte
    setPixelFormat[9] = 31; // red-max low byte (31)
    setPixelFormat[10] = 0; // green-max high byte
    setPixelFormat[11] = 63; // green-max low byte (63)
    setPixelFormat[12] = 0; // blue-max high byte
    setPixelFormat[13] = 31; // blue-max low byte (31)
    setPixelFormat[14] = 11; // red-shift
    setPixelFormat[15] = 5; // green-shift
    setPixelFormat[16] = 0; // blue-shift

    _socket!.add(setPixelFormat);
    _log('Set pixel format to 16-bit RGB565');
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
    while (_buffer.isNotEmpty) {
      if (_buffer.isEmpty) return;

      final messageType = _buffer[0];
      int messageLength = 0;

      switch (messageType) {
        case 0: // FramebufferUpdate
          if (_buffer.length < 4) return; // Need at least header
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
          // Skip this byte and try to resync
          _buffer.removeAt(0);
          continue;
      }

      if (messageLength == 0 || _buffer.length < messageLength) {
        return; // Wait for more data
      }

      // Extract and process the complete message
      final messageData =
          Uint8List.fromList(_buffer.take(messageLength).toList());
      _buffer.removeRange(0, messageLength);

      _handleServerMessage(messageData);
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
        // Raw encoding - calculate pixel data size
        final pixelDataSize = width * height * 4; // Server sends 32bpp
        _log('Adding $pixelDataSize bytes of pixel data for rectangle $i');
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
        break;
      case 3: // ServerCutText
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

  void _updateState(VNCConnectionState newState) {
    print('DEBUG: _updateState called with: $newState, old state: $_state');
    _state = newState;
    print(
        'DEBUG: Broadcasting state $newState to ${_stateController.hasListener ? "listeners" : "no listeners"}');
    _stateController.add(newState);
    print('DEBUG: State update complete, current state: $_state');
  }

  void dispose() {
    _socket?.close();
    _frameUpdateController.close();
    _stateController.close();
    _logController.close();
    _socketSubscription?.cancel();
  }
}

enum VNCConnectionState {
  disconnected,
  connecting,
  connected,
  disconnecting,
  failed,
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

  const VNCClientWidget({super.key, required this.client});

  @override
  State<VNCClientWidget> createState() => _VNCClientWidgetState();
}

class _VNCClientWidgetState extends State<VNCClientWidget> {
  VNCConnectionState _connectionState = VNCConnectionState.disconnected;
  VNCFrameBuffer? _frameBuffer;

  @override
  void initState() {
    super.initState();

    widget.client.connectionState.listen((state) {
      setState(() {
        _connectionState = state;
      });
    });

    widget.client.frameUpdates.listen((update) {
      setState(() {
        _frameBuffer = widget.client.frameBuffer;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          if (_frameBuffer != null)
            Positioned.fill(
              child: GestureDetector(
                onTapDown: (details) {
                  final x = details.localPosition.dx.round();
                  final y = details.localPosition.dy.round();
                  widget.client.sendPointerEvent(x, y, 1); // Left click
                },
                onTapUp: (details) {
                  final x = details.localPosition.dx.round();
                  final y = details.localPosition.dy.round();
                  widget.client.sendPointerEvent(x, y, 0); // Release
                },
                child: CustomPaint(
                  painter: VNCFramePainter(_frameBuffer!),
                  child: Container(), // Ensure the painter fills the area
                ),
              ),
            ),

          // Connection status overlay
          if (_connectionState != VNCConnectionState.connected)
            Container(
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
                    ] else if (_connectionState ==
                        VNCConnectionState.failed) ...[
                      const Icon(Icons.error, color: Colors.red, size: 48),
                      const SizedBox(height: 16),
                      const Text(
                        'Connection failed',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ] else if (_connectionState ==
                        VNCConnectionState.disconnected) ...[
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
            ),
        ],
      ),
    );
  }
}

class VNCFramePainter extends CustomPainter {
  final VNCFrameBuffer frameBuffer;

  VNCFramePainter(this.frameBuffer);

  @override
  void paint(Canvas canvas, Size size) {
    // Debug info
    print(
        '[VNCFramePainter] Paint called - Canvas size: ${size.width}x${size.height}');
    print(
        '[VNCFramePainter] Frame buffer: ${frameBuffer.width}x${frameBuffer.height}');
    print(
        '[VNCFramePainter] Has pixels: ${frameBuffer.pixels != null}, Length: ${frameBuffer.pixels?.length ?? 0}');

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
    final pixels = frameBuffer.pixels!;
    final width = frameBuffer.width;
    final height = frameBuffer.height;

    print(
        '[VNCFramePainter] Drawing pixels - FB: ${width}x${height}, Canvas: ${size.width}x${size.height}');

    // Calculate scaling factors
    final scaleX = size.width / width;
    final scaleY = size.height / height;
    final scale = scaleX < scaleY ? scaleX : scaleY; // Maintain aspect ratio

    final offsetX = (size.width - width * scale) / 2;
    final offsetY = (size.height - height * scale) / 2;

    print('[VNCFramePainter] Scale: $scale, Offset: ($offsetX, $offsetY)');

    // Draw pixels - sample every few pixels for performance when scaled down
    final sampleRate = (scale < 0.5) ? (1 / scale).ceil() : 1;

    print('[VNCFramePainter] Sample rate: $sampleRate');

    int pixelsDrawn = 0;
    for (int y = 0; y < height; y += sampleRate) {
      for (int x = 0; x < width; x += sampleRate) {
        final pixelOffset = (y * width + x) * 4; // RGBA format

        if (pixelOffset + 3 < pixels.length) {
          final r = pixels[pixelOffset]; // Red
          final g = pixels[pixelOffset + 1]; // Green
          final b = pixels[pixelOffset + 2]; // Blue
          // final a = pixels[pixelOffset + 3]; // Alpha - not used, forcing full opacity

          // Don't skip any pixels - draw everything for debugging
          final color = Color.fromARGB(255, r, g, b); // Force alpha to 255
          final paint = Paint()..color = color;

          // Draw scaled pixel
          final pixelSize = scale * sampleRate;
          final rect = Rect.fromLTWH(
            offsetX + x * scale,
            offsetY + y * scale,
            pixelSize < 1.0 ? 1.0 : pixelSize,
            pixelSize < 1.0 ? 1.0 : pixelSize,
          );

          canvas.drawRect(rect, paint);
          pixelsDrawn++;
        }
      }
    }

    print('[VNCFramePainter] Drew $pixelsDrawn pixels');
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
