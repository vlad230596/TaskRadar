import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/read_cache_providers.dart';
import '../screens/plan_screen.dart' show formatUpdatedAt;
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// One line saying that the list below is the local copy, not the server's
/// answer -- the board's "Данные из кэша" banner, small, for the lists added to
/// the offline read set (the "in work" set, a project's notes).
///
/// Draws nothing while [cacheKey] is served fresh, so a screen can keep it in
/// its tree unconditionally.
class LocalCopyNote extends ConsumerWidget {
  const LocalCopyNote({super.key, required this.cacheKey});

  final String cacheKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedAt = ref.watch(
      cachedReadsProvider.select((reads) => reads[cacheKey]),
    );
    if (savedAt == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(Insets.gutter, 4, Insets.gutter, 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.indigoFill,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(Radii.row),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.history, size: 16, color: AppColors.indigoInk),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Локальная копия от ${formatUpdatedAt(savedAt)} — '
              'изменения сейчас могут не сохраниться.',
              style: AppText.hint.copyWith(color: AppColors.indigoInk),
            ),
          ),
        ],
      ),
    );
  }
}
