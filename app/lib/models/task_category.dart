import 'package:freezed_annotation/freezed_annotation.dart';

part 'task_category.freezed.dart';
part 'task_category.g.dart';

/// A group of tasks inside one project, as `GET /projects/:id/categories`
/// returns it -- "Кухня", "Документы".
///
/// Each project has its own list; a task points at one of them through
/// [Task.categoryId] or at none. Grouping only: the order of the tasks and
/// which one is current stay the project's, see `TaskCategory` in
/// `backend/prisma/schema.prisma`.
@freezed
abstract class TaskCategory with _$TaskCategory {
  const factory TaskCategory({
    required String id,
    required String projectId,
    required String name,

    /// Order of the groups. Read for diagnostics only, as with
    /// [Task.position]: the list comes back sorted.
    required double position,
    required String createdAt,
    required String updatedAt,
  }) = _TaskCategory;

  factory TaskCategory.fromJson(Map<String, dynamic> json) =>
      _$TaskCategoryFromJson(json);
}
