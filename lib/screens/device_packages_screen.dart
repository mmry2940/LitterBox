import 'package:flutter/material.dart';
import 'package:dartssh2/dartssh2.dart';
import 'dart:convert';

enum PackageManager { dpkg, rpm, pacman, apk, pkg, unknown }

enum PackageStatus { installed, upgradable, available, removed, unknown }

enum SortOption { name, version, size, status, arch }

class PackageInfo {
  final String name;
  final String version;
  final String architecture;
  final String description;
  final String status;
  final String? size;
  final String? section;
  final String? maintainer;
  final String? homepage;
  final bool isInstalled;
  final bool isUpgradable;

  PackageInfo({
    required this.name,
    required this.version,
    required this.architecture,
    required this.description,
    required this.status,
    this.size,
    this.section,
    this.maintainer,
    this.homepage,
    this.isInstalled = true,
    this.isUpgradable = false,
  });

  Map<String, String> toMap() {
    return {
      'Name': name,
      'Version': version,
      'Arch': architecture,
      'Description': description,
      'Status': status,
      'Size': size ?? 'Unknown',
      'Section': section ?? 'Unknown',
      'Maintainer': maintainer ?? 'Unknown',
      'Homepage': homepage ?? '',
    };
  }
}

class DevicePackagesScreen extends StatefulWidget {
  final SSHClient? sshClient;
  final String? error;
  final bool loading;
  const DevicePackagesScreen({
    super.key,
    this.sshClient,
    this.error,
    this.loading = false,
  });

  @override
  State<DevicePackagesScreen> createState() => _DevicePackagesScreenState();
}

class _DevicePackagesScreenState extends State<DevicePackagesScreen> {
  List<PackageInfo>? _packages;
  List<PackageInfo>? _filteredPackages;
  List<PackageInfo>? _availablePackages;
  String? _error;
  bool _loading = false;
  String _search = '';
  SortOption _sortColumn = SortOption.name;
  bool _sortAsc = true;
  PackageManager _detectedPackageManager = PackageManager.unknown;
  String _selectedFilter = 'All';
  bool _showAvailablePackages = false;
  late final TextEditingController _searchController;
  final Set<int> _selectedRows = {};

  // Available filters
  final List<String> _filters = [
    'All',
    'Installed',
    'Upgradable',
    'System',
    'User',
    'Libraries',
    'Development',
    'Utilities',
    'Games',
    'Graphics',
    'Network',
    'Audio/Video'
  ];

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    if (widget.sshClient != null) {
      _detectPackageManagerAndFetch();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(DevicePackagesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.key != oldWidget.key && widget.sshClient != null) {
      _detectPackageManagerAndFetch();
    }
  }

  Future<void> _detectPackageManagerAndFetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Detect package manager
      final packageManager = await _detectPackageManager();
      setState(() {
        _detectedPackageManager = packageManager;
      });

      // Fetch packages based on detected manager
      await _fetchPackages(packageManager);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<PackageManager> _detectPackageManager() async {
    // Try different package managers in order of likelihood
    final managers = [
      {'manager': PackageManager.dpkg, 'command': 'which dpkg'},
      {'manager': PackageManager.rpm, 'command': 'which rpm'},
      {'manager': PackageManager.pacman, 'command': 'which pacman'},
      {'manager': PackageManager.apk, 'command': 'which apk'},
      {'manager': PackageManager.pkg, 'command': 'which pkg'},
    ];

    for (final manager in managers) {
      try {
        final session =
            await widget.sshClient!.execute(manager['command'] as String);
        final output = await session.stdout
            .cast<List<int>>()
            .transform(utf8.decoder)
            .join();
        if (output.trim().isNotEmpty) {
          return manager['manager'] as PackageManager;
        }
      } catch (e) {
        // Continue to next manager
      }
    }
    return PackageManager.unknown;
  }

  Future<void> _fetchPackages(PackageManager manager) async {
    switch (manager) {
      case PackageManager.dpkg:
        await _fetchDpkgPackages();
        break;
      case PackageManager.rpm:
        await _fetchRpmPackages();
        break;
      case PackageManager.pacman:
        await _fetchPacmanPackages();
        break;
      case PackageManager.apk:
        await _fetchApkPackages();
        break;
      case PackageManager.pkg:
        await _fetchPkgPackages();
        break;
      case PackageManager.unknown:
        throw Exception('No supported package manager found');
    }
  }

  Future<void> _fetchDpkgPackages() async {
    final session = await widget.sshClient!.execute('dpkg -l');
    final output =
        await session.stdout.cast<List<int>>().transform(utf8.decoder).join();
    final lines = output.split('\n').where((l) => l.trim().isNotEmpty).toList();

    int headerIdx = lines.indexWhere((l) => l.startsWith('||/'));
    if (headerIdx == -1 || headerIdx + 1 >= lines.length) {
      throw Exception('No package data');
    }

    final packages = <PackageInfo>[];
    for (final line in lines.sublist(headerIdx + 1)) {
      if (line.length < 3 ||
          !RegExp(r'^(ii|rc|un|hi|pn|pi|iU|iF|iH|iW|iC|iR|iP|iB|iA|iS|iT|iD|iE|iG|iL|iM|iN|iO|iQ|iV|iX|iY|iZ|iJ|iK|iL|iM|iN|iO|iP|iQ|iR|iS|iT|iU|iV|iW|iX|iY|iZ)')
              .hasMatch(line.substring(0, 2))) {
        continue;
      }

      final cols = line.split(RegExp(r'\s+'));
      if (cols.length < 5) continue;

      packages.add(PackageInfo(
        name: cols[1],
        version: cols[2],
        architecture: cols[3],
        description: cols.sublist(4).join(' '),
        status: cols[0],
        isInstalled: cols[0] == 'ii',
        isUpgradable: false, // Would need apt list --upgradable for this
      ));
    }

    setState(() {
      _packages = packages;
      _applyFilterSort();
      _loading = false;
    });
  }

  Future<void> _fetchRpmPackages() async {
    final session = await widget.sshClient!.execute(
        'rpm -qa --queryformat "%{NAME}|%{VERSION}-%{RELEASE}|%{ARCH}|%{SUMMARY}|%{SIZE}\\n"');
    final output =
        await session.stdout.cast<List<int>>().transform(utf8.decoder).join();
    final lines = output.split('\n').where((l) => l.trim().isNotEmpty).toList();

    final packages = <PackageInfo>[];
    for (final line in lines) {
      final parts = line.split('|');
      if (parts.length < 4) continue;

      packages.add(PackageInfo(
        name: parts[0],
        version: parts[1],
        architecture: parts[2],
        description: parts[3],
        status: 'installed',
        size: parts.length > 4 ? parts[4] : null,
        isInstalled: true,
      ));
    }

    setState(() {
      _packages = packages;
      _applyFilterSort();
      _loading = false;
    });
  }

  Future<void> _fetchPacmanPackages() async {
    final session = await widget.sshClient!.execute('pacman -Q');
    final output =
        await session.stdout.cast<List<int>>().transform(utf8.decoder).join();
    final lines = output.split('\n').where((l) => l.trim().isNotEmpty).toList();

    final packages = <PackageInfo>[];
    for (final line in lines) {
      final parts = line.split(' ');
      if (parts.length < 2) continue;

      packages.add(PackageInfo(
        name: parts[0],
        version: parts[1],
        architecture: 'unknown',
        description: 'Pacman package',
        status: 'installed',
        isInstalled: true,
      ));
    }

    setState(() {
      _packages = packages;
      _applyFilterSort();
      _loading = false;
    });
  }

  Future<void> _fetchApkPackages() async {
    final session = await widget.sshClient!.execute('apk list --installed');
    final output =
        await session.stdout.cast<List<int>>().transform(utf8.decoder).join();
    final lines = output.split('\n').where((l) => l.trim().isNotEmpty).toList();

    final packages = <PackageInfo>[];
    for (final line in lines) {
      if (!line.contains('-')) continue;

      final parts = line.split(' ');
      final nameVersion = parts[0].split('-');
      if (nameVersion.length < 2) continue;

      packages.add(PackageInfo(
        name: nameVersion.sublist(0, nameVersion.length - 1).join('-'),
        version: nameVersion.last,
        architecture: 'unknown',
        description: 'Alpine package',
        status: 'installed',
        isInstalled: true,
      ));
    }

    setState(() {
      _packages = packages;
      _applyFilterSort();
      _loading = false;
    });
  }

  Future<void> _fetchPkgPackages() async {
    final session = await widget.sshClient!.execute('pkg info');
    final output =
        await session.stdout.cast<List<int>>().transform(utf8.decoder).join();
    final lines = output.split('\n').where((l) => l.trim().isNotEmpty).toList();

    final packages = <PackageInfo>[];
    for (final line in lines) {
      final parts = line.split('-');
      if (parts.length < 2) continue;

      packages.add(PackageInfo(
        name: parts.sublist(0, parts.length - 1).join('-'),
        version: parts.last,
        architecture: 'unknown',
        description: 'FreeBSD package',
        status: 'installed',
        isInstalled: true,
      ));
    }

    setState(() {
      _packages = packages;
      _applyFilterSort();
      _loading = false;
    });
  }

  void _applyFilterSort() {
    List<PackageInfo> filtered = _packages ?? [];

    // Apply search filter
    if (_search.isNotEmpty) {
      filtered = filtered.where((p) {
        final searchLower = _search.toLowerCase();
        return p.name.toLowerCase().contains(searchLower) ||
            p.description.toLowerCase().contains(searchLower) ||
            p.version.toLowerCase().contains(searchLower) ||
            p.status.toLowerCase().contains(searchLower);
      }).toList();
    }

    // Apply category filter
    if (_selectedFilter != 'All') {
      filtered = filtered.where((p) {
        switch (_selectedFilter) {
          case 'Installed':
            return p.isInstalled;
          case 'Upgradable':
            return p.isUpgradable;
          case 'System':
            return p.section?.toLowerCase().contains('base') == true ||
                p.section?.toLowerCase().contains('essential') == true ||
                p.name.startsWith('lib') ||
                p.name.startsWith('systemd');
          case 'User':
            return !(p.section?.toLowerCase().contains('base') == true ||
                p.section?.toLowerCase().contains('essential') == true ||
                p.name.startsWith('lib') ||
                p.name.startsWith('systemd'));
          case 'Libraries':
            return p.name.startsWith('lib') ||
                p.section?.toLowerCase().contains('libs') == true;
          case 'Development':
            return p.section?.toLowerCase().contains('devel') == true ||
                p.name.contains('dev') ||
                p.name.contains('compiler') ||
                p.name.contains('build');
          case 'Utilities':
            return p.section?.toLowerCase().contains('utils') == true ||
                p.section?.toLowerCase().contains('admin') == true;
          case 'Games':
            return p.section?.toLowerCase().contains('games') == true;
          case 'Graphics':
            return p.section?.toLowerCase().contains('graphics') == true ||
                p.name.contains('image') ||
                p.name.contains('video');
          case 'Network':
            return p.section?.toLowerCase().contains('net') == true ||
                p.name.contains('network') ||
                p.name.contains('wget') ||
                p.name.contains('curl');
          case 'Audio/Video':
            return p.section?.toLowerCase().contains('sound') == true ||
                p.section?.toLowerCase().contains('video') == true ||
                p.name.contains('audio') ||
                p.name.contains('media');
          default:
            return true;
        }
      }).toList();
    }

    // Apply sorting
    filtered.sort((a, b) {
      int result;
      switch (_sortColumn) {
        case SortOption.name:
          result = a.name.compareTo(b.name);
          break;
        case SortOption.version:
          result = a.version.compareTo(b.version);
          break;
        case SortOption.size:
          final aSize = a.size ?? '0';
          final bSize = b.size ?? '0';
          result = aSize.compareTo(bSize);
          break;
        case SortOption.status:
          result = a.status.compareTo(b.status);
          break;
        case SortOption.arch:
          result = a.architecture.compareTo(b.architecture);
          break;
      }
      return _sortAsc ? result : -result;
    });

    setState(() {
      _filteredPackages = filtered;
    });
  }

  void _onSearchChanged() {
    setState(() {
      _search = _searchController.text;
      _applyFilterSort();
    });
  }

  void _onFilterChanged(String filter) {
    setState(() {
      _selectedFilter = filter;
      _applyFilterSort();
    });
  }

  void _onSortChanged(SortOption option) {
    setState(() {
      if (_sortColumn == option) {
        _sortAsc = !_sortAsc;
      } else {
        _sortColumn = option;
        _sortAsc = true;
      }
      _applyFilterSort();
    });
  }

  void _onUninstallSelected() async {
    if (_filteredPackages == null || _selectedRows.isEmpty) return;
    final pkgs = _selectedRows.map((i) => _filteredPackages![i]).toList();
    final names = pkgs.map((p) => p.name).toList();
    String? sudoPassword;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final pwController = TextEditingController();
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Uninstall Packages'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Are you sure you want to uninstall the following packages?',
                ),
                const SizedBox(height: 8),
                ...names.map((n) => Text(n)),
                const SizedBox(height: 12),
                TextField(
                  controller: pwController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Sudo password (leave blank if not needed)',
                  ),
                  onChanged: (v) => sudoPassword = v,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  sudoPassword = pwController.text;
                  Navigator.pop(ctx, true);
                },
                child: const Text('Uninstall'),
              ),
            ],
          ),
        );
      },
    );
    if (confirmed == true && widget.sshClient != null) {
      try {
        String command;
        final joined =
            names.map((n) => "'${n.replaceAll("'", "'\\''")}'").join(' ');

        // Use appropriate uninstall command based on package manager
        switch (_detectedPackageManager) {
          case PackageManager.dpkg:
            if (sudoPassword != null && sudoPassword!.isNotEmpty) {
              command =
                  "echo '${sudoPassword!.replaceAll("'", "'\\''")}' | sudo -S apt-get remove -y $joined";
            } else {
              command = 'sudo apt-get remove -y $joined';
            }
            break;
          case PackageManager.rpm:
            if (sudoPassword != null && sudoPassword!.isNotEmpty) {
              command =
                  "echo '${sudoPassword!.replaceAll("'", "'\\''")}' | sudo -S dnf remove -y $joined";
            } else {
              command = 'sudo dnf remove -y $joined';
            }
            break;
          case PackageManager.pacman:
            if (sudoPassword != null && sudoPassword!.isNotEmpty) {
              command =
                  "echo '${sudoPassword!.replaceAll("'", "'\\''")}' | sudo -S pacman -R --noconfirm $joined";
            } else {
              command = 'sudo pacman -R --noconfirm $joined';
            }
            break;
          case PackageManager.apk:
            if (sudoPassword != null && sudoPassword!.isNotEmpty) {
              command =
                  "echo '${sudoPassword!.replaceAll("'", "'\\''")}' | sudo -S apk del $joined";
            } else {
              command = 'sudo apk del $joined';
            }
            break;
          case PackageManager.pkg:
            if (sudoPassword != null && sudoPassword!.isNotEmpty) {
              command =
                  "echo '${sudoPassword!.replaceAll("'", "'\\''")}' | sudo -S pkg remove -y $joined";
            } else {
              command = 'sudo pkg remove -y $joined';
            }
            break;
          default:
            throw Exception('Unsupported package manager for uninstall');
        }

        final session = await widget.sshClient!.execute(command);
        final output = await session.stdout
            .cast<List<int>>()
            .transform(utf8.decoder)
            .join();
        final error = await session.stderr
            .cast<List<int>>()
            .transform(utf8.decoder)
            .join();
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Uninstall Result'),
            content: SingleChildScrollView(
              child: Text(('$output\n$error').trim()),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        _selectedRows.clear();
        _detectPackageManagerAndFetch();
      } catch (e) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to uninstall: $e')));
      }
    }
  }

  Future<void> _installPackage() async {
    final controller = TextEditingController();
    final packageName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Install Package'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Package name',
            hintText: 'Enter package name to install',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Install'),
          ),
        ],
      ),
    );

    if (packageName == null || packageName.isEmpty) return;

    // Implementation for install would go here
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Install feature coming soon for $packageName')),
    );
  }

  Future<void> _updatePackages() async {
    // Implementation for update would go here
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Update feature coming soon')),
    );
  }

  Future<void> _showPackageDetails(PackageInfo package) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(package.name),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('Version', package.version),
              _buildDetailRow('Architecture', package.architecture),
              _buildDetailRow('Status', package.status),
              if (package.size != null) _buildDetailRow('Size', package.size!),
              if (package.section != null)
                _buildDetailRow('Section', package.section!),
              if (package.maintainer != null)
                _buildDetailRow('Maintainer', package.maintainer!),
              if (package.homepage != null && package.homepage!.isNotEmpty)
                _buildDetailRow('Homepage', package.homepage!),
              const SizedBox(height: 8),
              const Text('Description:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(package.description),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading || _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.error != null) {
      return Center(child: Text('SSH Error: ${widget.error}'));
    }
    if (_error != null) {
      return Center(child: Text('Error: $_error'));
    }
    if (_filteredPackages != null) {
      return Stack(
        children: [
          Column(
            children: [
              // Enhanced header with search, filters, and sorting
              Container(
                color: Colors.grey.shade50,
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Search bar
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search packages...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _search.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  _onSearchChanged();
                                },
                              )
                            : null,
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      onChanged: (_) => _onSearchChanged(),
                    ),
                    const SizedBox(height: 12),

                    // Filter and sort options
                    Row(
                      children: [
                        // Package manager indicator
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _getPackageManagerName(_detectedPackageManager),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Filter dropdown
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _selectedFilter,
                            decoration: const InputDecoration(
                              labelText: 'Filter',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            items: _filters
                                .map((filter) => DropdownMenuItem(
                                      value: filter,
                                      child: Text(filter),
                                    ))
                                .toList(),
                            onChanged: (value) {
                              if (value != null) _onFilterChanged(value);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Sort options
                        PopupMenuButton<SortOption>(
                          icon: Icon(Icons.sort, color: Colors.grey.shade700),
                          tooltip: 'Sort by',
                          onSelected: _onSortChanged,
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: SortOption.name,
                              child: Text('Name'),
                            ),
                            const PopupMenuItem(
                              value: SortOption.version,
                              child: Text('Version'),
                            ),
                            const PopupMenuItem(
                              value: SortOption.size,
                              child: Text('Size'),
                            ),
                            const PopupMenuItem(
                              value: SortOption.status,
                              child: Text('Status'),
                            ),
                            const PopupMenuItem(
                              value: SortOption.arch,
                              child: Text('Architecture'),
                            ),
                          ],
                        ),

                        // Refresh button
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          tooltip: 'Refresh',
                          onPressed: () => _detectPackageManagerAndFetch(),
                        ),
                      ],
                    ),

                    // Package count
                    if (_packages != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Showing ${_filteredPackages!.length} of ${_packages!.length} packages',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Package list
              Expanded(
                child: _filteredPackages!.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_off,
                                size: 64, color: Colors.grey),
                            SizedBox(height: 16),
                            Text('No packages found.',
                                style: TextStyle(fontSize: 16)),
                            Text('Try adjusting your search or filter.',
                                style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: _filteredPackages!.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, idx) {
                          final pkg = _filteredPackages![idx];
                          final selected = _selectedRows.contains(idx);
                          return Card(
                            color:
                                selected ? Colors.blue.shade50 : Colors.white,
                            elevation: selected ? 2 : 0,
                            margin: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: selected
                                  ? BorderSide(
                                      color: Colors.blue.shade200, width: 1.5)
                                  : BorderSide(
                                      color: Colors.grey.shade200, width: 1),
                            ),
                            child: ListTile(
                              leading: Icon(
                                _getPackageIcon(pkg),
                                color: _getPackageIconColor(pkg),
                                size: 32,
                              ),
                              title: Text(
                                pkg.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.black87,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (pkg.description.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          top: 2, bottom: 4),
                                      child: Text(
                                        pkg.description,
                                        style: const TextStyle(
                                            fontSize: 13,
                                            color: Colors.black87),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  Row(
                                    children: [
                                      Icon(
                                        pkg.isInstalled
                                            ? Icons.verified
                                            : Icons.download,
                                        size: 14,
                                        color: pkg.isInstalled
                                            ? Colors.green
                                            : Colors.orange,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(pkg.status,
                                          style: const TextStyle(fontSize: 12)),
                                      const SizedBox(width: 12),
                                      Icon(Icons.memory,
                                          size: 14, color: Colors.deepPurple),
                                      const SizedBox(width: 4),
                                      Text(pkg.version,
                                          style: const TextStyle(fontSize: 12)),
                                      const SizedBox(width: 12),
                                      Icon(Icons.architecture,
                                          size: 14, color: Colors.teal),
                                      const SizedBox(width: 4),
                                      Text(pkg.architecture,
                                          style: const TextStyle(fontSize: 12)),
                                      if (pkg.size != null) ...[
                                        const SizedBox(width: 12),
                                        Icon(Icons.storage,
                                            size: 14, color: Colors.brown),
                                        const SizedBox(width: 4),
                                        Text(pkg.size!,
                                            style:
                                                const TextStyle(fontSize: 12)),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) {
                                  switch (value) {
                                    case 'details':
                                      _showPackageDetails(pkg);
                                      break;
                                    case 'select':
                                      setState(() {
                                        if (selected) {
                                          _selectedRows.remove(idx);
                                        } else {
                                          _selectedRows.add(idx);
                                        }
                                      });
                                      break;
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'details',
                                    child: Row(
                                      children: [
                                        Icon(Icons.info, size: 16),
                                        SizedBox(width: 8),
                                        Text('Details'),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'select',
                                    child: Row(
                                      children: [
                                        Icon(
                                          selected
                                              ? Icons.check_box
                                              : Icons.check_box_outline_blank,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(selected ? 'Deselect' : 'Select'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              selected: selected,
                              onTap: () {
                                setState(() {
                                  if (selected) {
                                    _selectedRows.remove(idx);
                                  } else {
                                    _selectedRows.add(idx);
                                  }
                                });
                              },
                              onLongPress: () => _showPackageDetails(pkg),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),

          // Floating action buttons
          Positioned(
            bottom: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_selectedRows.isNotEmpty) ...[
                  FloatingActionButton.extended(
                    heroTag: 'uninstall',
                    icon: const Icon(Icons.delete),
                    label: Text('Uninstall (${_selectedRows.length})'),
                    backgroundColor: Colors.red,
                    onPressed: _onUninstallSelected,
                  ),
                  const SizedBox(height: 8),
                ],
                FloatingActionButton(
                  heroTag: 'install',
                  child: const Icon(Icons.add),
                  tooltip: 'Install Package',
                  onPressed: _installPackage,
                ),
              ],
            ),
          ),
        ],
      );
    }
    if (widget.sshClient == null) {
      return const Center(child: Text('Waiting for SSH connection...'));
    }
    return const Center(child: Text('No packages loaded.'));
  }

  String _getPackageManagerName(PackageManager manager) {
    switch (manager) {
      case PackageManager.dpkg:
        return 'APT/DPKG';
      case PackageManager.rpm:
        return 'DNF/RPM';
      case PackageManager.pacman:
        return 'Pacman';
      case PackageManager.apk:
        return 'APK';
      case PackageManager.pkg:
        return 'PKG';
      case PackageManager.unknown:
        return 'Unknown';
    }
  }

  IconData _getPackageIcon(PackageInfo package) {
    if (package.name.startsWith('lib')) return Icons.library_books;
    if (package.name.contains('dev') || package.name.contains('compiler'))
      return Icons.code;
    if (package.name.contains('game')) return Icons.sports_esports;
    if (package.name.contains('media') ||
        package.name.contains('video') ||
        package.name.contains('audio')) return Icons.play_circle;
    if (package.name.contains('network') || package.name.contains('net'))
      return Icons.network_check;
    if (package.name.contains('system') || package.name.contains('kernel'))
      return Icons.settings_system_daydream;
    if (package.name.contains('security') ||
        package.name.contains('ssl') ||
        package.name.contains('crypto')) return Icons.security;
    return Icons.apps;
  }

  Color _getPackageIconColor(PackageInfo package) {
    if (package.name.startsWith('lib')) return Colors.blue;
    if (package.name.contains('dev') || package.name.contains('compiler'))
      return Colors.green;
    if (package.name.contains('game')) return Colors.purple;
    if (package.name.contains('media') ||
        package.name.contains('video') ||
        package.name.contains('audio')) return Colors.red;
    if (package.name.contains('network') || package.name.contains('net'))
      return Colors.orange;
    if (package.name.contains('system') || package.name.contains('kernel'))
      return Colors.grey;
    if (package.name.contains('security') ||
        package.name.contains('ssl') ||
        package.name.contains('crypto')) return Colors.indigo;
    return Colors.blueGrey;
  }
}
