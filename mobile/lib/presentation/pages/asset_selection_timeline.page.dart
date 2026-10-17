import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/services/timeline.service.dart';
import 'package:immich_mobile/presentation/widgets/timeline/timeline.widget.dart';
import 'package:immich_mobile/providers/infrastructure/timeline.provider.dart';
import 'package:immich_mobile/providers/timeline/asset_selection_filter.provider.dart';
import 'package:immich_mobile/providers/timeline/multiselect.provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';

enum AssetSelectionSource {
  timeline,
  favorite,
  localAlbum,
}

@RoutePage()
class AssetSelectionTimelinePage extends ConsumerStatefulWidget {
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
  ConsumerState<AssetSelectionTimelinePage> createState() => _AssetSelectionTimelinePageState();
}

class _AssetSelectionTimelinePageState extends ConsumerState<AssetSelectionTimelinePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final initialSourceType = switch (widget.source) {
        AssetSelectionSource.favorite => AssetSelectionSourceType.favorites,
        AssetSelectionSource.localAlbum => AssetSelectionSourceType.localDevice,
        AssetSelectionSource.timeline => AssetSelectionSourceType.timeline,
      };
      ref.read(assetSelectionFilterProvider.notifier).state = AssetSelectionFilterState(
        source: initialSourceType,
        localAlbumId: widget.localAlbumId,
        localAlbumTitle: widget.title,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        multiSelectProvider.overrideWith(
          () => MultiSelectNotifier(
            MultiSelectState(selectedAssets: {}, lockedSelectionAssets: widget.lockedSelectionAssets, forceEnable: true),
          ),
        ),
        timelineServiceProvider.overrideWith((ref) {
          final factory = ref.watch(timelineFactoryProvider);
          final filterState = ref.watch(assetSelectionFilterProvider);
          final TimelineService timelineService;

          switch (filterState.source) {
            case AssetSelectionSourceType.favorites:
              final user = ref.watch(currentUserProvider);
              if (user == null) {
                throw Exception('User must be logged in to select favorites');
              }
              timelineService = factory.favorite(user.id);
            case AssetSelectionSourceType.localDevice:
              timelineService = factory.localAlbum(albumId: filterState.localAlbumId ?? '');
            case AssetSelectionSourceType.timeline:
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
