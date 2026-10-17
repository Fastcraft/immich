import 'package:hooks_riverpod/hooks_riverpod.dart';

enum AssetSelectionSourceType {
  timeline,
  localDevice,
  favorites,
}

class AssetSelectionFilterState {
  final AssetSelectionSourceType source;
  final String? localAlbumId;
  final String? localAlbumTitle;

  const AssetSelectionFilterState({
    this.source = AssetSelectionSourceType.timeline,
    this.localAlbumId,
    this.localAlbumTitle,
  });

  AssetSelectionFilterState copyWith({
    AssetSelectionSourceType? source,
    String? localAlbumId,
    String? localAlbumTitle,
  }) {
    return AssetSelectionFilterState(
      source: source ?? this.source,
      localAlbumId: localAlbumId ?? this.localAlbumId,
      localAlbumTitle: localAlbumTitle ?? this.localAlbumTitle,
    );
  }
}

final assetSelectionFilterProvider = StateProvider.autoDispose<AssetSelectionFilterState>((ref) {
  return const AssetSelectionFilterState();
});
