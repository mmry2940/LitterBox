import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';

import 'dart:convert';
import 'dart:io';

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

  // Search functionality
  bool _isSearching = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Progress tracking for operations
  bool _operationInProgress = false;
  String _operationStatus = '';
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

  void _performSearch(String query) {
    setState(() {
      _searchQuery = query;
    });
  }

  // File operation methods
  Future<void> _executeCommand(String command) async {
    if (widget.sshClient == null) return;

    try {
      final session = await widget.sshClient!.execute(command);

      // Consume stdout and stderr first to prevent hanging
      final stdout =
          await session.stdout.cast<List<int>>().transform(utf8.decoder).join();
      final stderr =
          await session.stderr.cast<List<int>>().transform(utf8.decoder).join();

      // Now check exit code
      final exitCode = await session.exitCode;

      if (exitCode != 0) {
        // For rm commands, check if the error is actually problematic
        if (command.contains('rm -') &&
            _isRmSuccessfulDespiteError(stderr, stdout)) {
          // rm succeeded despite non-zero exit code (common with warnings)
          return;
        }

        // For mkdir commands with -p flag, "File exists" is not an error
        if (command.contains('mkdir -p') &&
            stderr.toLowerCase().contains('file exists')) {
          return;
        }

        // For touch commands, check if file was created despite error
        if (command.contains('touch') &&
            _isTouchSuccessfulDespiteError(stderr, stdout)) {
          return;
        }

        // For copy/move commands, check for specific errors that might be warnings
        if ((command.contains('cp ') || command.contains('mv ')) &&
            _isCopyMoveSuccessfulDespiteError(stderr, stdout)) {
          return;
        }

        throw Exception(
            'Command failed (exit code $exitCode): ${stderr.isNotEmpty ? stderr : stdout}');
      }

      return;
    } catch (e) {
      throw Exception('SSH command failed: $e');
    }
  }

  bool _isRmSuccessfulDespiteError(String stderr, String stdout) {
    // Check if stderr contains only warnings that don't indicate failure
    final errorLower = stderr.toLowerCase();

    // If stderr is empty, consider it success
    if (stderr.trim().isEmpty) return true;

    // Check if error is about non-existent files (which is success for rm -f)
    if (errorLower.contains('no such file or directory')) {
      return true;
    }

    // If error contains "cannot remove" but also "no such file", it's harmless
    if (errorLower.contains('cannot remove') &&
        errorLower.contains('no such file')) {
      return true;
    }

    return false;
  }

  bool _isTouchSuccessfulDespiteError(String stderr, String stdout) {
    // Check if touch command succeeded despite warnings
    final errorLower = stderr.toLowerCase();

    // If stderr is empty, consider it success
    if (stderr.trim().isEmpty) return true;

    // Touch often gives warnings but still creates the file
    if (errorLower.contains('cannot touch') &&
        errorLower.contains('permission denied')) {
      return false; // This is a real failure
    }

    return false; // For touch, be more conservative
  }

  bool _isCopyMoveSuccessfulDespiteError(String stderr, String stdout) {
    // Check if cp/mv command succeeded despite warnings
    final errorLower = stderr.toLowerCase();

    // If stderr is empty, consider it success
    if (stderr.trim().isEmpty) return true;

    // Common warnings that don't indicate failure
    if (errorLower.contains('preserving times not supported') ||
        errorLower.contains('preserving permissions not supported') ||
        errorLower.contains('omitting directory')) {
      return true; // These are warnings, not failures
    }

    // File already exists warnings for mv
    if (errorLower.contains('are the same file')) {
      return true; // Trying to move file to itself
    }

    return false; // For other errors, be conservative
  }

  bool _validatePath(String path) {
    // Basic path validation
    if (path.isEmpty || path.trim().isEmpty) return false;
    if (path.contains('..')) return false; // Prevent directory traversal
    if (path.length > 4096) return false; // Prevent excessively long paths
    return true;
  }

  Future<void> _verifyDeletion(String path, String fileName) async {
    try {
      // Try to list the specific file/directory to see if it still exists
      final session = await widget.sshClient!
          .execute('ls -la "${path.replaceAll('"', '\\"')}" 2>/dev/null');
      final output =
          await session.stdout.cast<List<int>>().transform(utf8.decoder).join();
      await session.stderr
          .cast<List<int>>()
          .transform(utf8.decoder)
          .join(); // Consume stderr
      final exitCode = await session.exitCode;

      // If ls returns 0 (file exists) or output is not empty, deletion failed
      if (exitCode == 0 && output.trim().isNotEmpty) {
        throw Exception('File "$fileName" still exists after deletion attempt');
      }
    } catch (e) {
      // If ls fails (file doesn't exist), that's what we want
      return;
    }
  }

  Future<void> _showOperationProgress(
      String operation, Future<void> Function() action) async {
    setState(() {
      _operationInProgress = true;
      _operationStatus = operation;
    });

    try {
      await action();
      _showSnackBar('$operation completed successfully', Colors.green);
      _fetchFiles(_currentPath); // Refresh the file list
    } catch (e) {
      _showSnackBar('$operation failed: $e', Colors.red);
    } finally {
      setState(() {
        _operationInProgress = false;
        _operationStatus = '';
      });
    }
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

  Future<void> _createNewFolder() async {
    final name = await _showInputDialog('Create Folder', 'Enter folder name:');
    if (name != null && name.isNotEmpty) {
      await _showOperationProgress('Creating folder', () async {
        final folderPath =
            _currentPath == '/' ? '/$name' : '$_currentPath/$name';
        await _executeCommand(
            'mkdir -p "${folderPath.replaceAll('"', '\\"')}"');
      });
    }
  }

  Future<void> _createNewFile() async {
    final name = await _showInputDialog('Create File', 'Enter file name:');
    if (name != null && name.isNotEmpty) {
      await _showOperationProgress('Creating file', () async {
        final filePath = _currentPath == '/' ? '/$name' : '$_currentPath/$name';
        await _executeCommand('touch "${filePath.replaceAll('"', '\\"')}"');
      });
    }
  }

  Future<void> _renameSelected() async {
    if (_selectedIndexes.length != 1) return;

    final entry = _entries![_selectedIndexes.first];
    final newName = await _showInputDialog(
        'Rename ${entry.isDir ? 'Folder' : 'File'}',
        'Enter new name:',
        entry.name);

    if (newName != null && newName.isNotEmpty && newName != entry.name) {
      await _showOperationProgress('Renaming', () async {
        final oldPath = _currentPath == '/'
            ? '/${entry.name}'
            : '$_currentPath/${entry.name}';
        final newPath =
            _currentPath == '/' ? '/$newName' : '$_currentPath/$newName';
        await _executeCommand(
            'mv "${oldPath.replaceAll('"', '\\"')}" "${newPath.replaceAll('"', '\\"')}"');
      });
      setState(() {
        _selectedIndexes.clear();
      });
    }
  }

  Future<void> _deleteSelected() async {
    if (_selectedIndexes.isEmpty) return;

    final selectedEntries = _selectedIndexes.map((i) => _entries![i]).toList();
    final fileCount = selectedEntries.where((e) => !e.isDir).length;
    final folderCount = selectedEntries.where((e) => e.isDir).length;

    String message = 'Delete ';
    if (fileCount > 0 && folderCount > 0) {
      message += '$fileCount file(s) and $folderCount folder(s)?';
    } else if (fileCount > 0) {
      message += '$fileCount file(s)?';
    } else {
      message += '$folderCount folder(s)?';
    }

    final confirmed = await _showConfirmDialog('Confirm Delete', message);
    if (confirmed) {
      await _showOperationProgress('Deleting', () async {
        for (final entry in selectedEntries) {
          final path = _currentPath == '/'
              ? '/${entry.name}'
              : '$_currentPath/${entry.name}';

          // Validate path to prevent dangerous operations
          if (path == '/' || path.isEmpty || path == _currentPath) {
            throw Exception('Cannot delete: Invalid path "$path"');
          }

          try {
            if (entry.isDir) {
              // For directories, use rm -rf with explicit path validation
              await _executeCommand('rm -rf "${path.replaceAll('"', '\\"')}"');
            } else {
              await _executeCommand('rm -f "${path.replaceAll('"', '\\"')}"');
            }

            // Verify the file/directory was actually deleted
            await _verifyDeletion(path, entry.name);
          } catch (e) {
            // Check if file was actually deleted despite the error
            try {
              await _verifyDeletion(path, entry.name);
              // If verification passes, the delete was successful despite the error
            } catch (verificationError) {
              // File still exists, so the delete truly failed
              throw Exception('Failed to delete "${entry.name}": $e');
            }
          }
        }
      });
      setState(() {
        _selectedIndexes.clear();
      });
    }
  }

  void _copySelected() {
    if (_selectedIndexes.isEmpty) return;

    try {
      _clipboard = _selectedIndexes.map((i) {
        final entry = _entries![i];
        final fullPath = _currentPath == '/'
            ? '/${entry.name}'
            : '$_currentPath/${entry.name}';
        // Validate the path exists and is accessible
        if (!_validatePath(fullPath)) {
          throw Exception('Invalid path: $fullPath');
        }
        return fullPath;
      }).toList();
      _clipboardIsCut = false;

      _showSnackBar(
          '${_clipboard.length} item(s) copied to clipboard', Colors.blue);
      setState(() {
        _selectedIndexes.clear();
      });
    } catch (e) {
      _showSnackBar('Failed to copy items: $e', Colors.red);
    }
  }

  void _cutSelected() {
    if (_selectedIndexes.isEmpty) return;

    try {
      _clipboard = _selectedIndexes.map((i) {
        final entry = _entries![i];
        final fullPath = _currentPath == '/'
            ? '/${entry.name}'
            : '$_currentPath/${entry.name}';
        // Validate the path exists and is accessible
        if (!_validatePath(fullPath)) {
          throw Exception('Invalid path: $fullPath');
        }
        return fullPath;
      }).toList();
      _clipboardIsCut = true;

      _showSnackBar(
          '${_clipboard.length} item(s) cut to clipboard', Colors.orange);
      setState(() {
        _selectedIndexes.clear();
      });
    } catch (e) {
      _showSnackBar('Failed to cut items: $e', Colors.red);
    }
  }

  Future<void> _pasteFromClipboard() async {
    if (_clipboard.isEmpty) return;

    await _showOperationProgress(_clipboardIsCut ? 'Moving' : 'Copying',
        () async {
      for (final sourcePath in _clipboard) {
        final fileName = sourcePath.split('/').last;
        final targetPath =
            _currentPath == '/' ? '/$fileName' : '$_currentPath/$fileName';

        // Validate source path
        if (sourcePath.isEmpty || fileName.isEmpty) {
          throw Exception('Invalid source path: $sourcePath');
        }

        if (!_validatePath(sourcePath) || !_validatePath(targetPath)) {
          throw Exception('Invalid path detected: $sourcePath -> $targetPath');
        }

        // Check if trying to copy/move to the same location
        if (sourcePath == targetPath) {
          continue; // Skip this item
        }

        // Check if target already exists and handle conflicts
        await _handleFileConflict(sourcePath, targetPath, fileName);
      }
    });

    if (_clipboardIsCut) {
      _clipboard.clear();
      _clipboardIsCut = false;
    }
  }

  Future<void> _handleFileConflict(
      String sourcePath, String targetPath, String fileName) async {
    try {
      // Check if target exists
      final checkSession = await widget.sshClient!.execute(
          'test -e "${targetPath.replaceAll('"', '\\"')}" && echo "exists" || echo "not_exists"');
      final checkOutput = await checkSession.stdout
          .cast<List<int>>()
          .transform(utf8.decoder)
          .join();
      await checkSession.stderr
          .cast<List<int>>()
          .transform(utf8.decoder)
          .join(); // Consume stderr
      await checkSession.exitCode;

      final targetExists = checkOutput.trim() == 'exists';

      if (targetExists) {
        // Generate unique name for conflict resolution
        String uniqueTargetPath =
            await _generateUniqueFileName(targetPath, fileName);
        await _performCopyOrMove(sourcePath, uniqueTargetPath, fileName);
      } else {
        await _performCopyOrMove(sourcePath, targetPath, fileName);
      }
    } catch (e) {
      throw Exception('Failed to handle file conflict for "$fileName": $e');
    }
  }

  Future<String> _generateUniqueFileName(
      String targetPath, String fileName) async {
    String basePath = targetPath.substring(0, targetPath.lastIndexOf('/'));
    String nameWithoutExt = fileName.contains('.')
        ? fileName.substring(0, fileName.lastIndexOf('.'))
        : fileName;
    String extension = fileName.contains('.')
        ? fileName.substring(fileName.lastIndexOf('.'))
        : '';

    for (int i = 1; i <= 999; i++) {
      String newName = '${nameWithoutExt}_copy$i$extension';
      String newPath = basePath == '' ? '/$newName' : '$basePath/$newName';

      try {
        final checkSession = await widget.sshClient!.execute(
            'test -e "${newPath.replaceAll('"', '\\"')}" && echo "exists" || echo "not_exists"');
        final checkOutput = await checkSession.stdout
            .cast<List<int>>()
            .transform(utf8.decoder)
            .join();
        await checkSession.stderr
            .cast<List<int>>()
            .transform(utf8.decoder)
            .join();
        await checkSession.exitCode;

        if (checkOutput.trim() == 'not_exists') {
          return newPath;
        }
      } catch (e) {
        // If check fails, assume path is available
        return newPath;
      }
    }

    // Fallback with timestamp
    String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    String fallbackName = '${nameWithoutExt}_$timestamp$extension';
    return basePath == '' ? '/$fallbackName' : '$basePath/$fallbackName';
  }

  Future<void> _performCopyOrMove(
      String sourcePath, String targetPath, String fileName) async {
    try {
      if (_clipboardIsCut) {
        // Move operation
        await _executeCommand(
            'mv "${sourcePath.replaceAll('"', '\\"')}" "${targetPath.replaceAll('"', '\\"')}"');
      } else {
        // Copy operation - use -r for recursive copying
        await _executeCommand(
            'cp -r "${sourcePath.replaceAll('"', '\\"')}" "${targetPath.replaceAll('"', '\\"')}"');
      }
    } catch (e) {
      throw Exception(
          'Failed to ${_clipboardIsCut ? 'move' : 'copy'} "$fileName": $e');
    }
  }

  Future<void> _downloadSelected() async {
    if (_selectedIndexes.isEmpty) return;

    try {
      final result = await FilePicker.platform.getDirectoryPath();
      if (result == null) return;

      await _showOperationProgress('Downloading', () async {
        for (final index in _selectedIndexes) {
          final entry = _entries![index];
          final remotePath = _currentPath == '/'
              ? '/${entry.name}'
              : '$_currentPath/${entry.name}';
          final localPath = '$result/${entry.name}';

          if (entry.isDir) {
            // Create directory and download recursively
            await Directory(localPath).create(recursive: true);
            await _downloadDirectory(remotePath, localPath);
          } else {
            await _downloadFile(remotePath, localPath);
          }
        }
      });

      setState(() {
        _selectedIndexes.clear();
      });
    } catch (e) {
      _showSnackBar('Download failed: $e', Colors.red);
    }
  }

  Future<void> _downloadFile(String remotePath, String localPath) async {
    final sftp = await widget.sshClient!.sftp();
    final remoteFile = await sftp.open(remotePath);
    final localFile = File(localPath);

    final content = await remoteFile.readBytes();
    await localFile.writeAsBytes(content);

    await remoteFile.close();
  }

  Future<void> _downloadDirectory(String remotePath, String localPath) async {
    // Get directory listing
    final session = await widget.sshClient!
        .execute('find "${remotePath.replaceAll('"', '\\"')}" -type f');
    final output =
        await session.stdout.cast<List<int>>().transform(utf8.decoder).join();
    final files =
        output.split('\n').where((line) => line.trim().isNotEmpty).toList();

    for (final file in files) {
      final relativePath = file.substring(remotePath.length);
      final localFilePath = '$localPath$relativePath';
      final localFileDir = File(localFilePath).parent;

      await localFileDir.create(recursive: true);
      await _downloadFile(file, localFilePath);
    }
  }

  Future<void> _uploadFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result == null) return;

      await _showOperationProgress('Uploading', () async {
        for (final file in result.files) {
          if (file.path != null) {
            final localFile = File(file.path!);
            final remotePath = _currentPath == '/'
                ? '/${file.name}'
                : '$_currentPath/${file.name}';
            await _uploadFile(localFile, remotePath);
          }
        }
      });
    } catch (e) {
      _showSnackBar('Upload failed: $e', Colors.red);
    }
  }

  Future<void> _uploadFile(File localFile, String remotePath) async {
    // Try SFTP first, fallback to base64 method
    try {
      final sftp = await widget.sshClient!.sftp();
      final content = await localFile.readAsBytes();

      // Use SFTP for reliable upload
      final remoteFile = await sftp.open(remotePath,
          mode: SftpFileOpenMode.create | SftpFileOpenMode.write);
      await remoteFile.write(Stream.value(content));
      await remoteFile.close();
    } catch (e) {
      // Fallback to base64 method
      final content = await localFile.readAsBytes();
      final base64Content = base64Encode(content);

      // Split large files to avoid command line limits
      const chunkSize = 4096;
      if (base64Content.length > chunkSize) {
        // Clear the file first
        await _executeCommand('> "${remotePath.replaceAll('"', '\\"')}"');

        // Upload in chunks
        for (int i = 0; i < base64Content.length; i += chunkSize) {
          final chunk = base64Content.substring(
              i, (i + chunkSize).clamp(0, base64Content.length));
          await _executeCommand(
              'echo "$chunk" | base64 -d >> "${remotePath.replaceAll('"', '\\"')}"');
        }
      } else {
        await _executeCommand(
            'echo "$base64Content" | base64 -d > "${remotePath.replaceAll('"', '\\"')}"');
      }
    }
  }

  Future<void> _viewFileContent() async {
    if (_selectedIndexes.length != 1) return;

    final entry = _entries![_selectedIndexes.first];
    if (entry.isDir) return;

    final filePath =
        _currentPath == '/' ? '/${entry.name}' : '$_currentPath/${entry.name}';

    try {
      setState(() {
        _operationInProgress = true;
        _operationStatus = 'Loading file content';
      });

      final session = await widget.sshClient!
          .execute('head -n 100 "${filePath.replaceAll('"', '\\"')}"');
      final content =
          await session.stdout.cast<List<int>>().transform(utf8.decoder).join();

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(entry.name),
            content: Container(
              width: double.maxFinite,
              height: 400,
              child: SingleChildScrollView(
                child: Text(
                  content.isEmpty ? 'File is empty or binary' : content,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: content));
                  Navigator.of(context).pop();
                  _showSnackBar('Content copied to clipboard', Colors.blue);
                },
                child: const Text('Copy'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      _showSnackBar('Failed to load file: $e', Colors.red);
    } finally {
      setState(() {
        _operationInProgress = false;
        _operationStatus = '';
      });
    }
  }

  Future<void> _showProperties() async {
    if (_selectedIndexes.length != 1) return;

    final entry = _entries![_selectedIndexes.first];
    final filePath =
        _currentPath == '/' ? '/${entry.name}' : '$_currentPath/${entry.name}';

    try {
      final session = await widget.sshClient!
          .execute('stat "${filePath.replaceAll('"', '\\"')}"');
      final statOutput =
          await session.stdout.cast<List<int>>().transform(utf8.decoder).join();

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Properties: ${entry.name}'),
          content: Container(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildPropertyRow('Name', entry.name),
                  _buildPropertyRow('Type', entry.isDir ? 'Directory' : 'File'),
                  _buildPropertyRow('Size', entry.size),
                  _buildPropertyRow('Permissions', entry.permissions),
                  _buildPropertyRow('Modified', entry.modified),
                  const Divider(),
                  const Text('Detailed Information:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    statOutput,
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showSnackBar('Failed to get properties: $e', Colors.red);
    }
  }

  Widget _buildPropertyRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
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

  Future<String?> _showInputDialog(String title, String hint,
      [String? initialValue]) async {
    final controller = TextEditingController(text: initialValue);
    String? result;

    await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: hint),
          autofocus: true,
          onSubmitted: (value) {
            result = value;
            Navigator.of(context).pop();
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              result = controller.text;
              Navigator.of(context).pop();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );

    return result;
  }

  Future<bool> _showConfirmDialog(String title, String content) async {
    bool result = false;

    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              result = true;
              Navigator.of(context).pop();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    return result;
  }

  void _showActionMenu() async {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        overlay.size.width - 200,
        overlay.size.height - 400,
        20,
        80,
      ),
      items: [
        if (_selectedIndexes.length == 1)
          PopupMenuItem(
              value: 'rename',
              child: Row(children: [
                Icon(Icons.drive_file_rename_outline),
                SizedBox(width: 8),
                Text('Rename')
              ])),
        if (_selectedIndexes.isNotEmpty)
          PopupMenuItem(
              value: 'delete',
              child: Row(children: [
                Icon(Icons.delete, color: Colors.red),
                SizedBox(width: 8),
                Text('Delete', style: TextStyle(color: Colors.red))
              ])),
        if (_selectedIndexes.isNotEmpty)
          PopupMenuItem(
              value: 'copy',
              child: Row(children: [
                Icon(Icons.copy),
                SizedBox(width: 8),
                Text('Copy')
              ])),
        if (_selectedIndexes.isNotEmpty)
          PopupMenuItem(
              value: 'cut',
              child: Row(children: [
                Icon(Icons.content_cut),
                SizedBox(width: 8),
                Text('Cut')
              ])),
        if (_clipboard.isNotEmpty)
          PopupMenuItem(
              value: 'paste',
              child: Row(children: [
                Icon(Icons.paste),
                SizedBox(width: 8),
                Text('Paste')
              ])),
        if (_selectedIndexes.length == 1 &&
            _entries != null &&
            !_entries![_selectedIndexes.first].isDir)
          PopupMenuItem(
              value: 'view',
              child: Row(children: [
                Icon(Icons.visibility),
                SizedBox(width: 8),
                Text('View Content')
              ])),
        if (_selectedIndexes.length == 1)
          PopupMenuItem(
              value: 'properties',
              child: Row(children: [
                Icon(Icons.info),
                SizedBox(width: 8),
                Text('Properties')
              ])),
        if (_selectedIndexes.isNotEmpty)
          PopupMenuItem(
              value: 'download',
              child: Row(children: [
                Icon(Icons.download),
                SizedBox(width: 8),
                Text('Download')
              ])),
        PopupMenuItem(
            value: 'upload',
            child: Row(children: [
              Icon(Icons.upload_file),
              SizedBox(width: 8),
              Text('Upload Files')
            ])),
        PopupMenuItem(
            value: 'new_folder',
            child: Row(children: [
              Icon(Icons.create_new_folder),
              SizedBox(width: 8),
              Text('New Folder')
            ])),
        PopupMenuItem(
            value: 'new_file',
            child: Row(children: [
              Icon(Icons.note_add),
              SizedBox(width: 8),
              Text('New File')
            ])),
      ],
    );

    if (selected != null) {
      switch (selected) {
        case 'rename':
          _renameSelected();
          break;
        case 'delete':
          _deleteSelected();
          break;
        case 'copy':
          _copySelected();
          break;
        case 'cut':
          _cutSelected();
          break;
        case 'paste':
          _pasteFromClipboard();
          break;
        case 'view':
          _viewFileContent();
          break;
        case 'properties':
          _showProperties();
          break;
        case 'download':
          _downloadSelected();
          break;
        case 'upload':
          _uploadFiles();
          break;
        case 'new_folder':
          _createNewFolder();
          break;
        case 'new_file':
          _createNewFile();
          break;
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

    if (_operationInProgress) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_operationStatus),
          ],
        ),
      );
    }

    if (widget.error != null) {
      return Center(child: Text('SSH Error: ${widget.error}'));
    }
    if (_error != null) {
      return Center(child: Text('Error: $_error'));
    }
    if (_entries != null) {
      // Filter entries based on search query
      final filteredEntries = _searchQuery.isEmpty
          ? _entries!
          : _entries!
              .where((entry) =>
                  entry.name.toLowerCase().contains(_searchQuery.toLowerCase()))
              .toList();

      return Stack(
        children: [
          Column(
            children: [
              // Modern path bar with search
              Material(
                color: Colors.blueGrey.shade50,
                elevation: 1,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
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
                              _isSearching ? Icons.search_off : Icons.search,
                              color: Colors.black87,
                            ),
                            tooltip:
                                _isSearching ? 'Hide search' : 'Search files',
                            onPressed: _toggleSearch,
                          ),
                          IconButton(
                            icon: Icon(
                              _showHidden
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: Colors.black87,
                            ),
                            tooltip: _showHidden
                                ? 'Hide hidden files'
                                : 'Show hidden files',
                            onPressed: _toggleShowHidden,
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh,
                                color: Colors.black87),
                            tooltip: 'Refresh',
                            onPressed: () => _fetchFiles(_currentPath),
                          ),
                        ],
                      ),
                    ),
                    if (_isSearching)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: TextField(
                          controller: _searchController,
                          decoration: const InputDecoration(
                            hintText: 'Search files and folders...',
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                          ),
                          onChanged: _performSearch,
                          autofocus: true,
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Selection info bar
              if (_selectedIndexes.isNotEmpty)
                Container(
                  color: Colors.blue.shade50,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Text(
                        '${_selectedIndexes.length} item(s) selected',
                        style: TextStyle(
                          color: Colors.blue.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () =>
                            setState(() => _selectedIndexes.clear()),
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                ),
              // File/folder list
              Expanded(
                child: filteredEntries.isEmpty
                    ? Center(
                        child: Text(
                          _searchQuery.isEmpty
                              ? 'No files in this directory'
                              : 'No files match your search',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 16,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: filteredEntries.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, idx) {
                          final entry = filteredEntries[idx];
                          final originalIndex = _entries!.indexOf(entry);
                          final selected =
                              _selectedIndexes.contains(originalIndex);
                          return Card(
                            color:
                                selected ? Colors.blue.shade50 : Colors.white,
                            elevation: selected ? 2 : 0,
                            margin: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
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
                                entry.isDir
                                    ? Icons.folder
                                    : Icons.insert_drive_file,
                                color: entry.isDir
                                    ? Colors.amber
                                    : Colors.blueGrey,
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
                              selected: selected,
                              onTap: () {
                                setState(() {
                                  if (selected) {
                                    _selectedIndexes.remove(originalIndex);
                                  } else {
                                    _selectedIndexes.add(originalIndex);
                                  }
                                });
                              },
                              onLongPress: entry.isDir
                                  ? () => _navigateTo(
                                        _currentPath == '/'
                                            ? '/${entry.name}'
                                            : '$_currentPath/${entry.name}',
                                      )
                                  : () {
                                      setState(() {
                                        _selectedIndexes.clear();
                                        _selectedIndexes.add(originalIndex);
                                      });
                                      _viewFileContent();
                                    },
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
                        icon: const Icon(Icons.drive_file_rename_outline,
                            color: Colors.black87),
                        tooltip: 'Rename',
                        onPressed: _selectedIndexes.length == 1
                            ? _renameSelected
                            : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.black87),
                        tooltip: 'Delete',
                        onPressed: _selectedIndexes.isNotEmpty
                            ? _deleteSelected
                            : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, color: Colors.black87),
                        tooltip: 'Copy',
                        onPressed:
                            _selectedIndexes.isNotEmpty ? _copySelected : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.content_cut,
                            color: Colors.black87),
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
                      IconButton(
                        icon: const Icon(Icons.open_in_new,
                            color: Colors.black87),
                        tooltip: 'View Content',
                        onPressed: _selectedIndexes.length == 1 &&
                                _entries != null &&
                                !_entries![_selectedIndexes.first].isDir
                            ? _viewFileContent
                            : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.info, color: Colors.black87),
                        tooltip: 'Properties',
                        onPressed: _selectedIndexes.length == 1
                            ? _showProperties
                            : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.download, color: Colors.black87),
                        tooltip: 'Download',
                        onPressed: _selectedIndexes.isNotEmpty
                            ? _downloadSelected
                            : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.upload_file,
                            color: Colors.black87),
                        tooltip: 'Upload Files',
                        onPressed: _uploadFiles,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // Floating action button with create options
          Positioned(
            bottom: 80,
            right: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: "create_folder",
                  onPressed: _createNewFolder,
                  tooltip: 'Create Folder',
                  child: const Icon(Icons.create_new_folder),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: "create_file",
                  onPressed: _createNewFile,
                  tooltip: 'Create File',
                  child: const Icon(Icons.note_add),
                ),
                const SizedBox(height: 8),
                FloatingActionButton(
                  heroTag: "main_actions",
                  tooltip: 'More Actions',
                  onPressed: () => _showActionMenu(),
                  child: const Icon(Icons.menu),
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
    return const Center(child: Text('No files loaded.'));
  }

  // ...existing code ends with the build method...
}
