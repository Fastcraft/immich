import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/timeline.model.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/generated/translations.g.dart';
import 'package:immich_mobile/presentation/widgets/bottom_sheet/favorite_bottom_sheet.widget.dart';
import 'package:immich_mobile/presentation/widgets/timeline/timeline.widget.dart';
import 'package:immich_mobile/providers/infrastructure/timeline.provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:immich_mobile/widgets/common/mesmerizing_sliver_app_bar.dart';

@RoutePage()
class RecentlyAddedFavoritesPage extends StatelessWidget {
  const RecentlyAddedFavoritesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      key: const ValueKey('recently_added_favorites_timeline'),
      overrides: [
        timelineServiceProvider.overrideWith((ref) {
          final user = ref.watch(currentUserProvider);
          if (user == null) {
            throw Exception('User must be logged in to access recently added favorites');
          }

          final timelineService = ref.watch(timelineFactoryProvider).favorite(user.id, sortBy: SortAssetsBy.uploaded);
          ref.onDispose(timelineService.dispose);
          return timelineService;
        }),
      ],
      child: Timeline(
        appBar: MesmerizingSliverAppBar(
          title: '${context.t.favorites} (${context.t.recently_added})',
        ),
        bottomSheet: const FavoriteBottomSheet(),
      ),
    );
  }
}
