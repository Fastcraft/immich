import 'dart:async';
import 'dart:io';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/models/upload/share_intent_attachment.model.dart';
import 'package:share_handler/share_handler.dart';

final shareHandlerRepositoryProvider = Provider((ref) => ShareHandlerRepository());

class ShareHandlerRepository {
  ShareHandlerRepository();

  void Function(List<ShareIntentAttachment> attachments)? onSharedMedia;
  StreamSubscription<SharedMedia>? _subscription;

  Future<void> init() async {
    final handler = ShareHandlerPlatform.instance;

    await _subscription?.cancel();
    _subscription = handler.sharedMediaStream.listen((SharedMedia media) {
      if (media.attachments != null) {
        final payload = _buildPayload(media.attachments!);
        if (payload.isNotEmpty) {
          onSharedMedia?.call(payload);
        }
      }
    });

    final media = await handler.getInitialSharedMedia();
    if (media != null && media.attachments != null) {
      await handler.resetInitialSharedMedia();
      final payload = _buildPayload(media.attachments!);
      if (payload.isNotEmpty) {
        onSharedMedia?.call(payload);
      }
    }
  }

  List<ShareIntentAttachment> _buildPayload(List<SharedAttachment?> attachments) {
    final payload = <ShareIntentAttachment>[];

    for (final attachment in attachments) {
      if (attachment == null) {
        continue;
      }

      final type = attachment.type == SharedAttachmentType.image
          ? ShareIntentAttachmentType.image
          : ShareIntentAttachmentType.video;

      int fileLength = 0;
      try {
        fileLength = File(attachment.path).lengthSync();
      } catch (_) {
        fileLength = 0;
      }

      payload.add(
        ShareIntentAttachment(
          path: attachment.path,
          type: type,
          status: UploadStatus.enqueued,
          uploadProgress: 0.0,
          fileLength: fileLength,
        ),
      );
    }

    return payload;
  }
}
