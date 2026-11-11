import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/project.dart';
import '../models/task.dart';
import '../models/task_status.dart';
import '../providers/board_providers.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/ai_tidy.dart' show TidyLabel;
import '../widgets/attachment_image.dart';
import 'share_intake.dart';

/// Asks «В какую задачу?» for [files] shared into the app: a new task in a
/// chosen project, or an existing one. Null when the sheet was dismissed.
Future<ShareTarget?> showShareTargetSheet(
  BuildContext context,
  List<XFile> files,
) {
  return showModalBottomSheet<ShareTarget>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.voiceBackground,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.large)),
    ),
    builder: (_) => ShareTargetSheet(files: files),
  );
}

/// The body of [showShareTargetSheet]; pops with a [ShareTarget].
class ShareTargetSheet extends ConsumerStatefulWidget {
  const ShareTargetSheet({required this.files, super.key});

  final List<XFile> files;

  @override
  ConsumerState<ShareTargetSheet> createState() => _ShareTargetSheetState();
}

class _ShareTargetSheetState extends ConsumerState<ShareTargetSheet> {
  late final TextEditingController _title = TextEditingController(
    text: widget.files.length == 1 ? 'Картинка' : 'Картинки',
  );
  final TextEditingController _query = TextEditingController();
  String? _projectId;

  @override
  void initState() {
    super.initState();
    _title.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _title.text.length,
    );
    _title.addListener(_changed);
    _query.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _title.dispose();
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(boardViewProvider);
    final projects = view is BoardReady
        ? <Project>[
            for (final row in view.projects)
              if (row.project.archivedAt == null) row.project,
          ]
        : const <Project>[];
    final names = <String, String>{for (final p in projects) p.id: p.name};
    final tasks = view is BoardReady
        ? recentShareTargets(<Task>[
            for (final row in view.projects)
              if (row.project.archivedAt == null) ...row.tasks,
          ], query: _query.text)
        : const <Task>[];
    final projectId =
        _projectId ?? (projects.isEmpty ? null : projects.first.id);
    final canCreate = projectId != null && _title.text.trim().isNotEmpty;

    final media = MediaQuery.of(context);
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: Theme.of(context).colorScheme.copyWith(
          primary: AppColors.voiceBright,
          surface: AppColors.voiceBackground,
          onSurface: AppColors.voiceInk,
        ),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: AppColors.voiceBright,
          selectionColor: AppColors.voiceLine,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: media.size.height * 0.88),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(
              Insets.gutter,
              12,
              Insets.gutter,
              Insets.gutter,
            ),
            children: <Widget>[
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.voiceLine,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'В какую задачу?',
                style: AppText.screenTight.copyWith(color: AppColors.voiceInk),
              ),
              const SizedBox(height: 12),
              _SharedPreview(files: widget.files),
              const SizedBox(height: 18),
              const TidyLabel('НОВАЯ ЗАДАЧА'),
              TextField(
                key: const ValueKey<String>('share-title'),
                controller: _title,
                autofocus: false,
                style: AppText.dictated.copyWith(fontSize: 18),
                textCapitalization: TextCapitalization.sentences,
                decoration: _fieldDecoration('Название'),
              ),
              const SizedBox(height: 10),
              if (projects.isEmpty)
                const Text(
                  'Нет проектов — сначала создайте проект',
                  style: TextStyle(color: AppColors.voiceMuted, fontSize: 15),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final project in projects)
                      _ProjectChip(
                        name: project.name,
                        selected: project.id == projectId,
                        onTap: () => setState(() => _projectId = project.id),
                      ),
                  ],
                ),
              const SizedBox(height: 12),
              SizedBox(
                height: 56,
                child: FilledButton(
                  key: const ValueKey<String>('share-create'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.card,
                    foregroundColor: AppColors.voiceBackground,
                    disabledBackgroundColor: AppColors.voiceLine,
                    disabledForegroundColor: AppColors.voiceMuted,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Radii.card),
                    ),
                    textStyle: AppText.action.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onPressed: canCreate
                      ? () => Navigator.of(context).pop(
                          NewTaskTarget(
                            projectId: projectId,
                            title: _title.text.trim(),
                          ),
                        )
                      : null,
                  child: Text(
                    projectId == null
                        ? 'Создать задачу'
                        : 'Создать в «${names[projectId]}»',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              const TidyLabel('ИЛИ В СУЩЕСТВУЮЩУЮ'),
              TextField(
                key: const ValueKey<String>('share-search'),
                controller: _query,
                style: const TextStyle(color: AppColors.voiceInk, fontSize: 16),
                decoration: _fieldDecoration('Найти задачу').copyWith(
                  prefixIcon: const Icon(
                    Icons.search,
                    color: AppColors.voiceMuted,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              if (view is! BoardReady)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Задачи ещё загружаются',
                    style: TextStyle(color: AppColors.voiceMuted),
                  ),
                )
              else if (tasks.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Ничего не нашлось',
                    style: TextStyle(color: AppColors.voiceMuted),
                  ),
                )
              else
                for (final task in tasks)
                  _TaskRow(
                    task: task,
                    projectName: names[task.projectId] ?? '',
                    onTap: () =>
                        Navigator.of(context).pop(ExistingTaskTarget(task)),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: AppColors.voiceMuted),
    filled: true,
    fillColor: AppColors.voiceWell,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(Radii.row),
      borderSide: const BorderSide(color: AppColors.voiceLine),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(Radii.row),
      borderSide: const BorderSide(color: AppColors.voiceLevelHigh, width: 1.5),
    ),
  );
}

/// The tasks offered as a share target: not done, most recently touched
/// first, matching [query] (case-insensitive, in the title); at most
/// [limit].
List<Task> recentShareTargets(
  List<Task> tasks, {
  String query = '',
  int limit = 30,
}) {
  final needle = query.trim().toLowerCase();
  final open = <Task>[
    for (final task in tasks)
      if (task.status != TaskStatus.done &&
          (needle.isEmpty || task.title.toLowerCase().contains(needle)))
        task,
  ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return open.length > limit ? open.sublist(0, limit) : open;
}

class _SharedPreview extends StatelessWidget {
  const _SharedPreview({required this.files});

  final List<XFile> files;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: files.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => ClipRRect(
          borderRadius: BorderRadius.circular(Radii.chip),
          child: SizedBox.square(
            dimension: 72,
            child: AttachmentImage.file(files[i], thumb: true),
          ),
        ),
      ),
    );
  }
}

class _ProjectChip extends StatelessWidget {
  const _ProjectChip({
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? AppColors.voiceWell : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.chip),
          side: BorderSide(
            color: selected ? AppColors.voiceLevelHigh : AppColors.voiceLine,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.chip),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Targets.minimum),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    name,
                    style: TextStyle(
                      color: selected
                          ? AppColors.voiceInk
                          : AppColors.voiceMuted,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.task,
    required this.projectName,
    required this.onTap,
  });

  final Task task;
  final String projectName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.row),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Targets.row),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.voiceInk,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (projectName.isNotEmpty)
                      Text(
                        projectName,
                        style: const TextStyle(
                          color: AppColors.voiceMuted,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(
                Icons.add_photo_alternate_outlined,
                color: AppColors.voiceMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
