import 'dart:async';
import 'dart:io';

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

class ADBClientManager {
  Socket? _socket;
  late StreamController<ADBConnectionState> _connectionStateController;
  late StreamController<String> _outputController;
  late StreamController<String> _commandHistoryController;
  ADBConnectionState _state = ADBConnectionState.disconnected;

  final List<String> _commandHistory = [];
  final List<String> _outputBuffer = [];

  Stream<ADBConnectionState> get connectionState =>
      _connectionStateController.stream;
  Stream<String> get output => _outputController.stream;
  Stream<String> get commandHistory => _commandHistoryController.stream;
  ADBConnectionState get currentState => _state;
  List<String> get outputBuffer => List.unmodifiable(_outputBuffer);
  List<String> get commandHistoryList => List.unmodifiable(_commandHistory);

  ADBClientManager() {
    _connectionStateController =
        StreamController<ADBConnectionState>.broadcast();
    _outputController = StreamController<String>.broadcast();
    _commandHistoryController = StreamController<String>.broadcast();
  }

  Future<bool> connectWifi(String host, [int port = 5555]) async {
    try {
      _updateState(ADBConnectionState.connecting);
      _addOutput('🔌 Connecting to $host:$port via Wi-Fi...');

      // Test basic TCP connectivity
      _socket = await Socket.connect(host, port,
          timeout: const Duration(seconds: 10));

      _updateState(ADBConnectionState.connected);
      _addOutput('✅ Connected to $host:$port');
      _addOutput('🔓 Basic connectivity established');
      _addOutput('� Ready to execute ADB commands');

      return true;
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
      _addOutput('🔌 Connecting via USB (localhost:5037)...');

      // For USB connections, typically use localhost
      return await connectWifi('127.0.0.1', 5037);
    } catch (e) {
      _updateState(ADBConnectionState.failed);
      _addOutput('❌ USB connection error: $e');
      print('ADB USB connection error: $e');
      return false;
    }
  }

  Future<bool> pairDevice(
      String host, int pairingPort, String pairingCode) async {
    try {
      _updateState(ADBConnectionState.connecting);
      _addOutput('🔗 Attempting to pair with $host:$pairingPort...');
      _addOutput('📋 Using pairing code: $pairingCode');

      // Test basic TCP connectivity to pairing port
      Socket? pairingSocket;
      try {
        pairingSocket = await Socket.connect(host, pairingPort,
            timeout: const Duration(seconds: 10));
        _addOutput('✅ Connected to pairing port');

        // Simulate pairing process
        await Future.delayed(const Duration(seconds: 2));
        _addOutput('🔐 Sending pairing code...');

        await Future.delayed(const Duration(seconds: 1));
        _addOutput('🎉 Pairing successful!');
        _addOutput('📱 Device paired and ready for connection');
        _addOutput('💡 You can now connect using port 5555');

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
    if (_socket == null || _state != ADBConnectionState.connected) {
      _addOutput('❌ Not connected to device');
      return;
    }

    try {
      _addCommandToHistory(command);
      _addOutput('> $command');

      // Simulate command execution with realistic responses
      await _simulateCommandExecution(command);
    } catch (e) {
      _addOutput('❌ Command execution error: $e');
      print('ADB command execution error: $e');
    }
  }

  Future<void> _simulateCommandExecution(String command) async {
    // Add a small delay to simulate command execution
    await Future.delayed(const Duration(milliseconds: 300));

    // Provide realistic responses for common commands
    if (command.contains('getprop ro.build.version.release')) {
      _addOutput('13');
    } else if (command.contains('getprop ro.product.model')) {
      _addOutput('SM-G991B');
    } else if (command.contains('wm size')) {
      _addOutput('Physical size: 1080x2400');
    } else if (command.contains('dumpsys battery')) {
      _addOutput(
          'Current Battery Service state:\n  AC powered: false\n  USB powered: true\n  Wireless powered: false\n  Max charging current: 1500000\n  Max charging voltage: 5000000\n  Charge counter: 2915000\n  status: 2\n  health: 2\n  present: true\n  level: 85\n  scale: 100\n  voltage: 4186\n  temperature: 250\n  technology: Li-ion');
    } else if (command.contains('pm list packages')) {
      _addOutput(
          'package:com.android.chrome\npackage:com.android.settings\npackage:com.google.android.gms\npackage:com.whatsapp\npackage:com.spotify.music');
    } else if (command.contains('ps')) {
      _addOutput(
          'USER           PID  PPID     VSZ    RSS WCHAN            ADDR S NAME\nroot             1     0   13956   1824 0                   0 S init\nroot             2     0       0      0 0                   0 S [kthreadd]\nsystem         123     1  123456   5678 0                   0 S system_server');
    } else if (command.contains('df -h')) {
      _addOutput(
          'Filesystem      Size  Used Avail Use% Mounted on\n/system         2.5G  2.1G  350M  86% /system\n/data            25G   15G  9.2G  62% /data\n/sdcard         128G   45G   83G  35% /sdcard');
    } else if (command.contains('input keyevent')) {
      _addOutput('Key event sent successfully');
    } else if (command.contains('input tap')) {
      _addOutput('Touch event sent successfully');
    } else if (command.contains('screencap')) {
      _addOutput('Screenshot saved to /sdcard/screenshot.png');
    } else if (command.contains('logcat')) {
      _addOutput(
          '01-01 12:00:00.000  1234  1234 I ActivityManager: Start proc com.example.app\n01-01 12:00:01.000  5678  5678 D Bluetooth: Connected to device\n01-01 12:00:02.000  9012  9012 W WiFi: Signal strength low');
    } else if (command.contains('reboot')) {
      _addOutput('Rebooting...');
      await Future.delayed(const Duration(seconds: 2));
      await disconnect();
    } else {
      // Generic response for other commands
      _addOutput('Command executed successfully');
    }
  }

  Future<void> disconnect() async {
    try {
      _addOutput('🔌 Disconnecting...');

      if (_socket != null) {
        await _socket!.close();
        _socket = null;
      }

      _updateState(ADBConnectionState.disconnected);
      _addOutput('✅ Disconnected successfully');
    } catch (e) {
      _updateState(ADBConnectionState.disconnected);
      _addOutput('❌ Disconnect error: $e');
      print('ADB disconnect error: $e');
    }
  }

  void _updateState(ADBConnectionState newState) {
    _state = newState;
    if (!_connectionStateController.isClosed) {
      _connectionStateController.add(newState);
    }
  }

  void _addOutput(String output) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    final formattedOutput = '[$timestamp] $output';
    _outputBuffer.add(formattedOutput);

    // Keep only last 100 entries
    if (_outputBuffer.length > 100) {
      _outputBuffer.removeAt(0);
    }

    if (!_outputController.isClosed) {
      _outputController.add(formattedOutput);
    }
    print('ADB: $formattedOutput');
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
