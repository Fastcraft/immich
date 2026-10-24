import 'dart:async';

import 'package:flutter/material.dart';

enum SkipDirection { rewind, forward }

class VideoPlaybackFeedbackController {
  void Function(SkipDirection direction, {int? seconds})? _onSkip;
  ValueChanged<bool>? onActiveChanged;
  bool _isActive = false;

  bool get isActive => _isActive;

  void _setActive(bool active) {
    if (_isActive == active) {
      return;
    }
    _isActive = active;
    onActiveChanged?.call(active);
  }

  void triggerSkip(SkipDirection direction, {int? seconds}) {
    _onSkip?.call(direction, seconds: seconds);
  }
}

class VideoPlaybackFeedback extends StatefulWidget {
  final bool isFastForwarding;
  final VideoPlaybackFeedbackController? controller;

  const VideoPlaybackFeedback({
    super.key,
    required this.isFastForwarding,
    this.controller,
  });

  @override
  State<VideoPlaybackFeedback> createState() => _VideoPlaybackFeedbackState();
}

class _VideoPlaybackFeedbackState extends State<VideoPlaybackFeedback>
    with SingleTickerProviderStateMixin {
  SkipDirection? _currentDirection;
  int _accumulatedSeconds = 0;
  Timer? _dismissTimer;
  late final AnimationController _animController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    widget.controller?._onSkip = _handleSkip;

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.8, end: 1.1).chain(
          CurveTween(curve: Curves.easeOutCubic),
        ),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.1, end: 1.0).chain(
          CurveTween(curve: Curves.easeInOut),
        ),
        weight: 60,
      ),
    ]).animate(_animController);

    _opacityAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0).chain(
          CurveTween(curve: Curves.easeIn),
        ),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(1.0),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0).chain(
          CurveTween(curve: Curves.easeOut),
        ),
        weight: 40,
      ),
    ]).animate(_animController);
  }

  @override
  void didUpdateWidget(covariant VideoPlaybackFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller?._onSkip = null;
      widget.controller?._onSkip = _handleSkip;
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _animController.dispose();
    widget.controller?._setActive(false);
    widget.controller?._onSkip = null;
    super.dispose();
  }

  void _handleSkip(SkipDirection direction, {int? seconds}) {
    _dismissTimer?.cancel();

    final step = seconds ?? 10;
    setState(() {
      if (_currentDirection == direction) {
        _accumulatedSeconds += step;
      } else {
        _currentDirection = direction;
        _accumulatedSeconds = step;
      }
    });
    widget.controller?._setActive(true);

    _animController.forward(from: 0.0);

    _dismissTimer = Timer(const Duration(milliseconds: 750), () {
      if (mounted) {
        setState(() {
          _currentDirection = null;
          _accumulatedSeconds = 0;
        });
      }
      widget.controller?._setActive(false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isForward = _currentDirection == SkipDirection.forward;
    final isRewind = _currentDirection == SkipDirection.rewind;
    final hasSkip = _currentDirection != null;

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Skip Ripple and indicator
          if (hasSkip)
            Align(
              alignment: isForward ? Alignment.centerRight : Alignment.centerLeft,
              child: FadeTransition(
                opacity: _opacityAnimation,
                child: FractionallySizedBox(
                  widthFactor: 0.5,
                  heightFactor: 1.0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.horizontal(
                        left: isForward ? const Radius.circular(500) : Radius.zero,
                        right: isRewind ? const Radius.circular(500) : Radius.zero,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: ScaleTransition(
                      scale: _scaleAnimation,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isForward ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
                            color: Colors.white,
                            size: 44,
                            shadows: const [
                              Shadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 2)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            isForward ? "+$_accumulatedSeconds s" : "-$_accumulatedSeconds s",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                              shadows: [
                                Shadow(color: Colors.black87, blurRadius: 10, offset: Offset(0, 2)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // 2.0x Fast Forward Badge (Shown at top center when long-pressing)
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 16.0),
                child: AnimatedOpacity(
                  opacity: widget.isFastForwarding ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 150),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                        width: 1,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black38,
                          blurRadius: 12,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "2.0x",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        SizedBox(width: 6),
                        Icon(
                          Icons.fast_forward_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
