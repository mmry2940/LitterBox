import 'package:flutter/material.dart';

class CardMetadata {
  final int? count;
  final String? status;
  final String? detail;
  final bool isActive;
  final bool isLoading;
  final String? error;

  const CardMetadata({
    this.count,
    this.status,
    this.detail,
    this.isActive = false,
    this.isLoading = false,
    this.error,
  });
}

class EnhancedMiscCard extends StatefulWidget {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final VoidCallback? onQuickAction;
  final String? quickActionLabel;
  final CardMetadata? metadata;
  final String? tooltipTitle;
  final List<String>? tooltipFeatures;

  const EnhancedMiscCard({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    this.onTap,
    this.onQuickAction,
    this.quickActionLabel,
    this.metadata,
    this.tooltipTitle,
    this.tooltipFeatures,
  });

  @override
  State<EnhancedMiscCard> createState() => _EnhancedMiscCardState();
}

class _EnhancedMiscCardState extends State<EnhancedMiscCard>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    // Start pulse animation if card is active
    if (widget.metadata?.isActive == true) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(EnhancedMiscCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Update pulse animation based on active state
    if (widget.metadata?.isActive == true && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (widget.metadata?.isActive == false &&
        _pulseController.isAnimating) {
      _pulseController.stop();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Widget _buildTooltip({required Widget child}) {
    if (widget.tooltipTitle == null) return child;

    return Tooltip(
      richMessage: WidgetSpan(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 300),
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(widget.icon, color: widget.color, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.tooltipTitle!,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                widget.description,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[300],
                ),
              ),
              if (widget.tooltipFeatures != null &&
                  widget.tooltipFeatures!.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'Features:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                ...widget.tooltipFeatures!.map(
                  (feature) => Padding(
                    padding: const EdgeInsets.only(left: 8, top: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '• ',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            feature,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (widget.metadata?.detail != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: widget.color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    widget.metadata!.detail!,
                    style: TextStyle(
                      fontSize: 11,
                      color: widget.color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      preferBelow: false,
      child: child,
    );
  }

  Widget _buildStatusIndicator() {
    if (widget.metadata == null) return const SizedBox.shrink();

    Color statusColor;
    IconData statusIcon;

    if (widget.metadata!.isLoading) {
      statusColor = Colors.yellow;
      statusIcon = Icons.refresh;
    } else if (widget.metadata!.error != null) {
      statusColor = Colors.red;
      statusIcon = Icons.error_outline;
    } else if (widget.metadata!.isActive) {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
    } else {
      statusColor = Colors.grey;
      statusIcon = Icons.circle_outlined;
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.2),
        shape: BoxShape.circle,
      ),
      child: Icon(
        statusIcon,
        size: 12,
        color: statusColor,
      ),
    );
  }

  Widget _buildBadge() {
    if (widget.metadata?.detail == null && widget.metadata?.count == null) {
      return const SizedBox.shrink();
    }

    String badgeText = widget.metadata!.detail ?? '${widget.metadata!.count}';

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 120),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: widget.color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: widget.color.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.metadata?.isActive == true) ...[
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                badgeText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: widget.color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _buildTooltip(
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: AnimatedScale(
          scale: _isHovered ? 1.02 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: _isHovered
                  ? [
                      BoxShadow(
                        color: widget.color.withOpacity(0.3),
                        blurRadius: 16,
                        spreadRadius: 2,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        spreadRadius: 1,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: InkWell(
                onTap: widget.onTap,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        widget.color.withOpacity(0.15),
                        widget.color.withOpacity(0.05),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Icon with pulse animation if active
                        AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) {
                            final scale = widget.metadata?.isActive == true
                                ? 1.0 + (0.1 * _pulseController.value)
                                : 1.0;
                            return Transform.scale(
                              scale: scale,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: widget.color.withOpacity(0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  widget.icon,
                                  size: 30,
                                  color: widget.color,
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),

                        // Title with status indicator
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                widget.title,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (widget.metadata != null) ...[
                              const SizedBox(width: 6),
                              _buildStatusIndicator(),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),

                        // Description
                        Text(
                          widget.description,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[600],
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),

                        // Badge with metadata
                        _buildBadge(),

                        // Quick action button (visible on hover)
                        if (_isHovered &&
                            widget.onQuickAction != null &&
                            widget.quickActionLabel != null) ...[
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: widget.onQuickAction,
                            style: TextButton.styleFrom(
                              foregroundColor: widget.color,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              minimumSize: const Size(0, 28),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: Text(
                                    widget.quickActionLabel!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.arrow_forward, size: 14),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
