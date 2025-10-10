import 'package:flutter/material.dart';
import 'dart:async';

/// Device type for icon selection
enum AdbDeviceType {
  phone,
  tablet,
  tv,
  watch,
  auto,
  other,
}

/// Connection type
enum AdbConnectionType {
  wifi,
  usb,
  paired,
  custom,
}

/// Connection status
enum AdbDeviceStatus {
  online,
  offline,
  connecting,
  notTested,
}

/// Enhanced ADB Device Card with hover effects, status indicators, and metadata
class EnhancedAdbDeviceCard extends StatefulWidget {
  final String deviceName;
  final String address; // IP:Port or USB identifier
  final AdbDeviceType deviceType;
  final AdbConnectionType connectionType;
  final AdbDeviceStatus status;
  final String? group;
  final bool isFavorite;
  final DateTime? lastUsed;
  final int? latencyMs; // Ping latency
  final VoidCallback? onConnect;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onToggleFavorite;
  final bool isMultiSelectMode;
  final bool isSelected;
  final ValueChanged<bool>? onSelectionChanged;
  final String? subtitle; // Additional info
  
  const EnhancedAdbDeviceCard({
    super.key,
    required this.deviceName,
    required this.address,
    this.deviceType = AdbDeviceType.phone,
    this.connectionType = AdbConnectionType.wifi,
    this.status = AdbDeviceStatus.notTested,
    this.group,
    this.isFavorite = false,
    this.lastUsed,
    this.latencyMs,
    this.onConnect,
    this.onEdit,
    this.onDelete,
    this.onToggleFavorite,
    this.isMultiSelectMode = false,
    this.isSelected = false,
    this.onSelectionChanged,
    this.subtitle,
  });

  @override
  State<EnhancedAdbDeviceCard> createState() => _EnhancedAdbDeviceCardState();
}

class _EnhancedAdbDeviceCardState extends State<EnhancedAdbDeviceCard>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _pulseController;
  Timer? _pulseTimer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _startPulseIfOnline();
  }

  @override
  void didUpdateWidget(EnhancedAdbDeviceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) {
      _startPulseIfOnline();
    }
  }

  void _startPulseIfOnline() {
    _pulseTimer?.cancel();
    if (widget.status == AdbDeviceStatus.online) {
      _pulseController.repeat(reverse: true);
    } else if (widget.status == AdbDeviceStatus.connecting) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  IconData _getDeviceTypeIcon() {
    switch (widget.deviceType) {
      case AdbDeviceType.phone:
        return Icons.smartphone;
      case AdbDeviceType.tablet:
        return Icons.tablet_android;
      case AdbDeviceType.tv:
        return Icons.tv;
      case AdbDeviceType.watch:
        return Icons.watch;
      case AdbDeviceType.auto:
        return Icons.directions_car;
      case AdbDeviceType.other:
        return Icons.devices_other;
    }
  }

  Color _getStatusColor() {
    switch (widget.status) {
      case AdbDeviceStatus.online:
        if (widget.latencyMs != null) {
          if (widget.latencyMs! < 50) return Colors.green;
          if (widget.latencyMs! < 200) return Colors.yellow.shade700;
          return Colors.orange;
        }
        return Colors.green;
      case AdbDeviceStatus.offline:
        return Colors.red;
      case AdbDeviceStatus.connecting:
        return Colors.blue;
      case AdbDeviceStatus.notTested:
        return Colors.grey;
    }
  }

  String _getStatusText() {
    switch (widget.status) {
      case AdbDeviceStatus.online:
        return 'Online';
      case AdbDeviceStatus.offline:
        return 'Offline';
      case AdbDeviceStatus.connecting:
        return 'Connecting...';
      case AdbDeviceStatus.notTested:
        return 'Not tested';
    }
  }

  IconData _getConnectionTypeIcon() {
    switch (widget.connectionType) {
      case AdbConnectionType.wifi:
        return Icons.wifi;
      case AdbConnectionType.usb:
        return Icons.usb;
      case AdbConnectionType.paired:
        return Icons.link;
      case AdbConnectionType.custom:
        return Icons.settings_ethernet;
    }
  }

  String _getConnectionTypeText() {
    switch (widget.connectionType) {
      case AdbConnectionType.wifi:
        return 'Wi-Fi';
      case AdbConnectionType.usb:
        return 'USB';
      case AdbConnectionType.paired:
        return 'Paired';
      case AdbConnectionType.custom:
        return 'Custom';
    }
  }

  String _getLastUsedText() {
    if (widget.lastUsed == null) return 'Never used';
    
    final now = DateTime.now();
    final difference = now.difference(widget.lastUsed!);
    
    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${(difference.inDays / 7).floor()}w ago';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered && !widget.isMultiSelectMode ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Card(
          elevation: _isHovered ? 8 : 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: widget.isSelected
                ? BorderSide(color: colorScheme.primary, width: 2)
                : BorderSide.none,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: widget.isMultiSelectMode
                ? () => widget.onSelectionChanged?.call(!widget.isSelected)
                : widget.onConnect,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header: Icon, Name, Status, Favorite
                  Row(
                    children: [
                      // Multi-select checkbox
                      if (widget.isMultiSelectMode) ...[
                        Checkbox(
                          value: widget.isSelected,
                          onChanged: (value) =>
                              widget.onSelectionChanged?.call(value ?? false),
                        ),
                        const SizedBox(width: 4),
                      ],
                      
                      // Device type icon
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _getDeviceTypeIcon(),
                          size: 24,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 8),
                      
                      // Device name
                      Expanded(
                        child: Text(
                          widget.deviceName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      
                      // Status indicator with pulse animation
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _getStatusColor(),
                              boxShadow: widget.status == AdbDeviceStatus.online ||
                                      widget.status == AdbDeviceStatus.connecting
                                  ? [
                                      BoxShadow(
                                        color: _getStatusColor()
                                            .withOpacity(0.5 * _pulseController.value),
                                        blurRadius: 8 * _pulseController.value,
                                        spreadRadius: 2 * _pulseController.value,
                                      ),
                                    ]
                                  : null,
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 4),
                      
                      // Favorite star
                      if (!widget.isMultiSelectMode)
                        IconButton(
                          icon: Icon(
                            widget.isFavorite ? Icons.star : Icons.star_border,
                            size: 20,
                          ),
                          color: widget.isFavorite
                              ? Colors.amber
                              : colorScheme.onSurfaceVariant,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: widget.onToggleFavorite,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  
                  // Address
                  Text(
                    widget.address,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  
                  // Subtitle (if provided)
                  if (widget.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  
                  const SizedBox(height: 10),
                  
                  // Metadata row: Status text, latency, connection type, group
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      // Status text with latency
                      _buildChip(
                        context,
                        label: widget.latencyMs != null
                            ? '${_getStatusText()} • ${widget.latencyMs}ms'
                            : _getStatusText(),
                        color: _getStatusColor(),
                      ),
                      
                      // Connection type
                      _buildChip(
                        context,
                        icon: _getConnectionTypeIcon(),
                        label: _getConnectionTypeText(),
                      ),
                      
                      // Group
                      if (widget.group != null)
                        _buildChip(
                          context,
                          icon: Icons.folder,
                          label: widget.group!,
                        ),
                    ],
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // Last used
                  Text(
                    '⏱️ ${_getLastUsedText()}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                    ),
                  ),
                  
                  // Quick actions (show on hover or always on mobile)
                  if ((_isHovered || MediaQuery.of(context).size.width < 600) &&
                      !widget.isMultiSelectMode) ...[
                    const SizedBox(height: 10),
                    const Divider(height: 1),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        if (widget.onEdit != null)
                          _buildActionButton(
                            context,
                            icon: Icons.edit_outlined,
                            label: 'Edit',
                            onPressed: widget.onEdit!,
                          ),
                        if (widget.onDelete != null)
                          _buildActionButton(
                            context,
                            icon: Icons.delete_outline,
                            label: 'Delete',
                            onPressed: widget.onDelete!,
                            isDestructive: true,
                          ),
                        if (widget.onConnect != null)
                          _buildActionButton(
                            context,
                            icon: Icons.play_arrow,
                            label: 'Connect',
                            onPressed: widget.onConnect!,
                            isPrimary: true,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChip(
    BuildContext context, {
    IconData? icon,
    required String label,
    Color? color,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color != null
            ? color.withOpacity(0.15)
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: color != null
            ? Border.all(color: color.withOpacity(0.3), width: 1)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 14,
              color: color ?? colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: color ?? colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool isPrimary = false,
    bool isDestructive = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    Color buttonColor;
    Color textColor;
    
    if (isPrimary) {
      buttonColor = colorScheme.primaryContainer;
      textColor = colorScheme.onPrimaryContainer;
    } else if (isDestructive) {
      buttonColor = colorScheme.errorContainer;
      textColor = colorScheme.onErrorContainer;
    } else {
      buttonColor = colorScheme.surfaceContainerHighest;
      textColor = colorScheme.onSurfaceVariant;
    }
    
    return Expanded(
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: buttonColor,
          foregroundColor: textColor,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
