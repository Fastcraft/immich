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
class FavoritePage extends ConsumerStatefulWidget {
  const FavoritePage({super.key});

  @override
  ConsumerState<FavoritePage> createState() => _FavoritePageState();
}

class _FavoritePageState extends ConsumerState<FavoritePage> {
  SortAssetsBy _sortBy = SortAssetsBy.taken;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      key: ValueKey('favorite_timeline_${_sortBy.name}'),
      overrides: [
        timelineServiceProvider.overrideWith((ref) {
          final user = ref.watch(currentUserProvider);
          if (user == null) {
            throw Exception('User must be logged in to access favorite');
          }

          final timelineService = ref.watch(timelineFactoryProvider).favorite(user.id, sortBy: _sortBy);
          ref.onDispose(timelineService.dispose);
          return timelineService;
        }),
      ],
      child: Timeline(
        appBar: MesmerizingSliverAppBar(
          title: _sortBy == SortAssetsBy.uploaded
              ? '${context.t.favorites} (${context.t.recently_added})'
              : context.t.favorites,
          actionsBuilder: (context, actionIconColor, actionIconShadows) => [
            PopupMenuButton<SortAssetsBy>(
              icon: Icon(
                _sortBy == SortAssetsBy.uploaded ? Icons.history_rounded : Icons.swap_vert_rounded,
                color: actionIconColor,
                shadows: actionIconShadows,
              ),
              tooltip: context.t.sort_recent,
              initialValue: _sortBy,
              onSelected: (SortAssetsBy value) {
                if (_sortBy != value) {
                  setState(() {
                    _sortBy = value;
                  });
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: SortAssetsBy.taken,
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today_outlined,
                        size: 20,
                        color: _sortBy == SortAssetsBy.taken ? context.primaryColor : null,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        context.t.sort_created,
                        style: TextStyle(
                          fontWeight: _sortBy == SortAssetsBy.taken ? FontWeight.bold : FontWeight.normal,
                          color: _sortBy == SortAssetsBy.taken ? context.primaryColor : null,
                        ),
                      ),
                      if (_sortBy == SortAssetsBy.taken) ...[
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
                        color: _sortBy == SortAssetsBy.uploaded ? context.primaryColor : null,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        context.t.recently_added,
                        style: TextStyle(
                          fontWeight: _sortBy == SortAssetsBy.uploaded ? FontWeight.bold : FontWeight.normal,
                          color: _sortBy == SortAssetsBy.uploaded ? context.primaryColor : null,
                        ),
                      ),
                      if (_sortBy == SortAssetsBy.uploaded) ...[
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
