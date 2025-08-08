import 'package:flutter/material.dart';

class AndroidScreen extends StatelessWidget {
  const AndroidScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Android Screen'),
      ),
      body: const Center(
        child: Text('Welcome to the Android Screen!'),
      ),
    );
  }
}
