import 'package:flutter/material.dart';
import 'misc_details_screen.dart';

class DeviceMiscScreen extends StatelessWidget {
  final void Function(int tabIndex)? onCardTap;
  final Map<String, dynamic> device; // Add device parameter

  const DeviceMiscScreen({
    super.key,
    this.onCardTap,
    required this.device, // Mark device as required
  });

  @override
  Widget build(BuildContext context) {
    final List<_OverviewCardData> cards = [
      _OverviewCardData('Info', Icons.info, 0),
      _OverviewCardData('Terminal', Icons.terminal, 1),
      _OverviewCardData('Files', Icons.folder, 2),
      _OverviewCardData('Processes', Icons.memory, 3),
      _OverviewCardData('Packages', Icons.list, 4),
      _OverviewCardData('Misc', Icons.dashboard_customize, 5),
    ];

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: GridView.count(
        crossAxisCount: 2,
        children: cards
            .map(
              (card) => _OverviewCard(
                title: card.title, // Provide required title parameter
                icon: card.icon, // Provide required icon parameter
                onTap: () {
                  if (card.tabIndex == 5) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => MiscDetailsScreen(
                          device: device.map((key, value) => MapEntry(
                              key, value.toString())), // Ensure type matches
                        ),
                      ),
                    );
                  } else if (onCardTap != null) {
                    onCardTap!(card.tabIndex);
                  }
                },
              ),
            )
            .toList(),
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
