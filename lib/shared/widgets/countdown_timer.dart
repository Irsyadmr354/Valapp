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
    this.deadline,
    this.deadlineIdentity,
  });

  final int remainingSeconds;
  final VoidCallback? onExpired;
  final TextStyle? style;
  final DateTime? deadline;
  final Object? deadlineIdentity;

  @override
  State<CountdownTimer> createState() => _CountdownTimerState();
}

class _CountdownTimerState extends State<CountdownTimer>
    with WidgetsBindingObserver {
  late int _remaining;
  late DateTime _expiresAt;
  Timer? _timer;
  bool _expiredNotified = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resetExpiry();
    _startTimer();
  }

  @override
  void didUpdateWidget(CountdownTimer old) {
    super.didUpdateWidget(old);
    if (old.deadlineIdentity != widget.deadlineIdentity ||
        old.deadline != widget.deadline ||
        (widget.deadline == null &&
            old.remainingSeconds != widget.remainingSeconds)) {
      _timer?.cancel();
      _resetExpiry();
      _startTimer();
    }
  }

  void _startTimer() {
    _updateRemaining();
    if (_remaining <= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _notifyExpired());
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _updateRemaining();
      if (_remaining <= 0) {
        _timer?.cancel();
        _notifyExpired();
      }
    });
  }

  void _resetExpiry() {
    _expiredNotified = false;
    _remaining = widget.remainingSeconds.clamp(0, 1 << 31);
    _expiresAt =
        widget.deadline ?? DateTime.now().add(Duration(seconds: _remaining));
    _remaining = _secondsUntil(_expiresAt);
  }

  int _secondsUntil(DateTime deadline) {
    final milliseconds = deadline.difference(DateTime.now()).inMilliseconds;
    return milliseconds <= 0 ? 0 : (milliseconds / 1000).ceil();
  }

  void _updateRemaining() {
    final next = _secondsUntil(_expiresAt);
    if (next != _remaining && mounted) setState(() => _remaining = next);
  }

  void _notifyExpired() {
    if (!mounted || _expiredNotified || _remaining > 0) return;
    _expiredNotified = true;
    widget.onExpired?.call();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _updateRemaining();
      if (_remaining <= 0) {
        _timer?.cancel();
        _notifyExpired();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
