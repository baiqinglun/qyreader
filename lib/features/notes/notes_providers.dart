/// 「笔记回顾」数据流：全库划线 + 全库书签。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/providers.dart';
import '../../domain/entities/annotation.dart';
import '../../domain/entities/bookmark.dart';
import '../../domain/repositories/annotation_repository.dart';

part 'notes_providers.g.dart';

/// 全库划线（新在前，实时刷新）。
@riverpod
Stream<List<Annotation>> allAnnotations(Ref ref) async* {
  final AnnotationRepository repo = await ref.watch(
    annotationRepositoryProvider.future,
  );
  yield* repo.watchAll();
}

/// 全库书签（新在前，实时刷新）。
@riverpod
Stream<List<Bookmark>> allBookmarks(Ref ref) async* {
  final AnnotationRepository repo = await ref.watch(
    annotationRepositoryProvider.future,
  );
  yield* repo.watchAllBookmarks();
}
