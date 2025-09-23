
import 'package:flutter/material.dart';
import '../adb_client.dart';
import '../models/app_info.dart';
import '../services/shared_adb_manager.dart';
import '../main.dart';

class AppsScreen extends StatefulWidget {
  const AppsScreen({super.key});

  @override
  State<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends State<AppsScreen> {
  // Favorites state
  final Set<String> _favoritePackages = {};
  // Batch selection state
  final Set<String> _selectedPackages = {};
  bool _batchMode = false;
  late ADBClientManager _adb;
  
  // App management state
  List<AppInfo> _installedApps = [];
  List<AppInfo> _systemApps = [];
  bool _loadingApps = false;
  bool _showLoadingOverlay = false;
  String _appSearchQuery = '';
  String _selectedAppFilter = 'All'; // All, User, System, Enabled, Disabled
  
  // Output buffer for debug information
  final List<String> _outputBuffer = [];
  
  @override
  void initState() {
    super.initState();
    
    // Use the shared ADB connection
    _adb = SharedADBManager.instance.getSharedClient();
    _addOutput('📱 Using shared ADB connection');
    
    // Check connection status and load apps if connected
    if (_adb.currentState == ADBConnectionState.connected) {
      _addOutput('✅ ADB already connected to ${_adb.connectedDeviceId}');
      _addOutput('🔄 Auto-loading apps...');
      _loadInstalledApps();
    } else {
      _addOutput('❌ ADB not connected (state: ${_adb.currentState})');
    }
    
    // Listen to output
    _adb.output.listen((line) {
      _addOutput(line);
    });
  }

  void _addOutput(String message) {
    setState(() {
      if (_outputBuffer.length > 100) {
        _outputBuffer.removeRange(0, 50);
      }
      _outputBuffer.add('${DateTime.now().toString().substring(11, 19)} $message');
    });
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<String?> _executeShellCommand(String command) async {
    if (_adb.currentState != ADBConnectionState.connected) {
      _addOutput('❌ Cannot execute command: Device not connected');
      return null;
    }

    try {
      _addOutput('🔍 Executing: $command');
      // Use the exact same approach as adb_screen_refactored.dart
      if (_adb.backend != null && _adb.connectedDeviceId.isNotEmpty) {
        _addOutput('📱 Device: ${_adb.connectedDeviceId}');
        final result = await _adb.backend!.shell(_adb.connectedDeviceId, command);
        _addOutput('✅ Command result: ${result.length} characters');
        if (result.length > 100) {
          _addOutput('📋 Preview: ${result.substring(0, 100)}...');
        } else {
          _addOutput('📋 Full result: $result');
        }
        return result;
      } else {
        _addOutput('❌ No backend (${_adb.backend != null ? "available" : "null"}) or device ID (${_adb.connectedDeviceId})');
        return null;
      }
    } catch (e) {
      _addOutput('❌ Error executing command: $e');
      return null;
    }
  }

  Future<void> _loadInstalledApps() async {
    if (_adb.currentState != ADBConnectionState.connected) {
      _addOutput('❌ Cannot load apps: Device not connected');
      return;
    }

    _addOutput('🔄 Starting to load apps...');
    setState(() => _loadingApps = true);

    try {
      final allApps = <AppInfo>[];
      
      _addOutput('📦 Getting user packages...');
      // Get list of user packages (3rd party) - same as Android screen
      final userPackagesOutput = await _executeShellCommand('pm list packages -3');
      if (userPackagesOutput != null) {
        _addOutput('📝 User packages output: ${userPackagesOutput.length} chars');
        for (final line in userPackagesOutput.split('\n')) {
          if (line.startsWith('package:')) {
            final packageName = line.substring(8).trim();
            if (packageName.isNotEmpty) {
              allApps.add(_createAppInfoFromPackageName(packageName, false));
            }
          }
        }
        _addOutput('✅ Found ${allApps.length} user packages');
      } else {
        _addOutput('❌ No user packages output received');
      }

      _addOutput('⚙️ Getting system packages...');
      // Get list of system packages (limited to first 30 for performance) - same as Android screen
      final systemPackagesOutput = await _executeShellCommand('pm list packages -s');
      if (systemPackagesOutput != null) {
        _addOutput('📝 System packages output: ${systemPackagesOutput.length} chars');
        final systemLines = systemPackagesOutput.split('\n').where((line) => line.startsWith('package:')).take(30);
        for (final line in systemLines) {
          final packageName = line.substring(8).trim();
          if (packageName.isNotEmpty) {
            allApps.add(_createAppInfoFromPackageName(packageName, true));
          }
        }
        _addOutput('✅ Found ${allApps.where((app) => app.isSystemApp).length} system packages');
      } else {
        _addOutput('❌ No system packages output received');
      }

      // Separate user and system apps - same as Android screen
      setState(() {
        _installedApps = allApps.where((app) => !app.isSystemApp).toList();
        _systemApps = allApps.where((app) => app.isSystemApp).toList();
        _loadingApps = false;
      });
      
      _addOutput('✅ Loaded ${_installedApps.length + _systemApps.length} apps (${_installedApps.length} user, ${_systemApps.length} system)');
    } catch (e) {
      _addOutput('❌ Error loading apps: $e');
      setState(() => _loadingApps = false);
    }
  }

  AppInfo _createAppInfoFromPackageName(String packageName, bool isSystemApp) {
    // Create basic app info - detailed info loaded on-demand (same as Android screen)
    return AppInfo(
      packageName: packageName,
      label: packageName.split('.').last, // Use last part as label
      isSystemApp: isSystemApp,
      isEnabled: true, // Assume enabled by default
      version: 'Unknown',
      versionCode: '0',
      apkPath: '',
      size: 0,
    );
  }

  List<AppInfo> get _filteredApps {
    List<AppInfo> apps = [];
    switch (_selectedAppFilter) {
      case 'User':
        apps = _installedApps;
        break;
      case 'System':
        apps = _systemApps;
        break;
      case 'Favorites':
        apps = [..._installedApps, ..._systemApps].where((a) => _favoritePackages.contains(a.packageName)).toList();
        break;
      case 'All':
      default:
        apps = [..._installedApps, ..._systemApps];
        break;
    }
    if (_appSearchQuery.isNotEmpty) {
      apps = apps.where((app) =>
        app.packageName.toLowerCase().contains(_appSearchQuery.toLowerCase()) ||
        app.label.toLowerCase().contains(_appSearchQuery.toLowerCase())
      ).toList();
    }
    return apps;
  }

  Future<void> _uninstallApp(AppInfo app) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Uninstall ${app.label}'),
        content: Text('Are you sure you want to uninstall ${app.packageName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Uninstall'),
          ),
        ],
      ),
    );

    if (result == true) {
      setState(() => _showLoadingOverlay = true);
      _addOutput('🗑️ Uninstalling ${app.packageName}...');
      final uninstallResult = await _executeShellCommand('pm uninstall ${app.packageName}');
      setState(() => _showLoadingOverlay = false);
      if (uninstallResult != null && uninstallResult.contains('Success')) {
        _addOutput('✅ Successfully uninstalled ${app.packageName}');
        _loadInstalledApps(); // Reload apps list
      } else {
        _addOutput('❌ Failed to uninstall ${app.packageName}: $uninstallResult');
        _showErrorDialog('Uninstall Failed', uninstallResult ?? 'Unknown error');
      }
    }
  }

  Future<void> _launchApp(AppInfo app) async {
    _addOutput('🚀 Launching ${app.packageName}...');
    final launchResult = await _executeShellCommand('monkey -p ${app.packageName} -c android.intent.category.LAUNCHER 1');
    if (launchResult != null) {
      _addOutput('📱 Launch result: $launchResult');
    }
  }

  Future<void> _forceStopApp(AppInfo app) async {
    _addOutput('⏹️ Force stopping ${app.packageName}...');
    await _executeShellCommand('am force-stop ${app.packageName}');
    _addOutput('⏹️ Force stop completed');
  }

  Future<void> _clearAppData(AppInfo app) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Clear ${app.label} Data'),
        content: Text('This will clear all data for ${app.packageName}. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Clear Data'),
          ),
        ],
      ),
    );

    if (result == true) {
      setState(() => _showLoadingOverlay = true);
      _addOutput('🧹 Clearing data for ${app.packageName}...');
      final clearResult = await _executeShellCommand('pm clear ${app.packageName}');
      setState(() => _showLoadingOverlay = false);
      if (clearResult != null && clearResult.contains('Success')) {
        _addOutput('✅ Successfully cleared data for ${app.packageName}');
      } else {
        _addOutput('❌ Failed to clear data for ${app.packageName}: $clearResult');
        _showErrorDialog('Clear Data Failed', clearResult ?? 'Unknown error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: const Text('Apps Manager'),
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                icon: Icon(_batchMode ? Icons.check_box : Icons.check_box_outline_blank),
                tooltip: _batchMode ? 'Exit Batch Mode' : 'Batch Select',
                onPressed: () {
                  setState(() {
                    _batchMode = !_batchMode;
                    if (!_batchMode) _selectedPackages.clear();
                  });
                },
              ),
              // ...existing code...
              IconButton(
                icon: Icon(themeModeNotifier.value == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode),
                tooltip: 'Toggle Theme',
                onPressed: () {
                  themeModeNotifier.value = themeModeNotifier.value == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
                },
              ),
              PopupMenuButton<double>(
                icon: const Icon(Icons.format_size),
                tooltip: 'Text Size',
                onSelected: (v) {
                  textScaleNotifier.value = v;
                },
                itemBuilder: (context) => [
                  for (final scale in [.8, 1.0, 1.2, 1.4, 1.6])
                    PopupMenuItem(
                      value: scale,
                      child: Text('${(scale * 100).toInt()}%', style: TextStyle(fontSize: 14 * scale)),
                    ),
                ],
              ),
              Container(
                margin: const EdgeInsets.only(right: 16),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _adb.currentState == ADBConnectionState.connected 
                      ? Colors.green 
                      : Colors.red,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _adb.currentState == ADBConnectionState.connected 
                      ? 'Connected' 
                      : 'Disconnected',
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              // Control Panel
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Load and filter controls
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: _adb.currentState == ADBConnectionState.connected && !_loadingApps
                              ? _loadInstalledApps
                              : null,
                          icon: _loadingApps 
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.refresh),
                          label: Text(_loadingApps ? 'Loading...' : 'Load Apps'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _selectedAppFilter,
                            decoration: const InputDecoration(
                              labelText: 'Filter',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              border: OutlineInputBorder(),
                            ),
              items: ['All', 'User', 'System', 'Favorites']
                .map((filter) => DropdownMenuItem(value: filter, child: Text(filter)))
                .toList(),
                            onChanged: (value) {
                              setState(() {
                                _selectedAppFilter = value ?? 'All';
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Search field
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Search apps...',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (value) {
                        setState(() {
                          _appSearchQuery = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
              
              // Batch operation controls
              if (_batchMode)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _selectedPackages.isNotEmpty ? () => _batchUninstall() : null,
                        icon: const Icon(Icons.delete),
                        label: Text('Uninstall (${_selectedPackages.length})'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _selectedPackages.isNotEmpty ? () => _batchClearData() : null,
                        icon: const Icon(Icons.cleaning_services),
                        label: Text('Clear Data'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _selectedPackages.isNotEmpty ? () => _batchEnableDisable() : null,
                        icon: const Icon(Icons.toggle_on),
                        label: Text('Toggle Enable'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                      ),
                    ],
                  ),
                ),
              // Apps List
              Expanded(
                flex: 2,
                child: _buildAppsList(),
              ),
              
              // Debug Output (collapsible)
              ExpansionTile(
                title: Text('Debug Output (${_outputBuffer.length} lines)'),
                leading: const Icon(Icons.terminal),
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          setState(() => _outputBuffer.clear());
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Clear Output'),
                      ),
                    ],
                  ),
                  Container(
                    height: 150,
                    padding: const EdgeInsets.all(8),
                    child: ListView.builder(
                      itemCount: _outputBuffer.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          child: Text(
                            _outputBuffer[index],
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_showLoadingOverlay)
          Container(
            color: Colors.black.withOpacity(0.4),
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          ),
      ],
    );
  }

  Widget _buildAppsList() {
    final apps = _filteredApps;
    
    if (_loadingApps) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading apps...'),
          ],
        ),
      );
    }

    if (apps.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.apps, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _adb.currentState == ADBConnectionState.connected
                  ? 'No apps found. Tap "Load Apps" to refresh.'
                  : 'Connect to a device first.',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: apps.length,
      itemBuilder: (context, index) {
        final app = apps[index];
        final selected = _selectedPackages.contains(app.packageName);
        final isFavorite = _favoritePackages.contains(app.packageName);
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: ListTile(
            leading: _batchMode
                ? Checkbox(
                    value: selected,
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selectedPackages.add(app.packageName);
                        } else {
                          _selectedPackages.remove(app.packageName);
                        }
                      });
                    },
                  )
                : CircleAvatar(
                    backgroundColor: app.isSystemApp ? Colors.orange : Colors.blue,
                    child: Icon(
                      app.isSystemApp ? Icons.settings : Icons.apps,
                      color: Colors.white,
                    ),
                  ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    app.label,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: Icon(isFavorite ? Icons.star : Icons.star_border, color: isFavorite ? Colors.amber : Colors.grey),
                  tooltip: isFavorite ? 'Unpin from favorites' : 'Pin to favorites',
                  onPressed: () {
                    setState(() {
                      if (isFavorite) {
                        _favoritePackages.remove(app.packageName);
                      } else {
                        _favoritePackages.add(app.packageName);
                      }
                    });
                  },
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  app.packageName,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                Text(
                  app.isSystemApp ? 'System App' : 'User App',
                  style: TextStyle(
                    fontSize: 11,
                    color: app.isSystemApp ? Colors.orange : Colors.blue,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            isThreeLine: true,
            trailing: !_batchMode
                ? PopupMenuButton<String>(
                    onSelected: (action) async {
                      switch (action) {
                        case 'launch':
                          await _launchApp(app);
                          break;
                        case 'stop':
                          await _forceStopApp(app);
                          break;
                        case 'clear':
                          await _clearAppData(app);
                          break;
                        case 'uninstall':
                          if (!app.isSystemApp) {
                            await _uninstallApp(app);
                          }
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'launch', child: Text('🚀 Launch')),
                      const PopupMenuItem(value: 'stop', child: Text('⏹️ Force Stop')),
                      const PopupMenuItem(value: 'clear', child: Text('🧹 Clear Data')),
                      if (!app.isSystemApp)
                        const PopupMenuItem(value: 'uninstall', child: Text('🗑️ Uninstall')),
                    ],
                  )
                : null,
          ),
        );
      },
    );
  }

  // Batch operation methods
  Future<void> _batchUninstall() async {
    setState(() => _showLoadingOverlay = true);
    for (final pkg in _selectedPackages) {
      await _executeShellCommand('pm uninstall $pkg');
    }
    setState(() => _showLoadingOverlay = false);
    _loadInstalledApps();
    _selectedPackages.clear();
  }

  Future<void> _batchClearData() async {
    setState(() => _showLoadingOverlay = true);
    for (final pkg in _selectedPackages) {
      await _executeShellCommand('pm clear $pkg');
    }
    setState(() => _showLoadingOverlay = false);
    _selectedPackages.clear();
  }

  Future<void> _batchEnableDisable() async {
    setState(() => _showLoadingOverlay = true);
    for (final pkg in _selectedPackages) {
      await _executeShellCommand('pm enable $pkg');
      await _executeShellCommand('pm disable $pkg');
    }
    setState(() => _showLoadingOverlay = false);
    _selectedPackages.clear();
  }
}
