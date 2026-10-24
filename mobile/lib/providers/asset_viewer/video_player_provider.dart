import 'dart:async';

import 'package:flutter/services.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:native_video_player/native_video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

part 'video_player_provider.freezed.dart';

enum VideoPlaybackStatus { paused, playing, buffering, completed }

@freezed
abstract class VideoPlayerState with _$VideoPlayerState {
  const factory VideoPlayerState({
    required Duration position,
    required Duration duration,
    required VideoPlaybackStatus status,
  }) = _VideoPlayerState;
}

const _defaultState = VideoPlayerState(
  position: Duration.zero,
  duration: Duration.zero,
  status: VideoPlaybackStatus.paused,
);

final videoPlayerProvider = StateNotifierProvider.autoDispose.family<VideoPlayerNotifier, VideoPlayerState, String>((
  ref,
  name,
) {
  return VideoPlayerNotifier();
});

class VideoPlayerNotifier extends StateNotifier<VideoPlayerState> {
  static final _log = Logger('VideoPlayerNotifier');

  VideoPlayerNotifier() : super(_defaultState);

  NativeVideoPlayerController? _controller;
  Timer? _bufferingTimer;
  Timer? _seekTimer;
  Timer? _seekSettleTimer;
  Duration? _pendingSeekPosition;
  bool _isSeekingNative = false;
  VideoPlaybackStatus? _holdStatus;

  Duration get effectivePosition => _pendingSeekPosition ?? state.position;

  @override
  void dispose() {
    _bufferingTimer?.cancel();
    _seekTimer?.cancel();
    _seekSettleTimer?.cancel();
    _pendingSeekPosition = null;
    unawaited(WakelockPlus.disable());
    _controller = null;

    super.dispose();
  }

  void attachController(NativeVideoPlayerController controller) {
    _controller = controller;
  }

  Future<void> load(VideoSource source) async {
    _startBufferingTimer();
    try {
      await _controller?.loadVideoSource(source);
    } catch (e) {
      if (e is MissingPluginException) {
        return;
      }
      _log.warning('Error loading video source: $e');
    }
  }

  Future<void> pause() async {
    if (_controller == null) {
      return;
    }

    _bufferingTimer?.cancel();

    try {
      await _controller!.pause();
      await _flushSeek();
    } catch (e) {
      if (e is MissingPluginException) {
        return;
      }
      _log.warning('Error pausing video: $e');
    }
  }

  Future<void> play() async {
    if (_controller == null) {
      return;
    }

    try {
      await _flushSeek();
      await _controller!.play();
    } catch (e) {
      if (e is MissingPluginException) {
        return;
      }
      _log.warning('Error playing video: $e');
    }

    _startBufferingTimer();
  }

  Future<void> _flushSeek() async {
    final timer = _seekTimer;
    if (timer == null || !timer.isActive) {
      return;
    }

    timer.cancel();
    final target = _pendingSeekPosition ?? state.position;
    await _executeSeek(target);
  }

  Future<void> _executeSeek(Duration target) async {
    final controller = _controller;
    if (controller == null) {
      return;
    }

    // NativeVideoPlayerController.seekTo clamps position to videoInfo?.duration ?? 0.
    // If videoInfo is not ready yet (or duration <= 0), defer until onNativePlaybackReady.
    if ((controller.videoInfo?.duration ?? 0) <= 0) {
      return;
    }

    _isSeekingNative = true;
    try {
      await controller.seekTo(target.inMilliseconds);
    } catch (e) {
      if (e is MissingPluginException) {
        return;
      }
      _log.warning('Error seeking video: $e');
    } finally {
      _isSeekingNative = false;
      if (mounted && !(_seekTimer?.isActive ?? false)) {
        _seekSettleTimer?.cancel();
        _seekSettleTimer = Timer(const Duration(seconds: 5), () {
          if (mounted && !(_seekTimer?.isActive ?? false) && !_isSeekingNative) {
            _pendingSeekPosition = null;
          }
        });
      }
    }
  }

  void seekTo(Duration position) {
    if (_controller == null) {
      return;
    }

    _pendingSeekPosition = position;
    if (state.position != position) {
      state = state.copyWith(position: position);
    }

    _seekSettleTimer?.cancel();
    _seekTimer?.cancel();
    _seekTimer = Timer(const Duration(milliseconds: 350), () async {
      final target = _pendingSeekPosition ?? state.position;
      await _executeSeek(target);
    });
  }

  void toggle() {
    _holdStatus = null;

    switch (state.status) {
      case VideoPlaybackStatus.paused:
        unawaited(play());
      case VideoPlaybackStatus.playing || VideoPlaybackStatus.buffering:
        unawaited(pause());
      case VideoPlaybackStatus.completed:
        unawaited(restart());
    }
  }

  /// Pauses playback and preserves the current status for later restoration.
  void hold() {
    if (_holdStatus != null) {
      return;
    }

    _holdStatus = state.status;
    unawaited(pause());
  }

  /// Restores playback to the status before [hold] was called.
  void release() {
    final status = _holdStatus;
    _holdStatus = null;

    switch (status) {
      case VideoPlaybackStatus.playing || VideoPlaybackStatus.buffering:
        unawaited(play());
      default:
    }
  }

  Future<void> restart() async {
    seekTo(Duration.zero);
    await play();
  }

  Future<void> setVolume(double volume) async {
    try {
      await _controller?.setVolume(volume);
    } catch (e) {
      _log.warning('Error setting volume: $e');
    }
  }

  Future<void> setLoop(bool loop) async {
    try {
      await _controller?.setLoop(loop);
    } catch (e) {
      _log.warning('Error setting loop: $e');
    }
  }

  void seekRelative(Duration delta, {Duration? fallbackDuration}) {
    if (_controller == null) {
      return;
    }

    final effectiveDuration = state.duration > Duration.zero ? state.duration : (fallbackDuration ?? Duration.zero);
    if (effectiveDuration <= Duration.zero) {
      return;
    }

    if (state.duration <= Duration.zero) {
      state = state.copyWith(duration: effectiveDuration);
    }

    final int durationMs = effectiveDuration.inMilliseconds;
    // Leave a safe margin before end of stream to prevent decoder crash or immediate loop restart
    final int marginMs = durationMs >= 10000 ? 1000 : 250;
    final int safeMaxMs = durationMs > marginMs ? durationMs - marginMs : durationMs;
    final Duration basePosition = _pendingSeekPosition ?? state.position;
    final int targetMs = (basePosition + delta).inMilliseconds;
    final int clampedMs = targetMs.clamp(0, safeMaxMs);
    seekTo(Duration(milliseconds: clampedMs));
  }

  Future<void> setPlaybackSpeed(double speed) async {
    try {
      await _controller?.setPlaybackSpeed(speed);
    } catch (e) {
      _log.warning('Error setting playback speed: $e');
    }
  }

  void onNativePlaybackReady() {
    if (!mounted) {
      return;
    }

    final playbackInfo = _controller?.playbackInfo;
    final videoInfo = _controller?.videoInfo;

    if (playbackInfo == null || videoInfo == null) {
      return;
    }

    var status = _mapStatus(playbackInfo.status);
    if (playbackInfo.status == PlaybackStatus.stopped && state.status != VideoPlaybackStatus.completed) {
      // Never played yet, not completed = we show the resume button instead of the replay button
      status = VideoPlaybackStatus.paused;
    }

    if (status != VideoPlaybackStatus.playing) {
      // No playback = no loading indicator needed
      _bufferingTimer?.cancel();
    }

    final pendingTarget = _pendingSeekPosition;
    final hasActiveSeek = (_seekTimer?.isActive ?? false) || _isSeekingNative || (_seekSettleTimer?.isActive ?? false);

    state = state.copyWith(
      position: pendingTarget ?? Duration(milliseconds: playbackInfo.position),
      duration: videoInfo.duration > 0 ? Duration(milliseconds: videoInfo.duration) : state.duration,
      status: status,
    );

    if (pendingTarget != null && !hasActiveSeek && videoInfo.duration > 0) {
      unawaited(_executeSeek(pendingTarget));
    }
  }

  void onNativePositionChanged() {
    if (!mounted || (_seekTimer?.isActive ?? false) || _isSeekingNative) {
      return;
    }

    final playbackInfo = _controller?.playbackInfo;
    if (playbackInfo == null) {
      return;
    }

    final position = Duration(milliseconds: playbackInfo.position);
    final pendingTarget = _pendingSeekPosition;
    if (pendingTarget != null) {
      // Ignore stale pre-seek position updates from the native 8ms timer until the player
      // actually catches up to the target seek position (or the settle timer expires).
      if ((position - pendingTarget).abs() > const Duration(milliseconds: 2500)) {
        return;
      }
      _seekSettleTimer?.cancel();
      _pendingSeekPosition = null;
    }

    if (state.position == position) {
      return;
    }

    if (state.status == VideoPlaybackStatus.playing) {
      _startBufferingTimer();
    }

    state = state.copyWith(
      position: position,
      status: state.status == VideoPlaybackStatus.buffering ? VideoPlaybackStatus.playing : state.status,
    );
  }

  void onNativeStatusChanged() {
    if (!mounted) {
      return;
    }

    final playbackInfo = _controller?.playbackInfo;
    if (playbackInfo == null) {
      return;
    }

    final newStatus = _mapStatus(playbackInfo.status);
    switch (newStatus) {
      case VideoPlaybackStatus.playing:
        unawaited(WakelockPlus.enable());
        _startBufferingTimer();
      default:
        onNativePlaybackEnded();
    }

    if (state.status != newStatus) {
      state = state.copyWith(status: newStatus);
    }
  }

  void onNativePlaybackEnded() {
    unawaited(WakelockPlus.disable());
    _bufferingTimer?.cancel();
  }

  void _startBufferingTimer() {
    _bufferingTimer?.cancel();
    _bufferingTimer = Timer(const Duration(seconds: 1), () {
      if (mounted && state.status != VideoPlaybackStatus.completed) {
        state = state.copyWith(status: VideoPlaybackStatus.buffering);
      }
    });
  }

  static VideoPlaybackStatus _mapStatus(PlaybackStatus status) => switch (status) {
    PlaybackStatus.playing => VideoPlaybackStatus.playing,
    PlaybackStatus.paused => VideoPlaybackStatus.paused,
    PlaybackStatus.stopped => VideoPlaybackStatus.completed,
  };
}
