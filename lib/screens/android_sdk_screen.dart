import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/android_sdk_manager.dart';

/// Screen for managing Android SDK setup and emulators
class AndroidSDKScreen extends StatefulWidget {
  const AndroidSDKScreen({super.key});

  @override
  State<AndroidSDKScreen> createState() => _AndroidSDKScreenState();
}

class _AndroidSDKScreenState extends State<AndroidSDKScreen> with TickerProviderStateMixin {
  late final AndroidSDKManager _sdkManager;
  late final TabController _tabController;
  
  AndroidSDKStatus _currentStatus = AndroidSDKStatus.notInstalled;
  List<AndroidAVD> _avds = [];
  final List<String> _outputLines = [];
  final ScrollController _outputScrollController = ScrollController();
  
  // AVD Creation Form
  final TextEditingController _avdNameController = TextEditingController(text: 'flutter_avd');
  String _selectedApiLevel = '33';
  String _selectedABI = 'x86_64';
  final List<String> _apiLevels = ['30', '31', '32', '33', '34'];
  final List<String> _abis = ['x86_64', 'arm64-v8a'];
  
  StreamSubscription? _outputSub;
  StreamSubscription? _statusSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _sdkManager = AndroidSDKManager();
    _initializeSDK();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _outputSub?.cancel();
    _statusSub?.cancel();
    _avdNameController.dispose();
    _outputScrollController.dispose();
    super.dispose();
  }

  Future<void> _initializeSDK() async {
    _outputSub = _sdkManager.output.listen((line) {
      setState(() {
        _outputLines.add(line);
        if (_outputLines.length > 500) {
          _outputLines.removeAt(0);
        }
      });
      _scrollToBottom();
    });

    _statusSub = _sdkManager.status.listen((status) {
      setState(() {
        _currentStatus = status;
      });
      if (status == AndroidSDKStatus.ready) {
        _refreshAVDs();
      }
    });

    await _sdkManager.initialize();
    if (_sdkManager.isReady) {
      await _refreshAVDs();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_outputScrollController.hasClients) {
        _outputScrollController.animateTo(
          _outputScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _refreshAVDs() async {
    final avds = await _sdkManager.listAVDs();
    setState(() {
      _avds = avds;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Android SDK & Emulator Manager'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.settings), text: 'SDK Setup'),
            Tab(icon: Icon(Icons.smartphone), text: 'Emulators'),
            Tab(icon: Icon(Icons.terminal), text: 'Output'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSDKSetupTab(),
          _buildEmulatorsTab(),
          _buildOutputTab(),
        ],
      ),
    );
  }

  Widget _buildSDKSetupTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatusCard(),
          const SizedBox(height: 16),
          _buildSDKInfoCard(),
          const SizedBox(height: 16),
          _buildActionsCard(),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    IconData statusIcon;
    Color statusColor;
    String statusText;

    switch (_currentStatus) {
      case AndroidSDKStatus.notInstalled:
        statusIcon = Icons.error_outline;
        statusColor = Colors.orange;
        statusText = 'Android SDK not found';
        break;
      case AndroidSDKStatus.installing:
        statusIcon = Icons.downloading;
        statusColor = Colors.blue;
        statusText = 'Installing Android SDK...';
        break;
      case AndroidSDKStatus.ready:
        statusIcon = Icons.check_circle;
        statusColor = Colors.green;
        statusText = 'Android SDK ready';
        break;
      case AndroidSDKStatus.error:
        statusIcon = Icons.error;
        statusColor = Colors.red;
        statusText = 'SDK setup failed';
        break;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(statusIcon, color: statusColor, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SDK Status',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(statusText, style: TextStyle(color: statusColor)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSDKInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SDK Information',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _buildInfoRow('SDK Path', _sdkManager.sdkPath ?? 'Not set'),
            _buildInfoRow('Status', _getStatusDescription()),
            _buildInfoRow('Available AVDs', '${_avds.length}'),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  String _getStatusDescription() {
    switch (_currentStatus) {
      case AndroidSDKStatus.notInstalled:
        return 'SDK not found - setup required';
      case AndroidSDKStatus.installing:
        return 'Installing SDK components...';
      case AndroidSDKStatus.ready:
        return 'Ready for development';
      case AndroidSDKStatus.error:
        return 'Error occurred during setup';
    }
  }

  Widget _buildActionsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Actions',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _currentStatus == AndroidSDKStatus.installing
                      ? null
                      : () => _setupSDK(),
                  icon: Icon(_currentStatus == AndroidSDKStatus.installing
                      ? Icons.downloading
                      : Icons.download),
                  label: Text(_currentStatus == AndroidSDKStatus.installing
                      ? 'Setting up...'
                      : 'Setup Android SDK'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _sdkManager.isReady ? () => _refreshAVDs() : null,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                ),
                ElevatedButton.icon(
                  onPressed: () => _showSetupGuide(),
                  icon: const Icon(Icons.help),
                  label: const Text('Setup Guide'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmulatorsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCreateAVDCard(),
          const SizedBox(height: 16),
          _buildAVDListCard(),
        ],
      ),
    );
  }

  Widget _buildCreateAVDCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Create New AVD',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _avdNameController,
              decoration: const InputDecoration(
                labelText: 'AVD Name',
                border: OutlineInputBorder(),
                hintText: 'flutter_avd',
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedApiLevel,
                    decoration: const InputDecoration(
                      labelText: 'API Level',
                      border: OutlineInputBorder(),
                    ),
                    items: _apiLevels.map((level) {
                      return DropdownMenuItem(
                        value: level,
                        child: Text('API $level'),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedApiLevel = value!;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedABI,
                    decoration: const InputDecoration(
                      labelText: 'ABI',
                      border: OutlineInputBorder(),
                    ),
                    items: _abis.map((abi) {
                      return DropdownMenuItem(
                        value: abi,
                        child: Text(abi),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedABI = value!;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _sdkManager.isReady ? _createAVD : null,
              icon: const Icon(Icons.add),
              label: const Text('Create AVD'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAVDListCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Available AVDs',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: _refreshAVDs,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_avds.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(Icons.smartphone, size: 48, color: Colors.grey),
                      SizedBox(height: 8),
                      Text(
                        'No AVDs found',
                        style: TextStyle(color: Colors.grey),
                      ),
                      Text(
                        'Create an AVD to get started',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...(_avds.map((avd) => _buildAVDTile(avd)).toList()),
          ],
        ),
      ),
    );
  }

  Widget _buildAVDTile(AndroidAVD avd) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: const Icon(Icons.smartphone),
        title: Text(avd.name),
        subtitle: Text(avd.device ?? 'Unknown device'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () => _startEmulator(avd.name),
              icon: const Icon(Icons.play_arrow),
              tooltip: 'Start Emulator',
            ),
            IconButton(
              onPressed: () => _deleteAVD(avd.name),
              icon: const Icon(Icons.delete),
              tooltip: 'Delete AVD',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOutputTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              const Text('Output Log'),
              const Spacer(),
              IconButton(
                onPressed: () {
                  setState(() {
                    _outputLines.clear();
                  });
                },
                icon: const Icon(Icons.clear),
                tooltip: 'Clear Output',
              ),
              IconButton(
                onPressed: () {
                  final text = _outputLines.join('\n');
                  Clipboard.setData(ClipboardData(text: text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Output copied to clipboard')),
                  );
                },
                icon: const Icon(Icons.copy),
                tooltip: 'Copy Output',
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(4),
            ),
            child: ListView.builder(
              controller: _outputScrollController,
              itemCount: _outputLines.length,
              itemBuilder: (context, index) {
                return SelectableText(
                  _outputLines[index],
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _setupSDK() async {
    setState(() {
      _currentStatus = AndroidSDKStatus.installing;
    });
    
    final success = await _sdkManager.setupAndroidSDK();
    if (success) {
      await _refreshAVDs();
    }
  }

  Future<void> _createAVD() async {
    final name = _avdNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an AVD name')),
      );
      return;
    }

    final success = await _sdkManager.createAVD(
      name,
      apiLevel: _selectedApiLevel,
      abi: _selectedABI,
    );

    if (success) {
      await _refreshAVDs();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AVD "$name" created successfully')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create AVD "$name"')),
      );
    }
  }

  Future<void> _startEmulator(String avdName) async {
    final success = await _sdkManager.startEmulator(avdName);
    
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Emulator "$avdName" is starting...')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start emulator "$avdName"')),
      );
    }
  }

  Future<void> _deleteAVD(String avdName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete AVD'),
        content: Text('Are you sure you want to delete AVD "$avdName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // In a real implementation, we would call avdmanager to delete the AVD
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AVD "$avdName" deletion requested')),
      );
      await _refreshAVDs();
    }
  }

  void _showSetupGuide() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Android SDK Setup Guide'),
        content: const SingleChildScrollView(
          child: Text('''
Android SDK Setup Steps:

1. Install Java JDK 17 (already done)
2. Download Android command-line tools
3. Install necessary SDK packages:
   - platform-tools
   - emulator
   - build-tools
   - system images

4. Accept Android SDK licenses
5. Create Android Virtual Device (AVD)
6. Start emulator

This tool will automate these steps for you. Click "Setup Android SDK" to begin the process.

Requirements:
- Internet connection for downloading SDK components
- Sufficient disk space (2-3 GB)
- System permissions for creating directories
          '''),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}