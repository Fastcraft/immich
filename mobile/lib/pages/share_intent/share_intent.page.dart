import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/album/album.model.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/generated/translations.g.dart';
import 'package:immich_mobile/models/upload/share_intent_attachment.model.dart';
import 'package:immich_mobile/pages/common/large_leading_tile.dart';
import 'package:immich_mobile/presentation/widgets/album/new_album_name_modal.widget.dart';
import 'package:immich_mobile/providers/asset_viewer/share_intent_upload.provider.dart';
import 'package:immich_mobile/providers/infrastructure/remote_album.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/utils/url_helper.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';

@RoutePage()
class ShareIntentPage extends ConsumerStatefulWidget {
  const ShareIntentPage({super.key, required this.attachments});

  final List<ShareIntentAttachment> attachments;

  @override
  ConsumerState<ShareIntentPage> createState() => _ShareIntentPageState();
}

class _ShareIntentPageState extends ConsumerState<ShareIntentPage> {
  RemoteAlbum? _selectedAlbum;
  String? _newAlbumTitle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref.read(remoteAlbumProvider.notifier).refresh());
    });
  }

  Future<void> _openAlbumPicker() async {
    final albums = ref.read(remoteAlbumProvider).albums;

    final result = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return _ShareIntentAlbumPickerSheet(
          albums: albums,
          currentSelectedAlbumId: _selectedAlbum?.id,
          currentNewAlbumTitle: _newAlbumTitle,
        );
      },
    );

    if (!mounted || result == null) {
      return;
    }

    if (result == '__NONE__') {
      setState(() {
        _selectedAlbum = null;
        _newAlbumTitle = null;
      });
    } else if (result is RemoteAlbum) {
      setState(() {
        _selectedAlbum = result;
        _newAlbumTitle = null;
      });
    } else if (result is String) {
      setState(() {
        _newAlbumTitle = result;
        _selectedAlbum = null;
      });
    }
  }

  Widget _buildAlbumSelectorCard(BuildContext context, bool disabled) {
    final String albumText;
    final bool hasSelection = _selectedAlbum != null || _newAlbumTitle != null;

    if (_selectedAlbum != null) {
      albumText = _selectedAlbum!.name;
    } else if (_newAlbumTitle != null) {
      albumText = '${_newAlbumTitle!} (${context.t.create_album})';
    } else {
      albumText = context.t.none;
    }

    return Material(
      color: context.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: disabled ? null : _openAlbumPicker,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
          child: Row(
            children: [
              Icon(
                hasSelection ? Icons.photo_album_rounded : Icons.photo_album_outlined,
                color: hasSelection ? context.primaryColor : context.colorScheme.onSurfaceVariant,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t.add_to_album,
                      style: context.textTheme.labelSmall?.copyWith(
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      albumText,
                      style: context.textTheme.bodyMedium?.copyWith(
                        fontWeight: hasSelection ? FontWeight.w600 : FontWeight.normal,
                        color: hasSelection ? context.colorScheme.onSurface : context.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (hasSelection && !disabled)
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 16,
                  onPressed: () {
                    setState(() {
                      _selectedAlbum = null;
                      _newAlbumTitle = null;
                    });
                  },
                )
              else
                Icon(
                  Icons.arrow_drop_down_rounded,
                  color: context.colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentEndpoint = getServerUrl() ?? '--';
    final candidates = ref.watch(shareIntentUploadProvider);

    final isUploading = candidates.any((candidate) => candidate.status == UploadStatus.running);
    final isUploaded =
        candidates.isNotEmpty &&
        candidates.every(
          (candidate) => candidate.status == UploadStatus.complete || candidate.status == UploadStatus.failed,
        );

    void removeAttachment(ShareIntentAttachment attachment) {
      ref.read(shareIntentUploadProvider.notifier).removeAttachment(attachment);
    }

    void addAttachments(List<ShareIntentAttachment> attachments) {
      ref.read(shareIntentUploadProvider.notifier).addAttachments(attachments);
    }

    Future<void> upload() async {
      final files = candidates.map((candidate) => candidate.file).toList();
      final uploadedIds = await ref.read(shareIntentUploadProvider.notifier).uploadAll(files);

      if (uploadedIds.isNotEmpty) {
        if (_selectedAlbum != null) {
          try {
            await ref.read(remoteAlbumProvider.notifier).addAssets(_selectedAlbum!.id, uploadedIds);
            if (context.mounted) {
              ImmichToast.show(
                context: context,
                msg: context.t.add_to_album_bottom_sheet_added(album: _selectedAlbum!.name),
              );
            }
          } catch (_) {
            // Error handling handled by provider
          }
        } else if (_newAlbumTitle != null && _newAlbumTitle!.isNotEmpty) {
          try {
            final album = await ref.read(remoteAlbumProvider.notifier).createAlbum(
              title: _newAlbumTitle!,
              assetIds: uploadedIds,
            );
            if (context.mounted && album != null) {
              ImmichToast.show(
                context: context,
                msg: context.t.add_to_album_bottom_sheet_added(album: album.name),
              );
            }
          } catch (_) {
            // Error handling handled by provider
          }
        }
      }
    }

    bool isSelected(ShareIntentAttachment attachment) {
      return candidates.contains(attachment);
    }

    void toggleSelection(ShareIntentAttachment attachment) {
      if (isSelected(attachment)) {
        removeAttachment(attachment);
      } else {
        addAttachments([attachment]);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(context.t.upload_to_immich(count: candidates.length)),
            Text(
              currentEndpoint,
              style: context.textTheme.labelMedium?.copyWith(color: context.colorScheme.onSurface.withAlpha(200)),
            ),
          ],
        ),
        leading: IconButton(
          onPressed: () {
            unawaited(context.navigateTo(const TabShellRoute()));
          },
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: ListView.builder(
        itemCount: widget.attachments.length,
        itemBuilder: (context, index) {
          final attachment = widget.attachments[index];
          final target = candidates.firstWhere((element) => element.id == attachment.id, orElse: () => attachment);

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 16),
            child: LargeLeadingTile(
              onTap: () => toggleSelection(attachment),
              disabled: isUploading || isUploaded,
              selected: isSelected(attachment),
              leading: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.all(Radius.circular(16)),
                    child: attachment.isImage
                        ? Image.file(attachment.file, width: 64, height: 64, fit: BoxFit.cover)
                        : const SizedBox(
                            width: 64,
                            height: 64,
                            child: Center(child: Icon(Icons.videocam, color: Colors.white)),
                          ),
                  ),
                  if (attachment.isImage)
                    const Positioned(
                      top: 8,
                      right: 8,
                      child: Icon(
                        Icons.image,
                        color: Colors.white,
                        size: 20,
                        shadows: [Shadow(offset: Offset.zero, blurRadius: 8.0, color: Colors.black45)],
                      ),
                    ),
                ],
              ),
              title: Text(attachment.fileName, style: context.textTheme.titleSmall),
              subtitle: Text(attachment.fileSize, style: context.textTheme.labelLarge),
              trailing: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: UploadStatusIcon(
                  selected: isSelected(attachment),
                  status: target.status,
                  progress: target.uploadProgress,
                ),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildAlbumSelectorCard(context, isUploading || isUploaded),
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: (isUploading || isUploaded) ? null : upload,
                  child: (isUploading || isUploaded) ? UploadingText(candidates: candidates) : Text(context.t.upload),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShareIntentAlbumPickerSheet extends StatefulWidget {
  final List<RemoteAlbum> albums;
  final String? currentSelectedAlbumId;
  final String? currentNewAlbumTitle;

  const _ShareIntentAlbumPickerSheet({
    required this.albums,
    this.currentSelectedAlbumId,
    this.currentNewAlbumTitle,
  });

  @override
  State<_ShareIntentAlbumPickerSheet> createState() => _ShareIntentAlbumPickerSheetState();
}

class _ShareIntentAlbumPickerSheetState extends State<_ShareIntentAlbumPickerSheet> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final filteredAlbums = widget.albums.where((album) {
      if (_searchQuery.isEmpty) return true;
      return album.name.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.colorScheme.onSurfaceVariant.withAlpha(100),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      context.t.add_to_album,
                      style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () async {
                        final albumName = await showDialog<String?>(
                          context: context,
                          builder: (context) => const NewAlbumNameModal(),
                        );
                        if (albumName != null && albumName.isNotEmpty && context.mounted) {
                          Navigator.of(context).pop(albumName);
                        }
                      },
                      icon: Icon(Icons.add, color: context.primaryColor, size: 20),
                      label: Text(
                        context.t.common_create_new_album,
                        style: TextStyle(color: context.primaryColor, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.albums.length > 5)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: context.t.search,
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value.trim();
                      });
                    },
                  ),
                ),
              const Divider(height: 16),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: filteredAlbums.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      final isSelected = widget.currentSelectedAlbumId == null && widget.currentNewAlbumTitle == null;
                      return ListTile(
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: context.colorScheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.photo_library_outlined, color: context.colorScheme.primary),
                        ),
                        title: Text(context.t.none),
                        subtitle: Text(context.t.photos),
                        trailing: isSelected ? Icon(Icons.check_rounded, color: context.primaryColor) : null,
                        onTap: () => Navigator.of(context).pop('__NONE__'),
                      );
                    }

                    final album = filteredAlbums[index - 1];
                    final isSelected = widget.currentSelectedAlbumId == album.id;

                    return ListTile(
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: context.colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          album.isShared ? Icons.folder_shared_outlined : Icons.folder_outlined,
                          color: context.colorScheme.primary,
                        ),
                      ),
                      title: Text(
                        album.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
                      ),
                      subtitle: Text(context.t.items_count(count: album.assetCount)),
                      trailing: isSelected ? Icon(Icons.check_rounded, color: context.primaryColor) : null,
                      onTap: () => Navigator.of(context).pop(album),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class UploadingText extends StatelessWidget {
  const UploadingText({super.key, required this.candidates});
  final List<ShareIntentAttachment> candidates;

  @override
  Widget build(BuildContext context) {
    final uploadedCount = candidates.where((element) {
      return element.status == UploadStatus.complete;
    }).length;

    return Text(context.t.shared_intent_upload_button_progress_text(current: uploadedCount, total: candidates.length));
  }
}

class UploadStatusIcon extends StatelessWidget {
  const UploadStatusIcon({super.key, required this.status, required this.selected, this.progress = 0});

  final UploadStatus status;
  final double progress;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    if (!selected) {
      return Icon(
        Icons.check_circle_outline_rounded,
        color: context.colorScheme.onSurface.withAlpha(100),
        semanticLabel: context.t.not_selected,
      );
    }

    final statusIcon = switch (status) {
      UploadStatus.enqueued => Icon(
        Icons.check_circle_rounded,
        color: context.primaryColor,
        semanticLabel: context.t.enqueued,
      ),
      UploadStatus.running => Stack(
        alignment: AlignmentDirectional.center,
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: TweenAnimationBuilder(
              tween: Tween<double>(begin: 0.0, end: progress),
              duration: const Duration(milliseconds: 500),
              builder: (context, value, _) => CircularProgressIndicator(
                backgroundColor: context.colorScheme.surfaceContainerLow,
                strokeWidth: 3,
                value: value,
                semanticsLabel: context.t.uploading,
              ),
            ),
          ),
          Text(
            (progress * 100).toStringAsFixed(0),
            style: context.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
      UploadStatus.complete => Icon(
        Icons.check_circle_rounded,
        color: Colors.green,
        semanticLabel: context.t.completed,
      ),
      UploadStatus.failed => Icon(Icons.error_rounded, color: Colors.red, semanticLabel: context.t.failed),
    };

    return statusIcon;
  }
}
