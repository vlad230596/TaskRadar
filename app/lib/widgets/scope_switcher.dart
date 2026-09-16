import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/scope_providers.dart';

/// The row of scopes above the board (F7), or nothing at all.
///
/// ## Why it disappears with one scope
///
/// Every installation has exactly one scope the moment the migration runs, and
/// most days most people have one. A switcher offering a single choice is
/// furniture: it costs a permanent strip of the home screen to answer a
/// question nobody is asking. So the whole feature stays invisible until a
/// second scope exists, which makes F7 free for someone who never wanted it and
/// makes "I created a scope and nothing happened" impossible.
///
/// ## Why chips and not tabs
///
/// A `TabBar` would tie the switcher to a `TabBarView` and to one controller per
/// board, and it ellipses names to fit rather than scrolling. Scopes are named
/// by hand ("Работа — компания Б"), there may be six of them, and the board
/// underneath is a single scroll view that must not be swiped sideways by
/// accident. A scrolling row of chips keeps the names readable, keeps the
/// horizontal gesture out of the way of the vertical one, and is the same
/// control on a phone and on a desktop.
class ScopeSwitcher extends ConsumerWidget {
  const ScopeSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(hasMultipleScopesProvider)) return const SizedBox.shrink();

    final scopes = ref.watch(scopesProvider).value ?? const [];
    final active = ref.watch(activeScopeProvider);
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            for (final scope in scopes) ...[
              ChoiceChip(
                label: Text(scope.name),
                selected: scope.id == active?.id,
                // Selecting the scope that is already selected is a no-op
                // rather than a write: `ChoiceChip` reports every tap, and
                // persisting the same id again would be a pointless disk write
                // on every stray tap.
                onSelected: (selected) {
                  if (!selected || scope.id == active?.id) return;
                  ref.read(selectedScopeIdProvider.notifier).select(scope.id);
                },
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}
