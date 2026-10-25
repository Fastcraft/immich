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

final favoriteSortByProvider = StateProvider<SortAssetsBy>((ref) => SortAssetsBy.taken);

@RoutePage()
class FavoritePage extends ConsumerWidget {
  const FavoritePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sortBy = ref.watch(favoriteSortByProvider);

    return ProviderScope(
      overrides: [
        timelineServiceProvider.overrideWith((ref) {
          final user = ref.watch(currentUserProvider);
          if (user == null) {
            throw Exception('User must be logged in to access favorite');
          }

          final timelineService = ref.watch(timelineFactoryProvider).favorite(user.id, sortBy: sortBy);
          ref.onDispose(timelineService.dispose);
          return timelineService;
        }),
      ],
      child: Timeline(
        appBar: MesmerizingSliverAppBar(
          title: context.t.favorites,
          actionsBuilder: (context, actionIconColor, actionIconShadows) => [
            PopupMenuButton<SortAssetsBy>(
              icon: Icon(
                sortBy == SortAssetsBy.uploaded ? Icons.history_rounded : Icons.swap_vert_rounded,
                color: actionIconColor,
                shadows: actionIconShadows,
              ),
              tooltip: context.t.sort_recent,
              initialValue: sortBy,
              onSelected: (SortAssetsBy value) {
                ref.read(favoriteSortByProvider.notifier).state = value;
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: SortAssetsBy.taken,
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today_outlined,
                        size: 20,
                        color: sortBy == SortAssetsBy.taken ? context.primaryColor : null,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        context.t.sort_created,
                        style: TextStyle(
                          fontWeight: sortBy == SortAssetsBy.taken ? FontWeight.bold : FontWeight.normal,
                          color: sortBy == SortAssetsBy.taken ? context.primaryColor : null,
                        ),
                      ),
                      if (sortBy == SortAssetsBy.taken) ...[
                        const Spacer(),
                        Icon(Icons.check, size: 20, color: context.primaryColor),
                      ],
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: SortAssetsBy.uploaded,
                  child: Row(
                    children: [
                      Icon(
                        Icons.history_rounded,
                        size: 20,
                        color: sortBy == SortAssetsBy.uploaded ? context.primaryColor : null,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        context.t.recently_added,
                        style: TextStyle(
                          fontWeight: sortBy == SortAssetsBy.uploaded ? FontWeight.bold : FontWeight.normal,
                          color: sortBy == SortAssetsBy.uploaded ? context.primaryColor : null,
                        ),
                      ),
                      if (sortBy == SortAssetsBy.uploaded) ...[
                        const Spacer(),
                        Icon(Icons.check, size: 20, color: context.primaryColor),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        bottomSheet: const FavoriteBottomSheet(),
      ),
    );
  }
}
