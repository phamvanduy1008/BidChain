import 'dart:async';
import 'package:flutter/material.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/services/server_time_service.dart';

class CountdownTimer extends StatefulWidget {
  final DateTime? startTime;
  final DateTime endTime;
  final String? status;
  final TextStyle? textStyle;
  final bool showLarge;

  const CountdownTimer({
    super.key,
    this.startTime,
    required this.endTime,
    this.status,
    this.textStyle,
    this.showLarge = false,
  });

  @override
  State<CountdownTimer> createState() => _CountdownTimerState();
}

class _CountdownTimerState extends State<CountdownTimer>
    with SingleTickerProviderStateMixin {
  Timer? _timer;
  Duration _remaining = Duration.zero;
  late AnimationController _pulseController;
  late Animation<double> _opacityAnimation;

  bool get _isUpcoming =>
      (widget.status ?? '').toUpperCase() == 'APPROVED' &&
      widget.startTime != null;

  DateTime get _targetTime => _isUpcoming ? widget.startTime! : widget.endTime;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _opacityAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _updateRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        _updateRemaining();
      }
    });
  }

  void _updateRemaining() {
    setState(() {
      final now = ServerTimeService().now;
      _remaining = _targetTime.difference(now);
      if (_remaining.isNegative) {
        _remaining = Duration.zero;
        _pulseController.stop();
      } else if (_remaining.inMinutes < 3) {
        if (!_pulseController.isAnimating) {
          _pulseController.repeat(reverse: true);
        }
      } else {
        _pulseController.stop();
        _pulseController.reset();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Color _getTimerColor() {
    if (_remaining == Duration.zero) return AppColors.grey;
    if (_remaining.inMinutes < 3) return AppColors.timerCritical;
    if (_remaining.inMinutes < 10) return AppColors.timerWarning;
    return AppColors.accent;
  }

  String _buildTimeString() {
    final days = _remaining.inDays;
    final hours = _remaining.inHours % 24;
    final minutes = _remaining.inMinutes % 60;
    final seconds = _remaining.inSeconds % 60;

    String value;
    if (days > 0) {
      value = '${days}d ${hours}h ${minutes}m';
    } else if (hours > 0) {
      value = '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      value = '${minutes}m ${seconds}s';
    } else {
      value = '${seconds}s';
    }

    return _isUpcoming ? 'Bat dau sau $value' : value;
  }

  @override
  Widget build(BuildContext context) {
    if (_remaining == Duration.zero) {
      return Text(
        _isUpcoming ? 'Sap bat dau' : 'Da ket thuc',
        style:
            widget.textStyle ??
            (widget.showLarge
                ? AppTextStyles.h3.copyWith(
                    color: AppColors.grey,
                    fontWeight: FontWeight.w600,
                  )
                : AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.grey,
                    fontWeight: FontWeight.w600,
                  )),
      );
    }

    final timeString = _buildTimeString();
    final timerColor = _getTimerColor();
    final isCritical = _remaining.inMinutes < 3;

    if (widget.showLarge) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: timerColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: timerColor.withOpacity(0.3), width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_outlined, size: 32, color: timerColor),
            const SizedBox(width: 12),
            AnimatedBuilder(
              animation: _opacityAnimation,
              builder: (context, child) {
                final textOpacity = isCritical ? _opacityAnimation.value : 1.0;
                return Text(
                  timeString,
                  style: AppTextStyles.h3.copyWith(
                    color: timerColor.withOpacity(textOpacity),
                    fontWeight: FontWeight.bold,
                    fontSize: 28,
                  ),
                );
              },
            ),
          ],
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.timer_outlined, size: 18, color: timerColor),
        const SizedBox(width: 6),
        AnimatedBuilder(
          animation: _opacityAnimation,
          builder: (context, child) {
            final textOpacity = isCritical ? _opacityAnimation.value : 1.0;
            return Text(
              timeString,
              style:
                  widget.textStyle ??
                  AppTextStyles.bodyMedium.copyWith(
                    color: timerColor.withOpacity(textOpacity),
                    fontWeight: FontWeight.w600,
                  ),
            );
          },
        ),
      ],
    );
  }
}
