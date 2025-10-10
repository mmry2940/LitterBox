import 'package:flutter/material.dart';
import '../models/saved_adb_device.dart';
import '../adb/adb_mdns_discovery.dart';
import '../adb/usb_bridge.dart';
import '../adb_client.dart';
import 'enhanced_adb_device_card.dart';

/// Enhanced Dashboard Tab with segmented view: Saved / Discovered / New Connection
class EnhancedAdbDashboard extends StatefulWidget {
  final List<SavedADBDevice> savedDevices;
  final List<AdbMdnsServiceInfo> mdnsServices;
  final List<UsbDeviceInfo> usbDevices;
  final Set<String> favoriteConnections;
  final String connectionFilter;
  final bool mdnsScanning;
  final DateTime? lastMdnsScan;
  final Function(SavedADBDevice) onLoadDevice;
  final Function(SavedADBDevice) onEditDevice;
  final Function(SavedADBDevice) onDeleteDevice;
  final Function(SavedADBDevice) onToggleFavorite;
  final Function(String host, int port) onConnectWifi;
  final Function() onConnectUsb;
  final Function() onRunMdnsScan;
  final Function() onRefreshUsb;
  final Function() onAddNewDevice;
  final Function(String) onConnectionFilterChanged;
  final String searchQuery;
  final Function(String) onSearchChanged;
  final String sortOption;
  final Function(String) onSortChanged;
  
  const EnhancedAdbDashboard({
    super.key,
    required this.savedDevices,
    required this.mdnsServices,
    required this.usbDevices,
    required this.favoriteConnections,
    required this.connectionFilter,
    required this.mdnsScanning,
    required this.lastMdnsScan,
    required this.onLoadDevice,
    required this.onEditDevice,
    required this.onDeleteDevice,
    required this.onToggleFavorite,
    required this.onConnectWifi,
    required this.onConnectUsb,
    required this.onRunMdnsScan,
    required this.onRefreshUsb,
    required this.onAddNewDevice,
    required this.onConnectionFilterChanged,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.sortOption,
    required this.onSortChanged,
  });

  @override
  State<EnhancedAdbDashboard> createState() => _EnhancedAdbDashboardState();
}

class _EnhancedAdbDashboardState extends State<EnhancedAdbDashboard>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Set<int> _selectedIndices = {};
  bool _isMultiSelectMode = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Segmented tab bar
        Container(
          padding: const EdgeInsets.all(12),
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: Theme.of(context).colorScheme.primary,
              ),
              labelColor: Theme.of(context).colorScheme.onPrimary,
              unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: 'Saved', icon: Icon(Icons.bookmark, size: 20)),
                Tab(text: 'Discovered', icon: Icon(Icons.radar, size: 20)),
                Tab(text: 'New', icon: Icon(Icons.add_circle, size: 20)),
              ],
            ),
          ),
        ),
        
        // Tab content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildSavedTab(),
              _buildDiscoveredTab(),
              _buildNewConnectionTab(),
            ],
          ),
        ),
      ],
    );
  }

  // Saved devices tab with enhanced cards
  Widget _buildSavedTab() {
    return Column(
      children: [
        // Toolbar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // Search bar
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search, size: 20),
                    hintText: 'Search saved devices...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onChanged: widget.onSearchChanged,
                ),
              ),
              const SizedBox(width: 8),
              
              // Filter dropdown
              PopupMenuButton<String>(
                icon: const Icon(Icons.filter_list),
                tooltip: 'Filter',
                onSelected: widget.onConnectionFilterChanged,
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'All', child: Text('All Devices')),
                  const PopupMenuItem(value: 'Favorites', child: Text('Favorites Only')),
                ],
              ),
              
              // Sort dropdown
              PopupMenuButton<String>(
                icon: const Icon(Icons.sort),
                tooltip: 'Sort',
                onSelected: widget.onSortChanged,
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'Alphabetical', child: Text('Alphabetical')),
                  const PopupMenuItem(value: 'Last Used', child: Text('Last Used')),
                  const PopupMenuItem(value: 'Pinned First', child: Text('Pinned First')),
                ],
              ),
              
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
            ],
          ),
        ),
        
        // Batch operations toolbar
        if (_isMultiSelectMode && _selectedIndices.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Row(
              children: [
                Text(
                  '${_selectedIndices.length} selected',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Connect'),
                  onPressed: _batchConnect,
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  icon: const Icon(Icons.delete, size: 18),
                  label: const Text('Delete'),
                  onPressed: _batchDelete,
                ),
              ],
            ),
          ),
        
        // Device cards grid
        Expanded(
          child: _buildDeviceGrid(_getFilteredSavedDevices()),
        ),
      ],
    );
  }

  // Discovered devices tab (mDNS + USB)
  Widget _buildDiscoveredTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Discovery controls
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: widget.mdnsScanning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering),
                  label: Text(widget.mdnsScanning ? 'Scanning...' : 'Scan Wi-Fi'),
                  onPressed: widget.mdnsScanning ? null : widget.onRunMdnsScan,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.usb),
                  label: const Text('Refresh USB'),
                  onPressed: widget.onRefreshUsb,
                ),
              ),
            ],
          ),
          
          // Last scan info
          if (widget.lastMdnsScan != null) ...[
            const SizedBox(height: 8),
            Text(
              'Last scan: ${_getRelativeTime(widget.lastMdnsScan!)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
          
          const SizedBox(height: 16),
          
          // Wi-Fi devices section
          if (widget.mdnsServices.isNotEmpty) ...[
            Row(
              children: [
                Icon(Icons.wifi, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Wi-Fi Devices (${widget.mdnsServices.length})',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = _getCrossAxisCount(constraints.maxWidth);
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    childAspectRatio: 0.85,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: widget.mdnsServices.length,
                  itemBuilder: (context, index) {
                    final service = widget.mdnsServices[index];
                    return _buildMdnsCard(service);
                  },
                );
              },
            ),
            const SizedBox(height: 24),
          ] else if (!widget.mdnsScanning) ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(
                      Icons.wifi_off,
                      size: 64,
                      color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No Wi-Fi devices found',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap "Scan Wi-Fi" to discover devices',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          
          // USB devices section
          if (widget.usbDevices.isNotEmpty) ...[
            Row(
              children: [
                Icon(Icons.usb, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'USB Devices (${widget.usbDevices.length})',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = _getCrossAxisCount(constraints.maxWidth);
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    childAspectRatio: 0.85,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: widget.usbDevices.length,
                  itemBuilder: (context, index) {
                    final device = widget.usbDevices[index];
                    return _buildUsbCard(device);
                  },
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  // New connection tab (simplified quick connect form)
  Widget _buildNewConnectionTab() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quick Connect',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Connect to a device manually',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'For advanced pairing and detailed connection options, use the full connection dialog.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Open Connection Wizard'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    onPressed: widget.onAddNewDevice,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Helper: Build device grid
  Widget _buildDeviceGrid(List<SavedADBDevice> devices) {
    if (devices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.devices_other,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              widget.searchQuery.isNotEmpty
                  ? 'No devices match your search'
                  : 'No saved devices',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add Device'),
              onPressed: () {
                _tabController.animateTo(2); // Switch to New tab
              },
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = _getCrossAxisCount(constraints.maxWidth);
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 0.85,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: devices.length,
          itemBuilder: (context, index) {
            final device = devices[index];
            final isFavorite = widget.favoriteConnections.contains(device.name);
            final isSelected = _selectedIndices.contains(index);
            
            return EnhancedAdbDeviceCard(
              deviceName: device.name,
              address: _getDeviceAddress(device),
              deviceType: _getDeviceType(device),
              connectionType: _mapConnectionType(device.connectionType),
              status: AdbDeviceStatus.notTested, // TODO: Add real status
              group: device.label,
              isFavorite: isFavorite,
              lastUsed: device.lastUsed,
              subtitle: _getDeviceSubtitle(device),
              isMultiSelectMode: _isMultiSelectMode,
              isSelected: isSelected,
              onConnect: () => widget.onLoadDevice(device),
              onEdit: () => widget.onEditDevice(device),
              onDelete: () => widget.onDeleteDevice(device),
              onToggleFavorite: () => widget.onToggleFavorite(device),
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
    );
  }

  // Helper: Build mDNS discovered device card
  Widget _buildMdnsCard(AdbMdnsServiceInfo service) {
    final host = service.ip ?? service.host;
    final port = service.port;
    final deviceName = service.txt['name'] ?? service.host;
    
    return EnhancedAdbDeviceCard(
      deviceName: deviceName,
      address: '$host:$port',
      deviceType: AdbDeviceType.phone, // Default, could be detected from TXT records
      connectionType: AdbConnectionType.wifi,
      status: AdbDeviceStatus.online, // Discovered = assumed online
      subtitle: 'mDNS discovered',
      onConnect: () => widget.onConnectWifi(host, port),
    );
  }

  // Helper: Build USB device card
  Widget _buildUsbCard(UsbDeviceInfo device) {
    return EnhancedAdbDeviceCard(
      deviceName: device.name.isNotEmpty ? device.name : 'USB Device',
      address: device.serial ?? 'Unknown Serial',
      deviceType: AdbDeviceType.phone,
      connectionType: AdbConnectionType.usb,
      status: AdbDeviceStatus.online,
      subtitle: 'Vendor: ${device.vendorId}, Product: ${device.productId}',
      onConnect: widget.onConnectUsb,
    );
  }

  // Helper: Get filtered and sorted saved devices
  List<SavedADBDevice> _getFilteredSavedDevices() {
    var devices = widget.savedDevices.where((d) {
      // Apply filter
      if (widget.connectionFilter == 'Favorites' &&
          !widget.favoriteConnections.contains(d.name)) {
        return false;
      }
      
      // Apply search
      if (widget.searchQuery.isNotEmpty) {
        final query = widget.searchQuery.toLowerCase();
        return d.name.toLowerCase().contains(query) ||
            d.host.toLowerCase().contains(query) ||
            (d.label?.toLowerCase().contains(query) ?? false);
      }
      
      return true;
    }).toList();

    // Apply sort
    switch (widget.sortOption) {
      case 'Alphabetical':
        devices.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case 'Last Used':
        devices.sort((a, b) =>
            (b.lastUsed ?? DateTime(1970)).compareTo(a.lastUsed ?? DateTime(1970)));
        break;
      case 'Pinned First':
        final favs = devices.where((d) => widget.favoriteConnections.contains(d.name)).toList();
        final nonFavs =
            devices.where((d) => !widget.favoriteConnections.contains(d.name)).toList();
        favs.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        nonFavs.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        devices = [...favs, ...nonFavs];
        break;
    }

    return devices;
  }

  // Batch operations
  void _batchConnect() {
    final devices = _getFilteredSavedDevices();
    for (final index in _selectedIndices) {
      if (index < devices.length) {
        widget.onLoadDevice(devices[index]);
      }
    }
    setState(() {
      _selectedIndices.clear();
      _isMultiSelectMode = false;
    });
  }

  void _batchDelete() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Devices'),
        content: Text('Delete ${_selectedIndices.length} selected devices?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final devices = _getFilteredSavedDevices();
              for (final index in _selectedIndices) {
                if (index < devices.length) {
                  widget.onDeleteDevice(devices[index]);
                }
              }
              setState(() {
                _selectedIndices.clear();
                _isMultiSelectMode = false;
              });
              Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // Helper: Get cross-axis count for responsive grid
  int _getCrossAxisCount(double width) {
    if (width < 600) return 1;
    if (width < 900) return 2;
    if (width < 1200) return 3;
    return 4;
  }

  // Helper: Get device address string
  String _getDeviceAddress(SavedADBDevice device) {
    if (device.connectionType == ADBConnectionType.usb) {
      return 'USB Device';
    }
    return '${device.host}:${device.port}';
  }

  // Helper: Get device type from saved device
  AdbDeviceType _getDeviceType(SavedADBDevice device) {
    // Could be enhanced with device property detection
    return AdbDeviceType.phone;
  }

  // Helper: Map connection type
  AdbConnectionType _mapConnectionType(ADBConnectionType type) {
    switch (type) {
      case ADBConnectionType.wifi:
        return AdbConnectionType.wifi;
      case ADBConnectionType.usb:
        return AdbConnectionType.usb;
      case ADBConnectionType.pairing:
        return AdbConnectionType.paired;
      case ADBConnectionType.custom:
        return AdbConnectionType.custom;
    }
  }

  // Helper: Get device subtitle
  String? _getDeviceSubtitle(SavedADBDevice device) {
    return device.connectionType.displayName;
  }

  // Helper: Get relative time
  String _getRelativeTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
