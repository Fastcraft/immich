import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/album/local_album.model.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/generated/translations.g.dart';
import 'package:immich_mobile/presentation/pages/asset_selection_timeline.page.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';

/// Shows a bottom sheet allowing the user to pick assets from:
/// 1. Timeline (cloud and backed up media)
/// 2. Device Photos (local albums stored on this device)
/// 3. Favorites
Future<Set<BaseAsset>?> showAssetSourceSelectionSheet({
  required BuildContext context,
  required WidgetRef ref,
  Set<BaseAsset> lockedAssets = const {},
}) async {
  final source = await showModalBottomSheet<_AssetSourceType>(
    context: context,
    backgroundColor: context.colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (BuildContext sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: sheetContext.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Text(
                  sheetContext.t.add_photos,
                  style: sheetContext.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: sheetContext.colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.photo_library_outlined, color: sheetContext.colorScheme.primary),
                ),
                title: Text(sheetContext.t.photos),
                subtitle: Text(sheetContext.t.timeline),
                onTap: () => Navigator.of(sheetContext).pop(_AssetSourceType.timeline),
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: sheetContext.colorScheme.secondaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.phone_android_rounded, color: sheetContext.colorScheme.secondary),
                ),
                title: Text(sheetContext.t.on_this_device),
                subtitle: Text(sheetContext.t.albums),
                onTap: () => Navigator.of(sheetContext).pop(_AssetSourceType.localAlbum),
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: sheetContext.colorScheme.tertiaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.favorite_rounded, color: sheetContext.colorScheme.tertiary),
                ),
                title: Text(sheetContext.t.favorites),
                subtitle: Text(sheetContext.t.favorite),
                onTap: () => Navigator.of(sheetContext).pop(_AssetSourceType.favorite),
              ),
            ],
          ),
        ),
      );
    },
  );

  if (source == null || !context.mounted) {
    return null;
  }

  switch (source) {
    case _AssetSourceType.timeline:
      return Navigator.of(context).push<Set<BaseAsset>>(
        MaterialPageRoute(
          builder: (_) => AssetSelectionTimelinePage(
            lockedSelectionAssets: lockedAssets,
            source: AssetSelectionSource.timeline,
          ),
        ),
      );

    case _AssetSourceType.favorite:
      return Navigator.of(context).push<Set<BaseAsset>>(
        MaterialPageRoute(
          builder: (_) => AssetSelectionTimelinePage(
            lockedSelectionAssets: lockedAssets,
            source: AssetSelectionSource.favorite,
          ),
        ),
      );

    case _AssetSourceType.localAlbum:
      final localAlbums = await ref.read(localAlbumProvider.future);
      if (!context.mounted) {
        return null;
      }

      if (localAlbums.isEmpty) {
        return null;
      }

      LocalAlbum? targetAlbum;
      if (localAlbums.length == 1) {
        targetAlbum = localAlbums.first;
      } else {
        targetAlbum = await showModalBottomSheet<LocalAlbum>(
          context: context,
          backgroundColor: context.colorScheme.surface,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (BuildContext pickerContext) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      pickerContext.t.on_this_device,
                      style: pickerContext.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: localAlbums.length,
                      itemBuilder: (ctx, index) {
                        final album = localAlbums[index];
                        return ListTile(
                          leading: const Icon(Icons.folder_outlined),
                          title: Text(album.name),
                          subtitle: Text(ctx.t.items_count(count: album.assetCount)),
                          onTap: () => Navigator.of(ctx).pop(album),
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

      if (targetAlbum == null || !context.mounted) {
        return null;
      }

      return Navigator.of(context).push<Set<BaseAsset>>(
        MaterialPageRoute(
          builder: (_) => AssetSelectionTimelinePage(
            lockedSelectionAssets: lockedAssets,
            source: AssetSelectionSource.localAlbum,
            localAlbumId: targetAlbum.id,
            title: targetAlbum.name,
          ),
        ),
      );
  }
}

enum _AssetSourceType {
  timeline,
  localAlbum,
  favorite,
}
