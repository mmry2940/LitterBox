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
  String _currentPath = '/home/';
  List<_FileEntry>? _entries;
  String? _error;
  bool _loading = false;
  bool _showHidden = false;

  // Clipboard functionality
  List<String> _clipboard = [];
  bool _clipboardIsCut = false;

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

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _copySelected() {
    if (_selectedIndexes.isEmpty) return;

    _clipboard = _selectedIndexes.map((i) {
      final entry = _entries![i];
      return _currentPath == '/'
          ? '/${entry.name}'
          : '$_currentPath/${entry.name}';
    }).toList();
    _clipboardIsCut = false;

    _showSnackBar(
        '${_clipboard.length} item(s) copied to clipboard', Colors.blue);
    setState(() {
      _selectedIndexes.clear();
    });
  }

  void _cutSelected() {
    if (_selectedIndexes.isEmpty) return;

    _clipboard = _selectedIndexes.map((i) {
      final entry = _entries![i];
      return _currentPath == '/'
          ? '/${entry.name}'
          : '$_currentPath/${entry.name}';
    }).toList();
    _clipboardIsCut = true;

    _showSnackBar(
        '${_clipboard.length} item(s) cut to clipboard', Colors.orange);
    setState(() {
      _selectedIndexes.clear();
    });
  }

  Future<void> _pasteFromClipboard() async {
    if (_clipboard.isEmpty) return;

    setState(() {
      _loading = true;
    });

    try {
      for (final sourcePath in _clipboard) {
        final fileName = sourcePath.split('/').last;
        final targetPath =
            _currentPath == '/' ? '/$fileName' : '$_currentPath/$fileName';

        if (_clipboardIsCut) {
          final session = await widget.sshClient!.execute(
              'mv "${sourcePath.replaceAll('"', '\\"')}" "${targetPath.replaceAll('"', '\\"')}"');
          await session.stdout.cast<List<int>>().transform(utf8.decoder).join();
          await session.stderr.cast<List<int>>().transform(utf8.decoder).join();
          session.exitCode;
        } else {
          final session = await widget.sshClient!.execute(
              'cp -r "${sourcePath.replaceAll('"', '\\"')}" "${targetPath.replaceAll('"', '\\"')}"');
          await session.stdout.cast<List<int>>().transform(utf8.decoder).join();
          await session.stderr.cast<List<int>>().transform(utf8.decoder).join();
          session.exitCode;
        }
      }

      if (_clipboardIsCut) {
        _clipboard.clear();
        _clipboardIsCut = false;
      }

      _showSnackBar(
          '${_clipboardIsCut ? 'Move' : 'Copy'} completed successfully',
          Colors.green);
      _fetchFiles(_currentPath); // Refresh the file list
    } catch (e) {
      _showSnackBar(
          '${_clipboardIsCut ? 'Move' : 'Copy'} failed: $e', Colors.red);
    } finally {
      setState(() {
        _loading = false;
      });
    }
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
      final output =
          await session.stdout.cast<List<int>>().transform(utf8.decoder).join();
      final lines =
          output.split('\n').where((l) => l.trim().isNotEmpty).toList();
      // Skip total line if present
      final fileLines = lines.isNotEmpty && lines.first.startsWith('total')
          ? lines.sublist(1)
          : lines;
      final entries = fileLines
          .map(_FileEntry.parse)
          .where((e) => e != null)
          .cast<_FileEntry>()
          .toList();
      // Sort: folders first (ascending), then files (ascending)
      List<_FileEntry> sortedEntries = _showHidden
          ? entries
          : entries.where((e) => !e.name.startsWith('.')).toList();
      sortedEntries.sort((a, b) {
        if (a.isDir && !b.isDir) return -1;
        if (!a.isDir && b.isDir) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      setState(() {
        _entries = sortedEntries;
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
    return PopScope(
      canPop: _currentPath == '/',
      onPopInvoked: (didPop) {
        if (!didPop && _currentPath != '/') {
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
      },
      child: _buildFileManagerBody(),
    );
  }

  Widget _buildFileManagerBody() {
    if (widget.loading || _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.error != null) {
      return Center(child: Text('SSH Error: ${widget.error}'));
    }
    if (_error != null) {
      return Center(child: Text('Error: $_error'));
    }
    if (_entries != null) {
      return Column(
        children: [
          // Modern path bar
          Material(
            color: Colors.blueGrey.shade50,
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _showHidden ? Icons.visibility_off : Icons.visibility,
                      color: Colors.black87,
                    ),
                    tooltip:
                        _showHidden ? 'Hide hidden files' : 'Show hidden files',
                    onPressed: _toggleShowHidden,
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          // File/folder list
          Expanded(
            child: ListView.separated(
              itemCount: _entries!.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, idx) {
                final entry = _entries![idx];
                final selected = _selectedIndexes.contains(idx);
                return Card(
                  color: selected ? Colors.blue.shade50 : Colors.white,
                  elevation: selected ? 2 : 0,
                  margin:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: selected
                        ? BorderSide(color: Colors.blue.shade200, width: 1.5)
                        : BorderSide(color: Colors.grey.shade200, width: 1),
                  ),
                  child: ListTile(
                    leading: Icon(
                      entry.isDir ? Icons.folder : Icons.insert_drive_file,
                      color: entry.isDir ? Colors.amber : Colors.blueGrey,
                      size: 28,
                    ),
                    title: Text(
                      entry.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                        color: Colors.black87,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Row(
                      children: [
                        Icon(Icons.calendar_today,
                            size: 14, color: Colors.grey.shade800),
                        const SizedBox(width: 4),
                        Text(entry.modified,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black87)),
                        const SizedBox(width: 12),
                        Icon(Icons.sd_storage,
                            size: 14, color: Colors.grey.shade800),
                        const SizedBox(width: 4),
                        Text(entry.size,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black87)),
                        const SizedBox(width: 12),
                        Icon(Icons.lock, size: 14, color: Colors.grey.shade800),
                        const SizedBox(width: 4),
                        Text(entry.permissions,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black87)),
                      ],
                    ),
                    selected: selected,
                    onTap: () {
                      setState(() {
                        if (selected) {
                          _selectedIndexes.remove(idx);
                        } else {
                          _selectedIndexes.add(idx);
                        }
                      });
                    },
                    onLongPress: entry.isDir
                        ? () => _navigateTo(
                              _currentPath == '/'
                                  ? '/${entry.name}'
                                  : '$_currentPath/${entry.name}',
                            )
                        : null,
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
                    icon: const Icon(Icons.copy, color: Colors.black87),
                    tooltip: 'Copy',
                    onPressed:
                        _selectedIndexes.isNotEmpty ? _copySelected : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.content_cut, color: Colors.black87),
                    tooltip: 'Cut',
                    onPressed:
                        _selectedIndexes.isNotEmpty ? _cutSelected : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.paste, color: Colors.black87),
                    tooltip: 'Paste',
                    onPressed:
                        _clipboard.isNotEmpty ? _pasteFromClipboard : null,
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
}
