import 'package:flutter/material.dart';
import 'device_details_screen.dart';

class DeviceMiscScreen extends StatefulWidget {
  final void Function(int tabIndex)? onCardTap;
  final Map<String, dynamic> device;

  const DeviceMiscScreen({
    super.key,
    this.onCardTap,
    required this.device,
  });

  @override
  _DeviceMiscScreenState createState() => _DeviceMiscScreenState();
}

class _DeviceMiscScreenState extends State<DeviceMiscScreen> {
  @override
  Widget build(BuildContext context) {
    final List<_OverviewCardData> cards = [
      _OverviewCardData('Info', Icons.info, 0),
      _OverviewCardData('Terminal', Icons.terminal, 1),
      _OverviewCardData('Files', Icons.folder, 2),
      _OverviewCardData('Processes', Icons.memory, 3),
      _OverviewCardData('Packages', Icons.list, 4),
      _OverviewCardData('Details', Icons.dashboard_customize, 5),
    ];

    return Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Overview Cards Grid
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: cards
                    .map(
                      (card) => _OverviewCard(
                        title: card.title,
                        icon: card.icon,
                        onTap: () {
                          // Special handling for Details card - navigate to dedicated screen
                          if (card.title == 'Details') {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => DeviceDetailsScreen(
                                  device: widget.device,
                                ),
                              ),
                            );
                          } else if (widget.onCardTap != null) {
                            // For other cards, switch tabs
                            widget.onCardTap!(card.tabIndex);
                          }
                        },
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverviewCardData {
  final String title;
  final IconData icon;
  final int tabIndex;
  _OverviewCardData(this.title, this.icon, this.tabIndex);
}

class _OverviewCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback? onTap;
  const _OverviewCard({required this.title, required this.icon, this.onTap});
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48),
              const SizedBox(height: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}
