import 'package:flutter/material.dart';
import 'adb_screen_refactored.dart';

/// Deprecated Android screen - redirects to the new ADB screen
class AndroidScreen extends StatelessWidget {
  const AndroidScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Automatically redirect to the new ADB screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const AdbRefactoredScreen()),
      );
    });

    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Redirecting to ADB Screen...'),
          ],
        ),
      ),
    );
  }
}
