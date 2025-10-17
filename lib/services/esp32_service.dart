import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:network_info_plus/network_info_plus.dart';

enum ESP32ConnectionType { bluetooth, lan }

enum ESP32ConnectionStatus { disconnected, connecting, connected, error }

class ESP32Device {
  final String id;
  final String name;
  final ESP32ConnectionType connectionType;
  final String address; // Bluetooth address or IP address
  final int? port; // For LAN connections
  final String? password;
  ESP32ConnectionStatus status;
  DateTime? lastConnected;

  // Enhanced device information
  String? firmwareVersion;
  String? chipModel;
  String? macAddress;
  int? freeMemory;
  int? totalMemory;
  double? cpuFrequency;
  Map<String, dynamic>? gpioStates;
  Map<String, dynamic>? sensorData;
  List<String>? availableLibraries;
  String? currentFile;
  bool? isRunning;

  ESP32Device({
    required this.id,
    required this.name,
    required this.connectionType,
    required this.address,
    this.port,
    this.password,
    this.status = ESP32ConnectionStatus.disconnected,
    this.lastConnected,
    this.firmwareVersion,
    this.chipModel,
    this.macAddress,
    this.freeMemory,
    this.totalMemory,
    this.cpuFrequency,
    this.gpioStates,
    this.sensorData,
    this.availableLibraries,
    this.currentFile,
    this.isRunning,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'connectionType': connectionType.index,
        'address': address,
        'port': port,
        'password': password,
        'status': status.index,
        'lastConnected': lastConnected?.toIso8601String(),
        'firmwareVersion': firmwareVersion,
        'chipModel': chipModel,
        'macAddress': macAddress,
        'freeMemory': freeMemory,
        'totalMemory': totalMemory,
        'cpuFrequency': cpuFrequency,
        'gpioStates': gpioStates,
        'sensorData': sensorData,
        'availableLibraries': availableLibraries,
        'currentFile': currentFile,
        'isRunning': isRunning,
      };

  factory ESP32Device.fromJson(Map<String, dynamic> json) => ESP32Device(
        id: json['id'],
        name: json['name'],
        connectionType: ESP32ConnectionType.values[json['connectionType']],
        address: json['address'],
        port: json['port'],
        password: json['password'],
        status: ESP32ConnectionStatus.values[json['status'] ?? 0],
        lastConnected: json['lastConnected'] != null
            ? DateTime.parse(json['lastConnected'])
            : null,
        firmwareVersion: json['firmwareVersion'],
        chipModel: json['chipModel'],
        macAddress: json['macAddress'],
        freeMemory: json['freeMemory'],
        totalMemory: json['totalMemory'],
        cpuFrequency: json['cpuFrequency']?.toDouble(),
        gpioStates: json['gpioStates'],
        sensorData: json['sensorData'],
        availableLibraries: json['availableLibraries']?.cast<String>(),
        currentFile: json['currentFile'],
        isRunning: json['isRunning'],
      );
}

class ESP32Connection {
  final ESP32Device device;
  HttpClient? _httpClient;
  Timer? _statusTimer;
  final StreamController<String> _dataController =
      StreamController<String>.broadcast();

  ESP32Connection(this.device);

  Stream<String> get dataStream => _dataController.stream;
  bool get isConnected => device.status == ESP32ConnectionStatus.connected;

  Future<bool> connect() async {
    try {
      device.status = ESP32ConnectionStatus.connecting;

      if (device.connectionType == ESP32ConnectionType.bluetooth) {
        return await _connectBluetooth();
      } else {
        return await _connectLAN();
      }
    } catch (e) {
      device.status = ESP32ConnectionStatus.error;
      debugPrint('ESP32 connection error: $e');
      return false;
    }
  }

  Future<bool> _connectBluetooth() async {
    // Simplified Bluetooth connection - just mark as connected for now
    // In a real implementation, you would use platform channels or a Bluetooth plugin
    try {
      // Simulate connection delay
      await Future.delayed(const Duration(seconds: 2));

      device.status = ESP32ConnectionStatus.connected;
      device.lastConnected = DateTime.now();

      // Simulate receiving data periodically for demo
      Timer.periodic(const Duration(seconds: 5), (timer) {
        if (device.status == ESP32ConnectionStatus.connected) {
          _dataController
              .add('MicroPython v1.20.0 on ${DateTime.now()}\\n>>> ');
        } else {
          timer.cancel();
        }
      });

      return true;
    } catch (e) {
      debugPrint('Bluetooth connection error: $e');
      device.status = ESP32ConnectionStatus.error;
      return false;
    }
  }

  Future<bool> _connectLAN() async {
    try {
      // Test basic HTTP connectivity
      final response = await http.get(
        Uri.parse('http://${device.address}:${device.port ?? 80}/'),
        headers: {'Connection': 'close'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 404) {
        device.status = ESP32ConnectionStatus.connected;
        device.lastConnected = DateTime.now();

        // Set up HTTP client for commands
        _httpClient = HttpClient();

        // Start periodic status updates
        _statusTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
          if (device.status == ESP32ConnectionStatus.connected) {
            _checkDeviceStatus();
          } else {
            timer.cancel();
          }
        });

        // Send initial connection message
        _dataController.add(
            'Connected to ESP32 at ${device.address}:${device.port}\\n>>> ');

        return true;
      }
    } catch (e) {
      debugPrint('LAN connection error: $e');
    }

    device.status = ESP32ConnectionStatus.error;
    return false;
  }

  Future<void> _checkDeviceStatus() async {
    try {
      final response = await http.get(
        Uri.parse('http://${device.address}:${device.port ?? 80}/status'),
        headers: {'Connection': 'close'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        _dataController.add('Device status: OK - ${DateTime.now()}\\n');
      }
    } catch (e) {
      // Connection lost
      disconnect();
    }
  }

  Future<void> sendCommand(String command) async {
    if (!isConnected) return;

    try {
      if (device.connectionType == ESP32ConnectionType.bluetooth) {
        // For Bluetooth, simulate command echo and response
        _dataController.add('>>> $command\\n');

        // Simulate some common MicroPython responses
        await Future.delayed(const Duration(milliseconds: 500));

        if (command.trim() == 'help()') {
          _dataController.add('''Welcome to MicroPython!

For online docs please visit http://docs.micropython.org/

Control commands:
  CTRL-A        -- on a blank line, enter raw REPL mode
  CTRL-B        -- on a blank line, enter normal REPL mode
  CTRL-C        -- interrupt a running program
  CTRL-D        -- on a blank line, do a soft reset of the board

For further help on a specific object, type help(obj)
For a list of available modules, type help('modules')
>>> ''');
        } else if (command.trim().startsWith('print(')) {
          final content = command.substring(6, command.length - 1);
          _dataController.add('$content\\n>>> ');
        } else if (command.trim() == 'import os') {
          _dataController.add('>>> ');
        } else if (command.trim().startsWith('os.listdir')) {
          _dataController
              .add("['boot.py', 'main.py', 'lib', 'config.json']\\n>>> ");
        } else {
          _dataController.add('>>> ');
        }
      } else if (_httpClient != null) {
        // HTTP command sending for LAN connections
        try {
          final response = await http
              .post(
                Uri.parse(
                    'http://${device.address}:${device.port ?? 80}/command'),
                headers: {
                  'Content-Type': 'application/json',
                  'Connection': 'close',
                },
                body: jsonEncode({'command': command}),
              )
              .timeout(const Duration(seconds: 10));

          if (response.statusCode == 200) {
            _dataController.add('>>> $command\\n');
            _dataController.add('${response.body}\\n>>> ');
          } else {
            _dataController.add('>>> $command\\n');
            _dataController.add('Error: HTTP ${response.statusCode}\\n>>> ');
          }
        } catch (e) {
          debugPrint('HTTP command error: $e');
          _dataController.add('>>> $command\\n');
          _dataController.add('Connection error: $e\\n>>> ');
        }
      }
    } catch (e) {
      debugPrint('Send command error: $e');
    }
  }

  Future<String?> sendCommandWithResponse(String command,
      {Duration timeout = const Duration(seconds: 5)}) async {
    if (!isConnected) return null;

    final completer = Completer<String>();
    late StreamSubscription subscription;

    subscription = dataStream.listen((data) {
      if (!completer.isCompleted) {
        completer.complete(data);
        subscription.cancel();
      }
    });

    await sendCommand(command);

    try {
      return await completer.future.timeout(timeout);
    } catch (e) {
      subscription.cancel();
      return null;
    }
  }

  Future<List<String>> listFiles(String path) async {
    final response =
        await sendCommandWithResponse('import os; print(os.listdir("$path"))');
    if (response != null) {
      try {
        // Parse Python list output
        final cleanResponse = response.trim().replaceAll("'", '"');
        if (cleanResponse.startsWith('[') && cleanResponse.endsWith(']')) {
          final List<dynamic> files = jsonDecode(cleanResponse);
          return files.cast<String>();
        }
      } catch (e) {
        debugPrint('Error parsing file list: $e');
      }
    }

    // Return mock data if parsing fails
    return ['boot.py', 'main.py', 'lib', 'config.json'];
  }

  Future<String?> readFile(String filePath) async {
    final command = '''
try:
    with open("$filePath", "r") as f:
        print(f.read())
except Exception as e:
    print("Error:", str(e))
''';
    return await sendCommandWithResponse(command,
        timeout: const Duration(seconds: 10));
  }

  Future<bool> writeFile(String filePath, String content) async {
    final escapedContent =
        content.replaceAll('\\\\', '\\\\\\\\').replaceAll('"', '\\\\"');
    final command = '''
try:
    with open("$filePath", "w") as f:
        f.write("$escapedContent")
    print("File written successfully")
except Exception as e:
    print("Error:", str(e))
''';

    final response = await sendCommandWithResponse(command,
        timeout: const Duration(seconds: 10));
    return response?.contains('File written successfully') ?? false;
  }

  Future<bool> deleteFile(String filePath) async {
    final command = '''
try:
    import os
    os.remove("$filePath")
    print("File deleted successfully")
except Exception as e:
    print("Error:", str(e))
''';
    final response = await sendCommandWithResponse(command);
    return response?.contains('File deleted successfully') ?? false;
  }

  // Enhanced ESP32 Functions

  Future<Map<String, dynamic>?> getDeviceInfo() async {
    final command = '''
import sys
import os
import gc
try:
    import machine
    import network
    
    info = {
        "firmware": sys.version,
        "platform": sys.platform,
        "memory_free": gc.mem_free(),
        "memory_alloc": gc.mem_alloc(),
        "freq": machine.freq() if hasattr(machine, 'freq') else None,
        "unique_id": machine.unique_id().hex() if hasattr(machine, 'unique_id') else None,
    }
    
    # Get WiFi info if available
    try:
        wlan = network.WLAN(network.STA_IF)
        if wlan.active():
            info["wifi_connected"] = wlan.isconnected()
            if wlan.isconnected():
                info["ip"] = wlan.ifconfig()[0]
                info["mac"] = wlan.config('mac').hex()
    except:
        pass
    
    print("DEVICE_INFO:" + str(info))
except Exception as e:
    print("Error getting device info:", str(e))
''';

    final response = await sendCommandWithResponse(command,
        timeout: const Duration(seconds: 10));
    if (response != null && response.contains('DEVICE_INFO:')) {
      try {
        final infoStr = response.split('DEVICE_INFO:')[1].trim();
        // Parse the Python dict string (simplified parsing)
        return _parsePythonDict(infoStr);
      } catch (e) {
        debugPrint('Error parsing device info: $e');
      }
    }
    return null;
  }

  Future<Map<String, bool>?> getGPIOStates() async {
    final command = '''
try:
    import machine
    
    # Common ESP32 GPIO pins
    gpio_pins = [0, 2, 4, 5, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23, 25, 26, 27, 32, 33]
    gpio_states = {}
    
    for pin_num in gpio_pins:
        try:
            pin = machine.Pin(pin_num, machine.Pin.IN)
            gpio_states[pin_num] = pin.value()
        except:
            pass
    
    print("GPIO_STATES:" + str(gpio_states))
except Exception as e:
    print("Error reading GPIO:", str(e))
''';

    final response = await sendCommandWithResponse(command);
    if (response != null && response.contains('GPIO_STATES:')) {
      try {
        final statesStr = response.split('GPIO_STATES:')[1].trim();
        final parsed = _parsePythonDict(statesStr);
        return parsed?.map((k, v) => MapEntry(k.toString(), v == 1));
      } catch (e) {
        debugPrint('Error parsing GPIO states: $e');
      }
    }
    return null;
  }

  Future<bool> setGPIO(int pin, bool value) async {
    final command = '''
try:
    import machine
    pin = machine.Pin($pin, machine.Pin.OUT)
    pin.value(${value ? 1 : 0})
    print("GPIO_SET_SUCCESS:$pin=${value ? 1 : 0}")
except Exception as e:
    print("Error setting GPIO:", str(e))
''';

    final response = await sendCommandWithResponse(command);
    return response?.contains('GPIO_SET_SUCCESS') ?? false;
  }

  Future<Map<String, dynamic>?> getSensorData() async {
    final command = '''
try:
    import machine
    import time
    
    sensors = {}
    
    # Try to read common sensors
    try:
        # Temperature sensor (if available)
        temp_sensor = machine.ADC(machine.Pin(36))
        temp_sensor.atten(machine.ADC.ATTN_11DB)
        sensors["temperature_raw"] = temp_sensor.read()
    except:
        pass
    
    try:
        # Light sensor (LDR on pin 34)
        light_sensor = machine.ADC(machine.Pin(34))
        light_sensor.atten(machine.ADC.ATTN_11DB)
        sensors["light_raw"] = light_sensor.read()
    except:
        pass
    
    # System sensors
    try:
        sensors["hall_sensor"] = machine.ADC(machine.Pin(39)).read() if hasattr(machine, 'ADC') else None
    except:
        pass
    
    sensors["uptime"] = time.ticks_ms()
    
    print("SENSOR_DATA:" + str(sensors))
except Exception as e:
    print("Error reading sensors:", str(e))
''';

    final response = await sendCommandWithResponse(command);
    if (response != null && response.contains('SENSOR_DATA:')) {
      try {
        final dataStr = response.split('SENSOR_DATA:')[1].trim();
        return _parsePythonDict(dataStr);
      } catch (e) {
        debugPrint('Error parsing sensor data: $e');
      }
    }
    return null;
  }

  Future<List<String>?> getAvailableLibraries() async {
    final command = '''
try:
    import os
    libraries = []
    
    # Check built-in modules
    import sys
    libraries.extend(sys.modules.keys())
    
    # Check lib directory
    try:
        lib_files = os.listdir('/lib')
        for file in lib_files:
            if file.endswith('.py'):
                libraries.append(file[:-3])  # Remove .py extension
    except:
        pass
    
    print("LIBRARIES:" + str(sorted(set(libraries))))
except Exception as e:
    print("Error getting libraries:", str(e))
''';

    final response = await sendCommandWithResponse(command);
    if (response != null && response.contains('LIBRARIES:')) {
      try {
        final libStr = response.split('LIBRARIES:')[1].trim();
        // Simple parsing for Python list
        if (libStr.startsWith('[') && libStr.endsWith(']')) {
          final content = libStr.substring(1, libStr.length - 1);
          final items = content
              .split(',')
              .map((e) => e.trim().replaceAll("'", "").replaceAll('"', ''))
              .toList();
          return items.where((item) => item.isNotEmpty).toList();
        }
      } catch (e) {
        debugPrint('Error parsing libraries: $e');
      }
    }
    return null;
  }

  Future<bool> uploadFile(String filePath, String content) async {
    final command = '''
try:
    import os
    
    # Create directory if needed
    dir_path = "${filePath.split('/').sublist(0, filePath.split('/').length - 1).join('/')}"
    if dir_path and not dir_path.startswith('/'):
        dir_path = '/' + dir_path
    
    if dir_path and dir_path != '/':
        try:
            os.makedirs(dir_path)
        except:
            pass
    
    # Write file
    with open("$filePath", "w") as f:
        f.write("""$content""")
    
    print("UPLOAD_SUCCESS:$filePath")
except Exception as e:
    print("Upload error:", str(e))
''';

    final response = await sendCommandWithResponse(command,
        timeout: const Duration(seconds: 15));
    return response?.contains('UPLOAD_SUCCESS') ?? false;
  }

  Future<bool> runScript(String filePath) async {
    final command = '''
try:
    exec(open("$filePath").read())
    print("SCRIPT_EXECUTED:$filePath")
except Exception as e:
    print("Script error:", str(e))
''';

    final response = await sendCommandWithResponse(command,
        timeout: const Duration(seconds: 30));
    return response?.contains('SCRIPT_EXECUTED') ?? false;
  }

  Future<bool> stopScript() async {
    final command = '''
try:
    import machine
    machine.soft_reset()
    print("SCRIPT_STOPPED")
except Exception as e:
    print("Stop error:", str(e))
''';

    final response = await sendCommandWithResponse(command);
    return response?.contains('SCRIPT_STOPPED') ?? false;
  }

  Future<String?> getSystemStatus() async {
    final command = '''
try:
    import gc
    import machine
    import time
    
    status = {
        "memory_free": gc.mem_free(),
        "memory_alloc": gc.mem_alloc(),
        "uptime": time.ticks_ms(),
        "freq": machine.freq() if hasattr(machine, 'freq') else None,
    }
    
    print("SYSTEM_STATUS:" + str(status))
except Exception as e:
    print("Status error:", str(e))
''';

    final response = await sendCommandWithResponse(command);
    if (response != null && response.contains('SYSTEM_STATUS:')) {
      return response.split('SYSTEM_STATUS:')[1].trim();
    }
    return null;
  }

  Future<bool> installLibrary(String libraryName) async {
    final command = '''
try:
    import upip
    upip.install("$libraryName")
    print("LIBRARY_INSTALLED:$libraryName")
except Exception as e:
    print("Install error:", str(e))
''';

    final response = await sendCommandWithResponse(command,
        timeout: const Duration(minutes: 5));
    return response?.contains('LIBRARY_INSTALLED') ?? false;
  }

  // Helper method to parse Python dictionary strings
  Map<String, dynamic>? _parsePythonDict(String pythonStr) {
    try {
      // Simple Python dict to JSON conversion
      String jsonStr = pythonStr
          .replaceAll("'", '"')
          .replaceAll('True', 'true')
          .replaceAll('False', 'false')
          .replaceAll('None', 'null');

      return jsonDecode(jsonStr);
    } catch (e) {
      debugPrint('Error parsing Python dict: $e');
      return null;
    }
  }

  void disconnect() {
    device.status = ESP32ConnectionStatus.disconnected;

    _statusTimer?.cancel();
    _statusTimer = null;

    _httpClient?.close();
    _httpClient = null;

    _dataController.add('Disconnected from ${device.name}\n');
  }

  void dispose() {
    disconnect();
    _dataController.close();
  }
}

class ESP32Service {
  static final ESP32Service _instance = ESP32Service._internal();
  factory ESP32Service() => _instance;
  ESP32Service._internal();

  final Map<String, ESP32Connection> _connections = {};
  final StreamController<List<ESP32Device>> _devicesController =
      StreamController<List<ESP32Device>>.broadcast();

  Stream<List<ESP32Device>> get devicesStream => _devicesController.stream;

  Future<List<Map<String, String>>> scanBluetoothDevices() async {
    // Simplified Bluetooth scanning - return mock ESP32 devices
    // In a real implementation, you would use platform channels or a Bluetooth plugin
    try {
      await Future.delayed(const Duration(seconds: 2)); // Simulate scan time

      return [
        {
          'name': 'ESP32-DevBoard',
          'address': '24:0A:C4:00:00:01',
        },
        {
          'name': 'ESP32-WROOM',
          'address': '24:0A:C4:00:00:02',
        },
      ];
    } catch (e) {
      debugPrint('Bluetooth scan error: $e');
      return [];
    }
  }

  Future<List<String>> scanLANDevices() async {
    final List<String> foundDevices = [];

    try {
      // Get actual network information
      final info = NetworkInfo();
      final wifiIP = await info.getWifiIP();

      if (wifiIP == null) {
        debugPrint('No WiFi connection detected');
        return [];
      }

      // Extract network prefix (e.g., "192.168.1" from "192.168.1.100")
      final ipParts = wifiIP.split('.');
      if (ipParts.length != 4) {
        debugPrint('Invalid IP format: $wifiIP');
        return [];
      }

      final networkPrefix = '${ipParts[0]}.${ipParts[1]}.${ipParts[2]}';
      final currentDeviceIP = int.parse(ipParts[3]);

      debugPrint('Scanning network: $networkPrefix.x');

      // Common ESP32 ports
      final ports = [80, 81, 8080, 8266, 8000, 8001, 8080, 443];

      // Create a list of IP addresses to scan (prioritize nearby IPs)
      final List<int> ipsToScan = [];

      // Add nearby IPs first (±10 from current device)
      for (int offset = 1; offset <= 10; offset++) {
        if (currentDeviceIP - offset >= 1)
          ipsToScan.add(currentDeviceIP - offset);
        if (currentDeviceIP + offset <= 254)
          ipsToScan.add(currentDeviceIP + offset);
      }

      // Add common router/gateway IPs
      final commonIPs = [1, 254, 100, 101, 102, 10, 11, 12, 20, 21, 22];
      for (final ip in commonIPs) {
        if (!ipsToScan.contains(ip) && ip != currentDeviceIP) {
          ipsToScan.add(ip);
        }
      }

      // Add remaining IPs
      for (int i = 1; i <= 254; i++) {
        if (!ipsToScan.contains(i) && i != currentDeviceIP) {
          ipsToScan.add(i);
        }
      }

      debugPrint('Scanning ${ipsToScan.length} IPs on ${ports.length} ports');

      // Scan in batches to avoid overwhelming the network
      const batchSize = 20;
      for (int batch = 0; batch < ipsToScan.length; batch += batchSize) {
        final batchEnd = (batch + batchSize).clamp(0, ipsToScan.length);
        final batchIPs = ipsToScan.sublist(batch, batchEnd);

        final futures = <Future<void>>[];

        for (final ip in batchIPs) {
          for (final port in ports) {
            futures.add(
                _checkESP32Device('$networkPrefix.$ip', port).then((isESP32) {
              if (isESP32) {
                foundDevices.add('$networkPrefix.$ip:$port');
                debugPrint('Found ESP32 device: $networkPrefix.$ip:$port');
              }
            }));
          }
        }

        // Wait for this batch to complete with timeout
        try {
          await Future.wait(futures).timeout(const Duration(seconds: 10));
        } catch (e) {
          debugPrint('Batch $batch timeout: $e');
        }

        // Small delay between batches
        await Future.delayed(const Duration(milliseconds: 100));
      }
    } catch (e) {
      debugPrint('LAN scan error: $e');
    }

    debugPrint('LAN scan complete. Found ${foundDevices.length} devices');
    return foundDevices;
  }

  Future<bool> _checkESP32Device(String ip, int port) async {
    try {
      final response = await http.get(
        Uri.parse('http://$ip:$port/'),
        headers: {
          'Connection': 'close',
          'User-Agent': 'LitterBox-ESP32-Scanner/1.0',
        },
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode != 200) {
        return false;
      }

      // Check response body for ESP32/MicroPython indicators
      final body = response.body.toLowerCase();
      final headers = response.headers;

      // Check for ESP32-specific keywords
      final esp32Keywords = [
        'esp32',
        'esp-32',
        'espressif',
        'micropython',
        'micro python',
        'circuitpython',
        'circuit python',
        'webrepl',
        'web repl',
        'repl',
        'esp32cam',
        'esp32-cam',
        'esptool',
        'esp tool',
        'arduino',
        'nodemcu',
        'wemos',
        'esp8266',
        'esp-8266'
      ];

      final serverKeywords = [
        'esp32',
        'micropython',
        'circuitpython',
        'arduino',
        'esp8266',
        'nodemcu',
        'wemos'
      ];

      // Check body content
      bool hasKeyword = esp32Keywords.any((keyword) => body.contains(keyword));

      // Check server header
      final serverHeader = headers['server']?.toLowerCase() ?? '';
      bool hasServerKeyword =
          serverKeywords.any((keyword) => serverHeader.contains(keyword));

      // Check for MicroPython WebREPL specific patterns
      bool hasWebREPL = body.contains('webrepl') ||
          body.contains('ws://') ||
          body.contains('websocket');

      // Check for common ESP32 file structure
      bool hasESP32Structure = body.contains('boot.py') ||
          body.contains('main.py') ||
          body.contains('/files') ||
          body.contains('/upload');

      // Additional checks for ESP32 web interfaces
      bool hasESP32Interface = body.contains('gpio') ||
          body.contains('pin') ||
          body.contains('sensor') ||
          body.contains('wifi') ||
          body.contains('config');

      final isESP32 = hasKeyword ||
          hasServerKeyword ||
          hasWebREPL ||
          hasESP32Structure ||
          hasESP32Interface;

      if (isESP32) {
        debugPrint('ESP32 detected at $ip:$port - Server: $serverHeader');
      }

      return isESP32;
    } catch (e) {
      // Silently fail for connection errors (expected for most IPs)
      return false;
    }
  }

  ESP32Connection? getConnection(String deviceId) {
    return _connections[deviceId];
  }

  Future<bool> connectDevice(ESP32Device device) async {
    final connection = ESP32Connection(device);
    final success = await connection.connect();

    if (success) {
      _connections[device.id] = connection;
    }

    _devicesController.add(_connections.values.map((c) => c.device).toList());
    return success;
  }

  void disconnectDevice(String deviceId) {
    final connection = _connections[deviceId];
    if (connection != null) {
      connection.disconnect();
      _connections.remove(deviceId);
      _devicesController.add(_connections.values.map((c) => c.device).toList());
    }
  }

  void disconnectAll() {
    for (final connection in _connections.values) {
      connection.disconnect();
    }
    _connections.clear();
    _devicesController.add([]);
  }

  void dispose() {
    disconnectAll();
    _devicesController.close();
  }
}
