import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../../constants/app_colors.dart';

/// Key on the root of the "Image removed" placeholder, the widget that fills
/// the image's reserved area.
const Key kImageRemovedPlaceholderKey = Key('image-removed-placeholder');

/// Supplies the cache manager the image widgets below it load and evict
/// through.
class ImageCacheScope extends InheritedWidget {
  const ImageCacheScope({
    required this.cacheManager,
    required super.child,
    super.key,
  });

  final BaseCacheManager cacheManager;

  /// The scoped manager, or DefaultCacheManager() when there is no scope.
  static BaseCacheManager of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ImageCacheScope>()
          ?.cacheManager ??
      DefaultCacheManager();

  @override
  bool updateShouldNotify(ImageCacheScope oldWidget) =>
      cacheManager != oldWidget.cacheManager;
}

/// Whether a load failed because the image no longer exists upstream.
bool isImageRemoved(Object error) =>
    error is HttpExceptionWithStatus && error.statusCode == 404;

/// Drops [url] from [cacheManager] so a removed image is not served from
/// disk later. Fire-and-forget: a failed eviction only means the next load
/// fails again and retries it, so an I/O exception is only noted in debug
/// builds. Any other error is a bug, and since the callers do not await this
/// future it is handed to the framework's error handler rather than thrown.
Future<void> evictRemovedImage(
  BaseCacheManager cacheManager,
  String url,
) async {
  try {
    await cacheManager.removeFile(url);
  } on Exception catch (error) {
    if (kDebugMode) {
      debugPrint('Evicting a removed image failed: $error');
    }
  } on Object catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'coves image cache',
        context: ErrorDescription('evicting a removed image'),
      ),
    );
  }
}

/// The error widget shared by the image surfaces: a 404 shows
/// [ImageRemovedPlaceholder] and evicts [url] once; any other error shows the
/// surface's own [fallback].
class ImageLoadError extends StatefulWidget {
  const ImageLoadError({
    required this.url,
    required this.error,
    required this.cacheManager,
    required this.fallback,
    super.key,
  });

  final String url;
  final Object error;
  final BaseCacheManager cacheManager;
  final Widget fallback;

  @override
  State<ImageLoadError> createState() => _ImageLoadErrorState();
}

class _ImageLoadErrorState extends State<ImageLoadError> {
  @override
  void initState() {
    super.initState();
    _evictIfRemoved();
  }

  @override
  void didUpdateWidget(ImageLoadError oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.url != oldWidget.url) {
      _evictIfRemoved();
    }
  }

  void _evictIfRemoved() {
    if (isImageRemoved(widget.error)) {
      evictRemovedImage(widget.cacheManager, widget.url);
    }
  }

  @override
  Widget build(BuildContext context) => isImageRemoved(widget.error)
      ? const ImageRemovedPlaceholder()
      : widget.fallback;
}

/// Fills the image's reserved area to say the image was removed.
class ImageRemovedPlaceholder extends StatelessWidget {
  const ImageRemovedPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand(
      key: kImageRemovedPlaceholderKey,
      child: ColoredBox(
        color: AppColors.backgroundSecondary,
        child: Center(
          // Scales down rather than overflowing a small comment tile.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.hide_image_outlined, color: AppColors.textMuted),
                SizedBox(height: 8),
                Text(
                  'Image removed',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
