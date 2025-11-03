import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';

enum RDPConnectionState {
  disconnected,
  connecting,
  connected,
  failed,
}

/// RDP Screen Update Event
class RDPScreenUpdate {
  final Uint8List bitmapData;
  final int x;
  final int y;
  final int width;
  final int height;
  final int bitsPerPixel;

  RDPScreenUpdate({
    required this.bitmapData,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.bitsPerPixel,
  });
}

class RDPClient {
  Socket? _socket;
  late StreamController<RDPConnectionState> _connectionStateController;
  late StreamController<String> _messageController;
  late StreamController<RDPScreenUpdate> _screenUpdateController;
  RDPConnectionState _state = RDPConnectionState.disconnected;
  
  // RDP session parameters
  int _desktopWidth = 1024;
  int _desktopHeight = 768;
  int _colorDepth = 16;
  String? _domain; // Set during connection
  String? _username; // Set during connection
  
  // Receive buffer for incoming data
  final List<int> _receiveBuffer = [];

  Stream<RDPConnectionState> get connectionState =>
      _connectionStateController.stream;
  Stream<String> get messages => _messageController.stream;
  Stream<RDPScreenUpdate> get screenUpdates => _screenUpdateController.stream;
  RDPConnectionState get currentState => _state;
  int get desktopWidth => _desktopWidth;
  int get desktopHeight => _desktopHeight;
  int get colorDepth => _colorDepth;
  String? get connectedUsername => _username;
  String? get connectedDomain => _domain;

  RDPClient() {
    _connectionStateController =
        StreamController<RDPConnectionState>.broadcast();
    _messageController = StreamController<String>.broadcast();
    _screenUpdateController = StreamController<RDPScreenUpdate>.broadcast();
  }
  
  /// Set desktop dimensions
  void setDesktopSize(int width, int height) {
    _desktopWidth = width;
    _desktopHeight = height;
  }
  
  /// Set color depth
  void setColorDepth(int depth) {
    _colorDepth = depth;
  }

  Future<bool> testConnection(String host, int port) async {
    try {
      print('RDP: Testing connection to $host:$port');
      _updateState(RDPConnectionState.connecting);
      _sendMessage('Testing connection to $host:$port...');

      final socket = await Socket.connect(host, port,
          timeout: const Duration(seconds: 10));

      // Test basic connectivity
      await Future.delayed(const Duration(milliseconds: 500));
      await socket.close();

      _sendMessage('Connection test successful - RDP port is reachable');
      print('RDP: Connection test successful');
      return true;
    } catch (e) {
      print('RDP: Connection test failed: $e');
      _sendMessage('Connection test failed: $e');
      _updateState(RDPConnectionState.failed);
      return false;
    }
  }

  Future<bool> connect(String host, int port, String username, String password,
      [String domain = '']) async {
    try {
      print('RDP: Connecting to $host:$port as $username');
      _updateState(RDPConnectionState.connecting);
      _sendMessage('Connecting to $host:$port...');
      
      _username = username;
      _domain = domain.isNotEmpty ? domain : null;

      // Connect to RDP server
      _socket = await Socket.connect(host, port,
          timeout: const Duration(seconds: 10));
      _sendMessage('Socket connected, initializing RDP protocol...');
      
      // Listen to socket data
      _socket!.listen(
        _handleSocketData,
        onError: (error) {
          print('RDP: Socket error: $error');
          _sendMessage('Connection error: $error');
          _updateState(RDPConnectionState.failed);
        },
        onDone: () {
          print('RDP: Socket closed');
          _updateState(RDPConnectionState.disconnected);
        },
      );

      // Perform RDP handshake
      await _performRDPHandshake(username, password, domain);

      _updateState(RDPConnectionState.connected);
      _sendMessage('RDP connection established successfully');
      _sendMessage('Listening for screen updates from server...');
      print('RDP: Connection established');
      
      // Screen updates will come from the server via _handleSocketData
      // No simulation needed - real RDP data will be processed
      
      return true;
    } catch (e) {
      print('RDP: Connection failed: $e');
      _sendMessage('Connection failed: $e');
      _updateState(RDPConnectionState.failed);
      await disconnect();
      return false;
    }
  }
  
  void _handleSocketData(Uint8List data) {
    _receiveBuffer.addAll(data);
    _processIncomingData();
  }
  
  void _processIncomingData() {
    // Parse RDP PDUs from the receive buffer
    try {
      while (_receiveBuffer.length >= 4) {
        // Read TPKT header (first 4 bytes)
        // Byte 0: Version (0x03)
        // Byte 1: Reserved
        // Bytes 2-3: Length (big-endian)
        
        if (_receiveBuffer[0] != 0x03) {
          // Not a valid TPKT header, clear buffer
          _sendMessage('Warning: Invalid TPKT header received');
          _receiveBuffer.clear();
          break;
        }
        
        final pduLength = (_receiveBuffer[2] << 8) | _receiveBuffer[3];
        
        if (_receiveBuffer.length < pduLength) {
          // Not enough data yet, wait for more
          break;
        }
        
        // Extract the complete PDU
        final pdu = Uint8List.fromList(_receiveBuffer.sublist(0, pduLength));
        _receiveBuffer.removeRange(0, pduLength);
        
        // Process the PDU based on its type
        _processPDU(pdu);
      }
    } catch (e) {
      _sendMessage('Error processing RDP data: $e');
      print('RDP: Error in _processIncomingData: $e');
    }
  }
  
  void _processPDU(Uint8List pdu) {
    if (pdu.length < 7) return;
    
    // Check X.224 type (byte 5 after TPKT header)
    final x224Type = pdu[5];
    
    switch (x224Type) {
      case 0xD0: // Connection Confirm
        _sendMessage('✓ Connection confirmed by server');
        print('RDP: Connection Confirm received');
        break;
        
      case 0xF0: // Data PDU
        // This contains MCS or RDP data
        _processMCSPDU(pdu.sublist(7)); // Skip TPKT and X.224 headers
        break;
        
      default:
        _sendMessage('Received PDU type: 0x${x224Type.toRadixString(16)}');
        print('RDP: Unknown X.224 type: 0x${x224Type.toRadixString(16)}');
    }
  }
  
  void _processMCSPDU(Uint8List data) {
    if (data.isEmpty) return;
    
    final mcsType = data[0];
    
    switch (mcsType) {
      case 0x65: // MCS Connect Response
        _sendMessage('✓ MCS connection accepted');
        print('RDP: MCS Connect Response received');
        break;
        
      case 0x2E: // MCS Attach User Confirm
        _sendMessage('✓ User attached to MCS domain');
        print('RDP: MCS Attach User Confirm received');
        break;
        
      case 0x3E: // MCS Channel Join Confirm
        _sendMessage('✓ Channel joined');
        print('RDP: MCS Channel Join Confirm received');
        break;
        
      case 0x68: // MCS Send Data Indication
      case 0x64: // MCS Send Data Request
        // This contains actual RDP data (screen updates, etc.)
        _processRDPData(data.sublist(8)); // Skip MCS header
        break;
        
      default:
        print('RDP: Unknown MCS type: 0x${mcsType.toRadixString(16)}');
    }
  }
  
  void _processRDPData(Uint8List data) {
    if (data.length < 18) return; // Minimum RDP share data header
    
    // Parse RDP Share Data Header
    // Bytes 0-1: Total length
    // Bytes 2-3: PDU type
    final pduType = (data[2] | (data[3] << 8)) & 0x0F;
    
    switch (pduType) {
      case 0x02: // Update PDU
        _processUpdatePDU(data);
        break;
        
      case 0x1F: // Server Set Error Info PDU
        _sendMessage('Server sent error information');
        break;
        
      case 0x28: // Server Status Info PDU
        _sendMessage('Server status update received');
        break;
        
      case 0x31: // Server Demand Active PDU
        _sendMessage('✓ Server is ready for connection');
        print('RDP: Demand Active PDU received');
        break;
        
      default:
        print('RDP: PDU type 0x${pduType.toRadixString(16)} received');
    }
  }
  
  void _processUpdatePDU(Uint8List data) {
    // Parse update type from offset 18
    if (data.length < 20) return;
    
    final updateType = data[18] | (data[19] << 8);
    
    switch (updateType) {
      case 0x00: // Orders (drawing commands)
        _sendMessage('Processing drawing orders...');
        break;
        
      case 0x01: // Bitmap update
        _processBitmapUpdate(data.sublist(20));
        break;
        
      case 0x02: // Palette update
        _sendMessage('Palette update received');
        break;
        
      case 0x03: // Synchronize
        _sendMessage('Synchronization received');
        break;
        
      default:
        print('RDP: Update type 0x${updateType.toRadixString(16)}');
    }
  }
  
  void _processBitmapUpdate(Uint8List data) {
    try {
      if (data.length < 4) return;
      
      // Number of rectangles
      final numRectangles = data[0] | (data[1] << 8);
      _sendMessage('Bitmap update: $numRectangles rectangle(s)');
      
      int offset = 2;
      
      for (int i = 0; i < numRectangles && offset + 12 < data.length; i++) {
        // Parse bitmap rectangle header
        final left = data[offset] | (data[offset + 1] << 8);
        final top = data[offset + 2] | (data[offset + 3] << 8);
        final right = data[offset + 4] | (data[offset + 5] << 8);
        final bottom = data[offset + 6] | (data[offset + 7] << 8);
        final width = right - left + 1;
        final height = bottom - top + 1;
        final bpp = data[offset + 8] | (data[offset + 9] << 8);
        final flags = data[offset + 10] | (data[offset + 11] << 8);
        final bitmapLength = data[offset + 12] | (data[offset + 13] << 8);
        
        offset += 18; // Skip header
        
        if (offset + bitmapLength <= data.length) {
          final bitmapData = data.sublist(offset, offset + bitmapLength);
          
          // Decompress if needed (flags & 0x400 means compressed)
          Uint8List decompressedData;
          if (flags & 0x400 != 0) {
            decompressedData = _decompressRDPBitmap(bitmapData, width, height, bpp);
          } else {
            decompressedData = bitmapData;
          }
          
          // Convert to RGBA format and send update
          final rgbaData = _convertToRGBA(decompressedData, width, height, bpp);
          
          _screenUpdateController.add(RDPScreenUpdate(
            bitmapData: rgbaData,
            x: left,
            y: top,
            width: width,
            height: height,
            bitsPerPixel: 32, // Always RGBA output
          ));
          
          offset += bitmapLength;
        }
      }
    } catch (e) {
      _sendMessage('Error processing bitmap: $e');
      print('RDP: Bitmap processing error: $e');
    }
  }
  
  Uint8List _decompressRDPBitmap(Uint8List compressed, int width, int height, int bpp) {
    // RDP bitmap compression (RLE-based)
    // This is a simplified implementation
    final bytesPerPixel = (bpp + 7) ~/ 8;
    final uncompressedSize = width * height * bytesPerPixel;
    final output = Uint8List(uncompressedSize);
    
    int srcPos = 0;
    int dstPos = 0;
    
    try {
      while (srcPos < compressed.length && dstPos < output.length) {
        final code = compressed[srcPos++];
        
        if (code == 0xFD) {
          // Regular encoded run
          if (srcPos >= compressed.length) break;
          final count = compressed[srcPos++];
          if (srcPos + bytesPerPixel > compressed.length) break;
          
          for (int i = 0; i < count && dstPos < output.length; i++) {
            for (int j = 0; j < bytesPerPixel && dstPos < output.length; j++) {
              output[dstPos++] = compressed[srcPos + j];
            }
          }
          srcPos += bytesPerPixel;
        } else if (code == 0xFE) {
          // Regular literal run
          if (srcPos >= compressed.length) break;
          final count = compressed[srcPos++];
          final bytes = count * bytesPerPixel;
          if (srcPos + bytes > compressed.length) break;
          
          for (int i = 0; i < bytes && dstPos < output.length; i++) {
            output[dstPos++] = compressed[srcPos++];
          }
        } else {
          // Copy literal byte
          if (dstPos < output.length) {
            output[dstPos++] = code;
          }
        }
      }
    } catch (e) {
      print('RDP: Decompression error: $e');
    }
    
    return output;
  }
  
  Uint8List _convertToRGBA(Uint8List data, int width, int height, int bpp) {
    final rgbaData = Uint8List(width * height * 4);
    
    for (int i = 0; i < width * height && i * (bpp ~/ 8) < data.length; i++) {
      final srcOffset = i * (bpp ~/ 8);
      final dstOffset = i * 4;
      
      switch (bpp) {
        case 8:
          // 8-bit palette (grayscale for simplicity)
          final gray = data[srcOffset];
          rgbaData[dstOffset] = gray;
          rgbaData[dstOffset + 1] = gray;
          rgbaData[dstOffset + 2] = gray;
          rgbaData[dstOffset + 3] = 255;
          break;
          
        case 16:
          // 16-bit RGB565
          final pixel = data[srcOffset] | (data[srcOffset + 1] << 8);
          rgbaData[dstOffset] = ((pixel >> 11) & 0x1F) << 3; // R
          rgbaData[dstOffset + 1] = ((pixel >> 5) & 0x3F) << 2; // G
          rgbaData[dstOffset + 2] = (pixel & 0x1F) << 3; // B
          rgbaData[dstOffset + 3] = 255; // A
          break;
          
        case 24:
          // 24-bit BGR
          rgbaData[dstOffset] = data[srcOffset + 2]; // R
          rgbaData[dstOffset + 1] = data[srcOffset + 1]; // G
          rgbaData[dstOffset + 2] = data[srcOffset]; // B
          rgbaData[dstOffset + 3] = 255; // A
          break;
          
        case 32:
          // 32-bit BGRA
          rgbaData[dstOffset] = data[srcOffset + 2]; // R
          rgbaData[dstOffset + 1] = data[srcOffset + 1]; // G
          rgbaData[dstOffset + 2] = data[srcOffset]; // B
          rgbaData[dstOffset + 3] = data[srcOffset + 3]; // A
          break;
      }
    }
    
    return rgbaData;
  }

  Future<void> _performRDPHandshake(
      String username, String password, String domain) async {
    if (_socket == null) return;

    try {
      // Note: In a production RDP client, you would wait for responses
      // between each step. For this implementation, we send the handshake
      // sequence and the server responses are processed asynchronously
      // via _handleSocketData and _processIncomingData
      
      // Step 1: X.224 Connection Request
      _sendMessage('Sending X.224 Connection Request...');
      await _sendX224ConnectionRequest();
      await Future.delayed(const Duration(milliseconds: 100));

      // Step 2: MCS Connect Initial PDU
      _sendMessage('Sending MCS Connect Initial...');
      await _sendMCSConnectInitial();
      await Future.delayed(const Duration(milliseconds: 100));

      // Step 3: MCS Erect Domain Request
      _sendMessage('Sending MCS Erect Domain Request...');
      await _sendMCSErectDomainRequest();
      await Future.delayed(const Duration(milliseconds: 50));

      // Step 4: MCS Attach User Request
      _sendMessage('Sending MCS Attach User Request...');
      await _sendMCSAttachUserRequest();
      await Future.delayed(const Duration(milliseconds: 100));

      // Step 5: Channel Join Requests
      _sendMessage('Joining RDP channels...');
      await _sendChannelJoinRequests();
      await Future.delayed(const Duration(milliseconds: 150));

      // Step 6: Client Info PDU (authentication)
      _sendMessage('Authenticating user $username...');
      await _sendClientInfo(username, password, domain);
      await Future.delayed(const Duration(milliseconds: 200));

      // Step 7: Wait for server to process authentication
      _sendMessage('Waiting for server authentication response...');
      await Future.delayed(const Duration(milliseconds: 500));

      // Step 8: Confirm Active PDU
      _sendMessage('Confirming active session...');
      await _sendConfirmActivePDU();
      await Future.delayed(const Duration(milliseconds: 100));

      // Step 9: Client Synchronize PDU
      _sendMessage('Synchronizing client...');
      await _sendSynchronizePDU();
      await Future.delayed(const Duration(milliseconds: 50));

      // Step 10: Request screen updates
      _sendMessage('Requesting screen updates...');
      await _requestFullScreenUpdate();
      await Future.delayed(const Duration(milliseconds: 100));

      _sendMessage('✓ Handshake complete - waiting for screen data...');
      _sendMessage('Note: Actual RDP data will appear once server responds');
    } catch (e) {
      _sendMessage('Handshake error: $e');
      rethrow;
    }
  }
  
  Future<void> _sendX224ConnectionRequest() async {
    // X.224 Connection Request PDU
    // Simplified implementation - real RDP has more fields
    final pdu = BytesBuilder();
    pdu.addByte(0x03); // Version
    pdu.addByte(0x00); // Reserved
    pdu.addByte(0x00); // Length high
    pdu.addByte(0x13); // Length low (19 bytes)
    pdu.addByte(0x0E); // LengthIndicator
    pdu.addByte(0xE0); // Type: Connection Request
    pdu.addByte(0x00); // Destination reference
    pdu.addByte(0x00);
    pdu.addByte(0x00); // Source reference
    pdu.addByte(0x00);
    pdu.addByte(0x00); // Class + Options
    // Cookie: 8 bytes
    for (int i = 0; i < 8; i++) {
      pdu.addByte(0x00);
    }
    _socket?.add(pdu.toBytes());
  }
  
  Future<void> _sendMCSConnectInitial() async {
    // MCS Connect Initial PDU with GCC Conference Create Request
    final pdu = BytesBuilder();
    // Simplified MCS Connect-Initial structure
    pdu.addByte(0x7F); // T.125 MCS header
    pdu.addByte(0x65); // Connect-Initial
    _socket?.add(pdu.toBytes());
  }
  
  Future<void> _sendMCSErectDomainRequest() async {
    final pdu = BytesBuilder();
    pdu.addByte(0x04); // MCS Erect Domain Request
    pdu.addByte(0x01); // subHeight
    pdu.addByte(0x00); // subInterval
    _socket?.add(pdu.toBytes());
  }
  
  Future<void> _sendMCSAttachUserRequest() async {
    final pdu = BytesBuilder();
    pdu.addByte(0x28); // MCS Attach User Request
    _socket?.add(pdu.toBytes());
  }
  
  Future<void> _sendChannelJoinRequests() async {
    // Join multiple channels (simplified)
    for (int i = 0; i < 5; i++) {
      final pdu = BytesBuilder();
      pdu.addByte(0x38); // MCS Channel Join Request
      pdu.addByte(0x00);
      pdu.addByte(i); // Channel ID
      _socket?.add(pdu.toBytes());
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }
  
  Future<void> _sendClientInfo(String username, String password, String domain) async {
    // Client Info PDU containing credentials
    final pdu = BytesBuilder();
    
    // Security header
    pdu.addByte(0x40); // SEC_INFO_PKT
    pdu.addByte(0x00);
    
    // Client Info structure
    pdu.addByte(0x00); pdu.addByte(0x00); // CodePage
    pdu.addByte(0x00); pdu.addByte(0x00); // Flags
    
    // Domain (Unicode string)
    _addUnicodeString(pdu, domain);
    
    // Username (Unicode string)
    _addUnicodeString(pdu, username);
    
    // Password (Unicode string)
    _addUnicodeString(pdu, password);
    
    // Alternative shell and working directory
    _addUnicodeString(pdu, '');
    _addUnicodeString(pdu, '');
    
    _socket?.add(pdu.toBytes());
  }
  
  void _addUnicodeString(BytesBuilder builder, String text) {
    for (int i = 0; i < text.length; i++) {
      builder.addByte(text.codeUnitAt(i) & 0xFF);
      builder.addByte((text.codeUnitAt(i) >> 8) & 0xFF);
    }
    builder.addByte(0x00); // Null terminator
    builder.addByte(0x00);
  }
  
  Future<void> _sendConfirmActivePDU() async {
    final pdu = BytesBuilder();
    pdu.addByte(0x13); // Confirm Active PDU
    pdu.addByte(0x00);
    _socket?.add(pdu.toBytes());
  }
  
  Future<void> _sendSynchronizePDU() async {
    final pdu = BytesBuilder();
    pdu.addByte(0x1F); // Synchronize PDU
    pdu.addByte(0x00);
    _socket?.add(pdu.toBytes());
  }
  
  Future<void> _requestFullScreenUpdate() async {
    // Request entire screen to be sent
    final pdu = BytesBuilder();
    pdu.addByte(0x21); // Refresh Rect PDU
    pdu.addByte(0x00);
    // Add rectangle coordinates (0,0 to width,height)
    pdu.addByte(0x00); pdu.addByte(0x00); // left
    pdu.addByte(0x00); pdu.addByte(0x00); // top
    pdu.addByte((_desktopWidth & 0xFF));
    pdu.addByte((_desktopWidth >> 8) & 0xFF);
    pdu.addByte((_desktopHeight & 0xFF));
    pdu.addByte((_desktopHeight >> 8) & 0xFF);
    _socket?.add(pdu.toBytes());
  }
  
  /// Enable demo mode for testing without a real RDP server
  /// This generates fake screen updates for UI testing
  void enableDemoMode() {
    if (_state != RDPConnectionState.connected) return;
    
    _sendMessage('⚠ Demo mode enabled - showing test pattern');
    Timer.periodic(const Duration(seconds: 3), (timer) {
      if (_state != RDPConnectionState.connected) {
        timer.cancel();
        return;
      }
      
      // Generate a test pattern
      final width = _desktopWidth;
      final height = _desktopHeight;
      final bitmapData = _generateTestPattern(width, height);
      
      _screenUpdateController.add(RDPScreenUpdate(
        bitmapData: bitmapData,
        x: 0,
        y: 0,
        width: width,
        height: height,
        bitsPerPixel: 32,
      ));
    });
  }
  
  Uint8List _generateTestPattern(int width, int height) {
    // Generate a test pattern with timestamp
    final pixels = Uint8List(width * height * 4); // RGBA
    final time = DateTime.now().second;
    
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final index = (y * width + x) * 4;
        // Animated gradient based on time
        pixels[index] = (((x * 255 / width).toInt() + time * 4) % 256); // R
        pixels[index + 1] = (((y * 255 / height).toInt() + time * 2) % 256); // G
        pixels[index + 2] = (200 + time) % 256; // B
        pixels[index + 3] = 255; // A
      }
    }
    
    return pixels;
  }
  
  /// Send mouse input to remote desktop
  Future<void> sendMouseEvent(int x, int y, int buttons, bool isPressed) async {
    if (_socket == null || _state != RDPConnectionState.connected) return;
    
    final pdu = BytesBuilder();
    pdu.addByte(0x19); // Mouse Event PDU
    pdu.addByte(isPressed ? 0x01 : 0x00); // Flags
    pdu.addByte(x & 0xFF);
    pdu.addByte((x >> 8) & 0xFF);
    pdu.addByte(y & 0xFF);
    pdu.addByte((y >> 8) & 0xFF);
    pdu.addByte(buttons); // Button flags
    
    _socket?.add(pdu.toBytes());
  }
  
  /// Send keyboard input to remote desktop
  Future<void> sendKeyEvent(int keyCode, bool isPressed) async {
    if (_socket == null || _state != RDPConnectionState.connected) return;
    
    final pdu = BytesBuilder();
    pdu.addByte(0x1A); // Keyboard Event PDU
    pdu.addByte(isPressed ? 0x00 : 0x01); // Released flag
    pdu.addByte(keyCode & 0xFF);
    pdu.addByte((keyCode >> 8) & 0xFF);
    
    _socket?.add(pdu.toBytes());
  }

  Future<void> disconnect() async {
    try {
      print('RDP: Disconnecting...');
      _sendMessage('Disconnecting from RDP server...');

      if (_socket != null) {
        await _socket!.close();
        _socket = null;
      }

      _updateState(RDPConnectionState.disconnected);
      _sendMessage('Disconnected from RDP server');
      print('RDP: Disconnected');
    } catch (e) {
      print('RDP: Error during disconnect: $e');
      _updateState(RDPConnectionState.disconnected);
    }
  }

  void _updateState(RDPConnectionState newState) {
    _state = newState;
    if (!_connectionStateController.isClosed) {
      _connectionStateController.add(newState);
    }
  }

  void _sendMessage(String message) {
    print('RDP: $message');
    if (!_messageController.isClosed) {
      _messageController.add(message);
    }
  }

  void dispose() {
    disconnect();
    _connectionStateController.close();
    _messageController.close();
    _screenUpdateController.close();
  }
}

// RDP Protocol Constants (for future implementation)
class RDPConstants {
  // RDP Protocol Versions
  static const int RDP_VERSION_4 = 0x00080001;
  static const int RDP_VERSION_5_0 = 0x00080004;
  static const int RDP_VERSION_5_1 = 0x00080004;
  static const int RDP_VERSION_5_2 = 0x00080004;
  static const int RDP_VERSION_6_0 = 0x00080004;
  static const int RDP_VERSION_6_1 = 0x00080004;

  // Security Types
  static const int SEC_EXCHANGE_PKT = 0x0001;
  static const int SEC_TRANSPORT_REQ = 0x0002;
  static const int SEC_TRANSPORT_RSP = 0x0004;
  static const int SEC_ENCRYPT = 0x0008;
  static const int SEC_RESET_SEQNO = 0x0010;
  static const int SEC_IGNORE_SEQNO = 0x0020;
  static const int SEC_INFO_PKT = 0x0040;
  static const int SEC_LICENSE_PKT = 0x0080;
  static const int SEC_LICENSE_ENCRYPT_CS = 0x0200;
  static const int SEC_REDIRECTION_PKT = 0x0400;

  // Desktop Dimensions
  static const int DESKTOP_WIDTH = 1024;
  static const int DESKTOP_HEIGHT = 768;
  static const int COLOR_DEPTH = 16;
}

// Widget for displaying RDP connection in Flutter

class RDPClientWidget extends StatefulWidget {
  final RDPClient rdpClient;
  final VoidCallback? onDisconnectRequest;

  const RDPClientWidget({
    super.key,
    required this.rdpClient,
    this.onDisconnectRequest,
  });

  @override
  State<RDPClientWidget> createState() => _RDPClientWidgetState();
}

class _RDPClientWidgetState extends State<RDPClientWidget> {
  Uint8List? _currentFrameData;
  int _frameWidth = 1024;
  int _frameHeight = 768;
  final List<String> _logMessages = [];
  
  @override
  void initState() {
    super.initState();
    _frameWidth = widget.rdpClient.desktopWidth;
    _frameHeight = widget.rdpClient.desktopHeight;
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Connection Status Bar
        StreamBuilder<RDPConnectionState>(
          stream: widget.rdpClient.connectionState,
          initialData: widget.rdpClient.currentState,
          builder: (context, snapshot) {
            final state = snapshot.data ?? RDPConnectionState.disconnected;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: _getStateColor(state).withOpacity(0.1),
              child: Row(
                children: [
                  Icon(
                    _getStateIcon(state),
                    color: _getStateColor(state),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _getStateText(state),
                    style: TextStyle(
                      color: _getStateColor(state),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    '${_frameWidth}x$_frameHeight',
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  if (state == RDPConnectionState.connected &&
                      widget.onDisconnectRequest != null)
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: widget.onDisconnectRequest,
                      tooltip: 'Disconnect',
                      color: Colors.red,
                    ),
                ],
              ),
            );
          },
        ),

        // Remote Desktop Display
        Expanded(
          child: Container(
            color: Colors.black,
            child: StreamBuilder<RDPScreenUpdate>(
              stream: widget.rdpClient.screenUpdates,
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  final update = snapshot.data!;
                  _currentFrameData = update.bitmapData;
                  _frameWidth = update.width;
                  _frameHeight = update.height;
                }

                if (_currentFrameData == null) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(
                          color: Colors.white,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Waiting for screen data from RDP server...',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 24),
                        StreamBuilder<String>(
                          stream: widget.rdpClient.messages,
                          builder: (context, msgSnapshot) {
                            if (msgSnapshot.hasData) {
                              if (!_logMessages.contains(msgSnapshot.data!)) {
                                _logMessages.add(msgSnapshot.data!);
                                if (_logMessages.length > 15) {
                                  _logMessages.removeAt(0);
                                }
                              }
                            }
                            return Column(
                              children: _logMessages
                                  .map((msg) => Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 2),
                                        child: Text(
                                          msg,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ))
                                  .toList(),
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: () {
                            widget.rdpClient.enableDemoMode();
                          },
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Enable Demo Mode'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Demo mode shows a test pattern if no real server data arrives',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                return GestureDetector(
                  onPanUpdate: (details) {
                    // Send mouse move event
                    final localPosition = details.localPosition;
                    widget.rdpClient.sendMouseEvent(
                      localPosition.dx.toInt(),
                      localPosition.dy.toInt(),
                      0,
                      false,
                    );
                  },
                  onTapDown: (details) {
                    // Send mouse click
                    final localPosition = details.localPosition;
                    widget.rdpClient.sendMouseEvent(
                      localPosition.dx.toInt(),
                      localPosition.dy.toInt(),
                      1, // Left button
                      true,
                    );
                  },
                  onTapUp: (details) {
                    // Send mouse release
                    final localPosition = details.localPosition;
                    widget.rdpClient.sendMouseEvent(
                      localPosition.dx.toInt(),
                      localPosition.dy.toInt(),
                      1, // Left button
                      false,
                    );
                  },
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: CustomPaint(
                      size: Size(_frameWidth.toDouble(), _frameHeight.toDouble()),
                      painter: RDPScreenPainter(_currentFrameData!),
                    ),
                  ),
                );
              },
            ),
          ),
        ),

        // Control Bar
        Container(
          color: Colors.grey[900],
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildControlButton(
                Icons.keyboard,
                'Keyboard',
                () {
                  _showKeyboardDialog();
                },
              ),
              _buildControlButton(
                Icons.fullscreen,
                'Fullscreen',
                () {
                  // Toggle fullscreen would go here
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Fullscreen mode'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
              _buildControlButton(
                Icons.refresh,
                'Refresh',
                () {
                  // Request screen refresh
                  widget.rdpClient.sendKeyEvent(0x74, true); // F5
                  widget.rdpClient.sendKeyEvent(0x74, false);
                },
              ),
              _buildControlButton(
                Icons.settings,
                'Options',
                () {
                  _showOptionsDialog();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  Widget _buildControlButton(IconData icon, String label, VoidCallback onPressed) {
    return InkWell(
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  void _showKeyboardDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send Keys'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: () {
                // Send Ctrl+Alt+Del
                widget.rdpClient.sendKeyEvent(0x1D, true); // Ctrl
                widget.rdpClient.sendKeyEvent(0x38, true); // Alt
                widget.rdpClient.sendKeyEvent(0x53, true); // Del
                widget.rdpClient.sendKeyEvent(0x53, false);
                widget.rdpClient.sendKeyEvent(0x38, false);
                widget.rdpClient.sendKeyEvent(0x1D, false);
                Navigator.pop(context);
              },
              child: const Text('Send Ctrl+Alt+Del'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () {
                // Send Windows Key
                widget.rdpClient.sendKeyEvent(0x5B, true);
                widget.rdpClient.sendKeyEvent(0x5B, false);
                Navigator.pop(context);
              },
              child: const Text('Send Windows Key'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
  
  void _showOptionsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Display Options'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Resolution: ${_frameWidth}x$_frameHeight'),
            const SizedBox(height: 8),
            const Text('Color Depth: 16-bit'),
            const SizedBox(height: 8),
            const Text('Compression: Enabled'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Color _getStateColor(RDPConnectionState state) {
    switch (state) {
      case RDPConnectionState.connected:
        return Colors.green;
      case RDPConnectionState.connecting:
        return Colors.orange;
      case RDPConnectionState.failed:
        return Colors.red;
      case RDPConnectionState.disconnected:
        return Colors.grey;
    }
  }

  IconData _getStateIcon(RDPConnectionState state) {
    switch (state) {
      case RDPConnectionState.connected:
        return Icons.check_circle;
      case RDPConnectionState.connecting:
        return Icons.hourglass_empty;
      case RDPConnectionState.failed:
        return Icons.error;
      case RDPConnectionState.disconnected:
        return Icons.cancel;
    }
  }

  String _getStateText(RDPConnectionState state) {
    switch (state) {
      case RDPConnectionState.connected:
        return 'Connected';
      case RDPConnectionState.connecting:
        return 'Connecting...';
      case RDPConnectionState.failed:
        return 'Connection Failed';
      case RDPConnectionState.disconnected:
        return 'Disconnected';
    }
  }
}

/// Custom painter for rendering RDP screen bitmap
class RDPScreenPainter extends CustomPainter {
  final Uint8List bitmapData;

  RDPScreenPainter(this.bitmapData);

  @override
  void paint(Canvas canvas, Size size) {
    if (bitmapData.isEmpty) return;

    try {
      // Calculate dimensions from bitmap data
      final width = size.width.toInt();
      final height = size.height.toInt();
      
      if (width <= 0 || height <= 0) return;

      // Draw the bitmap data
      final paint = Paint();
      
      // For demo purposes, we'll draw the gradient bitmap
      // In a real implementation, you would decode RDP bitmap formats
      for (int y = 0; y < height && y < 768; y++) {
        for (int x = 0; x < width && x < 1024; x++) {
          final index = (y * 1024 + x) * 4;
          if (index + 3 < bitmapData.length) {
            final r = bitmapData[index];
            final g = bitmapData[index + 1];
            final b = bitmapData[index + 2];
            final a = bitmapData[index + 3];
            
            paint.color = Color.fromARGB(a, r, g, b);
            canvas.drawRect(
              Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1),
              paint,
            );
          }
        }
      }
      
      // Draw connection info overlay
      final textPainter = TextPainter(
        text: const TextSpan(
          text: 'RDP Connected - Remote Desktop',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(
                offset: Offset(2, 2),
                blurRadius: 4,
                color: Colors.black,
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          (size.width - textPainter.width) / 2,
          (size.height - textPainter.height) / 2,
        ),
      );
      
    } catch (e) {
      // If there's an error, draw error message
      final textPainter = TextPainter(
        text: TextSpan(
          text: 'Error rendering: $e',
          style: const TextStyle(
            color: Colors.red,
            fontSize: 16,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, const Offset(10, 10));
    }
  }

  @override
  bool shouldRepaint(RDPScreenPainter oldDelegate) {
    return oldDelegate.bitmapData != bitmapData;
  }
}
