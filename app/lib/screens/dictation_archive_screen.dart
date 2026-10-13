import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/voice_providers.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../voice/dictation_archive.dart';
import '../widgets/mutation_feedback.dart';

/// The last few dictations on this device, to hear each one next to what it
/// was recognised as -- see [DictationArchive]. A debugging aid: nothing on
/// this screen leaves the device.
class DictationArchiveScreen extends ConsumerStatefulWidget {
  const DictationArchiveScreen({super.key});

  static const String title = 'Последние диктовки';

  @override
  ConsumerState<DictationArchiveScreen> createState() =>
      _DictationArchiveScreenState();
}

class _DictationArchiveScreenState
    extends ConsumerState<DictationArchiveScreen> {
  final AudioPlayer _player = AudioPlayer();
  late Future<List<ArchivedDictation>> _items = _load();

  /// The recording playing now, by path.
  String? _playing;
  StreamSubscription<void>? _completion;

  @override
  void initState() {
    super.initState();
    _completion = _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = null);
    });
  }

  @override
  void dispose() {
    unawaited(_completion?.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<List<ArchivedDictation>> _load() =>
      ref.read(dictationArchiveProvider).list();

  Future<void> _toggle(ArchivedDictation item) async {
    try {
      if (_playing == item.path) {
        await _player.stop();
        if (mounted) setState(() => _playing = null);
        return;
      }
      await _player.stop();
      await _player.play(DeviceFileSource(item.path));
      if (mounted) setState(() => _playing = item.path);
    } catch (error) {
      debugPrint('Could not play ${item.path}: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось воспроизвести запись.')),
      );
    }
  }

  Future<void> _clear() async {
    final sure = await confirmDestructive(
      context,
      title: 'Удалить все записи?',
      message: 'Сохранённые на этом устройстве диктовки будут удалены.',
      confirmLabel: 'Удалить',
    );
    if (!sure || !mounted) return;
    await _player.stop();
    await ref.read(dictationArchiveProvider).clear();
    if (!mounted) return;
    setState(() {
      _playing = null;
      _items = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(DictationArchiveScreen.title),
        actions: <Widget>[
          IconButton(
            tooltip: 'Удалить все',
            onPressed: _clear,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: FutureBuilder<List<ArchivedDictation>>(
        future: _items,
        builder: (context, snapshot) {
          final items = snapshot.data;
          if (items == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (items.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(Insets.gutter),
              child: Text(
                'Здесь появятся последние 10 диктовок — запись и то, как она '
                'распозналась. Хранятся только на этом устройстве.',
                style: AppText.caption,
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(Insets.gutter),
            itemCount: items.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              if (index == items.length) {
                return const Text(
                  'Хранятся последние 10, только на этом устройстве; на '
                  'сервер записи не отправляются.',
                  style: AppText.caption,
                );
              }
              final item = items[index];
              return _ArchiveRow(
                item: item,
                playing: _playing == item.path,
                onToggle: () => unawaited(_toggle(item)),
              );
            },
          );
        },
      ),
    );
  }
}

class _ArchiveRow extends StatelessWidget {
  const _ArchiveRow({
    required this.item,
    required this.playing,
    required this.onToggle,
  });

  final ArchivedDictation item;
  final bool playing;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final local = item.recordedAt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final when =
        '${two(local.day)}.${two(local.month)} ${two(local.hour)}:${two(local.minute)}';
    final seconds = item.length.inSeconds;
    final text = item.text;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(Radii.row),
      ),
      padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          IconButton(
            tooltip: playing ? 'Остановить' : 'Прослушать',
            onPressed: onToggle,
            icon: Icon(
              playing ? Icons.stop_circle_outlined : Icons.play_circle_outline,
              color: AppColors.indigoLink,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '$when · ${seconds ~/ 60}:${two(seconds % 60)}',
                  style: AppText.caption,
                ),
                const SizedBox(height: 4),
                Text(
                  switch (text) {
                    null => 'Не распознано (ошибка).',
                    '' => 'Ничего не расслышали.',
                    _ => text,
                  },
                  style: AppText.body.copyWith(
                    fontSize: 14,
                    color: text == null || text.isEmpty
                        ? AppColors.muted
                        : AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
