import 'dart:async';

import 'package:file/file.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';

/// A cache manager that never touches disk or network.
///
/// A URL listed in [errors] fails with that error; any other URL stays
/// loading forever. When [gate] is set, every failure waits for it to
/// complete, so a test can lay out the loading state first. [removedKeys]
/// collects every key passed to [removeFile]. getSingleFile serves the
/// files in [files].
class FakeImageCacheManager extends Fake implements BaseCacheManager {
  FakeImageCacheManager({
    Map<String, Object>? errors,
    Map<String, File>? files,
    this.gate,
  }) : errors = errors ?? {},
       files = files ?? {};

  /// The error each URL fails with. Mutable, so a test can change an
  /// outcome between pumps.
  final Map<String, Object> errors;

  /// Holds every failure back until it completes.
  Completer<void>? gate;

  final Set<String> removedKeys = {};

  /// The file getSingleFile returns for each URL; any other URL stays
  /// loading forever.
  final Map<String, File> files;

  /// Every URL passed to getSingleFile, in order.
  final List<String> singleFileRequests = [];

  @override
  Future<File> getSingleFile(
    String url, {
    String? key,
    Map<String, String>? headers,
  }) {
    singleFileRequests.add(url);
    final file = files[url];
    return file == null ? Completer<File>().future : Future.value(file);
  }

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) {
    final error = errors[url];
    if (error == null) {
      // Never emits and never closes: the image stays in its loading state.
      return StreamController<FileResponse>().stream;
    }
    return _fail(error);
  }

  // A future-backed stream: an async* generator's error does not reach the
  // image listener within tester.pump() under the fake-async zone.
  Stream<FileResponse> _fail(Object error) {
    final pending = gate?.future ?? Future<void>.value();
    return Stream<FileResponse>.fromFuture(
      pending.then<FileResponse>((_) => Future<FileResponse>.error(error)),
    );
  }

  @override
  Future<void> removeFile(String key) async {
    removedKeys.add(key);
  }
}
