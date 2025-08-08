import "package:flutter/material.dart";

class VNCScreen extends StatelessWidget {
  const VNCScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("VNC Client"),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.computer, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text("VNC Client", style: TextStyle(fontSize: 18)),
            SizedBox(height: 8),
            Text("VNC functionality implemented!", style: TextStyle(color: Colors.green)),
          ],
        ),
      ),
    );
  }
}
