import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/album/local_album.model.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/generated/translations.g.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/providers/timeline/asset_selection_filter.provider.dart';
import 'package:immich_mobile/providers/timeline/multiselect.provider.dart';

class SelectionSliverAppBar extends ConsumerStatefulWidget {
  const SelectionSliverAppBar({super.key});

  @override
  ConsumerState<SelectionSliverAppBar> createState() => _SelectionSliverAppBarState();
}

class _SelectionSliverAppBarState extends ConsumerState<SelectionSliverAppBar> {
  Future<void> _showLocalAlbumPicker(BuildContext context, List<LocalAlbum> albums) async {
    final selected = await showModalBottomSheet<LocalAlbum>(
      context: context,
      backgroundColor: context.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  ctx.t.on_this_device,
                  style: ctx.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: albums.length,
                  itemBuilder: (c, index) {
                    final album = albums[index];
                    return ListTile(
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(album.name),
                      subtitle: Text(c.t.items_count(count: album.assetCount)),
                      onTap: () => Navigator.of(c).pop(album),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );

    if (selected != null && mounted) {
      ref.read(assetSelectionFilterProvider.notifier).state = ref
          .read(assetSelectionFilterProvider)
          .copyWith(
            source: AssetSelectionSourceType.localDevice,
            localAlbumId: selected.id,
            localAlbumTitle: selected.name,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(multiSelectProvider.select((s) => s.selectedAssets));
    final toExclude = ref.watch(multiSelectProvider.select((s) => s.lockedSelectionAssets));
    final filteredAssets = selection.where((asset) => !toExclude.contains(asset)).toSet();

    final filterState = ref.watch(assetSelectionFilterProvider);
    final localAlbums = ref.watch(localAlbumProvider).valueOrNull ?? [];

    void onDone(Set<BaseAsset> selected) {
      ref.read(multiSelectProvider.notifier).reset();
      context.pop<Set<BaseAsset>>(selected);
    }

    return SliverAppBar(
      floating: true,
      pinned: true,
      snap: false,
      backgroundColor: context.colorScheme.surfaceContainer,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(5))),
      automaticallyImplyLeading: false,
      leading: IconButton(
        icon: const Icon(Icons.close_rounded),
        onPressed: () {
          ref.read(multiSelectProvider.notifier).reset();
          context.pop<Set<BaseAsset>>(null);
        },
      ),
      centerTitle: true,
      title: Text(context.t.selected_count(count: filteredAssets.length)),
      actions: [
        TextButton(
          onPressed: () => onDone(filteredAssets),
          child: Text(
            context.t.done,
            style: context.textTheme.titleSmall?.copyWith(color: context.colorScheme.primary, fontWeight: FontWeight.bold),
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(
                  avatar: const Icon(Icons.cloud_outlined, size: 18),
                  label: Text(context.t.all),
                  selected: filterState.source == AssetSelectionSourceType.timeline,
                  onSelected: (selected) {
                    if (selected) {
                      ref.read(assetSelectionFilterProvider.notifier).state = filterState.copyWith(
                        source: AssetSelectionSourceType.timeline,
                      );
                    }
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  avatar: const Icon(Icons.phone_android_rounded, size: 18),
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        filterState.source == AssetSelectionSourceType.localDevice && filterState.localAlbumTitle != null
                            ? filterState.localAlbumTitle!
                            : context.t.on_this_device,
                      ),
                      if (filterState.source == AssetSelectionSourceType.localDevice && localAlbums.length > 1) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_drop_down, size: 18),
                      ],
                    ],
                  ),
                  selected: filterState.source == AssetSelectionSourceType.localDevice,
                  onSelected: (selected) async {
                    if (filterState.source == AssetSelectionSourceType.localDevice && localAlbums.length > 1) {
                      await _showLocalAlbumPicker(context, localAlbums);
                    } else {
                      final firstAlbum = localAlbums.firstOrNull;
                      ref.read(assetSelectionFilterProvider.notifier).state = filterState.copyWith(
                        source: AssetSelectionSourceType.localDevice,
                        localAlbumId: filterState.localAlbumId ?? firstAlbum?.id,
                        localAlbumTitle: filterState.localAlbumTitle ?? firstAlbum?.name,
                      );
                    }
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  avatar: const Icon(Icons.favorite_rounded, size: 18),
                  label: Text(context.t.favorites),
                  selected: filterState.source == AssetSelectionSourceType.favorites,
                  onSelected: (selected) {
                    if (selected) {
                      ref.read(assetSelectionFilterProvider.notifier).state = filterState.copyWith(
                        source: AssetSelectionSourceType.favorites,
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
