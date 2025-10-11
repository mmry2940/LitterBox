import 'package:flutter/material.dart';
import 'adb_screen_refactored.dart';

/// Deprecated Android screen - redirects to the new ADB screen
@deprecated
class AndroidScreen extends StatelessWidget {
  const AndroidScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Android Screen (Deprecated)')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 72, color: Colors.orange),
              const SizedBox(height: 16),
              const Text(
                'Legacy screen removed. Use the new ADB interface from navigation.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open New ADB Screen'),
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                      builder: (_) => const AdbRefactoredScreen()),
                ),
              ),
            ],
          ),
        ),
      );
}
