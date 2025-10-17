import 'package:flutter/material.dart';
import '../widgets/enhanced_adb_device_card.dart';

/// Preview screen to showcase enhanced ADB device cards
/// This helps visualize the new design before full integration
class AdbCardsPreviewScreen extends StatefulWidget {
  const AdbCardsPreviewScreen({super.key});

  @override
  State<AdbCardsPreviewScreen> createState() => _AdbCardsPreviewScreenState();
}

class _AdbCardsPreviewScreenState extends State<AdbCardsPreviewScreen> {
  bool _isMultiSelectMode = false;
  final Set<int> _selectedIndices = {};
  
  // Sample devices for preview
  final List<_SampleDevice> _sampleDevices = [
    _SampleDevice(
      name: 'Pixel 8 Pro',
      address: '192.168.1.105:5555',
      deviceType: AdbDeviceType.phone,
      connectionType: AdbConnectionType.wifi,
      status: AdbDeviceStatus.online,
      group: 'Work',
      isFavorite: true,
      lastUsed: DateTime.now().subtract(const Duration(minutes: 2)),
      latencyMs: 25,
      subtitle: 'Android 14 • arm64-v8a',
    ),
    _SampleDevice(
      name: 'Galaxy Tab S8',
      address: '192.168.1.108:5555',
      deviceType: AdbDeviceType.tablet,
      connectionType: AdbConnectionType.wifi,
      status: AdbDeviceStatus.offline,
      group: 'Test',
      isFavorite: false,
      lastUsed: DateTime.now().subtract(const Duration(hours: 1)),
      subtitle: 'Android 13 • arm64-v8a',
    ),
    _SampleDevice(
      name: 'Fire TV Stick',
      address: '192.168.1.112:5555',
      deviceType: AdbDeviceType.tv,
      connectionType: AdbConnectionType.wifi,
      status: AdbDeviceStatus.online,
      isFavorite: false,
      lastUsed: DateTime.now().subtract(const Duration(hours: 3)),
      latencyMs: 180,
      subtitle: 'Fire OS 7 • arm64-v8a',
    ),
    _SampleDevice(
      name: 'OnePlus 12',
      address: 'USB:1234567890ABCDEF',
      deviceType: AdbDeviceType.phone,
      connectionType: AdbConnectionType.usb,
      status: AdbDeviceStatus.online,
      group: 'Home',
      isFavorite: true,
      lastUsed: DateTime.now(),
      latencyMs: 5,
      subtitle: 'Android 14 • OxygenOS',
    ),
    _SampleDevice(
      name: 'Development Tablet',
      address: '192.168.1.115:5555',
      deviceType: AdbDeviceType.tablet,
      connectionType: AdbConnectionType.paired,
      status: AdbDeviceStatus.notTested,
      group: 'Work',
      isFavorite: false,
      lastUsed: DateTime.now().subtract(const Duration(days: 3)),
      subtitle: 'Android 13 • LineageOS',
    ),
    _SampleDevice(
      name: 'Android Auto Head Unit',
      address: '192.168.1.120:5555',
      deviceType: AdbDeviceType.auto,
      connectionType: AdbConnectionType.custom,
      status: AdbDeviceStatus.connecting,
      isFavorite: false,
      lastUsed: DateTime.now().subtract(const Duration(days: 7)),
      subtitle: 'Android Automotive 12',
    ),
    _SampleDevice(
      name: 'Wear OS Watch',
      address: '192.168.1.125:5555',
      deviceType: AdbDeviceType.watch,
      connectionType: AdbConnectionType.wifi,
      status: AdbDeviceStatus.online,
      isFavorite: false,
      lastUsed: DateTime.now().subtract(const Duration(days: 1)),
      latencyMs: 45,
      subtitle: 'Wear OS 4 • arm64-v8a',
    ),
    _SampleDevice(
      name: 'Unknown Device',
      address: '192.168.1.130:5555',
      deviceType: AdbDeviceType.other,
      connectionType: AdbConnectionType.wifi,
      status: AdbDeviceStatus.offline,
      isFavorite: false,
      subtitle: 'Custom Android Build',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('ADB Device Cards Preview'),
        actions: [
          // Multi-select toggle
          IconButton(
            icon: Icon(_isMultiSelectMode ? Icons.close : Icons.checklist),
            tooltip: _isMultiSelectMode ? 'Exit Selection' : 'Multi-Select',
            onPressed: () {
              setState(() {
                _isMultiSelectMode = !_isMultiSelectMode;
                if (!_isMultiSelectMode) {
                  _selectedIndices.clear();
                }
              });
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Selection toolbar (shown when in multi-select mode)
          if (_isMultiSelectMode)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: theme.colorScheme.primaryContainer,
              child: Row(
                children: [
                  Text(
                    '${_selectedIndices.length} selected',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.select_all),
                    label: const Text('All'),
                    onPressed: () {
                      setState(() {
                        if (_selectedIndices.length == _sampleDevices.length) {
                          _selectedIndices.clear();
                        } else {
                          _selectedIndices.addAll(
                            List.generate(_sampleDevices.length, (i) => i),
                          );
                        }
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Connect'),
                    onPressed: _selectedIndices.isEmpty
                        ? null
                        : () {
                            _showSnackBar('Connect ${_selectedIndices.length} devices');
                          },
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.delete),
                    label: const Text('Delete'),
                    onPressed: _selectedIndices.isEmpty
                        ? null
                        : () {
                            _showSnackBar('Delete ${_selectedIndices.length} devices');
                          },
                  ),
                ],
              ),
            ),
          
          // Device cards grid
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Responsive grid
                int crossAxisCount;
                if (constraints.maxWidth < 600) {
                  crossAxisCount = 1;
                } else if (constraints.maxWidth < 900) {
                  crossAxisCount = 2;
                } else if (constraints.maxWidth < 1200) {
                  crossAxisCount = 3;
                } else {
                  crossAxisCount = 4;
                }
                
                return GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    childAspectRatio: 0.85,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: _sampleDevices.length,
                  itemBuilder: (context, index) {
                    final device = _sampleDevices[index];
                    final isSelected = _selectedIndices.contains(index);
                    
                    return EnhancedAdbDeviceCard(
                      deviceName: device.name,
                      address: device.address,
                      deviceType: device.deviceType,
                      connectionType: device.connectionType,
                      status: device.status,
                      group: device.group,
                      isFavorite: device.isFavorite,
                      lastUsed: device.lastUsed,
                      latencyMs: device.latencyMs,
                      subtitle: device.subtitle,
                      isMultiSelectMode: _isMultiSelectMode,
                      isSelected: isSelected,
                      onConnect: () => _showSnackBar('Connect to ${device.name}'),
                      onEdit: () => _showSnackBar('Edit ${device.name}'),
                      onDelete: () => _showSnackBar('Delete ${device.name}'),
                      onToggleFavorite: () {
                        setState(() {
                          device.isFavorite = !device.isFavorite;
                        });
                        _showSnackBar(
                          device.isFavorite
                              ? '${device.name} added to favorites'
                              : '${device.name} removed from favorites',
                        );
                      },
                      onSelectionChanged: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedIndices.add(index);
                          } else {
                            _selectedIndices.remove(index);
                          }
                        });
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showSnackBar('Add new device wizard'),
        icon: const Icon(Icons.add),
        label: const Text('Add Device'),
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

// Sample device data class
class _SampleDevice {
  final String name;
  final String address;
  final AdbDeviceType deviceType;
  final AdbConnectionType connectionType;
  final AdbDeviceStatus status;
  final String? group;
  bool isFavorite;
  final DateTime? lastUsed;
  final int? latencyMs;
  final String? subtitle;

  _SampleDevice({
    required this.name,
    required this.address,
    required this.deviceType,
    required this.connectionType,
    required this.status,
    this.group,
    required this.isFavorite,
    this.lastUsed,
    this.latencyMs,
    this.subtitle,
  });
}
