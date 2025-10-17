import 'package:flutter/material.dart';
import '../services/esp32_service.dart';

class ESP32ScanTestDialog extends StatefulWidget {
  const ESP32ScanTestDialog({super.key});

  @override
  State<ESP32ScanTestDialog> createState() => _ESP32ScanTestDialogState();
}

class _ESP32ScanTestDialogState extends State<ESP32ScanTestDialog> {
  final ESP32Service _esp32Service = ESP32Service();
  bool _isScanning = false;
  List<String> _scanResults = [];
  String _networkInfo = '';

  @override
  void initState() {
    super.initState();
    _startNetworkDetection();
  }

  Future<void> _startNetworkDetection() async {
    try {
      // Test network detection
      await _detectNetwork();
    } catch (e) {
      setState(() {
        _networkInfo = 'Network detection error: $e';
      });
    }
  }

  Future<void> _detectNetwork() async {
    try {
      final scanResults = await _esp32Service.scanLANDevices();
      setState(() {
        _scanResults = scanResults;
        _networkInfo = 'Network scan completed. Found ${scanResults.length} potential ESP32 devices.';
      });
    } catch (e) {
      setState(() {
        _networkInfo = 'Scan error: $e';
      });
    }
  }

  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
      _scanResults.clear();
    });

    try {
      final results = await _esp32Service.scanLANDevices();
      setState(() {
        _scanResults = results;
      });
    } catch (e) {
      setState(() {
        _scanResults = ['Error: $e'];
      });
    } finally {
      setState(() {
        _isScanning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('ESP32 Network Scan Test'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Network Info:', style: Theme.of(context).textTheme.titleMedium),
            Text(_networkInfo),
            const SizedBox(height: 16),
            Row(
              children: [
                ElevatedButton(
                  onPressed: _isScanning ? null : _startScan,
                  child: _isScanning 
                    ? const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
                          Text('Scanning...'),
                        ],
                      )
                    : const Text('Start Scan'),
                ),
                const SizedBox(width: 8),
                Text('Found: ${_scanResults.length}'),
              ],
            ),
            const SizedBox(height: 16),
            Text('Scan Results:', style: Theme.of(context).textTheme.titleMedium),
            Expanded(
              child: _scanResults.isEmpty
                  ? const Center(child: Text('No devices found'))
                  : ListView.builder(
                      itemCount: _scanResults.length,
                      itemBuilder: (context, index) {
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.wifi),
                          title: Text(_scanResults[index]),
                          subtitle: Text('Potential ESP32 device'),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}