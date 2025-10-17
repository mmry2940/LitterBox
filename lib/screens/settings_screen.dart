import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notifications = true;
  bool _developer = false;
  double _textScale = 1.0;
  ThemeMode _themeMode = ThemeMode.dark;
  Color _seed = Colors.deepPurple;
  final Map<String, Locale> _supportedLocales = const {
    'English': Locale('en'),
    'Spanish': Locale('es'),
  };
  String _currentLang = 'English';
  // New settings
  String _startupPage = 'home'; // home, android, settings
  bool _autoConnectAdb = false;
  bool _verboseLogging = false;
  int _logRetentionDays = 7; // 1-30
  int _consoleBufferLines = 500; // 100-5000
  bool _telemetry = false;
  bool _crashReports = false;
  bool _confirmClearLogcat = true;
  String _vncDefaultScaling = 'fit'; // fit, original, fill
  bool _adbProgressNotifications = true;

  // Security settings
  bool _requireAuthentication = false;
  String _authenticationMethod = 'biometric'; // biometric, pin, password
  int _sessionTimeout = 30; // minutes
  bool _hideRecentApps = false;
  bool _enableAppLock = false;

  // Performance settings
  bool _enableHardwareAcceleration = true;
  int _maxConcurrentConnections = 5;
  bool _enableConnectionPooling = true;
  int _networkTimeout = 30; // seconds
  bool _enableLowPowerMode = false;

  // Advanced preferences
  String _defaultShell = '/bin/bash';
  String _terminalEmulator = 'xterm-256color';
  bool _enableUTF8 = true;
  int _scrollbackLines = 1000;
  String _fontFamily = 'Courier';
  double _fontSize = 14.0;

  // Backup and restore
  bool _autoBackup = false;
  int _backupFrequency = 7; // days
  String _backupLocation = 'local'; // local, cloud

  // Connection defaults
  int _defaultSSHPort = 22;
  int _defaultVNCPort = 5900;
  int _defaultRDPPort = 3389;
  bool _enableCompression = true;
  String _compressionLevel = 'medium'; // low, medium, high

  // UI enhancements
  bool _showConnectionIndicator = true;
  bool _enableAnimations = true;
  bool _compactMode = false;
  bool _showTooltips = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _notifications = prefs.getBool('notifications_enabled') ?? true;
      _developer = prefs.getBool('dev_mode') ?? false;
      _textScale = prefs.getDouble('app_text_scale') ?? 1.0;
      final themeIndex = prefs.getInt('app_theme_mode');
      if (themeIndex != null && themeIndex < ThemeMode.values.length) {
        _themeMode = ThemeMode.values[themeIndex];
      }
      final seed = prefs.getInt('app_color_seed');
      if (seed != null) _seed = Color(seed);
      _currentLang = prefs.getString('app_lang') ?? 'English';
      _startupPage = prefs.getString('startup_page') ?? 'home';
      _autoConnectAdb = prefs.getBool('auto_connect_adb') ?? false;
      _verboseLogging = prefs.getBool('verbose_logging') ?? false;
      _logRetentionDays = prefs.getInt('log_retention_days')?.clamp(1, 30) ?? 7;
      _consoleBufferLines =
          prefs.getInt('console_buffer_lines')?.clamp(100, 5000) ?? 500;
      _telemetry = prefs.getBool('telemetry_opt_in') ?? false;
      _crashReports = prefs.getBool('crash_reports') ?? false;
      _confirmClearLogcat = prefs.getBool('confirm_clear_logcat') ?? true;
      _vncDefaultScaling = prefs.getString('vnc_default_scaling') ?? 'fit';
      _adbProgressNotifications =
          prefs.getBool('adb_progress_notifications') ?? true;

      // Security settings
      _requireAuthentication = prefs.getBool('require_authentication') ?? false;
      _authenticationMethod =
          prefs.getString('authentication_method') ?? 'biometric';
      _sessionTimeout = prefs.getInt('session_timeout') ?? 30;
      _hideRecentApps = prefs.getBool('hide_recent_apps') ?? false;
      _enableAppLock = prefs.getBool('enable_app_lock') ?? false;

      // Performance settings
      _enableHardwareAcceleration =
          prefs.getBool('enable_hardware_acceleration') ?? true;
      _maxConcurrentConnections =
          prefs.getInt('max_concurrent_connections') ?? 5;
      _enableConnectionPooling =
          prefs.getBool('enable_connection_pooling') ?? true;
      _networkTimeout = prefs.getInt('network_timeout') ?? 30;
      _enableLowPowerMode = prefs.getBool('enable_low_power_mode') ?? false;

      // Advanced preferences
      _defaultShell = prefs.getString('default_shell') ?? '/bin/bash';
      _terminalEmulator =
          prefs.getString('terminal_emulator') ?? 'xterm-256color';
      _enableUTF8 = prefs.getBool('enable_utf8') ?? true;
      _scrollbackLines = prefs.getInt('scrollback_lines') ?? 1000;
      _fontFamily = prefs.getString('font_family') ?? 'Courier';
      _fontSize = prefs.getDouble('font_size') ?? 14.0;

      // Backup and restore
      _autoBackup = prefs.getBool('auto_backup') ?? false;
      _backupFrequency = prefs.getInt('backup_frequency') ?? 7;
      _backupLocation = prefs.getString('backup_location') ?? 'local';

      // Connection defaults
      _defaultSSHPort = prefs.getInt('default_ssh_port') ?? 22;
      _defaultVNCPort = prefs.getInt('default_vnc_port') ?? 5900;
      _defaultRDPPort = prefs.getInt('default_rdp_port') ?? 3389;
      _enableCompression = prefs.getBool('enable_compression') ?? true;
      _compressionLevel = prefs.getString('compression_level') ?? 'medium';

      // UI enhancements
      _showConnectionIndicator =
          prefs.getBool('show_connection_indicator') ?? true;
      _enableAnimations = prefs.getBool('enable_animations') ?? true;
      _compactMode = prefs.getBool('compact_mode') ?? false;
      _showTooltips = prefs.getBool('show_tooltips') ?? true;
    });
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_enabled', _notifications);
    await prefs.setBool('dev_mode', _developer);
    await prefs.setDouble('app_text_scale', _textScale);
    await prefs.setInt('app_theme_mode', _themeMode.index);
    await prefs.setInt('app_color_seed', _seed.value);
    await prefs.setString('app_lang', _currentLang);
    await prefs.setString('startup_page', _startupPage);
    await prefs.setBool('auto_connect_adb', _autoConnectAdb);
    await prefs.setBool('verbose_logging', _verboseLogging);
    await prefs.setInt('log_retention_days', _logRetentionDays);
    await prefs.setInt('console_buffer_lines', _consoleBufferLines);
    await prefs.setBool('telemetry_opt_in', _telemetry);
    await prefs.setBool('crash_reports', _crashReports);
    await prefs.setBool('confirm_clear_logcat', _confirmClearLogcat);
    await prefs.setString('vnc_default_scaling', _vncDefaultScaling);
    await prefs.setBool(
        'adb_progress_notifications', _adbProgressNotifications);

    // Save security settings
    await prefs.setBool('require_authentication', _requireAuthentication);
    await prefs.setString('authentication_method', _authenticationMethod);
    await prefs.setInt('session_timeout', _sessionTimeout);
    await prefs.setBool('hide_recent_apps', _hideRecentApps);
    await prefs.setBool('enable_app_lock', _enableAppLock);

    // Save performance settings
    await prefs.setBool(
        'enable_hardware_acceleration', _enableHardwareAcceleration);
    await prefs.setInt('max_concurrent_connections', _maxConcurrentConnections);
    await prefs.setBool('enable_connection_pooling', _enableConnectionPooling);
    await prefs.setInt('network_timeout', _networkTimeout);
    await prefs.setBool('enable_low_power_mode', _enableLowPowerMode);

    // Save advanced preferences
    await prefs.setString('default_shell', _defaultShell);
    await prefs.setString('terminal_emulator', _terminalEmulator);
    await prefs.setBool('enable_utf8', _enableUTF8);
    await prefs.setInt('scrollback_lines', _scrollbackLines);
    await prefs.setString('font_family', _fontFamily);
    await prefs.setDouble('font_size', _fontSize);

    // Save backup and restore
    await prefs.setBool('auto_backup', _autoBackup);
    await prefs.setInt('backup_frequency', _backupFrequency);
    await prefs.setString('backup_location', _backupLocation);

    // Save connection defaults
    await prefs.setInt('default_ssh_port', _defaultSSHPort);
    await prefs.setInt('default_vnc_port', _defaultVNCPort);
    await prefs.setInt('default_rdp_port', _defaultRDPPort);
    await prefs.setBool('enable_compression', _enableCompression);
    await prefs.setString('compression_level', _compressionLevel);

    // Save UI enhancements
    await prefs.setBool('show_connection_indicator', _showConnectionIndicator);
    await prefs.setBool('enable_animations', _enableAnimations);
    await prefs.setBool('compact_mode', _compactMode);
    await prefs.setBool('show_tooltips', _showTooltips);
  }

  Future<void> _toggleNotifications(bool value) async {
    setState(() => _notifications = value);
    await _persist();
  }

  Future<void> _showLanguageDialog(BuildContext context) async {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Select Language'),
          content: SizedBox(
            width: 300,
            child: ListView(
              shrinkWrap: true,
              children: _supportedLocales.keys.map((name) {
                return RadioListTile<String>(
                  title: Text(name),
                  value: name,
                  groupValue: _currentLang,
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _currentLang = v);
                      _persist();
                      Navigator.pop(ctx);
                    }
                  },
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showAboutDialog(BuildContext context) async {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('About'),
          content: const Text(
              'LitterBox App\nVersion 1.0.0\nDeveloped by mmry2940\nOSS licenses available on request.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _chooseColorSeed() async {
    // Simple palette picker
    final palette = <Color>[
      Colors.deepPurple,
      Colors.indigo,
      Colors.teal,
      Colors.green,
      Colors.orange,
      Colors.pink,
      Colors.cyan,
      Colors.blueGrey,
    ];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Select Accent Color'),
        content: SizedBox(
          width: 320,
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: palette.map((c) {
              final selected = c.value == _seed.value;
              return InkWell(
                onTap: () {
                  setState(() => _seed = c);
                  colorSeedNotifier.value = c;
                  _persist();
                  Navigator.pop(ctx);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: selected ? Colors.white : Colors.black26,
                        width: selected ? 3 : 1),
                    boxShadow: [
                      if (selected)
                        BoxShadow(
                          color: c.withOpacity(.6),
                          blurRadius: 8,
                          spreadRadius: 1,
                        )
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Future<void> _exportSettings() async {
    final data = jsonEncode({
      'notifications_enabled': _notifications,
      'dev_mode': _developer,
      'app_text_scale': _textScale,
      'app_theme_mode': _themeMode.index,
      'app_color_seed': _seed.value,
      'app_lang': _currentLang,
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Settings exported (copy below)')),
      );
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Exported Settings JSON'),
        content: SingleChildScrollView(
          child: SelectableText(data, style: const TextStyle(fontSize: 12)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close'))
        ],
      ),
    );
  }

  Future<void> _importSettings() async {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import Settings JSON'),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: controller,
            maxLines: 10,
            decoration: const InputDecoration(
              hintText: '{"notifications_enabled":true,...}',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              try {
                final map = jsonDecode(controller.text);
                if (map is Map<String, dynamic>) {
                  _notifications =
                      map['notifications_enabled'] ?? _notifications;
                  _developer = map['dev_mode'] ?? _developer;
                  _textScale = (map['app_text_scale'] ?? _textScale).toDouble();
                  final ti = map['app_theme_mode'];
                  if (ti is int && ti >= 0 && ti < ThemeMode.values.length) {
                    _themeMode = ThemeMode.values[ti];
                    themeModeNotifier.value = _themeMode;
                  }
                  final seed = map['app_color_seed'];
                  if (seed is int) {
                    _seed = Color(seed);
                    colorSeedNotifier.value = _seed;
                  }
                  final lang = map['app_lang'];
                  if (lang is String) _currentLang = lang;
                  textScaleNotifier.value = _textScale;
                  await _persist();
                  setState(() {});
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Settings imported')));
                }
                Navigator.pop(ctx);
              } catch (_) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Invalid JSON'),
                      backgroundColor: Colors.red));
                }
              }
            },
            child: const Text('Import'),
          )
        ],
      ),
    );
  }

  Future<void> _clearCaches() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    themeModeNotifier.value = ThemeMode.dark;
    colorSeedNotifier.value = Colors.deepPurple;
    textScaleNotifier.value = 1.0;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All settings cleared')),
      );
    }
    _load();
  }

  Future<void> _showSystemInfo() async {
    String systemInfoText = 'System Information\n' + '=' * 50 + '\n';

    try {
      // App information - basic info without package_info_plus
      systemInfoText += 'App Information:\n';
      systemInfoText += 'Name: LitterBox\n';
      systemInfoText += 'Version: 1.0.0\n';
      systemInfoText += 'Built with Flutter\n\n';

      // Platform information
      systemInfoText += 'Platform Information:\n';
      systemInfoText += 'Operating System: ${Platform.operatingSystem}\n';
      systemInfoText +=
          'Operating System Version: ${Platform.operatingSystemVersion}\n';
      systemInfoText += 'Locale: ${Platform.localeName}\n';
      systemInfoText +=
          'Number of Processors: ${Platform.numberOfProcessors}\n';
      systemInfoText += 'Path Separator: ${Platform.pathSeparator}\n';
      systemInfoText += 'Executable: ${Platform.resolvedExecutable}\n';
      systemInfoText += 'Script: ${Platform.script}\n\n';

      // Environment variables (selective)
      systemInfoText += 'Environment:\n';
      final env = Platform.environment;
      for (final key in ['HOME', 'USER', 'PATH', 'ANDROID_HOME', 'JAVA_HOME']) {
        if (env.containsKey(key)) {
          systemInfoText += '$key: ${env[key]}\n';
        }
      }
      systemInfoText += '\n';

      // Flutter/Dart version info
      final dartVersion = Platform.version;
      systemInfoText += 'Dart Information:\n';
      systemInfoText += 'Dart Version: $dartVersion\n\n';

      // Settings summary
      systemInfoText += 'App Settings Summary:\n';
      systemInfoText += 'Theme Mode: ${_themeMode.name}\n';
      systemInfoText += 'Text Scale: ${_textScale.toStringAsFixed(2)}\n';
      systemInfoText += 'Developer Mode: $_developer\n';
      systemInfoText += 'Notifications: $_notifications\n';
      systemInfoText += 'Verbose Logging: $_verboseLogging\n';
    } catch (e) {
      systemInfoText += 'Error getting system information: $e\n';
    }

    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('System Information'),
          content: Container(
            width: 400,
            height: 500,
            child: SingleChildScrollView(
              child: SelectableText(
                systemInfoText,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: systemInfoText));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('System info copied to clipboard')),
                );
              },
              child: const Text('Copy'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _performDiagnostics() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Running diagnostics...'),
          ],
        ),
      ),
    );

    await Future.delayed(const Duration(seconds: 2));

    final diagnosticResults = StringBuffer();
    diagnosticResults.writeln('LitterBox Diagnostic Report');
    diagnosticResults.writeln('Generated: ${DateTime.now()}');
    diagnosticResults.writeln('=' * 50);

    // Check SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      diagnosticResults
          .writeln('✓ SharedPreferences: ${keys.length} keys stored');
    } catch (e) {
      diagnosticResults.writeln('✗ SharedPreferences error: $e');
    }

    // Check network connectivity (basic)
    try {
      final socket =
          await Socket.connect('8.8.8.8', 53, timeout: Duration(seconds: 5));
      socket.destroy();
      diagnosticResults.writeln('✓ Network connectivity: OK');
    } catch (e) {
      diagnosticResults.writeln('✗ Network connectivity: Failed ($e)');
    }

    // Check available storage
    try {
      final tempDir = Directory.systemTemp;
      final exists = await tempDir.exists();
      diagnosticResults.writeln(
          '✓ System temp directory access: ${exists ? 'OK' : 'Failed'}');
    } catch (e) {
      diagnosticResults.writeln('✗ Storage access error: $e');
    }

    // Check platform capabilities
    diagnosticResults.writeln('\nPlatform Capabilities:');
    diagnosticResults.writeln('- OS: ${Platform.operatingSystem}');
    diagnosticResults.writeln('- Version: ${Platform.operatingSystemVersion}');
    diagnosticResults.writeln('- Processors: ${Platform.numberOfProcessors}');
    diagnosticResults.writeln('- Locale: ${Platform.localeName}');

    // Check app settings integrity
    diagnosticResults.writeln('\nSettings Integrity:');
    diagnosticResults.writeln('- Theme configured: ✓');
    diagnosticResults.writeln(
        '- Text scale valid: ${_textScale > 0 && _textScale <= 2 ? '✓' : '✗'}');
    diagnosticResults
        .writeln('- Language set: ${_currentLang.isNotEmpty ? '✓' : '✗'}');

    Navigator.pop(context); // Close progress dialog

    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Diagnostic Results'),
          content: Container(
            width: 400,
            height: 400,
            child: SingleChildScrollView(
              child: SelectableText(
                diagnosticResults.toString(),
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(
                    ClipboardData(text: diagnosticResults.toString()));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Diagnostic report copied to clipboard')),
                );
              },
              child: const Text('Copy Report'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _createFullBackup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final backup = <String, dynamic>{};

      for (final key in keys) {
        backup[key] = prefs.get(key);
      }

      final backupData = {
        'timestamp': DateTime.now().toIso8601String(),
        'app_version': '1.0.0',
        'platform': Platform.operatingSystem,
        'settings': backup,
      };

      final jsonString = const JsonEncoder.withIndent('  ').convert(backupData);

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Full Backup Created'),
          content: Container(
            width: 400,
            height: 300,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Copy this backup data to restore later:'),
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      jsonString,
                      style: const TextStyle(
                          fontSize: 10, fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: jsonString));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Backup copied to clipboard')),
                );
              },
              child: const Text('Copy'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Backup failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _restoreFromBackup() async {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore from Backup'),
        content: Container(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Paste your backup data:'),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                maxLines: 10,
                decoration: const InputDecoration(
                  hintText: 'Paste backup JSON here...',
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                final backupData =
                    jsonDecode(controller.text) as Map<String, dynamic>;
                final settings = backupData['settings'] as Map<String, dynamic>;

                final prefs = await SharedPreferences.getInstance();
                await prefs.clear();

                for (final entry in settings.entries) {
                  final value = entry.value;
                  if (value is String) {
                    await prefs.setString(entry.key, value);
                  } else if (value is int) {
                    await prefs.setInt(entry.key, value);
                  } else if (value is double) {
                    await prefs.setDouble(entry.key, value);
                  } else if (value is bool) {
                    await prefs.setBool(entry.key, value);
                  } else if (value is List<String>) {
                    await prefs.setStringList(entry.key, value);
                  }
                }

                Navigator.pop(ctx);
                _load(); // Reload settings

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Settings restored successfully')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Restore failed: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Restore'),
          ),
        ],
      ),
    );
  }

  void _pickAuthMethod() {
    final options = {
      'biometric': 'Biometric (Fingerprint/Face)',
      'pin': 'PIN',
      'password': 'Password'
    };
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Authentication Method'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.entries
              .map((e) => RadioListTile<String>(
                    title: Text(e.value),
                    value: e.key,
                    groupValue: _authenticationMethod,
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _authenticationMethod = v);
                        _persist();
                        Navigator.pop(ctx);
                      }
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }

  void _pickSessionTimeout() {
    int temp = _sessionTimeout;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Session Timeout (minutes)'),
        content: StatefulBuilder(builder: (ctx, setSt) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Slider(
                value: temp.toDouble(),
                min: 5,
                max: 120,
                divisions: 23,
                label: '$temp min',
                onChanged: (v) => setSt(() => temp = v.round()),
              ),
              Text('$temp minutes')
            ],
          );
        }),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => _sessionTimeout = temp);
              _persist();
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _pickMaxConnections() {
    int temp = _maxConcurrentConnections;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Max Concurrent Connections'),
        content: StatefulBuilder(builder: (ctx, setSt) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Slider(
                value: temp.toDouble(),
                min: 1,
                max: 20,
                divisions: 19,
                label: '$temp',
                onChanged: (v) => setSt(() => temp = v.round()),
              ),
              Text('$temp connections')
            ],
          );
        }),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => _maxConcurrentConnections = temp);
              _persist();
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _pickNetworkTimeout() {
    int temp = _networkTimeout;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Network Timeout (seconds)'),
        content: StatefulBuilder(builder: (ctx, setSt) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Slider(
                value: temp.toDouble(),
                min: 5,
                max: 120,
                divisions: 23,
                label: '${temp}s',
                onChanged: (v) => setSt(() => temp = v.round()),
              ),
              Text('$temp seconds')
            ],
          );
        }),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => _networkTimeout = temp);
              _persist();
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _pickPort(String type, int currentPort, Function(int) onChanged) {
    final controller = TextEditingController(text: currentPort.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$type Default Port'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Port Number',
            hintText: 'Enter port (1-65535)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final port = int.tryParse(controller.text);
              if (port != null && port > 0 && port <= 65535) {
                setState(() => onChanged(port));
                _persist();
                Navigator.pop(ctx);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Invalid port number'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _pickCompressionLevel() {
    final options = {'low': 'Low', 'medium': 'Medium', 'high': 'High'};
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Compression Level'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.entries
              .map((e) => RadioListTile<String>(
                    title: Text(e.value),
                    value: e.key,
                    groupValue: _compressionLevel,
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _compressionLevel = v);
                        _persist();
                        Navigator.pop(ctx);
                      }
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }

  void _pickDefaultShell() {
    final shells = [
      '/bin/bash',
      '/bin/sh',
      '/bin/zsh',
      '/bin/fish',
      '/bin/csh'
    ];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Default Shell'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: shells
              .map((shell) => RadioListTile<String>(
                    title: Text(shell),
                    value: shell,
                    groupValue: _defaultShell,
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _defaultShell = v);
                        _persist();
                        Navigator.pop(ctx);
                      }
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }

  void _pickTerminalEmulator() {
    final emulators = ['xterm', 'xterm-256color', 'vt100', 'vt220', 'screen'];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Terminal Emulator'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: emulators
              .map((emu) => RadioListTile<String>(
                    title: Text(emu),
                    value: emu,
                    groupValue: _terminalEmulator,
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _terminalEmulator = v);
                        _persist();
                        Navigator.pop(ctx);
                      }
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }

  void _pickFontFamily() {
    final fonts = ['Courier', 'Monaco', 'Consolas', 'Ubuntu Mono', 'Fira Code'];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Font Family'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: fonts
              .map((font) => RadioListTile<String>(
                    title: Text(font, style: TextStyle(fontFamily: font)),
                    value: font,
                    groupValue: _fontFamily,
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _fontFamily = v);
                        _persist();
                        Navigator.pop(ctx);
                      }
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }

  void _pickFontSize() {
    double temp = _fontSize;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Font Size'),
        content: StatefulBuilder(builder: (ctx, setSt) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Slider(
                value: temp,
                min: 8.0,
                max: 24.0,
                divisions: 16,
                label: '${temp.toStringAsFixed(1)} pt',
                onChanged: (v) => setSt(() => temp = v),
              ),
              Text('${temp.toStringAsFixed(1)} pt')
            ],
          );
        }),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => _fontSize = temp);
              _persist();
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _pickScrollbackLines() {
    int temp = _scrollbackLines;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Scrollback Lines'),
        content: StatefulBuilder(builder: (ctx, setSt) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Slider(
                value: temp.toDouble(),
                min: 100,
                max: 10000,
                divisions: 99,
                label: '$temp',
                onChanged: (v) => setSt(() => temp = (v / 100).round() * 100),
              ),
              Text('$temp lines')
            ],
          );
        }),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => _scrollbackLines = temp);
              _persist();
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _pickBackupFrequency() {
    int temp = _backupFrequency;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Backup Frequency (days)'),
        content: StatefulBuilder(builder: (ctx, setSt) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Slider(
                value: temp.toDouble(),
                min: 1,
                max: 30,
                divisions: 29,
                label: '$temp',
                onChanged: (v) => setSt(() => temp = v.round()),
              ),
              Text('Every $temp day(s)')
            ],
          );
        }),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => _backupFrequency = temp);
              _persist();
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _sectionHeader('Appearance'),
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode),
            title: const Text('Dark Mode'),
            value: _themeMode == ThemeMode.dark,
            onChanged: (v) async {
              setState(() => _themeMode = v ? ThemeMode.dark : ThemeMode.light);
              themeModeNotifier.value = _themeMode;
              await _persist();
            },
          ),
          ListTile(
            leading: const Icon(Icons.palette),
            title: const Text('Accent Color'),
            subtitle: Text('#${_seed.value.toRadixString(16).padLeft(8, '0')}'),
            trailing: CircleAvatar(backgroundColor: _seed),
            onTap: _chooseColorSeed,
          ),
          ListTile(
            leading: const Icon(Icons.format_size),
            title: const Text('Text Size'),
            subtitle: Text('Scale: ${_textScale.toStringAsFixed(2)}x'),
            onTap: () {
              showModalBottomSheet(
                context: context,
                builder: (ctx) => StatefulBuilder(
                  builder: (ctx, setSheet) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Adjust Text Scale',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        Slider(
                          value: _textScale,
                          min: .8,
                          max: 1.6,
                          divisions: 8,
                          label: _textScale.toStringAsFixed(2),
                          onChanged: (v) {
                            setSheet(() => _textScale = v);
                            textScaleNotifier.value = v;
                          },
                          onChangeEnd: (_) => _persist(),
                        )
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const Divider(),
          _sectionHeader('General'),
          SwitchListTile(
            secondary: const Icon(Icons.notifications),
            title: const Text('Notifications'),
            value: _notifications,
            onChanged: _toggleNotifications,
          ),
          ListTile(
            leading: const Icon(Icons.play_circle_outline),
            title: const Text('Startup Page'),
            subtitle: Text(_startupPageLabel(_startupPage)),
            onTap: _pickStartupPage,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.usb),
            title: const Text('Auto-connect last ADB device'),
            value: _autoConnectAdb,
            onChanged: (v) {
              setState(() => _autoConnectAdb = v);
              _persist();
            },
          ),
          ListTile(
            leading: const Icon(Icons.language),
            title: const Text('Language'),
            subtitle: Text(_currentLang),
            onTap: () => _showLanguageDialog(context),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            onTap: () => _showAboutDialog(context),
          ),
          const Divider(),
          _sectionHeader('Behavior'),
          SwitchListTile(
            secondary: const Icon(Icons.tune),
            title: const Text('Verbose Logging'),
            value: _verboseLogging,
            onChanged: (v) {
              setState(() => _verboseLogging = v);
              _persist();
            },
          ),
          ListTile(
            leading: const Icon(Icons.storage),
            title: const Text('Log Retention'),
            subtitle: Text('$_logRetentionDays day(s)'),
            onTap: () => _pickLogRetention(),
          ),
          ListTile(
            leading: const Icon(Icons.format_line_spacing),
            title: const Text('Console Buffer Lines'),
            subtitle: Text('$_consoleBufferLines'),
            onTap: () => _pickConsoleBuffer(),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.help_outline),
            title: const Text('Confirm before clearing Logcat'),
            value: _confirmClearLogcat,
            onChanged: (v) {
              setState(() => _confirmClearLogcat = v);
              _persist();
            },
          ),
          ListTile(
            leading: const Icon(Icons.fit_screen),
            title: const Text('VNC Default Scaling'),
            subtitle: Text(_vncDefaultScaling),
            onTap: _pickVncScaling,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.file_upload_outlined),
            title: const Text('ADB Progress Notifications'),
            value: _adbProgressNotifications,
            onChanged: (v) {
              setState(() => _adbProgressNotifications = v);
              _persist();
            },
          ),
          const Divider(),
          _sectionHeader('Data & Backup'),
          ListTile(
            leading: const Icon(Icons.file_upload),
            title: const Text('Export Settings'),
            onTap: _exportSettings,
          ),
          ListTile(
            leading: const Icon(Icons.file_download),
            title: const Text('Import Settings'),
            onTap: _importSettings,
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Reset / Clear Settings'),
            onTap: _clearCaches,
          ),
          const Divider(),
          _sectionHeader('Security'),
          SwitchListTile(
            secondary: const Icon(Icons.security),
            title: const Text('Require Authentication'),
            subtitle: const Text('Enable app lock'),
            value: _requireAuthentication,
            onChanged: (v) {
              setState(() => _requireAuthentication = v);
              _persist();
            },
          ),
          if (_requireAuthentication)
            ListTile(
              leading: const Icon(Icons.fingerprint),
              title: const Text('Authentication Method'),
              subtitle: Text(_authenticationMethod.toUpperCase()),
              onTap: _pickAuthMethod,
            ),
          if (_requireAuthentication)
            ListTile(
              leading: const Icon(Icons.timer),
              title: const Text('Session Timeout'),
              subtitle: Text('$_sessionTimeout minutes'),
              onTap: _pickSessionTimeout,
            ),
          SwitchListTile(
            secondary: const Icon(Icons.visibility_off),
            title: const Text('Hide from Recent Apps'),
            value: _hideRecentApps,
            onChanged: (v) {
              setState(() => _hideRecentApps = v);
              _persist();
            },
          ),
          const Divider(),
          _sectionHeader('Performance'),
          SwitchListTile(
            secondary: const Icon(Icons.speed),
            title: const Text('Hardware Acceleration'),
            value: _enableHardwareAcceleration,
            onChanged: (v) {
              setState(() => _enableHardwareAcceleration = v);
              _persist();
            },
          ),
          ListTile(
            leading: const Icon(Icons.timeline),
            title: const Text('Max Concurrent Connections'),
            subtitle: Text('$_maxConcurrentConnections'),
            onTap: _pickMaxConnections,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.pool),
            title: const Text('Connection Pooling'),
            subtitle: const Text('Reuse connections for better performance'),
            value: _enableConnectionPooling,
            onChanged: (v) {
              setState(() => _enableConnectionPooling = v);
              _persist();
            },
          ),
          ListTile(
            leading: const Icon(Icons.network_check),
            title: const Text('Network Timeout'),
            subtitle: Text('$_networkTimeout seconds'),
            onTap: _pickNetworkTimeout,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.battery_saver),
            title: const Text('Low Power Mode'),
            subtitle: const Text('Reduce background activity'),
            value: _enableLowPowerMode,
            onChanged: (v) {
              setState(() => _enableLowPowerMode = v);
              _persist();
            },
          ),
          const Divider(),
          _sectionHeader('Connection Defaults'),
          ListTile(
            leading: const Icon(Icons.terminal),
            title: const Text('SSH Port'),
            subtitle: Text('$_defaultSSHPort'),
            onTap: () =>
                _pickPort('SSH', _defaultSSHPort, (v) => _defaultSSHPort = v),
          ),
          ListTile(
            leading: const Icon(Icons.desktop_windows),
            title: const Text('VNC Port'),
            subtitle: Text('$_defaultVNCPort'),
            onTap: () =>
                _pickPort('VNC', _defaultVNCPort, (v) => _defaultVNCPort = v),
          ),
          ListTile(
            leading: const Icon(Icons.computer),
            title: const Text('RDP Port'),
            subtitle: Text('$_defaultRDPPort'),
            onTap: () =>
                _pickPort('RDP', _defaultRDPPort, (v) => _defaultRDPPort = v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.compress),
            title: const Text('Enable Compression'),
            value: _enableCompression,
            onChanged: (v) {
              setState(() => _enableCompression = v);
              _persist();
            },
          ),
          if (_enableCompression)
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Compression Level'),
              subtitle: Text(_compressionLevel.toUpperCase()),
              onTap: _pickCompressionLevel,
            ),
          const Divider(),
          _sectionHeader('Terminal'),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('Default Shell'),
            subtitle: Text(_defaultShell),
            onTap: _pickDefaultShell,
          ),
          ListTile(
            leading: const Icon(Icons.text_fields),
            title: const Text('Terminal Emulator'),
            subtitle: Text(_terminalEmulator),
            onTap: _pickTerminalEmulator,
          ),
          ListTile(
            leading: const Icon(Icons.font_download),
            title: const Text('Font Family'),
            subtitle: Text(_fontFamily),
            onTap: _pickFontFamily,
          ),
          ListTile(
            leading: const Icon(Icons.format_size),
            title: const Text('Font Size'),
            subtitle: Text('${_fontSize.toStringAsFixed(1)} pt'),
            onTap: _pickFontSize,
          ),
          ListTile(
            leading: const Icon(Icons.view_list),
            title: const Text('Scrollback Lines'),
            subtitle: Text('$_scrollbackLines'),
            onTap: _pickScrollbackLines,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.translate),
            title: const Text('UTF-8 Encoding'),
            value: _enableUTF8,
            onChanged: (v) {
              setState(() => _enableUTF8 = v);
              _persist();
            },
          ),
          const Divider(),
          _sectionHeader('Backup & Restore'),
          SwitchListTile(
            secondary: const Icon(Icons.backup),
            title: const Text('Auto Backup'),
            subtitle: const Text('Automatically backup settings'),
            value: _autoBackup,
            onChanged: (v) {
              setState(() => _autoBackup = v);
              _persist();
            },
          ),
          if (_autoBackup)
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Backup Frequency'),
              subtitle: Text('Every $_backupFrequency days'),
              onTap: _pickBackupFrequency,
            ),
          ListTile(
            leading: const Icon(Icons.save),
            title: const Text('Create Full Backup'),
            subtitle: const Text('Export all settings and data'),
            onTap: _createFullBackup,
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('Restore from Backup'),
            subtitle: const Text('Import settings from backup'),
            onTap: _restoreFromBackup,
          ),
          const Divider(),
          _sectionHeader('System'),
          ListTile(
            leading: const Icon(Icons.info),
            title: const Text('System Information'),
            subtitle: const Text('View device and app details'),
            onTap: _showSystemInfo,
          ),
          ListTile(
            leading: const Icon(Icons.bug_report),
            title: const Text('Run Diagnostics'),
            subtitle: const Text('Check system health'),
            onTap: _performDiagnostics,
          ),
          const Divider(),
          _sectionHeader('Developer'),
          SwitchListTile(
            secondary: const Icon(Icons.code),
            title: const Text('Developer Mode'),
            value: _developer,
            onChanged: (v) async {
              setState(() => _developer = v);
              await _persist();
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.analytics_outlined),
            title: const Text('Telemetry (anonymous metrics)'),
            value: _telemetry,
            onChanged: (v) {
              setState(() => _telemetry = v);
              _persist();
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.report_problem_outlined),
            title: const Text('Crash Reports'),
            value: _crashReports,
            onChanged: (v) {
              setState(() => _crashReports = v);
              _persist();
            },
          ),
          if (_developer) ...[
            ListTile(
              leading: const Icon(Icons.bug_report),
              title: const Text('Dump SharedPreferences'),
              onTap: () async {
                final p = await SharedPreferences.getInstance();
                final map =
                    p.getKeys().fold<Map<String, dynamic>>({}, (acc, k) {
                  acc[k] = p.get(k);
                  return acc;
                });
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Prefs Dump'),
                    content: SizedBox(
                      width: 400,
                      child: SingleChildScrollView(
                        child: SelectableText(
                          const JsonEncoder.withIndent('  ').convert(map),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Close'))
                    ],
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(title.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 1.1,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              )),
    );
  }

  String _startupPageLabel(String key) {
    switch (key) {
      case 'android':
        return 'Android Manager';
      case 'settings':
        return 'Settings';
      case 'home':
      default:
        return 'Home';
    }
  }

  void _pickStartupPage() {
    showModalBottomSheet(
        context: context,
        builder: (ctx) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                    title: Text('Select Startup Page',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                for (final opt in ['home', 'android', 'settings'])
                  RadioListTile<String>(
                    title: Text(_startupPageLabel(opt)),
                    value: opt,
                    groupValue: _startupPage,
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _startupPage = v);
                        _persist();
                        Navigator.pop(ctx);
                      }
                    },
                  ),
              ],
            ),
          );
        });
  }

  void _pickLogRetention() {
    int temp = _logRetentionDays;
    showDialog(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Log Retention (days)'),
            content: StatefulBuilder(builder: (ctx, setSt) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Slider(
                    value: temp.toDouble(),
                    min: 1,
                    max: 30,
                    divisions: 29,
                    label: '$temp',
                    onChanged: (v) {
                      setSt(() => temp = v.round());
                    },
                  ),
                  Text('$temp day(s)')
                ],
              );
            }),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
              ElevatedButton(
                  onPressed: () {
                    setState(() => _logRetentionDays = temp);
                    _persist();
                    Navigator.pop(ctx);
                  },
                  child: const Text('Save')),
            ],
          );
        });
  }

  void _pickConsoleBuffer() {
    int temp = _consoleBufferLines;
    showDialog(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Console Buffer Lines'),
            content: StatefulBuilder(builder: (ctx, setSt) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Slider(
                    value: temp.toDouble(),
                    min: 100,
                    max: 5000,
                    divisions: 49,
                    label: '$temp',
                    onChanged: (v) {
                      setSt(() => temp = (v / 100).round() * 100);
                    },
                  ),
                  Text('$temp lines')
                ],
              );
            }),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
              ElevatedButton(
                  onPressed: () {
                    setState(() => _consoleBufferLines = temp);
                    _persist();
                    Navigator.pop(ctx);
                  },
                  child: const Text('Save')),
            ],
          );
        });
  }

  void _pickVncScaling() {
    final options = {'fit': 'Fit', 'original': 'Original', 'fill': 'Fill'};
    showDialog(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('VNC Default Scaling'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: options.entries
                  .map((e) => RadioListTile<String>(
                        title: Text(e.value),
                        value: e.key,
                        groupValue: _vncDefaultScaling,
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _vncDefaultScaling = v);
                            _persist();
                            Navigator.pop(ctx);
                          }
                        },
                      ))
                  .toList(),
            ),
          );
        });
  }
}
