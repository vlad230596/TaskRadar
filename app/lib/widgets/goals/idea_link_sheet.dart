import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_error_message.dart';
import '../../models/board_project.dart';
import '../../models/goal.dart';
import '../../models/note.dart';
import '../../providers/board_providers.dart';
import '../../providers/dependencies.dart';
import '../../providers/goal_providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../ime_text_controller.dart';
import 'goal_icons.dart';
import 'goal_picker_sheet.dart';

/// «+ Идея» on a goal (`design/goals-ideas-spec.md`, «Цель», п. 6): the
/// ideas of every project on the board, with a search, as «Задачи в цель» but
/// without statuses. Ideas live per project, so this reads each project's
/// ideas once when it opens.
Future<void> showIdeaLinkSheet(
  BuildContext context,
  WidgetRef ref, {
  required GoalView goal,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.voiceBackground,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.large)),
    ),
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.92,
      child: _IdeaLinkSheet(goal: goal),
    ),
  );
}

class _IdeaLinkSheet extends ConsumerStatefulWidget {
  const _IdeaLinkSheet({required this.goal});

  final GoalView goal;

  @override
  ConsumerState<_IdeaLinkSheet> createState() => _IdeaLinkSheetState();
}

class _IdeaLinkSheetState extends ConsumerState<_IdeaLinkSheet> {
  final ImeTextController _search = ImeTextController();
  final List<String> _chosen = <String>[];
  List<(BoardProject, List<Note>)>? _ideas;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    unawaited(_load());
  }

  Future<void> _load() async {
    final view = ref.read(boardViewProvider);
    final projects = view is BoardReady ? view.projects : <BoardProject>[];
    final api = ref.read(projectApiProvider);
    try {
      final notes = await Future.wait(
        projects.map((p) => api.fetchNotes(p.project.id)),
      );
      if (!mounted) return;
      setState(() {
        _ideas = <(BoardProject, List<Note>)>[
          for (var i = 0; i < projects.length; i++)
            if (notes[i].isNotEmpty) (projects[i], notes[i]),
        ];
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _link() async {
    if (_chosen.isEmpty || _busy) return;
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final goals = ref.read(goalsProvider.notifier);
    try {
      for (final id in _chosen) {
        await goals.linkIdea(widget.goal.id, id);
      }
      navigator.pop();
    } catch (error) {
      if (mounted) setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Не удалось связать. ${describeApiError(error)}'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final linked = <String>{for (final idea in widget.goal.ideas) idea.id};
    final query = _search.text.trim().toLowerCase();
    final ideas = _ideas;
    final rows = <Widget>[];
    for (final (project, notes)
        in ideas ?? const <(BoardProject, List<Note>)>[]) {
      final matching = <Note>[
        for (final note in notes)
          if (query.isEmpty ||
              note.title.toLowerCase().contains(query) ||
              note.content.toLowerCase().contains(query))
            note,
      ];
      if (matching.isEmpty) continue;
      rows.add(
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: Text(
            project.project.name,
            style: const TextStyle(
              fontFamily: AppFonts.text,
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: AppColors.voiceBright,
            ),
          ),
        ),
      );
      for (final note in matching) {
        final already = linked.contains(note.id);
        rows.add(
          Opacity(
            opacity: already ? 0.55 : 1,
            child: InkWell(
              onTap: already
                  ? null
                  : () => setState(() {
                      if (!_chosen.remove(note.id)) _chosen.add(note.id);
                    }),
              child: SizedBox(
                height: 52,
                child: Row(
                  children: <Widget>[
                    DarkCheck(checked: already || _chosen.contains(note.id)),
                    const SizedBox(width: 12),
                    const BulbIcon(size: 18, color: AppColors.ideaOnDark),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        note.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppFonts.text,
                          fontWeight: FontWeight.w500,
                          fontSize: 15,
                          color: AppColors.voiceInk,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: 44,
            child: Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    'Идеи в цель',
                    style: TextStyle(
                      fontFamily: AppFonts.display,
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                      color: AppColors.voiceInk,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Закрыть',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: AppColors.voiceMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: TextField(
              controller: _search,
              style: const TextStyle(fontSize: 15, color: AppColors.voiceInk),
              decoration: InputDecoration(
                hintText: 'Найти идею во всех проектах',
                prefixIcon: const Icon(Icons.search, size: 18),
                filled: true,
                fillColor: AppColors.voiceWell,
                contentPadding: EdgeInsets.zero,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.voiceLine),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.voiceLevelHigh),
                ),
              ),
            ),
          ),
          Expanded(
            child: ideas == null
                ? Center(
                    child: _error == null
                        ? const CircularProgressIndicator()
                        : Text(
                            'Не удалось загрузить идеи. ${describeApiError(_error!)}',
                            textAlign: TextAlign.center,
                            style: AppText.voiceNote,
                          ),
                  )
                : rows.isEmpty
                ? const Center(
                    child: Text('Идей не нашлось.', style: AppText.voiceNote),
                  )
                : ListView(children: rows),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 22),
            child: SizedBox(
              height: 64,
              child: FilledButton(
                onPressed: _chosen.isEmpty || _busy
                    ? null
                    : () => unawaited(_link()),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.onInk,
                  foregroundColor: AppColors.voiceBackground,
                  disabledBackgroundColor: AppColors.voiceLine,
                  disabledForegroundColor: AppColors.voiceMuted,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: AppFonts.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
                child: Text(
                  _chosen.isEmpty
                      ? 'Выберите идеи'
                      : 'Связать · ${_chosen.length}',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
