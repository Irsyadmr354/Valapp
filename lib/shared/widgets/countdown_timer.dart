import 'dart:async';
import 'package:flutter/material.dart';

/// Displays a live hh:mm:ss countdown from [remainingSeconds].
/// Calls [onExpired] when the timer reaches zero.
class CountdownTimer extends StatefulWidget {
  const CountdownTimer({
    super.key,
    required this.remainingSeconds,
    this.onExpired,
    this.style,
  });

  final int remainingSeconds;
  final VoidCallback? onExpired;
  final TextStyle? style;

  @override
  State<CountdownTimer> createState() => _CountdownTimerState();
}

class _CountdownTimerState extends State<CountdownTimer> {
  late int _remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _remaining = widget.remainingSeconds;
    _startTimer();
  }

  @override
  void didUpdateWidget(CountdownTimer old) {
    super.didUpdateWidget(old);
    if (old.remainingSeconds != widget.remainingSeconds) {
      _timer?.cancel();
      _remaining = widget.remainingSeconds;
      _startTimer();
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remaining <= 0) {
        _timer?.cancel();
        widget.onExpired?.call();
        return;
      }
      setState(() => _remaining--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hours = _remaining ~/ 3600;
    final minutes = (_remaining % 3600) ~/ 60;
    final seconds = _remaining % 60;

    final formatted =
        '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    return Text(
      formatted,
      style: widget.style ??
          const TextStyle(
            color: Color(0xFFFF4655),
            fontSize: 18,
            fontWeight: FontWeight.w700,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
    );
  }
}
