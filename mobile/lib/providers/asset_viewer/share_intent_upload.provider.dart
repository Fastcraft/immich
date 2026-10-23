import 'dart:async';
import 'dart:io';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/models/upload/share_intent_attachment.model.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/services/foreground_upload.service.dart';
import 'package:immich_mobile/services/share_intent_service.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

final shareIntentUploadProvider = StateNotifierProvider<ShareIntentUploadStateNotifier, List<ShareIntentAttachment>>(
  (ref) => ShareIntentUploadStateNotifier(
    ref.watch(appRouterProvider),
    ref.read(foregroundUploadServiceProvider),
    ref.read(shareIntentServiceProvider),
  ),
);

class ShareIntentUploadStateNotifier extends StateNotifier<List<ShareIntentAttachment>> {
  final AppRouter router;
  final ForegroundUploadService _foregroundUploadService;
  final ShareIntentService _shareIntentService;
  final Logger _logger = Logger('ShareIntentUploadStateNotifier');

  ShareIntentUploadStateNotifier(this.router, this._foregroundUploadService, this._shareIntentService) : super([]);

  void init() {
    _shareIntentService.onSharedMedia = onSharedMedia;
    _shareIntentService.init();
  }

  void onSharedMedia(List<ShareIntentAttachment> attachments) {
    router.removeWhere((route) => route.name == "ShareIntentRoute");
    clearAttachments();
    addAttachments(attachments);
    unawaited(router.push(ShareIntentRoute(attachments: attachments)));
  }

  void addAttachments(List<ShareIntentAttachment> attachments) {
    if (attachments.isEmpty) {
      return;
    }
    state = [...state, ...attachments];
  }

  void removeAttachment(ShareIntentAttachment attachment) {
    final updatedState = state.where((element) => element != attachment).toList();
    if (updatedState.length != state.length) {
      state = updatedState;
    }
  }

  void clearAttachments() {
    if (state.isEmpty) {
      return;
    }

    state = [];
  }

  Future<List<String>> uploadAll(List<File> files) async {
    final List<String> uploadedRemoteAssetIds = [];
    final runningIds = <int>{for (final file in files) p.hash(file.path)};
    if (runningIds.isNotEmpty) {
      state = [
        for (final attachment in state)
          if (runningIds.contains(attachment.id))
            attachment.copyWith(status: UploadStatus.running)
          else
            attachment,
      ];
    }

    await _foregroundUploadService.uploadShareIntent(
      files,
      onProgress: (fileId, bytes, totalBytes) {
        final progress = totalBytes > 0 ? bytes / totalBytes : 0.0;
        _updateProgress(fileId, progress);
      },
      onSuccess: (fileId, remoteAssetId) {
        uploadedRemoteAssetIds.add(remoteAssetId);
        _updateStatus(fileId, UploadStatus.complete, progress: 1.0);
      },
      onError: (fileId, errorMessage) {
        _logger.warning("Upload failed for file: $fileId, error: $errorMessage");
        _updateStatus(fileId, UploadStatus.failed);
      },
    );

    return uploadedRemoteAssetIds;
  }

  void _updateStatus(String fileId, UploadStatus status, {double? progress}) {
    final id = int.tryParse(fileId);
    if (id == null) {
      return;
    }
    final index = state.indexWhere((a) => a.id == id);
    if (index == -1) {
      return;
    }
    final current = state[index];
    final nextProgress = progress ?? current.uploadProgress;
    if (current.status == status && current.uploadProgress == nextProgress) {
      return;
    }
    final next = List<ShareIntentAttachment>.of(state, growable: false);
    next[index] = current.copyWith(status: status, uploadProgress: nextProgress);
    state = next;
  }

  void _updateProgress(String fileId, double progress) {
    final id = int.tryParse(fileId);
    if (id == null) {
      return;
    }
    final index = state.indexWhere((a) => a.id == id);
    if (index == -1) {
      return;
    }
    final current = state[index];
    // Throttle UI state updates to >= 1% steps to avoid rebuilding on every network packet
    if ((progress - current.uploadProgress).abs() < 0.01 && progress < 1.0) {
      return;
    }
    final next = List<ShareIntentAttachment>.of(state, growable: false);
    next[index] = current.copyWith(uploadProgress: progress);
    state = next;
  }
}
