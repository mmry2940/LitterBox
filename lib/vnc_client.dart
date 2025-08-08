import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';

/// A basic VNC client implementing the RFB protocol
/// This is a simplified implementation inspired by dart_vnc
class VNCClient {
  Socket? _socket;
  String? _host;
  int? _port;
  String? _password;

  StreamController<VNCFrameUpdate>? _frameUpdateController;
  StreamController<VNCConnectionState>? _stateController;
  StreamController<String>? _logController;

  VNCConnectionState _state = VNCConnectionState.disconnected;
  VNCFrameBuffer? _frameBuffer;

  Stream<VNCFrameUpdate> get frameUpdates =>
      _frameUpdateController?.stream ?? const Stream.empty();
  Stream<VNCConnectionState> get connectionState =>
      _stateController?.stream ?? const Stream.empty();
  Stream<String> get logs => _logController?.stream ?? const Stream.empty();

  VNCConnectionState get currentState => _state;
  VNCFrameBuffer? get frameBuffer => _frameBuffer;

  void _log(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    final logMessage = '[$timestamp] VNCClient: $message';
    print(logMessage);
    _logController?.add(logMessage);
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

  /// Connect to VNC server
  Future<bool> connect(String host, int port, {String? password}) async {
    try {
      _host = host;
      _port = port;
      _password = password;

      _frameUpdateController = StreamController<VNCFrameUpdate>.broadcast();
      _stateController = StreamController<VNCConnectionState>.broadcast();
      _logController = StreamController<String>.broadcast();

      _updateState(VNCConnectionState.connecting);
      _log('Starting connection to $host:$port');

      // Add timeout to connection
      _socket =
          await Socket.connect(host, port).timeout(const Duration(seconds: 10));

      _log('Socket connected successfully');

      // Start RFB handshake
      if (await _performHandshake()) {
        _log('Handshake completed successfully');
        _updateState(VNCConnectionState.connected);
        _startListening();
        return true;
      } else {
        _log('Handshake failed');
        _updateState(VNCConnectionState.failed);
        return false;
      }
    } catch (e) {
      _log('Connection failed: $e');
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

    await _frameUpdateController?.close();
    await _stateController?.close();
    await _logController?.close();

    _frameUpdateController = null;
    _stateController = null;
    _logController = null;

    _updateState(VNCConnectionState.disconnected);
    _log('Disconnected successfully');
  }

  /// Send pointer event (mouse)
  void sendPointerEvent(int x, int y, int buttonMask) {
    if (_socket == null || _state != VNCConnectionState.connected) return;

    final message = Uint8List(6);
    message[0] = 5; // PointerEvent message type
    message[1] = buttonMask;
    message.buffer.asByteData().setUint16(2, x, Endian.big);
    message.buffer.asByteData().setUint16(4, y, Endian.big);

    _socket!.add(message);
  }

  /// Send key event
  void sendKeyEvent(int key, bool down) {
    if (_socket == null || _state != VNCConnectionState.connected) return;

    final message = Uint8List(8);
    message[0] = 4; // KeyEvent message type
    message[1] = down ? 1 : 0;
    message.buffer.asByteData().setUint32(4, key, Endian.big);

    _socket!.add(message);
  }

  /// Request frame buffer update
  void requestFrameUpdate({bool incremental = true}) {
    if (_socket == null || _state != VNCConnectionState.connected) return;

    final message = Uint8List(10);
    message[0] = 3; // FramebufferUpdateRequest message type
    message[1] = incremental ? 1 : 0;
    // x, y, width, height = 0, 0, frameBuffer.width, frameBuffer.height
    if (_frameBuffer != null) {
      message.buffer.asByteData().setUint16(6, _frameBuffer!.width, Endian.big);
      message.buffer
          .asByteData()
          .setUint16(8, _frameBuffer!.height, Endian.big);
    }

    _socket!.add(message);
  }

  Future<bool> _performHandshake() async {
    try {
      _log('Starting RFB handshake');

      // RFB Protocol Version Handshake
      _log('Reading server version');
      final versionData = await _readBytes(12);
      final version = String.fromCharCodes(versionData).trim();
      _log('Server version: $version');

      if (!version.startsWith('RFB ')) {
        _log('Invalid RFB version string');
        return false;
      }

      // Send our version (support 3.8)
      final clientVersion = 'RFB 003.008\n';
      _log('Sending client version: ${clientVersion.trim()}');
      _socket!.add(clientVersion.codeUnits);

      // Security handshake
      _log('Reading security types');
      final securityTypesCount = await _readBytes(1);
      final numSecurityTypes = securityTypesCount[0];
      _log('Number of security types: $numSecurityTypes');

      if (numSecurityTypes == 0) {
        _log('Server offered no security types - connection failed');
        // Read reason for failure
        final reasonLength = await _readBytes(4);
        final length =
            reasonLength.buffer.asByteData().getUint32(0, Endian.big);
        if (length > 0) {
          final reason = await _readBytes(length);
          _log('Server failure reason: ${String.fromCharCodes(reason)}');
        }
        return false;
      }

      final availableSecurityTypes = await _readBytes(numSecurityTypes);
      _log('Available security types: $availableSecurityTypes');

      // Choose security type (1 = None, 2 = VNC Authentication)
      int chosenSecurityType = 1; // None by default
      if (_password != null &&
          _password!.isNotEmpty &&
          availableSecurityTypes.contains(2)) {
        chosenSecurityType = 2; // VNC Authentication
        _log('Using VNC Authentication');
      } else if (availableSecurityTypes.contains(1)) {
        chosenSecurityType = 1; // None
        _log('Using no authentication');
      } else {
        _log('No supported security type available');
        return false;
      }

      // Send chosen security type
      _log('Sending security type: $chosenSecurityType');
      _socket!.add([chosenSecurityType]);

      if (chosenSecurityType == 2) {
        _log('Performing VNC authentication');
        // VNC Authentication
        final challenge = await _readBytes(16);
        _log('Received challenge');
        final response = _encryptChallenge(challenge, _password!);
        _socket!.add(response);
        _log('Sent encrypted response');
      }

      // Security result
      _log('Reading security result');
      final securityResult = await _readBytes(4);
      final result =
          securityResult.buffer.asByteData().getUint32(0, Endian.big);
      _log('Security result: $result');

      if (result != 0) {
        _log('Authentication failed');
        if (result == 1) {
          // Try to read failure reason if available
          try {
            final reasonLength = await _readBytes(4);
            final length =
                reasonLength.buffer.asByteData().getUint32(0, Endian.big);
            if (length > 0) {
              final reason = await _readBytes(length);
              _log(
                  'Authentication failure reason: ${String.fromCharCodes(reason)}');
            }
          } catch (e) {
            _log('Could not read failure reason: $e');
          }
        }
        return false;
      }

      _log('Authentication successful');

      // Client initialization
      _log('Sending client initialization');
      _socket!.add([1]); // Shared flag = true

      // Server initialization
      _log('Reading server initialization');
      final serverInitData = await _readBytes(24);
      final serverInit = serverInitData.buffer.asByteData();

      final width = serverInit.getUint16(0, Endian.big);
      final height = serverInit.getUint16(2, Endian.big);
      _log('Server framebuffer size: ${width}x$height');

      final pixelFormat = _parsePixelFormat(serverInitData.sublist(4, 20));
      final nameLength = serverInit.getUint32(20, Endian.big);
      _log('Server name length: $nameLength');

      final nameData = await _readBytes(nameLength);
      final serverName = String.fromCharCodes(nameData);
      _log('Server name: $serverName');

      _frameBuffer = VNCFrameBuffer(width, height, pixelFormat, serverName);
      _log('Framebuffer initialized successfully');

      return true;
    } catch (e) {
      _log('Handshake error: $e');
      return false;
    }
  }

  void _startListening() {
    _socket!.listen((data) {
      _handleServerMessage(data);
    }, onDone: () {
      _updateState(VNCConnectionState.disconnected);
    }, onError: (error) {
      _updateState(VNCConnectionState.failed);
    });

    // Request initial frame update
    requestFrameUpdate(incremental: false);
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
    // Simplified framebuffer update handling
    // In a real implementation, this would parse the actual pixel data
    final update = VNCFrameUpdate(
      x: 0,
      y: 0,
      width: _frameBuffer?.width ?? 0,
      height: _frameBuffer?.height ?? 0,
      pixels: data,
    );

    _frameUpdateController?.add(update);
  }

  Future<Uint8List> _readBytes(int count) async {
    if (_socket == null) {
      throw Exception('Socket is null');
    }

    final completer = Completer<Uint8List>();
    final buffer = <int>[];
    StreamSubscription? subscription;
    Timer? timeoutTimer;

    // Set up timeout
    timeoutTimer = Timer(const Duration(seconds: 30), () {
      subscription?.cancel();
      if (!completer.isCompleted) {
        completer
            .completeError(TimeoutException('Timeout reading $count bytes'));
      }
    });

    subscription = _socket!.listen(
      (data) {
        try {
          buffer.addAll(data);
          _log(
              'Read ${data.length} bytes, buffer now has ${buffer.length}/$count bytes');

          if (buffer.length >= count) {
            timeoutTimer?.cancel();
            subscription?.cancel();

            if (!completer.isCompleted) {
              final result = Uint8List.fromList(buffer.take(count).toList());
              completer.complete(result);
            }
          }
        } catch (e) {
          timeoutTimer?.cancel();
          subscription?.cancel();
          if (!completer.isCompleted) {
            completer.completeError(e);
          }
        }
      },
      onError: (error) {
        timeoutTimer?.cancel();
        subscription?.cancel();
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      },
      onDone: () {
        timeoutTimer?.cancel();
        subscription?.cancel();
        if (!completer.isCompleted) {
          completer.completeError(Exception('Socket closed while reading'));
        }
      },
    );

    return completer.future;
  }

  VNCPixelFormat _parsePixelFormat(Uint8List data) {
    final pixelFormat = data.buffer.asByteData();
    return VNCPixelFormat(
      bitsPerPixel: pixelFormat.getUint8(0),
      depth: pixelFormat.getUint8(1),
      bigEndianFlag: pixelFormat.getUint8(2) != 0,
      trueColourFlag: pixelFormat.getUint8(3) != 0,
      redMax: pixelFormat.getUint16(4, Endian.big),
      greenMax: pixelFormat.getUint16(6, Endian.big),
      blueMax: pixelFormat.getUint16(8, Endian.big),
      redShift: pixelFormat.getUint8(10),
      greenShift: pixelFormat.getUint8(11),
      blueShift: pixelFormat.getUint8(12),
    );
  }

  Uint8List _encryptChallenge(Uint8List challenge, String password) {
    // Simplified DES encryption for VNC authentication
    // In a real implementation, you would use proper DES encryption
    return challenge; // Placeholder
  }

  void _updateState(VNCConnectionState newState) {
    _state = newState;
    _stateController?.add(newState);
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
            GestureDetector(
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
                size: Size(_frameBuffer!.width.toDouble(),
                    _frameBuffer!.height.toDouble()),
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
    // Draw a placeholder pattern since we don't have actual pixel data yet
    final paint = Paint()
      ..color = Colors.blue.shade900
      ..style = PaintingStyle.fill;

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    // Draw grid pattern to simulate desktop
    final gridPaint = Paint()
      ..color = Colors.blue.shade800
      ..strokeWidth = 1;

    for (int i = 0; i < size.width; i += 50) {
      canvas.drawLine(Offset(i.toDouble(), 0),
          Offset(i.toDouble(), size.height), gridPaint);
    }

    for (int i = 0; i < size.height; i += 50) {
      canvas.drawLine(
          Offset(0, i.toDouble()), Offset(size.width, i.toDouble()), gridPaint);
    }

    // Draw server name
    final textPainter = TextPainter(
      text: TextSpan(
        text:
            'Native VNC Client\n${frameBuffer.serverName}\n${frameBuffer.width}x${frameBuffer.height}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();
    textPainter.paint(canvas, const Offset(20, 20));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
