import 'package:flutter/material.dart';
import '../models/device_status.dart';

class EnhancedDeviceCard extends StatefulWidget {
  final Map<String, dynamic> device;
  final bool isFavorite;
  final bool isSelected;
  final DeviceStatus? status;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onToggleFavorite;
  final bool multiSelectMode;

  const EnhancedDeviceCard({
    super.key,
    required this.device,
    required this.isFavorite,
    this.isSelected = false,
    this.status,
    this.onTap,
    this.onLongPress,
    this.onEdit,
    this.onDelete,
    this.onToggleFavorite,
    this.multiSelectMode = false,
  });

  @override
  State<EnhancedDeviceCard> createState() => _EnhancedDeviceCardState();
}

class _EnhancedDeviceCardState extends State<EnhancedDeviceCard>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Color _getStatusColor() {
    if (widget.status == null || !widget.status!.isOnline) {
      return Colors.red.shade400;
    }
    final ping = widget.status!.pingMs;
    if (ping == null) return Colors.green.shade400;
    if (ping < 50) return Colors.green.shade400;
    if (ping < 100) return Colors.lightGreen.shade400;
    return Colors.orange.shade400;
  }

  Color _getDeviceTypeColor() {
    final port = widget.device['port']?.toString() ?? '22';
    if (port == '5555') return Colors.green; // Android ADB
    if (port == '5900' || port == '5901') return Colors.purple; // VNC
    if (port == '3389') return Colors.cyan; // RDP
    return Colors.blue; // SSH
  }

  IconData _getDeviceTypeIcon() {
    final port = widget.device['port']?.toString() ?? '22';
    if (port == '5555') return Icons.android;
    if (port == '5900' || port == '5901') return Icons.desktop_windows;
    if (port == '3389') return Icons.computer;
    return Icons.terminal;
  }

  String _getConnectionType() {
    final port = widget.device['port']?.toString() ?? '22';
    if (port == '5555') return 'ADB';
    if (port == '5900' || port == '5901') return 'VNC';
    if (port == '3389') return 'RDP';
    return 'SSH';
  }

  Color _getGroupColor(String group) {
    switch (group) {
      case 'Work':
        return Colors.blue.shade600;
      case 'Home':
        return Colors.green.shade600;
      case 'Servers':
        return Colors.purple.shade600;
      case 'Development':
        return Colors.orange.shade600;
      case 'Local':
        return Colors.teal.shade600;
      default:
        return Colors.grey.shade600;
    }
  }

  String _getTimeSinceCheck() {
    if (widget.status == null) return 'Never';
    final diff = DateTime.now().difference(widget.status!.lastChecked);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}min ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Widget _buildStatusTooltip() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.status?.isOnline == true
                    ? Icons.check_circle
                    : Icons.cancel,
                color: _getStatusColor(),
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                widget.status?.isOnline == true ? 'Online' : 'Offline',
                style: TextStyle(
                  color: _getStatusColor(),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          if (widget.status?.isOnline == true &&
              widget.status?.pingMs != null) ...[
            const SizedBox(height: 4),
            Text(
              'Ping: ${widget.status!.pingMs}ms',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Checked: ${_getTimeSinceCheck()}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceTooltip() {
    final deviceName = widget.device['name'] ?? 'Unnamed Device';
    final username = widget.device['username'] ?? 'user';
    final host = widget.device['host'] ?? 'unknown';
    final port = widget.device['port'] ?? '22';
    final group = widget.device['group'] ?? 'Default';

    return Container(
      padding: const EdgeInsets.all(16),
      constraints: const BoxConstraints(maxWidth: 300),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 12,
            spreadRadius: 3,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _getDeviceTypeIcon(),
                color: _getDeviceTypeColor(),
                size: 24,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  deviceName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white24, height: 16),
          _buildInfoRow(Icons.vpn_key, 'Type', _getConnectionType()),
          _buildInfoRow(Icons.group, 'Group', group),
          _buildInfoRow(Icons.link, 'Address', '$username@$host:$port'),
          if (widget.status != null) ...[
            const SizedBox(height: 8),
            _buildInfoRow(
              widget.status!.isOnline ? Icons.check_circle : Icons.cancel,
              'Status',
              widget.status!.isOnline ? 'Online' : 'Offline',
              valueColor: _getStatusColor(),
            ),
            if (widget.status!.pingMs != null)
              _buildInfoRow(
                Icons.speed,
                'Latency',
                '${widget.status!.pingMs}ms',
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value,
      {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: Colors.white54, size: 14),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final deviceName = widget.device['name'] ?? '';
    final username = widget.device['username'] ?? 'user';
    final host = widget.device['host'] ?? 'unknown';
    final port = widget.device['port'] ?? '22';
    final group = widget.device['group'] ?? 'Default';

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered && !widget.multiSelectMode ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: widget.isSelected
                    ? Colors.blue.withOpacity(0.3)
                    : Colors.black.withOpacity(_isHovered ? 0.15 : 0.08),
                blurRadius: _isHovered ? 12 : 4,
                spreadRadius: _isHovered ? 2 : 0,
                offset: Offset(0, _isHovered ? 4 : 2),
              ),
            ],
          ),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: widget.isSelected
                  ? BorderSide(color: Colors.blue.shade400, width: 2)
                  : BorderSide.none,
            ),
            child: InkWell(
              onTap: widget.onTap,
              onLongPress: widget.onLongPress,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top row: Icon, Name, Status, Favorite
                    Row(
                      children: [
                        // Device type icon
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _getDeviceTypeColor().withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            _getDeviceTypeIcon(),
                            color: _getDeviceTypeColor(),
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Device name
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Tooltip(
                                message: deviceName.isNotEmpty
                                    ? deviceName
                                    : '$username@$host:$port',
                                preferBelow: false,
                                child: Text(
                                  deviceName.isNotEmpty
                                      ? deviceName
                                      : '$username@$host',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Icon(
                                    Icons.dns,
                                    size: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      '$username@$host:$port',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // Status indicator with tooltip
                        if (!widget.multiSelectMode) ...[
                          Tooltip(
                            richMessage: WidgetSpan(
                              child: _buildStatusTooltip(),
                            ),
                            preferBelow: false,
                            child: AnimatedBuilder(
                              animation: _pulseAnimation,
                              builder: (context, child) {
                                return Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _getStatusColor().withOpacity(
                                        widget.status?.isOnline == true
                                            ? _pulseAnimation.value * 0.3
                                            : 0.2),
                                    border: Border.all(
                                      color: _getStatusColor(),
                                      width: 2,
                                    ),
                                  ),
                                  child: Center(
                                    child: Icon(
                                      widget.status?.isOnline == true
                                          ? Icons.check
                                          : Icons.close,
                                      color: _getStatusColor(),
                                      size: 16,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Favorite star
                          IconButton(
                            icon: Icon(
                              widget.isFavorite
                                  ? Icons.star
                                  : Icons.star_border,
                              color: widget.isFavorite
                                  ? Colors.amber
                                  : Colors.grey,
                            ),
                            tooltip: widget.isFavorite
                                ? 'Unpin from favorites'
                                : 'Pin to favorites',
                            onPressed: widget.onToggleFavorite,
                          ),
                        ] else
                          Checkbox(
                            value: widget.isSelected,
                            onChanged: (_) => widget.onTap?.call(),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Metadata row: Connection type, Group, Quick actions
                    Row(
                      children: [
                        // Connection type chip
                        Tooltip(
                          message: '${_getConnectionType()} via port $port',
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _getDeviceTypeColor().withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _getDeviceTypeColor().withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _getDeviceTypeIcon(),
                                  size: 14,
                                  color: _getDeviceTypeColor(),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _getConnectionType(),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: _getDeviceTypeColor(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Group chip
                        if (group != 'Default')
                          Tooltip(
                            message: 'Group: $group',
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: _getGroupColor(group),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.folder,
                                    size: 12,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    group,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        const Spacer(),
                        // Quick action buttons (show on hover)
                        if (_isHovered && !widget.multiSelectMode) ...[
                          IconButton(
                            icon: const Icon(Icons.edit, size: 20),
                            color: Colors.blue,
                            tooltip: 'Edit device',
                            onPressed: widget.onEdit,
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, size: 20),
                            color: Colors.red,
                            tooltip: 'Delete device',
                            onPressed: widget.onDelete,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
