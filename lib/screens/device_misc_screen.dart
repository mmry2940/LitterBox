import 'package:flutter/material.dart';

class DeviceMiscScreen extends StatelessWidget {
  final void Function(int tabIndex)? onCardTap;
  const DeviceMiscScreen({super.key, this.onCardTap});

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
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        children: cards
            .map(
              (card) => _OverviewCard(
                title: card.title,
                icon: card.icon,
                onTap: () {
                  if (onCardTap != null) {
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
