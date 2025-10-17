import 'package:flutter/material.dart';

class MarqueeText extends StatefulWidget {
  final String text;
  final double velocity;
  const MarqueeText({super.key, required this.text, this.velocity = 30.0});
  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> with SingleTickerProviderStateMixin {
  late final ScrollController _scrollController;
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _controller = AnimationController(vsync: this, duration: Duration(seconds: 5))
      ..repeat();
    _controller.addListener(() {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo((_controller.value * _scrollController.position.maxScrollExtent));
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      children: [
        Text(widget.text, style: const TextStyle(overflow: TextOverflow.visible)),
      ],
    );
  }
}
