import 'package:flutter/material.dart';
import 'dart:convert';
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
