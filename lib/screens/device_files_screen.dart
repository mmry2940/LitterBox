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
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

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

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchQuery = '';
        _searchController.clear();
      }
    });
  }

  void _updateSearchQuery(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
    });
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

  Future<void> _deleteSelected() async {
    if (_selectedIndexes.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text('Delete ${_selectedIndexes.length} selected item(s)?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _loading = true);

    try {
      for (final index in _selectedIndexes) {
        final entry = _entries![index];
        final filePath = _currentPath == '/'
            ? '/${entry.name}'
            : '$_currentPath/${entry.name}';

        final command = entry.isDir ? 'rm -rf' : 'rm';
        final session = await widget.sshClient!
            .execute('$command "${filePath.replaceAll('"', '\\"')}"');
        await session.stdout.cast<List<int>>().transform(utf8.decoder).join();
        final stderr = await session.stderr
            .cast<List<int>>()
            .transform(utf8.decoder)
            .join();

        if (stderr.isNotEmpty) {
          throw Exception('Failed to delete ${entry.name}: $stderr');
        }
      }

      _showSnackBar('${_selectedIndexes.length} item(s) deleted', Colors.green);
      setState(() => _selectedIndexes.clear());
      _fetchFiles(_currentPath);
    } catch (e) {
      _showSnackBar('Delete failed: $e', Colors.red);
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _renameFile(int index) async {
    final entry = _entries![index];
    final controller = TextEditingController(text: entry.name);

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Rename ${entry.isDir ? 'Folder' : 'File'}'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'New name',
            border: OutlineInputBorder(),
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
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty || newName == entry.name) return;

    setState(() => _loading = true);

    try {
      final oldPath = _currentPath == '/'
          ? '/${entry.name}'
          : '$_currentPath/${entry.name}';
      final newPath =
          _currentPath == '/' ? '/$newName' : '$_currentPath/$newName';

      final session = await widget.sshClient!.execute(
          'mv "${oldPath.replaceAll('"', '\\"')}" "${newPath.replaceAll('"', '\\"')}"');
      await session.stdout.cast<List<int>>().transform(utf8.decoder).join();
      final stderr =
          await session.stderr.cast<List<int>>().transform(utf8.decoder).join();

      if (stderr.isNotEmpty) {
        throw Exception(stderr);
      }

      _showSnackBar('Renamed to "$newName"', Colors.green);
      _fetchFiles(_currentPath);
    } catch (e) {
      _showSnackBar('Rename failed: $e', Colors.red);
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();

    final folderName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Folder'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Folder name',
            border: OutlineInputBorder(),
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
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (folderName == null || folderName.isEmpty) return;

    setState(() => _loading = true);

    try {
      final folderPath =
          _currentPath == '/' ? '/$folderName' : '$_currentPath/$folderName';

      final session = await widget.sshClient!
          .execute('mkdir -p "${folderPath.replaceAll('"', '\\"')}"');
      await session.stdout.cast<List<int>>().transform(utf8.decoder).join();
      final stderr =
          await session.stderr.cast<List<int>>().transform(utf8.decoder).join();

      if (stderr.isNotEmpty) {
        throw Exception(stderr);
      }

      _showSnackBar('Folder "$folderName" created', Colors.green);
      _fetchFiles(_currentPath);
    } catch (e) {
      _showSnackBar('Create folder failed: $e', Colors.red);
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _createArchive() async {
    if (_selectedIndexes.isEmpty) return;

    final controller = TextEditingController();

    final archiveName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Archive'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Archive ${_selectedIndexes.length} selected item(s)'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Archive name (without extension)',
                border: OutlineInputBorder(),
                suffixText: '.tar.gz',
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (archiveName == null || archiveName.isEmpty) return;

    setState(() => _loading = true);

    try {
      final fileNames = _selectedIndexes.map((i) => _entries![i].name).toList();
      final filesArg =
          fileNames.map((name) => '"${name.replaceAll('"', '\\"')}"').join(' ');

      final session = await widget.sshClient!.execute(
          'cd "${_currentPath.replaceAll('"', '\\"')}" && tar -czf "${archiveName.replaceAll('"', '\\"')}.tar.gz" $filesArg');
      await session.stdout.cast<List<int>>().transform(utf8.decoder).join();
      final stderr =
          await session.stderr.cast<List<int>>().transform(utf8.decoder).join();

      if (stderr.isNotEmpty) {
        throw Exception(stderr);
      }

      _showSnackBar('Archive "$archiveName.tar.gz" created', Colors.green);
      setState(() => _selectedIndexes.clear());
      _fetchFiles(_currentPath);
    } catch (e) {
      _showSnackBar('Create archive failed: $e', Colors.red);
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _extractArchive(int index) async {
    final entry = _entries![index];
    if (!entry.name.endsWith('.tar.gz') && !entry.name.endsWith('.zip')) {
      _showSnackBar(
          'Only .tar.gz and .zip archives are supported', Colors.orange);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Extract Archive'),
        content: Text('Extract "${entry.name}" to current directory?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Extract'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _loading = true);

    try {
      String command;
      if (entry.name.endsWith('.tar.gz')) {
        command =
            'cd "${_currentPath.replaceAll('"', '\\"')}" && tar -xzf "${entry.name.replaceAll('"', '\\"')}"';
      } else {
        command =
            'cd "${_currentPath.replaceAll('"', '\\"')}" && unzip "${entry.name.replaceAll('"', '\\"')}"';
      }

      final session = await widget.sshClient!.execute(command);
      await session.stdout.cast<List<int>>().transform(utf8.decoder).join();
      final stderr =
          await session.stderr.cast<List<int>>().transform(utf8.decoder).join();

      if (stderr.isNotEmpty && !stderr.contains('inflating:')) {
        throw Exception(stderr);
      }

      _showSnackBar('Archive "${entry.name}" extracted', Colors.green);
      _fetchFiles(_currentPath);
    } catch (e) {
      _showSnackBar('Extract failed: $e', Colors.red);
    } finally {
      setState(() => _loading = false);
    }
  }

  void _selectAll() {
    setState(() {
      final filteredEntries = _getFilteredEntries();
      if (_selectedIndexes.length == filteredEntries.length) {
        _selectedIndexes.clear();
      } else {
        _selectedIndexes.clear();
        for (int i = 0; i < filteredEntries.length; i++) {
          final originalIdx = _entries!.indexOf(filteredEntries[i]);
          _selectedIndexes.add(originalIdx);
        }
      }
    });
  }

  List<_FileEntry> _getFilteredEntries() {
    if (_entries == null) return [];
    if (_searchQuery.isEmpty) return _entries!;
    return _entries!
        .where((entry) => entry.name.toLowerCase().contains(_searchQuery))
        .toList();
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
            child: Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Refresh',
                        onPressed: () => _fetchFiles(_currentPath),
                      ),
                      IconButton(
                        icon: Icon(
                          _isSearching ? Icons.search_off : Icons.search,
                          color: Colors.black87,
                        ),
                        tooltip: _isSearching ? 'Close search' : 'Search files',
                        onPressed: _toggleSearch,
                      ),
                      IconButton(
                        icon: Icon(
                          _showHidden ? Icons.visibility_off : Icons.visibility,
                          color: Colors.black87,
                        ),
                        tooltip: _showHidden
                            ? 'Hide hidden files'
                            : 'Show hidden files',
                        onPressed: _toggleShowHidden,
                      ),
                    ],
                  ),
                ),
                if (_isSearching)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        hintText: 'Search files and folders...',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: _updateSearchQuery,
                      autofocus: true,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          // File/folder list
          Expanded(
            child: () {
              final filteredEntries = _getFilteredEntries();
              if (filteredEntries.isEmpty && _searchQuery.isNotEmpty) {
                return const Center(
                  child: Text('No files match your search',
                      style: TextStyle(color: Colors.grey, fontSize: 16)),
                );
              }
              return ListView.separated(
                itemCount: filteredEntries.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, idx) {
                  final entry = filteredEntries[idx];
                  final originalIdx = _entries!.indexOf(entry);
                  final selected = _selectedIndexes.contains(originalIdx);
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
                        entry.isDir ? Icons.folder : _getFileIcon(entry.name),
                        color: entry.isDir
                            ? Colors.amber
                            : _getFileColor(entry.name),
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
                          Icon(Icons.lock,
                              size: 14, color: Colors.grey.shade800),
                          const SizedBox(width: 4),
                          Text(entry.permissions,
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.black87)),
                        ],
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          switch (value) {
                            case 'rename':
                              _renameFile(originalIdx);
                              break;
                            case 'extract':
                              _extractArchive(originalIdx);
                              break;
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'rename',
                            child: Row(
                              children: [
                                Icon(Icons.edit, size: 16),
                                SizedBox(width: 8),
                                Text('Rename'),
                              ],
                            ),
                          ),
                          if (entry.name.endsWith('.tar.gz') ||
                              entry.name.endsWith('.zip'))
                            const PopupMenuItem(
                              value: 'extract',
                              child: Row(
                                children: [
                                  Icon(Icons.archive, size: 16),
                                  SizedBox(width: 8),
                                  Text('Extract'),
                                ],
                              ),
                            ),
                        ],
                      ),
                      selected: selected,
                      onTap: () {
                        setState(() {
                          if (selected) {
                            _selectedIndexes.remove(originalIdx);
                          } else {
                            _selectedIndexes.add(originalIdx);
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
              );
            }(),
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
                    icon: const Icon(Icons.select_all, color: Colors.black87),
                    tooltip: 'Select All',
                    onPressed: _selectAll,
                  ),
                  const SizedBox(width: 8),
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
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    tooltip: 'Delete',
                    onPressed:
                        _selectedIndexes.isNotEmpty ? _deleteSelected : null,
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.create_new_folder,
                        color: Colors.green),
                    tooltip: 'New Folder',
                    onPressed: _createFolder,
                  ),
                  IconButton(
                    icon: const Icon(Icons.archive, color: Colors.blue),
                    tooltip: 'Create Archive',
                    onPressed:
                        _selectedIndexes.isNotEmpty ? _createArchive : null,
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

  IconData _getFileIcon(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    switch (ext) {
      case 'txt':
      case 'md':
      case 'log':
        return Icons.description;
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'bmp':
        return Icons.image;
      case 'mp4':
      case 'avi':
      case 'mkv':
      case 'mov':
        return Icons.video_file;
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'ogg':
        return Icons.audio_file;
      case 'zip':
      case 'tar':
      case 'gz':
      case 'rar':
      case '7z':
        return Icons.archive;
      case 'apk':
        return Icons.android;
      case 'deb':
      case 'rpm':
        return Icons.install_desktop;
      case 'sh':
      case 'bash':
      case 'bat':
        return Icons.terminal;
      case 'json':
      case 'xml':
      case 'yaml':
      case 'yml':
        return Icons.code;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getFileColor(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    switch (ext) {
      case 'txt':
      case 'md':
      case 'log':
        return Colors.grey;
      case 'pdf':
        return Colors.red;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'bmp':
        return Colors.purple;
      case 'mp4':
      case 'avi':
      case 'mkv':
      case 'mov':
        return Colors.indigo;
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'ogg':
        return Colors.orange;
      case 'zip':
      case 'tar':
      case 'gz':
      case 'rar':
      case '7z':
        return Colors.brown;
      case 'apk':
        return Colors.green;
      case 'deb':
      case 'rpm':
        return Colors.blue;
      case 'sh':
      case 'bash':
      case 'bat':
        return Colors.black;
      case 'json':
      case 'xml':
      case 'yaml':
      case 'yml':
        return Colors.teal;
      default:
        return Colors.blueGrey;
    }
  }
}
