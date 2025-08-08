import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class VNCScreen extends StatefulWidget {
  const VNCScreen({super.key});

  @override
  State<VNCScreen> createState() => _VNCScreenState();
}

class _VNCScreenState extends State<VNCScreen> {
  List<Map<String, dynamic>> _vncDevices = [];
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadVNCDevices();
  }

  Future<void> _loadVNCDevices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final devicesString = prefs.getString('vnc_devices') ?? '[]';
      final devices = json.decode(devicesString) as List;
      if (mounted) {
        setState(() {
          _vncDevices = devices.cast<Map<String, dynamic>>();
        });
      }
    } catch (e) {
      print('Error loading VNC devices: $e');
    }
  }

  Future<void> _saveVNCDevices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('vnc_devices', json.encode(_vncDevices));
    } catch (e) {
      print('Error saving VNC devices: $e');
    }
  }

  void _showAddDeviceBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Add VNC Device',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildFormField(
                    controller: _nameController,
                    label: 'Device Name',
                    hint: 'My VNC Server',
                    icon: Icons.label,
                  ),
                  const SizedBox(height: 16),
                  _buildFormField(
                    controller: _hostController,
                    label: 'Host/IP Address',
                    hint: '192.168.1.100',
                    icon: Icons.computer,
                  ),
                  const SizedBox(height: 16),
                  _buildFormField(
                    controller: _portController,
                    label: 'Port',
                    hint: '5900',
                    icon: Icons.settings_ethernet,
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  _buildFormField(
                    controller: _usernameController,
                    label: 'Username (optional)',
                    hint: 'Enter username',
                    icon: Icons.person,
                  ),
                  const SizedBox(height: 16),
                  _buildFormField(
                    controller: _passwordController,
                    label: 'Password (optional)',
                    hint: 'Enter password',
                    icon: Icons.lock,
                    obscureText: true,
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _addVNCDevice,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Add VNC Device',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFormField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, color: Colors.grey.shade600),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(16),
        ),
      ),
    );
  }

  void _addVNCDevice() {
    if (_nameController.text.isNotEmpty && _hostController.text.isNotEmpty) {
      setState(() {
        _vncDevices.add({
          'name': _nameController.text,
          'host': _hostController.text,
          'port': int.tryParse(_portController.text) ?? 5900,
          'username': _usernameController.text,
          'password': _passwordController.text,
          'created': DateTime.now().toIso8601String(),
        });
      });
      _saveVNCDevices();
      _clearForm();
      Navigator.pop(context);

      // Show success snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('VNC device "${_nameController.text}" added successfully!'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      // Show error snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in device name and host/IP address'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _clearForm() {
    _nameController.clear();
    _hostController.clear();
    _portController.clear();
    _usernameController.clear();
    _passwordController.clear();
  }

  void _deleteVNCDevice(int index) {
    setState(() {
      _vncDevices.removeAt(index);
    });
    _saveVNCDevices();
  }

  void _connectToVNC(Map<String, dynamic> device) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => VNCViewerScreen(device: device),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VNC Client'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              _showInfoDialog();
            },
          ),
        ],
      ),
      body: _vncDevices.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.desktop_windows,
                    size: 100,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'No VNC Devices',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Add your first VNC server connection\nusing the + button below',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[500],
                    ),
                  ),
                  const SizedBox(height: 30),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.lightbulb, color: Colors.blue.shade600),
                        const SizedBox(height: 8),
                        Text(
                          'Tip: Make sure your VNC server is running\nand accessible on your network',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.blue.shade800,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadVNCDevices,
              child: ListView.builder(
                padding: const EdgeInsets.all(16.0),
                itemCount: _vncDevices.length,
                itemBuilder: (context, index) {
                  final device = _vncDevices[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: InkWell(
                        onTap: () => _connectToVNC(device),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            children: [
                              Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                child: Icon(
                                  Icons.desktop_windows,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 30,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      device['name'],
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${device['host']}:${device['port']}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    if (device['username']?.isNotEmpty == true)
                                      Text(
                                        'User: ${device['username']}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[500],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              PopupMenuButton(
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'connect',
                                    child: Row(
                                      children: [
                                        Icon(Icons.play_arrow,
                                            color: Colors.green),
                                        SizedBox(width: 8),
                                        Text('Connect'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete, color: Colors.red),
                                        SizedBox(width: 8),
                                        Text('Delete'),
                                      ],
                                    ),
                                  ),
                                ],
                                onSelected: (value) {
                                  switch (value) {
                                    case 'connect':
                                      _connectToVNC(device);
                                      break;
                                    case 'delete':
                                      _confirmDelete(index);
                                      break;
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDeviceBottomSheet,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Device'),
        elevation: 8,
      ),
    );
  }

  void _confirmDelete(int index) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete VNC Device'),
          content: Text(
              'Are you sure you want to delete "${_vncDevices[index]['name']}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                _deleteVNCDevice(index);
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('VNC device deleted'),
                    backgroundColor: Colors.orange,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child:
                  const Text('Delete', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _showInfoDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('VNC Client Info'),
          content: const SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'This VNC client allows you to connect to VNC servers on your network.',
                  style: TextStyle(fontSize: 16),
                ),
                SizedBox(height: 16),
                Text(
                  'Features:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text('• Add multiple VNC server connections'),
                Text('• Save device configurations'),
                Text('• Authentication support'),
                Text('• Easy connection management'),
                SizedBox(height: 16),
                Text(
                  'Note: VNC servers must be accessible from your device network.',
                  style: TextStyle(
                      fontStyle: FontStyle.italic, color: Colors.grey),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}

class VNCViewerScreen extends StatelessWidget {
  final Map<String, dynamic> device;

  const VNCViewerScreen({super.key, required this.device});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(device['name']),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(60),
                ),
                child: const Icon(
                  Icons.desktop_windows,
                  size: 60,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(height: 30),
              const Text(
                'VNC Connection',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                'Ready to connect to ${device['name']}',
                style: const TextStyle(fontSize: 18),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '${device['host']}:${device['port']}',
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 30),
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      const Icon(Icons.info, color: Colors.blue, size: 40),
                      const SizedBox(height: 16),
                      const Text(
                        'VNC Viewer Demo',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'This is a demonstration of the VNC connection interface. In a full implementation, this would show the remote desktop.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: () => _showConnectionDetails(context),
                        icon: const Icon(Icons.info_outline),
                        label: const Text('Connection Details'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showConnectionDetails(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Connection Details'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildInfoRow('Device Name', device['name']),
                _buildInfoRow('Host', device['host']),
                _buildInfoRow('Port', device['port'].toString()),
                if (device['username']?.isNotEmpty == true)
                  _buildInfoRow('Username', device['username']),
                const SizedBox(height: 16),
                const Text(
                  'Connection Requirements:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text('• VNC server must be running'),
                const Text('• Network connectivity required'),
                const Text('• Proper firewall configuration'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}
