import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'image_error.dart';

/// Loads the animated codec for a GIF url.
typedef GifCodecLoader = Future<ui.Codec> Function(String url);

/// Supplies the [GifCodecLoader] used by GIF players below it.
class GifCodecScope extends InheritedWidget {
  const GifCodecScope({required this.loader, required super.child, super.key});

  final GifCodecLoader loader;

  /// The scoped loader, or one that reads through the [ImageCacheScope]
  /// cache manager (a `file://` url straight from disk) when there is no
  /// scope.
  static GifCodecLoader of(BuildContext context) {
    final scoped = context
        .dependOnInheritedWidgetOfExactType<GifCodecScope>()
        ?.loader;
    if (scoped != null) {
      return scoped;
    }
    final cacheManager = ImageCacheScope.of(context);
    return (url) => _loadGifCodec(cacheManager, url);
  }

  @override
  bool updateShouldNotify(GifCodecScope oldWidget) =>
      loader != oldWidget.loader;
}

Future<ui.Codec> _loadGifCodec(
  BaseCacheManager cacheManager,
  String url,
) async {
  final uri = Uri.parse(url);
  final bytes = uri.isScheme('file')
      ? await File.fromUri(uri).readAsBytes()
      : await (await cacheManager.getSingleFile(url)).readAsBytes();
  return ui.instantiateImageCodec(bytes);
}
