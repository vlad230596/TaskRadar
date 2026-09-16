import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/session_provider.dart';
import 'notification_bench_screen.dart';

/// F0 placeholder for the board.
///
/// Its entire purpose is to be the visible proof that the F0 acceptance criterion
/// holds -- "the app logs in against the backend and shows «сессия жива»" -- and
/// to provide the way back out. The real board lands in F2 and replaces this
/// file; nothing should be built on top of it in the meantime.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TaskRadar'),
        actions: [
          IconButton(
            onPressed: () => ref.read(sessionProvider.notifier).signOut(),
            icon: const Icon(Icons.logout),
            tooltip: 'Выйти',
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline, size: 48),
            const SizedBox(height: 16),
            Text('Сессия жива', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Доска появится на F2',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            // TEMPORARY (F1). The only way into the notification bench; both go
            // away when F4 gives reminders a real home. Deliberately a plain
            // `Navigator.push` and not a route name -- see `app.dart` on why
            // there is no router yet.
            FilledButton.tonalIcon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const NotificationBenchScreen(),
                ),
              ),
              icon: const Icon(Icons.notifications_active_outlined),
              label: const Text(NotificationBenchScreen.title),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => ref.read(sessionProvider.notifier).signOut(),
              icon: const Icon(Icons.logout),
              label: const Text('Выйти'),
            ),
          ],
        ),
      ),
    );
  }
}
