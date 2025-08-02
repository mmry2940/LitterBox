import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dartssh2/dartssh2.dart';
import 'dart:async';
import 'dart:convert';

class DeviceTerminalScreen extends StatefulWidget {
  final SSHClient? sshClient;
  final String? error;
  final bool loading;
  const DeviceTerminalScreen({
    super.key,
    this.sshClient,
    this.error,
    this.loading = false,
  });

  @override
  State<DeviceTerminalScreen> createState() => _DeviceTerminalScreenState();
}

class _DeviceTerminalScreenState extends State<DeviceTerminalScreen> {
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final List<String> _history = [];
  int _historyIndex = -1;
  SSHSession? _shellSession;
  StreamSubscription? _stdoutSub;
  StreamSubscription? _stderrSub;
  final List<String> _scrollback = [];
  bool _shellReady = false;
  double _fontSize = 14.0;
  double _baseFontSize = 14.0;

  @override
  void initState() {
    super.initState();
    _startShell();
  }

  @override
  void didUpdateWidget(DeviceTerminalScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.key != oldWidget.key && widget.sshClient != null) {
      _disposeShell();
      _scrollback.clear();
      _startShell();
    }
  }

  @override
  void dispose() {
    _disposeShell();
    _inputController.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _disposeShell() {
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _shellSession?.close();
    _shellSession = null;
    _shellReady = false;
  }

  String _stripAnsi(String input) {
    // Removes ANSI escape sequences, OSC, and bracketed paste mode codes
    final ansiRegex = RegExp(r'\x1B\[[0-9;?]*[ -/]*[@-~]');
    final oscRegex = RegExp(r'\x1B\][^\x07\x1B]*(\x07|\x1B\\)');
    final bracketedPasteRegex = RegExp(r'\[\?2004[hl]');
    String out = input.replaceAll(ansiRegex, '');
    out = out.replaceAll(oscRegex, '');
    out = out.replaceAll(bracketedPasteRegex, '');
    return out;
  }

  Future<void> _startShell() async {
    if (widget.sshClient == null) return;
    try {
      final session = await widget.sshClient!.shell();
      _shellSession = session;
      _shellReady = true;
      _stdoutSub = session.stdout
          .cast<List<int>>()
          .transform(utf8.decoder)
          .listen((data) {
        setState(() {
          _scrollback.add(_stripAnsi(data));
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          }
        });
      });
      _stderrSub = session.stderr
          .cast<List<int>>()
          .transform(utf8.decoder)
          .listen((data) {
        setState(() {
          _scrollback.add(_stripAnsi(data));
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          }
        });
      });
    } catch (e) {
      setState(() {
        _scrollback.add('Shell error: $e\n');
      });
    }
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _baseFontSize = _fontSize;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    setState(() {
      _fontSize = (_baseFontSize * details.scale).clamp(8.0, 40.0);
    });
  }

  void _recallHistory(int index) {
    if (index >= 0 && index < _history.length) {
      setState(() {
        _inputController.text = _history[index];
        _inputController.selection = TextSelection.fromPosition(
          TextPosition(offset: _inputController.text.length),
        );
        _historyIndex = index;
      });
    }
  }

  void _handleKey(RawKeyEvent event) {
    if (event.runtimeType.toString() == 'RawKeyDownEvent') {
      if (event.logicalKey.keyLabel == 'Arrow Up') {
        if (_history.isNotEmpty && _historyIndex > 0) {
          _recallHistory(_historyIndex - 1);
        } else if (_history.isNotEmpty && _historyIndex == -1) {
          _recallHistory(_history.length - 1);
        }
      } else if (event.logicalKey.keyLabel == 'Arrow Down') {
        if (_history.isNotEmpty &&
            _historyIndex >= 0 &&
            _historyIndex < _history.length - 1) {
          _recallHistory(_historyIndex + 1);
        } else if (_historyIndex == _history.length - 1) {
          setState(() {
            _inputController.clear();
            _historyIndex = -1;
          });
        }
      }
    }
  }

  void _sendInput(String input) {
    if (_shellSession != null && _shellReady && input.trim().isNotEmpty) {
      _shellSession!.write(utf8.encode('$input\n'));
      setState(() {
        if (_history.isEmpty || _history.last != input) {
          _history.add(input);
        }
        _historyIndex = -1;
        _scrollback.add('> $input');
      });
      _inputController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      // Duplicate code removed
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.error != null) {
      return Center(child: Text('SSH Error: ${widget.error}'));
    }
    if (widget.sshClient == null) {
      return const Center(child: Text('Waiting for SSH connection...'));
    }
    return GestureDetector(
      onScaleStart: _handleScaleStart,
      onScaleUpdate: _handleScaleUpdate,
      child: Container(
        color: Colors.black,
        child: Column(
          children: [
            Expanded(
              child: RawKeyboardListener(
                focusNode: FocusNode(),
                onKey: _handleKey,
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(8),
                  itemCount: _scrollback.length + 1,
                  itemBuilder: (context, i) {
                    if (i < _scrollback.length) {
                      return SelectableText(
                        _scrollback[i],
                        style: TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: _fontSize),
                      );
                            } else {
                              // Inline input with prompt and blinking cursor directly after prompt
                              final prompt = _shellReady ? '~\$ ' : '';
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Text(
                                    prompt,
                                    style: TextStyle(
                                      color: Colors.greenAccent,
                                      fontFamily: 'monospace',
                                      fontSize: _fontSize,
                                    ),
                                  ),
                                  _BlinkingCursor(
                                    show: _inputFocusNode.hasFocus && _shellReady,
                                    color: Colors.greenAccent,
                                    fontSize: _fontSize,
                                  ),
                                  Expanded(
                                    child: AnimatedBuilder(
                                      animation: _inputController,
                                      builder: (context, _) {
                                        return TextField(
                                          controller: _inputController,
                                          focusNode: _inputFocusNode,
                                          enabled: _shellReady,
                                          style: TextStyle(
                                            color: Colors.greenAccent,
                                            fontFamily: 'monospace',
                                            fontSize: _fontSize,
                                          ),
                                          cursorColor: Colors.greenAccent,
                                          decoration: InputDecoration(
                                            border: InputBorder.none,
                                            isCollapsed: true,
                                            contentPadding: EdgeInsets.zero,
                                            hintText: _shellReady ? '' : 'Connecting...'
                                          ),
                                          autofocus: true,
                                          onSubmitted: (input) {
                                            _sendInput(input);
                                            // Always request focus after submit
                                            Future.delayed(Duration(milliseconds: 50), () {
                                              if (mounted) _inputFocusNode.requestFocus();
                                            });
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              );
                            }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Blinking cursor widget
class _BlinkingCursor extends StatefulWidget {
  final bool show;
  final Color color;
  final double fontSize;
  const _BlinkingCursor({required this.show, required this.color, required this.fontSize});
  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..repeat(reverse: true);
    _opacityAnim = Tween<double>(begin: 1, end: 0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.show) return SizedBox(width: widget.fontSize * 0.6);
    return FadeTransition(
      opacity: _opacityAnim,
      child: Container(
        width: widget.fontSize * 0.6,
        height: widget.fontSize * 1.2,
        color: widget.color,
      ),
    );
  }
}





