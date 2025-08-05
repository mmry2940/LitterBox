import 'package:flutter/material.dart';

class HostTileWithRetry extends StatefulWidget {
  final dynamic host;
  final Function(String) onDeviceSelected;
  const HostTileWithRetry(
      {Key? key, required this.host, required this.onDeviceSelected})
      : super(key: key);

  @override
  State<HostTileWithRetry> createState() => _HostTileWithRetryState();
}

class _HostTileWithRetryState extends State<HostTileWithRetry> {
  late Future<String?> _hostNameFuture;
  static const Duration _timeout = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    _resolveHostName();
  }

  void _resolveHostName() {
    setState(() {
      _hostNameFuture = Future.any([
        widget.host.hostName,
        Future.delayed(_timeout, () => null),
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _hostNameFuture,
      builder: (context, snapshot) {
        String hostName = 'Unknown Device';
        bool showRetry = false;

        if (snapshot.connectionState == ConnectionState.done) {
          if (snapshot.hasData &&
              snapshot.data != null &&
              snapshot.data!.isNotEmpty) {
            hostName = snapshot.data!;
          } else if (!snapshot.hasData) {
            hostName = 'Timed out';
            showRetry = true;
          }
        } else if (snapshot.connectionState == ConnectionState.waiting) {
          hostName = 'Resolving...';
        }

        final displayName = hostName != 'Unknown Device' &&
                hostName != 'Resolving...' &&
                hostName != 'Timed out'
            ? hostName
            : 'Device ${widget.host.address}';

        return ListTile(
          leading: const Icon(Icons.computer),
          title: Row(
            children: [
              Expanded(child: Text(displayName)),
              if (showRetry)
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: 'Retry hostname',
                  onPressed: _resolveHostName,
                ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('IP: ${widget.host.address}'),
              if (hostName != 'Unknown Device' &&
                  hostName != displayName &&
                  hostName != 'Timed out')
                Text('Hostname: $hostName'),
              Text(
                  'Response: ${widget.host.responseTime?.inMilliseconds ?? '?'}ms'),
            ],
          ),
          isThreeLine: true,
          onTap: () {
            Navigator.pop(context);
            widget.onDeviceSelected(widget.host.address);
          },
        );
      },
    );
  }
}
