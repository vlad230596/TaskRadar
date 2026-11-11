import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/task.dart';
import '../providers/attachment_providers.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// How many pictures [task] has: the server's plus those still in the outbox
/// ([pendingCounts] is `pendingAttachmentCountsProvider`).
int attachmentCount(Task task, Map<String, int> pendingCounts) =>
    task.attachments.length + (pendingCounts[task.id] ?? 0);

/// «🖼 3» in a task row (`design/task-editor-spec.md` §6); nothing when the
/// task has no pictures.
class AttachmentCountBadge extends ConsumerWidget {
  const AttachmentCountBadge({
    required this.task,
    this.color = AppColors.muted,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final Task task;
  final Color color;

  /// Around the badge, only when it is drawn.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = attachmentCount(
      task,
      ref.watch(pendingAttachmentCountsProvider),
    );
    if (count == 0) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: Semantics(
        label: 'Картинок: $count',
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.image_outlined, size: 14, color: color),
            const SizedBox(width: 3),
            Text('$count', style: AppText.chip.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}
