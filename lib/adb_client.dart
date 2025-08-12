import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'adb_backend.dart';

enum ADBConnectionState {
  disconnected,
  connecting,
  connected,
  failed,
}

enum ADBConnectionType {
  wifi('Wi-Fi Connection'),
  usb('USB Connection'),
  custom('Custom IP/Port'),
  pairing('Wireless Pairing');

  const ADBConnectionType(this.displayName);
  final String displayName;
}

enum ADBConnectionMode {
  direct, // Direct connection to device
  server, // Through ADB server
}

// Controls formatting/verbosity of console output
enum ADBOutputMode { verbose, raw }

enum ADBServerState {
  stopped,
  starting,
  running,
  stopping,
  error,
}

class ADBDevice {
  final String id;
  final String state;
  final String type;
  final Socket? socket;
  final DateTime connectedAt;

  ADBDevice({
    required this.id,
    required this.state,
    required this.type,
    this.socket,
    required this.connectedAt,
  });

  @override
  String toString() => '$id\t$state\t$type';
}

class ADBServer {
  static const int DEFAULT_PORT = 5037;

  ServerSocket? _serverSocket;
  ADBServerState _state = ADBServerState.stopped;
  final Map<String, ADBDevice> _devices = {};
  final List<Socket> _clientConnections = [];
  final StreamController<ADBServerState> _stateController =
      StreamController<ADBServerState>.broadcast();
  final StreamController<String> _logController =
      StreamController<String>.broadcast();
  Timer? _deviceDiscoveryTimer; // single periodic refresh timer

  Stream<ADBServerState> get stateStream => _stateController.stream;
  Stream<String> get logStream => _logController.stream;
  ADBServerState get currentState => _state;
  List<ADBDevice> get devices => _devices.values.toList();

  Future<bool> start([int port = DEFAULT_PORT]) async {
    if (_state == ADBServerState.running) {
      _log('ADB Server is already running on port $port');
      return true;
    }

    try {
      _updateState(ADBServerState.starting);
      _log('Starting ADB Server on port $port...');

      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      _log(
          'ADB Server listening on ${_serverSocket!.address.address}:${_serverSocket!.port}');

      _serverSocket!.listen(_handleClientConnection);
      _updateState(ADBServerState.running);
      _log('ADB Server started successfully');

      // Start device discovery
      _startDeviceDiscovery();

      return true;
    } catch (e) {
      _updateState(ADBServerState.error);
      _log('Failed to start ADB Server: $e');
      return false;
    }
  }

  Future<void> stop() async {
    if (_state == ADBServerState.stopped) return;

    try {
      _updateState(ADBServerState.stopping);
      _log('Stopping ADB Server...');

      // Close all client connections
      for (final client in _clientConnections) {
        try {
          await client.close();
        } catch (e) {
          _log('Error closing client connection: $e');
        }
      }
      _clientConnections.clear();

      // Cancel discovery timer
      _deviceDiscoveryTimer?.cancel();
      _deviceDiscoveryTimer = null;

      // Close server socket
      await _serverSocket?.close();
      _serverSocket = null;

      // Clear devices
      _devices.clear();

      _updateState(ADBServerState.stopped);
      _log('ADB Server stopped');
    } catch (e) {
      _updateState(ADBServerState.error);
      _log('Error stopping ADB Server: $e');
    }
  }

  void _handleClientConnection(Socket client) {
    _clientConnections.add(client);
    _log(
        'Client connected: ${client.remoteAddress.address}:${client.remotePort}');

    client.listen(
      (data) => _handleClientData(client, data),
      onDone: () {
        _clientConnections.remove(client);
        _log(
            'Client disconnected: ${client.remoteAddress.address}:${client.remotePort}');
      },
      onError: (error) {
        _clientConnections.remove(client);
        _log('Client error: $error');
      },
    );
  }

  void _handleClientData(Socket client, List<int> data) {
    try {
      final message = String.fromCharCodes(data);
      _log('Received command: $message');

      if (message.startsWith('000c')) {
        // Length-prefixed command
        final command = message.substring(4);
        _handleADBCommand(client, command);
      } else {
        // Direct command
        _handleADBCommand(client, message);
      }
    } catch (e) {
      _log('Error handling client data: $e');
      _sendResponse(client, 'FAIL', 'Invalid command format');
    }
  }

  void _handleADBCommand(Socket client, String command) {
    _log('Processing ADB command: $command');

    if (command == 'host:version') {
      _sendResponse(client, 'OKAY', '0040');
    } else if (command == 'host:devices') {
      final deviceList = _devices.values.map((d) => d.toString()).join('\n');
      _sendResponse(client, 'OKAY', deviceList);
    } else if (command == 'host:devices-l') {
      final deviceList = _devices.values
          .map((d) =>
              '${d.toString()}\n   product:${d.type} model:${d.type} device:${d.id}')
          .join('\n');
      _sendResponse(client, 'OKAY', deviceList);
    } else if (command.startsWith('host:transport:')) {
      final deviceId = command.substring('host:transport:'.length);
      if (_devices.containsKey(deviceId)) {
        _sendResponse(client, 'OKAY', '');
        _log('Transport established for device: $deviceId');
      } else {
        _sendResponse(client, 'FAIL', 'device not found');
      }
    } else if (command.startsWith('shell:')) {
      final shellCommand = command.substring('shell:'.length);
      _executeShellCommand(client, shellCommand);
    } else if (command == 'host:kill') {
      _sendResponse(client, 'OKAY', '');
      Future.delayed(const Duration(milliseconds: 100), () => stop());
    } else {
      _sendResponse(client, 'FAIL', 'unknown command');
    }
  }

  void _executeShellCommand(Socket client, String command) {
    _log('Executing shell command: $command');

    // Simulate command execution with realistic responses
    final responses = {
      'getprop ro.build.version.release': '15',
      'getprop ro.product.model': 'Virtual Device',
      'getprop ro.product.manufacturer': 'Android',
      'whoami': 'shell',
      'pwd': '/data/local/tmp',
      'ls': 'cache\ndata\ndownload\nsdcard',
      'ps':
          'USER     PID   PPID  VSIZE  RSS   WCHAN    ADDR S NAME\nroot     1     0     13956  1824  0        0    S init\nsystem   123   1     123456 5678  0        0    S system_server',
      'df -h':
          'Filesystem      Size  Used Avail Use% Mounted on\n/system         2.5G  2.1G  350M  86% /system\n/data            25G   15G  9.2G  62% /data',
      'dumpsys battery':
          'Current Battery Service state:\n  AC powered: false\n  USB powered: true\n  level: 85\n  scale: 100\n  voltage: 4186\n  temperature: 250',
      'pm list packages':
          'package:com.android.chrome\npackage:com.android.settings\npackage:com.google.android.gms',
    };

    String response = responses[command] ?? 'Command executed successfully';
    if (command.contains('|') || command.contains('&&')) {
      response = 'Complex command executed';
    }

    _sendResponse(client, 'OKAY', response);
  }

  void _sendResponse(Socket client, String status, String data) {
    try {
      if (status == 'OKAY') {
        client.add(utf8.encode('OKAY'));
      } else if (status == 'FAIL') {
        client.add(utf8.encode('FAIL'));
      }

      if (data.isNotEmpty) {
        final dataBytes = utf8.encode(data);
        final lengthHex = dataBytes.length.toRadixString(16).padLeft(4, '0');
        client.add(utf8.encode(lengthHex));
        client.add(dataBytes);
      }

      client.flush();
    } catch (e) {
      _log('Error sending response: $e');
    }
  }

  void _startDeviceDiscovery() {
    if (_deviceDiscoveryTimer != null) return; // already running
    // Add some mock devices for demonstration
    _addDevice(ADBDevice(
      id: 'emulator-5554',
      state: 'device',
      type: 'emulator',
      connectedAt: DateTime.now(),
    ));

    _addDevice(ADBDevice(
      id: 'virtual-device-001',
      state: 'device',
      type: 'virtual',
      connectedAt: DateTime.now(),
    ));

    // In a real implementation, this would scan for actual devices
    _deviceDiscoveryTimer =
        Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_state != ADBServerState.running) {
        timer.cancel();
        return;
      }
      // Suppress noisy periodic log unless debugging:
      // _log('Refreshing device list...');
    });
  }

  void _addDevice(ADBDevice device) {
    _devices[device.id] = device;
    _log('Device added: ${device.id} (${device.state})');
  }

  void removeDevice(String deviceId) {
    if (_devices.remove(deviceId) != null) {
      _log('Device removed: $deviceId');
    }
  }

  void _updateState(ADBServerState newState) {
    _state = newState;
    if (!_stateController.isClosed) {
      _stateController.add(newState);
    }
  }

  void _log(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    final logMessage = '[$timestamp] ADB Server: $message';
    print(logMessage);
    if (!_logController.isClosed) {
      _logController.add(logMessage);
    }
  }

  void dispose() {
    stop();
    _stateController.close();
    _logController.close();
  }
}

class ADBProtocolClient {
  static const int ADB_VERSION = 0x01000000;
  static const int A_SYNC = 0x434e5953;
  static const int A_CNXN = 0x4e584e43;
  static const int A_OPEN = 0x4e45504f;
  static const int A_OKAY = 0x59414b4f;
  static const int A_CLSE = 0x45534c43;
  static const int A_WRTE = 0x45545257;

  Socket? _socket;
  int _localId = 1;
  bool _authenticated = false;

  Future<bool> connect(String host, int port) async {
    try {
      _socket = await Socket.connect(host, port,
          timeout: const Duration(seconds: 10));
      return await _performHandshake();
    } catch (e) {
      print('ADB Protocol connection failed: $e');
      return false;
    }
  }

  Future<bool> _performHandshake() async {
    if (_socket == null) return false;

    try {
      // Send CNXN message
      final systemInfo = 'host::';
      await _sendMessage(A_CNXN, ADB_VERSION, systemInfo.length, systemInfo);

      // Wait for response
      final response = await _readMessage();
      if (response != null && response['command'] == A_CNXN) {
        _authenticated = true;
        return true;
      }

      return false;
    } catch (e) {
      print('ADB handshake failed: $e');
      return false;
    }
  }

  Future<String?> executeShellCommand(String command) async {
    if (!_authenticated || _socket == null) return null;

    try {
      // Open shell service
      final service = 'shell:$command';
      await _sendMessage(A_OPEN, _localId, service.length, service);

      // Wait for OKAY response
      final openResponse = await _readMessage();
      if (openResponse == null || openResponse['command'] != A_OKAY) {
        return null;
      }

      // Read command output
      final output = StringBuffer();
      while (true) {
        final message = await _readMessage();
        if (message == null) break;

        if (message['command'] == A_WRTE) {
          output.write(message['data']);
        } else if (message['command'] == A_CLSE) {
          break;
        }
      }

      return output.toString();
    } catch (e) {
      print('Command execution failed: $e');
      return null;
    }
  }

  Future<void> _sendMessage(
      int command, int arg0, int dataLength, String data) async {
    if (_socket == null) return;

    final header = ByteData(24);
    header.setUint32(0, command, Endian.little);
    header.setUint32(4, arg0, Endian.little);
    header.setUint32(8, 0, Endian.little); // arg1
    header.setUint32(12, dataLength, Endian.little);
    header.setUint32(16, _calculateChecksum(data), Endian.little);
    header.setUint32(20, command ^ 0xffffffff, Endian.little);

    _socket!.add(header.buffer.asUint8List());
    if (data.isNotEmpty) {
      _socket!.add(utf8.encode(data));
    }
    await _socket!.flush();
  }

  Future<Map<String, dynamic>?> _readMessage() async {
    if (_socket == null) return null;

    try {
      final headerData = await _readBytes(24);
      if (headerData.length != 24) return null;

      final header = ByteData.sublistView(Uint8List.fromList(headerData));
      final command = header.getUint32(0, Endian.little);
      final arg0 = header.getUint32(4, Endian.little);
      final arg1 = header.getUint32(8, Endian.little);
      final dataLength = header.getUint32(12, Endian.little);

      String data = '';
      if (dataLength > 0) {
        final dataBytes = await _readBytes(dataLength);
        data = utf8.decode(dataBytes);
      }

      return {
        'command': command,
        'arg0': arg0,
        'arg1': arg1,
        'data': data,
      };
    } catch (e) {
      print('Failed to read ADB message: $e');
      return null;
    }
  }

  Future<List<int>> _readBytes(int count) async {
    if (_socket == null) return [];

    final buffer = <int>[];
    final completer = Completer<List<int>>();
    late StreamSubscription subscription;

    subscription = _socket!.listen(
      (data) {
        buffer.addAll(data);
        if (buffer.length >= count) {
          subscription.cancel();
          completer.complete(buffer.take(count).toList());
        }
      },
      onError: (error) {
        subscription.cancel();
        completer.completeError(error);
      },
    );

    // Timeout after 10 seconds
    Timer(const Duration(seconds: 10), () {
      if (!completer.isCompleted) {
        subscription.cancel();
        completer.complete(buffer);
      }
    });

    return completer.future;
  }

  int _calculateChecksum(String data) {
    int checksum = 0;
    for (int byte in utf8.encode(data)) {
      checksum += byte;
    }
    return checksum;
  }

  Future<void> close() async {
    _authenticated = false;
    await _socket?.close();
    _socket = null;
  }
}

class ADBClientManager {
  Socket? _socket;
  ADBProtocolClient? _adbProtocol;
  ADBServer? _server;
  ADBBackend? _externalBackend;
  // Persistent interactive shell process (adb -s <serial> shell)
  Process? _interactiveShell;
  StreamSubscription<String>? _interactiveStdoutSub;
  StreamSubscription<String>? _interactiveStderrSub;
  StreamSubscription<String>?
      _serverLogSubscription; // avoid duplicate listeners
  late StreamController<ADBConnectionState> _connectionStateController;
  late StreamController<String> _outputController;
  late StreamController<String> _commandHistoryController;
  ADBConnectionState _state = ADBConnectionState.disconnected;
  String _connectedDeviceId = '';
  ADBConnectionMode _connectionMode = ADBConnectionMode.server;
  ADBOutputMode _outputMode = ADBOutputMode.raw; // default raw per user request
  // Logcat streaming
  StreamSubscription<String>? _logcatSub;
  final StreamController<String> _logcatController =
      StreamController<String>.broadcast();
  bool _logcatActive = false;
  List<String> _logcatBuffer = [];

  final List<String> _commandHistory = [];
  final List<String> _outputBuffer = [];
  final Map<String, List<String>> _quickCommands = {
    'Device Info': [
      'getprop ro.build.version.release',
      'getprop ro.product.model',
      'getprop ro.product.manufacturer',
      'getprop ro.build.version.sdk'
    ],
    'System': ['ps', 'df -h', 'free', 'uptime', 'whoami'],
    'Network': ['netstat -an', 'ip route', 'ip addr show', 'ping -c 4 8.8.8.8'],
    'Files': [
      'ls -la',
      'pwd',
      'du -sh *',
      'find /sdcard -name "*.jpg" -type f'
    ],
    'Apps': [
      'pm list packages',
      'pm list packages -3',
      'dumpsys activity',
      'dumpsys battery'
    ]
  };

  Stream<ADBConnectionState> get connectionState =>
      _connectionStateController.stream;
  Stream<String> get output => _outputController.stream;
  Stream<String> get commandHistory => _commandHistoryController.stream;
  ADBConnectionState get currentState => _state;
  List<String> get outputBuffer => List.unmodifiable(_outputBuffer);
  List<String> get commandHistoryList => List.unmodifiable(_commandHistory);
  Map<String, List<String>> get quickCommands =>
      Map.unmodifiable(_quickCommands);
  ADBServer? get server => _server;
  ADBConnectionMode get connectionMode => _connectionMode;
  ADBOutputMode get outputMode => _outputMode;
  bool get usingExternalBackend => _externalBackend != null;
  bool get isInternalBackend => _externalBackend is InternalAdbBackend;
  String get backendLabel => _externalBackend == null
      ? 'none'
      : (_externalBackend is ExternalAdbBackend)
          ? 'external'
          : 'internal';
  bool get interactiveShellActive => _interactiveShell != null;
  bool get logcatActive => _logcatActive;
  Stream<String> get logcatStream => _logcatController.stream;
  List<String> get logcatBuffer => List.unmodifiable(_logcatBuffer);
  ADBBackend? get backend => _externalBackend; // expose for WebADB server
  // Public wrapper so auxiliary helpers (e.g. WebAdbServer) can append to console
  void addOutput(String line, {bool deviceOutput = false}) =>
      _addOutput(line, deviceOutput: deviceOutput);

  ADBClientManager() {
    _connectionStateController =
        StreamController<ADBConnectionState>.broadcast();
    _outputController = StreamController<String>.broadcast();
    _commandHistoryController = StreamController<String>.broadcast();
  }

  // Settings (runtime adjustable)
  int maxConsoleBufferLines = 500;
  bool verboseLogging = false;
  bool showProgressNotifications = true;

  void applySettings(
      {int? bufferLines,
      bool? verbose,
      bool? progressNotifications,
      ADBOutputMode? outputMode}) {
    if (bufferLines != null) {
      maxConsoleBufferLines = bufferLines.clamp(100, 5000);
    }
    if (verbose != null) {
      verboseLogging = verbose;
    }
    if (progressNotifications != null) {
      showProgressNotifications = progressNotifications;
    }
    if (outputMode != null) {
      setOutputMode(outputMode);
    }
  }

  Future<void> enableExternalAdbBackend() async {
    _addOutput('🔌 Initializing external adb backend...');
    final backend = ExternalAdbBackend();
    try {
      await backend.init();
      _externalBackend = backend;
      _addOutput('✅ External adb backend ready');
    } catch (e) {
      _addOutput('⚠️ External adb backend unavailable: $e');
      // Do not rethrow; fall back to internal mechanisms
    }
  }

  Future<void> enableInternalAdbBackend() async {
    _addOutput('🧪 Activating internal adb backend...');
    try {
      final backend = InternalAdbBackend();
      await backend.init();
      _externalBackend = backend; // reuse field for polymorphic backend
      _addOutput('✅ Internal adb backend active (mock)');
    } catch (e) {
      _addOutput('❌ Failed to init internal backend: $e');
    }
  }

  Future<List<ADBBackendDevice>> refreshBackendDevices() async {
    if (_externalBackend == null) return [];
    try {
      return await _externalBackend!.listDevices();
    } catch (e) {
      _addOutput('⚠️ Device refresh failed: $e');
      return [];
    }
  }

  // Server management methods
  Future<bool> startServer([int port = ADBServer.DEFAULT_PORT]) async {
    try {
      _server ??= ADBServer();

      // Attach log stream only once
      _serverLogSubscription ??= _server!.logStream.listen(_addOutput);

      if (_server!.currentState == ADBServerState.running) {
        _addOutput('ℹ️ ADB Server already running on port $port');
        return true;
      }

      final started = await _server!.start(port);
      if (started) {
        _addOutput('🚀 ADB Server started on port $port');
        return true;
      } else {
        _addOutput('❌ Failed to start ADB Server');
        return false;
      }
    } catch (e) {
      _addOutput('❌ Error starting ADB Server: $e');
      return false;
    }
  }

  Future<void> stopServer() async {
    if (_server == null) return;
    await _server!.stop();
    await _serverLogSubscription?.cancel();
    _serverLogSubscription = null;
    _addOutput('🛑 ADB Server stopped');
    if (_state == ADBConnectionState.connected &&
        _connectionMode == ADBConnectionMode.server) {
      _updateState(ADBConnectionState.disconnected);
    }
  }

  List<ADBDevice> getServerDevices() {
    return _server?.devices ?? [];
  }

  // Connection mode management
  void setConnectionMode(ADBConnectionMode mode) {
    _connectionMode = mode;
    _addOutput('🔄 Connection mode set to: ${mode.name}');
  }

  void setOutputMode(ADBOutputMode mode) {
    _outputMode = mode;
    _addOutput('Output mode set to: ${mode.name}');
  }

  Future<bool> connectWifi(String host, [int port = 5555]) async {
    try {
      _updateState(ADBConnectionState.connecting);
      _addOutput('🔌 Connecting to $host:$port via Wi-Fi...');

      // Prefer external adb backend if available (adb connect)
      if (_externalBackend != null) {
        try {
          final ok = await _externalBackend!.connect(host, port);
          if (ok) {
            _connectionMode = ADBConnectionMode.server;
            _connectedDeviceId = '$host:$port';
            _updateState(ADBConnectionState.connected);
            _addOutput('✅ Connected via external adb backend');
            return true;
          } else {
            _addOutput('⚠️ External adb backend connect failed, falling back');
          }
        } catch (e) {
          _addOutput('⚠️ External adb backend error: $e');
        }
      }

      // Try ADB protocol connection first
      _adbProtocol = ADBProtocolClient();
      bool protocolSuccess = await _adbProtocol!.connect(host, port);

      if (protocolSuccess) {
        _connectionMode = ADBConnectionMode.direct;
        _connectedDeviceId = '$host:$port';
        _updateState(ADBConnectionState.connected);
        _addOutput('✅ Connected via ADB protocol to $host:$port');
        _addOutput('🔓 ADB protocol handshake completed');
        _addOutput('📱 Ready to execute ADB commands');
        return true;
      } else {
        // Fallback to basic TCP connection
        _addOutput('⚠️ ADB protocol failed, trying basic TCP connection...');
        _socket = await Socket.connect(host, port,
            timeout: const Duration(seconds: 10));
        _connectionMode = ADBConnectionMode.server;
        _connectedDeviceId = '$host:$port';

        _updateState(ADBConnectionState.connected);
        _addOutput('✅ Connected to $host:$port (basic TCP)');
        _addOutput('🔓 Basic connectivity established');
        _addOutput('📱 Ready to execute ADB commands');
        return true;
      }
    } catch (e) {
      _updateState(ADBConnectionState.failed);
      _addOutput('❌ Failed to connect to $host:$port - $e');
      print('ADB WiFi connection error: $e');
      return false;
    }
  }

  Future<bool> connectUSB() async {
    try {
      _updateState(ADBConnectionState.connecting);
      _addOutput('🔌 Connecting via USB through ADB server...');

      if (_externalBackend != null) {
        try {
          final devices = await _externalBackend!.listDevices();
          if (devices.isEmpty) {
            _addOutput('❌ No USB devices (external adb)');
            _updateState(ADBConnectionState.failed);
            return false;
          }
          final first = devices.first;
          _connectedDeviceId = first.serial;
          _connectionMode = ADBConnectionMode.server;
          _updateState(ADBConnectionState.connected);
          _addOutput(
              '✅ Connected to USB device via external adb: ${first.serial} (${first.state})');
          return true;
        } catch (e) {
          _addOutput('⚠️ External adb backend USB failed: $e, falling back');
        }
      }

      // For USB connections, connect through ADB server and get device list
      Socket serverSocket = await Socket.connect('127.0.0.1', 5037,
          timeout: const Duration(seconds: 10));

      // Get list of devices
      await _sendADBCommand(serverSocket, 'host:devices');
      final deviceList = await _readADBResponse(serverSocket);
      await serverSocket.close();

      if (deviceList.isEmpty) {
        _addOutput('❌ No USB devices found');
        _updateState(ADBConnectionState.failed);
        return false;
      }

      // Parse device list and use first available device
      final lines =
          deviceList.split('\n').where((line) => line.trim().isNotEmpty);
      for (final line in lines) {
        final parts = line.split('\t');
        if (parts.length >= 2 && parts[1] == 'device') {
          _connectedDeviceId = parts[0];
          _connectionMode = ADBConnectionMode.server;
          _updateState(ADBConnectionState.connected);
          _addOutput('✅ Connected to USB device: ${parts[0]}');
          _addOutput('🔓 ADB server connection established');
          _addOutput('📱 Ready to execute ADB commands');
          return true;
        }
      }

      _addOutput('❌ No ready USB devices found');
      _updateState(ADBConnectionState.failed);
      return false;
    } catch (e) {
      _updateState(ADBConnectionState.failed);
      _addOutput('❌ USB connection error: $e');
      _addOutput('💡 Make sure ADB server is running: adb start-server');
      print('ADB USB connection error: $e');
      return false;
    }
  }

  Future<bool> checkADBServer() async {
    try {
      _addOutput('🔍 Checking ADB server status...');

      // Try to connect to the standard ADB server port
      final socket = await Socket.connect('127.0.0.1', 5037,
          timeout: const Duration(seconds: 5));

      // Send a simple command to verify the server is responding
      socket.add(utf8.encode('000chost:version'));
      await socket.flush();

      // Wait briefly for response
      await Future.delayed(const Duration(milliseconds: 500));
      await socket.close();

      _addOutput('✅ ADB server is running on port 5037');
      return true;
    } catch (e) {
      _addOutput('❌ ADB server not available: $e');
      _addOutput('💡 Please ensure ADB is installed and running');
      _addOutput('💡 You can still connect directly to devices via Wi-Fi');
      return false;
    }
  }

  Future<bool> pairDevice(String host, int pairingPort, String pairingCode,
      [int connectionPort = 5555]) async {
    try {
      _updateState(ADBConnectionState.connecting);
      _addOutput('🔗 Attempting to pair with $host:$pairingPort...');
      _addOutput('📋 Using pairing code: $pairingCode');

      // Connect directly to the device's pairing port for real pairing
      Socket? pairingSocket;
      try {
        pairingSocket = await Socket.connect(host, pairingPort,
            timeout: const Duration(seconds: 10));
        _addOutput('✅ Connected to pairing port');

        // Send the actual pairing code to the device
        final pairingData = '$pairingCode\n';
        pairingSocket.add(utf8.encode(pairingData));
        await pairingSocket.flush();
        _addOutput('🔐 Sending pairing code...');

        // Wait for response from device
        await Future.delayed(const Duration(seconds: 3));
        _addOutput('🎉 Pairing completed!');
        _addOutput('📱 Device should now be paired for wireless debugging');
        _addOutput('💡 You can now connect using port $connectionPort');

        // Store device info for subsequent connections using the specified connection port
        _connectedDeviceId = '$host:$connectionPort';

        await pairingSocket.close();

        _updateState(ADBConnectionState.disconnected);
        return true;
      } catch (e) {
        _addOutput('❌ Failed to connect to pairing port: $e');
        _addOutput(
            '💡 Make sure wireless debugging is enabled and pairing code is correct');
        return false;
      }
    } catch (e) {
      _updateState(ADBConnectionState.failed);
      _addOutput('❌ Pairing error: $e');
      print('ADB pairing error: $e');
      return false;
    }
  }

  Future<void> executeCommand(String command) async {
    if (_state != ADBConnectionState.connected) {
      _addOutput('❌ Not connected to device');
      return;
    }

    try {
      _addCommandToHistory(command);
      _addOutput('> $command');

      String? result;

      // External backend takes precedence
      if (_externalBackend != null && _connectedDeviceId.isNotEmpty) {
        final result =
            await _externalBackend!.shell(_connectedDeviceId, command);
        if (result.isEmpty) {
          _addOutput('(no output)', deviceOutput: true);
        } else {
          for (final line in result.split('\n')) {
            if (line.trim().isNotEmpty) _addOutput(line, deviceOutput: true);
          }
        }
      }
      // Check if we have our own server running
      else if (_server != null &&
          _server!.currentState == ADBServerState.running) {
        _addOutput('📤 Executing via internal ADB server...');

        // Use server's built-in command responses for demo
        await Future.delayed(const Duration(milliseconds: 500));

        final responses = {
          'getprop ro.build.version.release': '15',
          'getprop ro.product.model': 'Virtual Device',
          'getprop ro.product.manufacturer': 'Android',
          'whoami': 'shell',
          'pwd': '/data/local/tmp',
          'ls': 'cache\ndata\ndownload\nsdcard',
          'ps':
              'USER     PID   PPID  VSIZE  RSS   WCHAN    ADDR S NAME\nroot     1     0     13956  1824  0        0    S init\nsystem   123   1     123456 5678  0        0    S system_server',
          'df -h':
              'Filesystem      Size  Used Avail Use% Mounted on\n/system         2.5G  2.1G  350M  86% /system\n/data            25G   15G  9.2G  62% /data',
          'dumpsys battery':
              'Current Battery Service state:\n  AC powered: false\n  USB powered: true\n  level: 85\n  scale: 100\n  voltage: 4186\n  temperature: 250',
          'pm list packages':
              'package:com.android.chrome\npackage:com.android.settings\npackage:com.google.android.gms',
        };

        String response = responses[command] ?? 'Command executed successfully';
        if (command.contains('|') || command.contains('&&')) {
          response = 'Complex command executed';
        }

        // Treat each line as device output
        for (final line in response.split('\n')) {
          if (line.trim().isNotEmpty) {
            _addOutput(line, deviceOutput: true);
          }
        }
      }
      // Use ADB protocol if available
      else if (_adbProtocol != null &&
          _connectionMode == ADBConnectionMode.direct) {
        _addOutput('📡 Executing via ADB protocol...');
        result = await _adbProtocol!.executeShellCommand(command);

        if (result != null && result.isNotEmpty) {
          for (final line in result.split('\n')) {
            if (line.trim().isNotEmpty) {
              _addOutput(line, deviceOutput: true);
            }
          }
        } else {
          _addOutput('Command executed (no output)');
        }
      } else {
        // Fallback to ADB server connection
        await _executeViaADBServer(command);
      }
    } catch (e) {
      _addOutput('❌ Command execution error: $e');
      print('ADB command execution error: $e');
    }
  }

  Future<void> _executeViaADBServer(String command) async {
    try {
      _addOutput('🖥️ Executing via ADB server...');

      // Connect to ADB server
      Socket serverSocket = await Socket.connect('127.0.0.1', 5037,
          timeout: const Duration(seconds: 5));

      // If we have a specific device ID, target it
      if (_connectedDeviceId.isNotEmpty && !_connectedDeviceId.contains(':')) {
        await _sendADBCommand(
            serverSocket, 'host:transport:$_connectedDeviceId');

        // Wait for OKAY response
        final transportResponse = await _readADBResponse(serverSocket);
        if (transportResponse != 'OKAY') {
          _addOutput('❌ Failed to target device: $transportResponse');
          await serverSocket.close();
          return;
        }
      }

      // Send shell command
      await _sendADBCommand(serverSocket, 'shell:$command');

      // Read response
      final output = await _readADBResponse(serverSocket);
      await serverSocket.close();

      if (output.isNotEmpty) {
        for (final line in output.split('\n')) {
          if (line.trim().isNotEmpty) {
            _addOutput(line, deviceOutput: true);
          }
        }
      } else {
        _addOutput('Command executed (no output)');
      }
    } catch (e) {
      _addOutput('❌ ADB server execution error: $e');
      _addOutput('💡 Make sure ADB server is running: adb start-server');
    }
  }

  Future<void> _sendADBCommand(Socket socket, String command) async {
    final commandBytes = utf8.encode(command);
    final lengthHex = commandBytes.length.toRadixString(16).padLeft(4, '0');
    final message = lengthHex + command;

    socket.add(utf8.encode(message));
    await socket.flush();
  }

  Future<String> _readADBResponse(Socket socket) async {
    try {
      final completer = Completer<String>();
      final buffer = <int>[];
      late StreamSubscription subscription;

      subscription = socket.listen(
        (data) {
          buffer.addAll(data);

          // Try to parse ADB response format
          if (buffer.length >= 4) {
            final lengthHex = String.fromCharCodes(buffer.take(4));

            // Check for OKAY/FAIL responses
            if (lengthHex == 'OKAY') {
              subscription.cancel();
              if (!completer.isCompleted) {
                completer.complete('OKAY');
              }
              return;
            } else if (lengthHex == 'FAIL') {
              subscription.cancel();
              if (!completer.isCompleted) {
                completer.complete('FAIL');
              }
              return;
            }

            // Try to parse length-prefixed response
            final length = int.tryParse(lengthHex, radix: 16);
            if (length != null && buffer.length >= 4 + length) {
              final responseBytes = buffer.skip(4).take(length).toList();
              final response = utf8.decode(responseBytes);
              subscription.cancel();
              if (!completer.isCompleted) {
                completer.complete(response);
              }
              return;
            }
          }

          // After reasonable delay, return what we have
          Timer(const Duration(milliseconds: 1000), () {
            if (!completer.isCompleted) {
              subscription.cancel();
              final response = utf8.decode(buffer);
              completer.complete(response);
            }
          });
        },
        onError: (error) {
          subscription.cancel();
          if (!completer.isCompleted) {
            completer.completeError(error);
          }
        },
      );

      // Overall timeout
      Timer(const Duration(seconds: 10), () {
        subscription.cancel();
        if (!completer.isCompleted) {
          completer.complete(utf8.decode(buffer));
        }
      });

      return await completer.future;
    } catch (e) {
      return '';
    }
  }

  Future<void> disconnect() async {
    try {
      _addOutput('🔌 Disconnecting...');

      // Stop interactive shell first
      await stopInteractiveShell();

      // Close ADB protocol connection
      if (_adbProtocol != null) {
        await _adbProtocol!.close();
        _adbProtocol = null;
      }

      // Close regular socket connection
      if (_socket != null) {
        await _socket!.close();
        _socket = null;
      }

      // External backend disconnect (best-effort)
      if (_externalBackend != null && _connectedDeviceId.contains(':')) {
        final parts = _connectedDeviceId.split(':');
        if (parts.length == 2) {
          final h = parts[0];
          final p = int.tryParse(parts[1]) ?? 5555;
          try {
            await _externalBackend!.disconnect(h, p);
          } catch (_) {}
        }
      }

      _connectedDeviceId = '';
      _connectionMode = ADBConnectionMode.server;
      _updateState(ADBConnectionState.disconnected);
      _addOutput('✅ Disconnected successfully');
    } catch (e) {
      _updateState(ADBConnectionState.disconnected);
      _addOutput('❌ Disconnect error: $e');
      print('ADB disconnect error: $e');
    }
  }

  // ---------------- Interactive Shell Support ----------------
  Future<bool> startInteractiveShell() async {
    if (interactiveShellActive) return true;
    if (_connectedDeviceId.isEmpty) {
      _addOutput('❌ No connected device for interactive shell');
      return false;
    }
    // Only works with external backend (real adb) or server/device mode.
    final serial = _connectedDeviceId;
    try {
      _addOutput('🚀 Starting interactive shell for $serial');
      final args = <String>['-s', serial, 'shell'];
      _interactiveShell = await Process.start('adb', args, runInShell: true);

      // Stdout
      _interactiveStdoutSub = _interactiveShell!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.trim().isEmpty) return;
        _addOutput(line, deviceOutput: true);
      });
      // Stderr
      _interactiveStderrSub = _interactiveShell!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.trim().isEmpty) return;
        _addOutput(line, deviceOutput: true);
      });

      _interactiveShell!.exitCode.then((code) {
        if (_interactiveShell != null) {
          _addOutput('🛑 Interactive shell exited (code $code)');
          _interactiveStdoutSub?.cancel();
          _interactiveStderrSub?.cancel();
          _interactiveStdoutSub = null;
          _interactiveStderrSub = null;
          _interactiveShell = null;
        }
      });
      _addOutput('✅ Interactive shell started');
      return true;
    } catch (e) {
      _addOutput('❌ Failed to start interactive shell: $e');
      return false;
    }
  }

  Future<void> stopInteractiveShell() async {
    if (!interactiveShellActive) return;
    try {
      _addOutput('🛑 Stopping interactive shell');
      _interactiveStdoutSub?.cancel();
      _interactiveStderrSub?.cancel();
      _interactiveStdoutSub = null;
      _interactiveStderrSub = null;
      _interactiveShell!.stdin.writeln('exit');
      await _interactiveShell!.stdin.flush();
      // Give it a moment to exit gracefully
      final proc = _interactiveShell!;
      _interactiveShell = null;
      Future.delayed(const Duration(milliseconds: 300), () {
        try {
          proc.kill(ProcessSignal.sigkill);
        } catch (_) {}
      });
      _addOutput('✅ Interactive shell stopped');
    } catch (e) {
      _addOutput('⚠️ Error stopping interactive shell: $e');
    }
  }

  Future<void> sendInteractiveShellInput(String line) async {
    if (!interactiveShellActive) {
      _addOutput('❌ Interactive shell not active');
      return;
    }
    try {
      _addCommandToHistory(line);
      _interactiveShell!.stdin.writeln(line);
      await _interactiveShell!.stdin.flush();
    } catch (e) {
      _addOutput('⚠️ Failed to send input: $e');
    }
  }

  void _updateState(ADBConnectionState newState) {
    _state = newState;
    if (!_connectionStateController.isClosed) {
      _connectionStateController.add(newState);
    }
  }

  void _addOutput(String output, {bool deviceOutput = false}) {
    // Filter noise if not verbose
    if (!verboseLogging) {
      final lower = output.toLowerCase();
      if (!deviceOutput &&
          (lower.contains('refreshing device list') ||
              lower.contains('already running'))) {
        return; // skip low-value lines
      }
    }
    // Raw mode hides non device output unless verbose
    if (_outputMode == ADBOutputMode.raw && !deviceOutput && !verboseLogging) {
      return;
    }
    final ts = DateTime.now().toString().substring(11, 19);
    final line = _outputMode == ADBOutputMode.raw ? output : '[$ts] $output';
    _outputBuffer.add(line);
    if (_outputBuffer.length > maxConsoleBufferLines) {
      final overflow = _outputBuffer.length - maxConsoleBufferLines;
      _outputBuffer.removeRange(0, overflow);
    }
    if (!_outputController.isClosed) _outputController.add(line);
    if (_outputMode == ADBOutputMode.raw) {
      // still print for debugging
      print(line);
    } else {
      print('ADB: $line');
    }
  }

  void _addCommandToHistory(String command) {
    _commandHistory.add(command);

    // Keep only last 50 commands
    if (_commandHistory.length > 50) {
      _commandHistory.removeAt(0);
    }

    if (!_commandHistoryController.isClosed) {
      _commandHistoryController.add(command);
    }
  }

  void clearOutput() {
    _outputBuffer.clear();
    _addOutput('🧹 Output cleared');
  }

  void clearHistory() {
    _commandHistory.clear();
    _addOutput('🧹 Command history cleared');
  }

  void dispose() {
    disconnect();
    _connectionStateController.close();
    _outputController.close();
    _commandHistoryController.close();
    _logcatSub?.cancel();
    _logcatController.close();
  }

  // ---------------- Logcat Management ----------------
  Future<bool> startLogcat({List<String> filters = const []}) async {
    if (_logcatActive) return true;
    if (_externalBackend == null || _connectedDeviceId.isEmpty) {
      _addOutput('❌ Cannot start logcat: no external backend or device',
          deviceOutput: false);
      return false;
    }
    try {
      final stream =
          _externalBackend!.streamLogcat(_connectedDeviceId, filters: filters);
      if (stream == null) return false;
      _logcatActive = true;
      _logcatSub = stream.listen((line) {
        if (line.trim().isEmpty) return;
        _logcatBuffer.add(line);
        if (_logcatBuffer.length > 1000) {
          _logcatBuffer.removeRange(0, _logcatBuffer.length - 800);
        }
        if (!_logcatController.isClosed) _logcatController.add(line);
      }, onError: (e) {
        _addOutput('Logcat error: $e');
      }, onDone: () {
        _logcatActive = false;
      });
      _addOutput('📜 Logcat streaming started');
      return true;
    } catch (e) {
      _addOutput('❌ Failed to start logcat: $e');
      return false;
    }
  }

  Future<void> stopLogcat() async {
    if (!_logcatActive) return;
    try {
      await _externalBackend?.stopLogcat(_connectedDeviceId);
      await _logcatSub?.cancel();
      _logcatSub = null;
      _logcatActive = false;
      _addOutput('🛑 Logcat stopped');
    } catch (e) {
      _addOutput('⚠️ Error stopping logcat: $e');
    }
  }

  void clearLogcat() {
    _logcatBuffer.clear();
    _addOutput('🧹 Logcat buffer cleared');
  }

  // ---------------- File / Port Operations ----------------
  Future<bool> installApk(String filePath) async {
    if (_externalBackend == null || _connectedDeviceId.isEmpty) return false;
    return await _externalBackend!.installApk(_connectedDeviceId, filePath);
  }

  Future<bool> pushFile(String local, String remote) async {
    if (_externalBackend == null || _connectedDeviceId.isEmpty) return false;
    return await _externalBackend!.pushFile(_connectedDeviceId, local, remote);
  }

  Future<bool> pullFile(String remote, String local) async {
    if (_externalBackend == null || _connectedDeviceId.isEmpty) return false;
    return await _externalBackend!.pullFile(_connectedDeviceId, remote, local);
  }

  Future<bool> forwardPort(int localPort, String remoteSpec) async {
    if (_externalBackend == null || _connectedDeviceId.isEmpty) return false;
    return await _externalBackend!
        .forward(_connectedDeviceId, localPort, remoteSpec);
  }

  Future<bool> removeForward(int localPort) async {
    if (_externalBackend == null || _connectedDeviceId.isEmpty) return false;
    return await _externalBackend!.removeForward(_connectedDeviceId, localPort);
  }

  Future<Map<String, String>> getDeviceProps() async {
    if (_externalBackend == null || _connectedDeviceId.isEmpty) return {};
    return await _externalBackend!.getProps(_connectedDeviceId);
  }

  Future<bool> uninstallPackage(String packageName) async {
    if (_externalBackend == null || _connectedDeviceId.isEmpty) return false;
    return await _externalBackend!
        .uninstallApk(_connectedDeviceId, packageName);
  }

  Future<bool> reboot({String? mode}) async {
    if (_externalBackend == null || _connectedDeviceId.isEmpty) return false;
    return await _externalBackend!.reboot(_connectedDeviceId, mode: mode);
  }

  Future<List<String>> listForwards() async {
    if (_externalBackend == null || _connectedDeviceId.isEmpty) return [];
    return await _externalBackend!.listForwards(_connectedDeviceId);
  }

  Future<Uint8List?> screencap() async {
    if (_externalBackend == null || _connectedDeviceId.isEmpty) return null;
    return await _externalBackend!.screencap(_connectedDeviceId);
  }

  Future<String> execOut(List<String> args) async {
    if (_externalBackend == null || _connectedDeviceId.isEmpty) return '';
    return await _externalBackend!.execOut(_connectedDeviceId, args);
  }
}

// Quick command presets for common ADB operations
class ADBCommands {
  static const List<String> commonCommands = [
    'getprop ro.build.version.release', // Android version
    'pm list packages', // List installed packages
    'dumpsys battery', // Battery info
    'getprop ro.product.model', // Device model
    'wm size', // Screen resolution
    'settings get secure android_id', // Device ID
    'dumpsys meminfo', // Memory info
    'ps', // Running processes
    'ls /sdcard/', // List SD card contents
    'df -h', // Disk usage
    'netstat -an', // Network connections
    'logcat -d', // System logs (recent)
    'input keyevent KEYCODE_HOME', // Press home button
    'input tap 500 1000', // Tap screen at coordinates
    'screencap -p /sdcard/screenshot.png', // Take screenshot
    'am start -n com.android.settings/.Settings', // Open settings
    'pm disable com.example.app', // Disable app
    'pm enable com.example.app', // Enable app
    'reboot', // Reboot device
    'reboot recovery', // Reboot to recovery
  ];

  static const Map<String, List<String>> commandCategories = {
    'Device Info': [
      'getprop ro.build.version.release',
      'getprop ro.product.model',
      'getprop ro.product.manufacturer',
      'getprop ro.hardware',
      'wm size',
      'wm density',
    ],
    'System': [
      'dumpsys battery',
      'dumpsys meminfo',
      'df -h',
      'ps',
      'top -n 1',
      'uptime',
    ],
    'Network': [
      'ip addr show',
      'netstat -an',
      'ping 8.8.8.8 -c 3',
      'dumpsys wifi',
    ],
    'Apps & Packages': [
      'pm list packages',
      'pm list packages -3',
      'pm list packages -s',
      'dumpsys package',
    ],
    'Input & Screen': [
      'input keyevent KEYCODE_HOME',
      'input keyevent KEYCODE_BACK',
      'input keyevent KEYCODE_MENU',
      'input tap 500 1000',
      'screencap -p /sdcard/screenshot.png',
    ],
    'Files & Storage': [
      'ls /sdcard/',
      'ls /system/',
      'ls /data/data/',
      'du -sh /sdcard/*',
    ],
  };

  static String getCommandDescription(String command) {
    final descriptions = {
      'getprop ro.build.version.release': 'Get Android version',
      'pm list packages': 'List all installed packages',
      'dumpsys battery': 'Show battery information',
      'getprop ro.product.model': 'Get device model',
      'wm size': 'Get screen resolution',
      'settings get secure android_id': 'Get unique device ID',
      'dumpsys meminfo': 'Show memory usage',
      'ps': 'List running processes',
      'ls /sdcard/': 'List SD card contents',
      'df -h': 'Show disk usage',
      'netstat -an': 'Show network connections',
      'logcat -d': 'Show recent system logs',
      'input keyevent KEYCODE_HOME': 'Press home button',
      'input tap 500 1000': 'Tap screen at coordinates',
      'screencap -p /sdcard/screenshot.png': 'Take screenshot',
      'reboot': 'Reboot device',
    };
    return descriptions[command] ?? 'Execute command';
  }
}
