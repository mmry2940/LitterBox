import 'package:flutter/material.dart';
import '../adb_client.dart';

/// Step-by-step connection wizard for ADB devices
class AdbConnectionWizard extends StatefulWidget {
  final Function(String host, int port, ADBConnectionType type, String? label) onConnect;
  final VoidCallback? onCancel;
  
  const AdbConnectionWizard({
    super.key,
    required this.onConnect,
    this.onCancel,
  });

  @override
  State<AdbConnectionWizard> createState() => _AdbConnectionWizardState();
}

class _AdbConnectionWizardState extends State<AdbConnectionWizard> {
  int _currentStep = 0;
  ADBConnectionType _selectedType = ADBConnectionType.wifi;
  
  // Form controllers
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '5555');
  final _pairingPortController = TextEditingController(text: '37205');
  final _pairingCodeController = TextEditingController();
  final _labelController = TextEditingController();
  
  // State
  bool _saveDevice = true;
  bool _markAsFavorite = false;
  bool _isConnecting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _pairingPortController.dispose();
    _pairingCodeController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    Icons.cable,
                    size: 28,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Connect to Device',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: widget.onCancel,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              // Stepper
              Expanded(
                child: Stepper(
                  currentStep: _currentStep,
                  onStepContinue: _onStepContinue,
                  onStepCancel: _onStepCancel,
                  controlsBuilder: _buildControls,
                  steps: [
                    Step(
                      title: const Text('Connection Type'),
                      content: _buildStepConnectionType(),
                      isActive: _currentStep >= 0,
                      state: _currentStep > 0 ? StepState.complete : StepState.indexed,
                    ),
                    Step(
                      title: const Text('Connection Details'),
                      content: _buildStepConnectionDetails(),
                      isActive: _currentStep >= 1,
                      state: _currentStep > 1 ? StepState.complete : StepState.indexed,
                    ),
                    Step(
                      title: const Text('Save Device'),
                      content: _buildStepSaveDevice(),
                      isActive: _currentStep >= 2,
                      state: _currentStep > 2 ? StepState.complete : StepState.indexed,
                    ),
                  ],
                ),
              ),
              
              // Error message
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepConnectionType() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How would you like to connect?',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildConnectionTypeCard(
              type: ADBConnectionType.wifi,
              icon: Icons.wifi,
              title: 'Wi-Fi',
              description: 'Connect over wireless network',
            ),
            _buildConnectionTypeCard(
              type: ADBConnectionType.usb,
              icon: Icons.usb,
              title: 'USB',
              description: 'Connect via USB cable',
            ),
            _buildConnectionTypeCard(
              type: ADBConnectionType.pairing,
              icon: Icons.link,
              title: 'Pairing',
              description: 'Pair with code (Android 11+)',
            ),
            _buildConnectionTypeCard(
              type: ADBConnectionType.custom,
              icon: Icons.settings_ethernet,
              title: 'Custom',
              description: 'Advanced connection',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildConnectionTypeCard({
    required ADBConnectionType type,
    required IconData icon,
    required String title,
    required String description,
  }) {
    final isSelected = _selectedType == type;
    final theme = Theme.of(context);
    
    return SizedBox(
      width: 140,
      child: InkWell(
        onTap: () => setState(() => _selectedType = type),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
              width: isSelected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
            color: isSelected
                ? theme.colorScheme.primaryContainer.withOpacity(0.3)
                : null,
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 40,
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isSelected ? theme.colorScheme.primary : null,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepConnectionDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_selectedType == ADBConnectionType.usb) ...[
          Text(
            'USB Connection',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Make sure your device is connected via USB cable and USB debugging is enabled.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'No additional configuration needed for USB connections.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ] else if (_selectedType == ADBConnectionType.pairing) ...[
          Text(
            'Pairing Configuration',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _hostController,
            decoration: const InputDecoration(
              labelText: 'Device IP Address',
              hintText: '192.168.1.100',
              prefixIcon: Icon(Icons.devices),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _pairingPortController,
                  decoration: const InputDecoration(
                    labelText: 'Pairing Port',
                    hintText: '37205',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _portController,
                  decoration: const InputDecoration(
                    labelText: 'Connection Port',
                    hintText: '5555',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pairingCodeController,
            decoration: const InputDecoration(
              labelText: 'Pairing Code',
              hintText: '123456',
              prefixIcon: Icon(Icons.vpn_key),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.phone_android,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'On your device:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '1. Go to Settings > Developer Options\n'
                  '2. Enable "Wireless debugging"\n'
                  '3. Tap "Pair device with pairing code"\n'
                  '4. Enter the IP, port, and code shown',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ] else ...[
          // Wi-Fi and Custom
          Text(
            'Connection Configuration',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _hostController,
            decoration: const InputDecoration(
              labelText: 'Device IP Address',
              hintText: '192.168.1.100',
              prefixIcon: Icon(Icons.devices),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _portController,
            decoration: const InputDecoration(
              labelText: 'Port',
              hintText: '5555',
              prefixIcon: Icon(Icons.settings_ethernet),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.phone_android,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'On your device:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '1. Enable "Wireless debugging" in Developer Options\n'
                  '2. Note your device\'s IP address\n'
                  '3. Default port is usually 5555',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStepSaveDevice() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Device Configuration',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          value: _saveDevice,
          onChanged: (value) => setState(() => _saveDevice = value),
          title: const Text('Save device for quick access'),
          subtitle: const Text('Add this device to your saved devices list'),
        ),
        if (_saveDevice) ...[
          const SizedBox(height: 16),
          TextField(
            controller: _labelController,
            decoration: InputDecoration(
              labelText: 'Device Name (Optional)',
              hintText: _selectedType == ADBConnectionType.usb
                  ? 'USB Device'
                  : '${_hostController.text.trim()}:${_portController.text.trim()}',
              prefixIcon: const Icon(Icons.label),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            value: _markAsFavorite,
            onChanged: (value) => setState(() => _markAsFavorite = value),
            title: const Text('Mark as favorite'),
            subtitle: const Text('Pin this device at the top of your list'),
            secondary: Icon(
              _markAsFavorite ? Icons.star : Icons.star_border,
              color: _markAsFavorite ? Colors.amber : null,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.check_circle_outline,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Ready to connect! Click "Connect" to establish connection.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildControls(BuildContext context, ControlsDetails details) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          if (_currentStep > 0)
            TextButton(
              onPressed: _isConnecting ? null : details.onStepCancel,
              child: const Text('Back'),
            ),
          const Spacer(),
          if (_currentStep < 2)
            FilledButton(
              onPressed: _isConnecting ? null : details.onStepContinue,
              child: const Text('Next'),
            )
          else
            FilledButton.icon(
              onPressed: _isConnecting ? null : _onConnect,
              icon: _isConnecting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link),
              label: Text(_isConnecting ? 'Connecting...' : 'Connect'),
            ),
        ],
      ),
    );
  }

  void _onStepContinue() {
    setState(() {
      _errorMessage = null;
      if (_currentStep < 2) {
        // Validate current step
        if (_currentStep == 1) {
          if (_selectedType != ADBConnectionType.usb) {
            if (_hostController.text.trim().isEmpty) {
              _errorMessage = 'Please enter device IP address';
              return;
            }
            if (_selectedType == ADBConnectionType.pairing) {
              if (_pairingCodeController.text.trim().isEmpty) {
                _errorMessage = 'Please enter pairing code';
                return;
              }
            }
          }
        }
        _currentStep++;
      }
    });
  }

  void _onStepCancel() {
    setState(() {
      _errorMessage = null;
      if (_currentStep > 0) {
        _currentStep--;
      }
    });
  }

  Future<void> _onConnect() async {
    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    try {
      final host = _hostController.text.trim();
      final port = int.tryParse(_portController.text.trim()) ?? 5555;
      final label = _saveDevice && _labelController.text.trim().isNotEmpty
          ? _labelController.text.trim()
          : null;

      widget.onConnect(host, port, _selectedType, label);
      
      if (mounted) {
        Navigator.of(context).pop({
          'save': _saveDevice,
          'favorite': _markAsFavorite,
          'label': label,
          'host': host,
          'port': port,
          'type': _selectedType,
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Connection failed: $e';
        _isConnecting = false;
      });
    }
  }
}
