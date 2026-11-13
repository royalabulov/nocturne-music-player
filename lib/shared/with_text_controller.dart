import 'package:flutter/material.dart';

/// Owns a text box's controller for a dialog's whole life: made when it opens, disposed once
/// the dialog has finished closing. A controller made before showDialog was never disposed,
/// and disposing it right after the dialog returned broke the closing animation.
class WithTextController extends StatefulWidget {
  const WithTextController({super.key, required this.text, required this.builder});
  final String text;
  final Widget Function(BuildContext context, TextEditingController controller) builder;

  @override
  State<WithTextController> createState() => _WithTextControllerState();
}

class _WithTextControllerState extends State<WithTextController> {
  late final _controller = TextEditingController(text: widget.text);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controller);
}
