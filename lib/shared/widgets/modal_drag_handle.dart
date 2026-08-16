import 'package:flutter/material.dart';

/// Reusable top drag handle indicator for bottom sheet modals.
class ModalDragHandle extends StatelessWidget {
  const ModalDragHandle({
    super.key,
    this.width = 38,
    this.height = 4,
    this.color = Colors.white24,
    this.topMargin = 12,
    this.bottomMargin = 12,
  });

  final double width;
  final double height;
  final Color color;
  final double topMargin;
  final double bottomMargin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: topMargin, bottom: bottomMargin),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(height / 2),
        ),
      ),
    );
  }
}
