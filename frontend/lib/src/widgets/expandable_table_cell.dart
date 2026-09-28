import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class ExpandableTableCell extends StatefulWidget {
  const ExpandableTableCell({
    super.key,
    required this.text,
    this.maxLength = 150,
  });

  final String text;
  final int maxLength;

  @override
  State<ExpandableTableCell> createState() => _ExpandableTableCellState();
}

class _ExpandableTableCellState extends State<ExpandableTableCell> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.text.length <= widget.maxLength) {
      return SelectableText(widget.text);
    }

    final displayedText = _isExpanded
        ? widget.text
        : '${widget.text.substring(0, widget.maxLength)}...';

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: displayedText),
          const TextSpan(text: ' '),
          TextSpan(
            text: _isExpanded ? 'Tampilkan Lebih Sedikit' : 'Baca Selengkapnya',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
            mouseCursor: SystemMouseCursors.click,
            recognizer: TapGestureRecognizer()
              ..onTap = () {
                setState(() {
                  _isExpanded = !_isExpanded;
                });
              },
          ),
        ],
      ),
    );
  }
}
