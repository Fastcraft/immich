import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/services/timeline.service.dart';
import 'package:immich_mobile/presentation/widgets/timeline/timeline.widget.dart';
import 'package:immich_mobile/providers/infrastructure/timeline.provider.dart';
import 'package:immich_mobile/providers/timeline/multiselect.provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';

enum AssetSelectionSource {
  timeline,
  favorite,
  localAlbum,
}

@RoutePage()
class AssetSelectionTimelinePage extends StatelessWidget {
  final Set<BaseAsset> lockedSelectionAssets;
  final AssetSelectionSource source;
  final String? localAlbumId;
  final String? title;

  const AssetSelectionTimelinePage({
    super.key,
    this.lockedSelectionAssets = const {},
    this.source = AssetSelectionSource.timeline,
    this.localAlbumId,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        multiSelectProvider.overrideWith(
          () => MultiSelectNotifier(
            MultiSelectState(selectedAssets: {}, lockedSelectionAssets: lockedSelectionAssets, forceEnable: true),
          ),
        ),
        timelineServiceProvider.overrideWith((ref) {
          final factory = ref.watch(timelineFactoryProvider);
          final TimelineService timelineService;

          switch (source) {
            case AssetSelectionSource.favorite:
              final user = ref.watch(currentUserProvider);
              if (user == null) {
                throw Exception('User must be logged in to select favorites');
              }
              timelineService = factory.favorite(user.id);
            case AssetSelectionSource.localAlbum:
              timelineService = factory.localAlbum(albumId: localAlbumId ?? '');
            case AssetSelectionSource.timeline:
              final timelineUsers = ref.watch(timelineUsersProvider).valueOrNull ?? [];
              timelineService = factory.main(timelineUsers);
          }

          ref.onDispose(timelineService.dispose);
          return timelineService;
        }),
      ],
      child: const Timeline(showStorageIndicator: true),
    );
  }
}

