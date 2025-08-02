import 'package:flutter/material.dart';
import 'package:dartssh2/dartssh2.dart';
import 'dart:convert';

// File entry model for file manager
class _FileEntry {
  final String permissions;
  final String size;
  final String modified;
  final String name;
  final bool isDir;
  _FileEntry({
    required this.permissions,
    required this.size,
    required this.modified,
    required this.name,
    required this.isDir,
  });

  static _FileEntry? parse(String line) {
    // Example: drwxr-xr-x  2 root root 4096 Jul 31 12:34 bin
    final parts = line.split(RegExp(r'\s+'));
    if (parts.length < 9) return null;
    final permissions = parts[0];
    final isDir = permissions.startsWith('d');
    final size = parts[4];
    final modified = '${parts[5]} ${parts[6]} ${parts[7]}';
    final fileName = parts.sublist(8).join(' ');
    return _FileEntry(
      permissions: permissions,
      size: size,
      modified: modified,
      name: fileName,
      isDir: isDir,
    );
  }
}

class DeviceFilesScreen extends StatefulWidget {
  final SSHClient? sshClient;
  final String? error;
  final bool loading;
  const DeviceFilesScreen({
    super.key,
    this.sshClient,
    this.error,
    this.loading = false,
  });

  @override
  State<DeviceFilesScreen> createState() => _DeviceFilesScreenState();
}

class _DeviceFilesScreenState extends State<DeviceFilesScreen> {
  final Set<int> _selectedIndexes = {};
  String _currentPath = '/';
  List<_FileEntry>? _entries;
  String? _error;
  bool _loading = false;
  bool _showHidden = false;
  void _navigateTo(String path) {
    setState(() {
      _currentPath = path;
      _selectedIndexes.clear();
    });
    _fetchFiles(path);
  }

  void _toggleShowHidden() {
    setState(() {
      _showHidden = !_showHidden;
      _selectedIndexes.clear();
    });
    _fetchFiles(_currentPath);
  }

  @override
  void initState() {
    super.initState();
    if (widget.sshClient != null) {
      _fetchFiles(_currentPath);
    }
  }

  @override
  void didUpdateWidget(DeviceFilesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.key != oldWidget.key && widget.sshClient != null) {
      _fetchFiles(_currentPath);
    }
  }

  Future<void> _fetchFiles(String path) async {
    setState(() {
      _loading = true;
      _error = null;
      _entries = null;
    });
    try {
      final session = await widget.sshClient!.execute(
        'ls -lAht "${path.replaceAll('"', '"')}"',
      );
      final output = await session.stdout
          .cast<List<int>>()
          .transform(utf8.decoder)
          .join();
      final lines = output
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();
      // Skip total line if present
      final fileLines = lines.isNotEmpty && lines.first.startsWith('total')
          ? lines.sublist(1)
          : lines;
      final entries = fileLines
          .map(_FileEntry.parse)
          .where((e) => e != null)
          .cast<_FileEntry>()
          .toList();
      setState(() {
        _entries = _showHidden
            ? entries
            : entries.where((e) => !e.name.startsWith('.')).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_currentPath != '/') {
          String up = _currentPath;
          if (up.endsWith('/') && up.length > 1) {
            up = up.substring(0, up.length - 1);
          }
          final lastSlash = up.lastIndexOf('/');
          String parent;
          if (lastSlash <= 0) {
            parent = '/';
          } else {
            parent = up.substring(0, lastSlash);
            if (parent.isEmpty) parent = '/';
          }
          _navigateTo(parent);
          return false;
        }
        return true;
      },
      child: _buildFileManagerBody(),
    );
  }

  Widget _buildFileManagerBody() {
    if (widget.loading || _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.error != null) {
      return Center(child: Text('SSH Error: \\${widget.error}'));
    }
    if (_error != null) {
      return Center(child: Text('Error: \\$_error'));
    }
    if (_entries != null) {
      return Column(
        children: [
          // Path bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_upward),
                  tooltip: 'Up',
                  onPressed: _currentPath != '/'
                      ? () {
                          String up = _currentPath;
                          if (up.endsWith('/') && up.length > 1) {
                            up = up.substring(0, up.length - 1);
                          }
                          final lastSlash = up.lastIndexOf('/');
                          String parent;
                          if (lastSlash <= 0) {
                            parent = '/';
                          } else {
                            parent = up.substring(0, lastSlash);
                            if (parent.isEmpty) parent = '/';
                          }
                          _navigateTo(parent);
                        }
                      : null,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Text(
                      _currentPath,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _showHidden ? Icons.visibility_off : Icons.visibility,
                  ),
                  tooltip: _showHidden
                      ? 'Hide hidden files'
                      : 'Show hidden files',
                  onPressed: _toggleShowHidden,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Table header
          Container(
            color: Colors.blueGrey.shade50,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: Row(
              children: const [
                SizedBox(width: 32),
                Expanded(
                  flex: 3,
                  child: Text(
                    'Name',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Size',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Modified',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Permissions',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: _entries!.length,
              itemBuilder: (context, idx) {
                final entry = _entries![idx];
                final selected = _selectedIndexes.contains(idx);
                return InkWell(
                  onTap: () {
                    setState(() {
                      if (selected) {
                        _selectedIndexes.remove(idx);
                      } else {
                        _selectedIndexes.add(idx);
                      }
                    });
                  },
                  onDoubleTap: entry.isDir
                      ? () => _navigateTo(
                          _currentPath == '/'
                              ? '/${entry.name}'
                              : '$_currentPath/${entry.name}',
                        )
                      : null, // TODO: file actions
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 8,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? Colors.blue.shade50 : null,
                      border: Border(
                        bottom: BorderSide(color: Colors.blueGrey.shade50),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          entry.isDir ? Icons.folder : Icons.insert_drive_file,
                          color: entry.isDir ? Colors.amber : Colors.blueGrey,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 3,
                          child: Text(
                            entry.name,
                            style: const TextStyle(fontFamily: 'monospace'),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            entry.size,
                            style: const TextStyle(fontFamily: 'monospace'),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            entry.modified,
                            style: const TextStyle(fontFamily: 'monospace'),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            entry.permissions,
                            style: const TextStyle(fontFamily: 'monospace'),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          // Bottom action bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.drive_file_rename_outline),
                    tooltip: 'Rename',
                    onPressed: _selectedIndexes.length == 1
                        ? () {
                            /* TODO */
                          }
                        : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete),
                    tooltip: 'Delete',
                    onPressed: _selectedIndexes.isNotEmpty
                        ? () {
                            /* TODO */
                          }
                        : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    tooltip: 'Copy',
                    onPressed: _selectedIndexes.isNotEmpty
                        ? () {
                            /* TODO */
                          }
                        : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.paste),
                    tooltip: 'Paste',
                    onPressed: null, // TODO: enable if clipboard
                  ),
                  IconButton(
                    icon: const Icon(Icons.drive_file_move),
                    tooltip: 'Move',
                    onPressed: _selectedIndexes.isNotEmpty
                        ? () {
                            /* TODO */
                          }
                        : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.open_in_new),
                    tooltip: 'Open',
                    onPressed: _selectedIndexes.length == 1
                        ? () {
                            /* TODO */
                          }
                        : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.share),
                    tooltip: 'Share',
                    onPressed: _selectedIndexes.length == 1
                        ? () {
                            /* TODO */
                          }
                        : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.download),
                    tooltip: 'Download',
                    onPressed: _selectedIndexes.isNotEmpty
                        ? () {
                            /* TODO */
                          }
                        : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.upload_file),
                    tooltip: 'Upload',
                    onPressed: () {
                      /* TODO */
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    if (widget.sshClient == null) {
      return const Center(child: Text('Waiting for SSH connection...'));
    }
    return const Center(child: Text('No files loaded.'));
  }

  // ...existing code ends with the build method...
}
