import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Represents a device available for WebRTC connection
class WebRTCDevice {
  final String id;
  final String name;
  final String type;
  final bool isOnline;
  final DateTime lastSeen;
  
  WebRTCDevice({
    required this.id,
    required this.name,
    required this.type,
    required this.isOnline,
    required this.lastSeen,
  });
  
  factory WebRTCDevice.fromJson(Map<String, dynamic> json) {
    return WebRTCDevice(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown Device',
      type: json['type'] as String? ?? 'unknown',
      isOnline: json['isOnline'] as bool? ?? false,
      lastSeen: json['lastSeen'] != null 
        ? DateTime.parse(json['lastSeen'] as String)
        : DateTime.now(),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'isOnline': isOnline,
      'lastSeen': lastSeen.toIso8601String(),
    };
  }
}

/// Service for handling WebRTC signaling via WebSocket
class WebRTCSignalingService {
  WebSocketChannel? _channel;
  String? _serverUrl;
  String? _clientId;
  List<WebRTCDevice> _availableDevices = [];
  
  // Callbacks
  Function(RTCSessionDescription)? onOffer;
  Function(RTCSessionDescription)? onAnswer;
  Function(RTCIceCandidate)? onIceCandidate;
  Function()? onConnected;
  Function()? onDisconnected;
  Function(String)? onError;
  Function(List<WebRTCDevice>)? onDeviceListUpdated;
  
  bool get isConnected => _channel != null;
  String? get clientId => _clientId;
  List<WebRTCDevice> get availableDevices => List.unmodifiable(_availableDevices);

  /// Connect to the signaling server
  Future<void> connect(String serverUrl) async {
    try {
      _serverUrl = serverUrl;
      _channel = WebSocketChannel.connect(Uri.parse(serverUrl));
      
      // Listen for messages
      _channel!.stream.listen(
        _handleMessage,
        onError: (error) {
          onError?.call('WebSocket error: $error');
          disconnect();
        },
        onDone: () {
          onDisconnected?.call();
          _channel = null;
        },
      );
      
      onConnected?.call();
    } catch (e) {
      onError?.call('Failed to connect: $e');
      rethrow;
    }
  }

  /// Disconnect from the signaling server
  void disconnect() {
    _channel?.sink.close();
    _channel = null;
    _clientId = null;
  }

  /// Send an offer to the remote peer
  Future<void> sendOffer(RTCSessionDescription offer, {String? targetId}) async {
    _sendMessage({
      'type': 'offer',
      'sdp': offer.sdp,
      if (targetId != null) 'target': targetId,
    });
  }

  /// Send an answer to the remote peer
  Future<void> sendAnswer(RTCSessionDescription answer, {String? targetId}) async {
    _sendMessage({
      'type': 'answer',
      'sdp': answer.sdp,
      if (targetId != null) 'target': targetId,
    });
  }

  /// Send an ICE candidate to the remote peer
  Future<void> sendIceCandidate(RTCIceCandidate candidate, {String? targetId}) async {
    _sendMessage({
      'type': 'ice-candidate',
      'candidate': candidate.candidate,
      'sdpMid': candidate.sdpMid,
      'sdpMLineIndex': candidate.sdpMLineIndex,
      if (targetId != null) 'target': targetId,
    });
  }

  /// Request list of available devices
  Future<void> requestDeviceList() async {
    _sendMessage({'type': 'list-devices'});
  }

  /// Register this client as a specific device
  Future<void> registerDevice(String deviceId) async {
    _sendMessage({
      'type': 'register',
      'deviceId': deviceId,
    });
  }

  void _sendMessage(Map<String, dynamic> message) {
    if (_channel == null) {
      onError?.call('Not connected to signaling server');
      return;
    }
    
    try {
      _channel!.sink.add(jsonEncode(message));
    } catch (e) {
      onError?.call('Failed to send message: $e');
    }
  }

  void _handleMessage(dynamic rawMessage) {
    try {
      final message = jsonDecode(rawMessage as String) as Map<String, dynamic>;
      final type = message['type'] as String?;
      
      switch (type) {
        case 'id':
          // Server assigned us an ID
          _clientId = message['id'] as String?;
          break;
          
        case 'offer':
          // Received an offer from remote peer
          final sdp = message['sdp'] as String?;
          if (sdp != null) {
            onOffer?.call(RTCSessionDescription(sdp, 'offer'));
          }
          break;
          
        case 'answer':
          // Received an answer from remote peer
          final sdp = message['sdp'] as String?;
          if (sdp != null) {
            onAnswer?.call(RTCSessionDescription(sdp, 'answer'));
          }
          break;
          
        case 'ice-candidate':
          // Received an ICE candidate from remote peer
          final candidateData = message['candidate'] as String?;
          final sdpMid = message['sdpMid'] as String?;
          final sdpMLineIndex = message['sdpMLineIndex'] as int?;
          
          if (candidateData != null) {
            onIceCandidate?.call(RTCIceCandidate(
              candidateData,
              sdpMid ?? '',
              sdpMLineIndex ?? 0,
            ));
          }
          break;
          
        case 'device-list':
          // List of available devices
          final devicesData = message['devices'] as List?;
          if (devicesData != null) {
            _availableDevices = devicesData
                .cast<Map<String, dynamic>>()
                .map((deviceJson) => WebRTCDevice.fromJson(deviceJson))
                .toList();
            onDeviceListUpdated?.call(_availableDevices);
          }
          break;
          
        case 'device-joined':
          // A device joined the network
          final deviceData = message['device'] as Map<String, dynamic>?;
          if (deviceData != null) {
            final device = WebRTCDevice.fromJson(deviceData);
            _availableDevices.removeWhere((d) => d.id == device.id);
            _availableDevices.add(device);
            onDeviceListUpdated?.call(_availableDevices);
          }
          break;
          
        case 'device-left':
          // A device left the network
          final deviceId = message['deviceId'] as String?;
          if (deviceId != null) {
            _availableDevices.removeWhere((d) => d.id == deviceId);
            onDeviceListUpdated?.call(_availableDevices);
          }
          break;
          
        case 'error':
          final errorMessage = message['message'] as String?;
          onError?.call(errorMessage ?? 'Unknown error from server');
          break;
          
        default:
          onError?.call('Unknown message type: $type');
      }
    } catch (e) {
      onError?.call('Failed to parse message: $e');
    }
  }

  /// Reconnect to the signaling server
  Future<void> reconnect() async {
    if (_serverUrl != null) {
      disconnect();
      await Future.delayed(const Duration(seconds: 1));
      await connect(_serverUrl!);
    }
  }
}
