import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/checklist_item.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// The task editor's checklist ("СПИСОК · 2/5", `design/task-editor-spec.md`
/// §6, WP5): one row per [ChecklistItem] -- a checkbox, a multi-line field
/// and a drag handle -- on the dark dictation palette (§8).
///
/// ## Who owns the list
///
/// The editor does. The section is controlled: it shows [items] and reports
/// every change of the list -- text typed, an item added, removed, moved,
/// ticked -- through [onChanged] as the whole next list. The editor keeps it
/// and saves it with the task:
///
/// - **New task**: the list is only local. Keep it in state, pass it back as
///   [items], and send `ChecklistSection.forSave(list)` with
///   `ProjectTasks.create(..., checklist:)`. Leave [onToggle] null.
/// - **Existing task**: text, adds, removes and moves are edits and wait for
///   "Сохранить" (`ProjectTasks.edit(task, checklist: PatchField.to(...))`,
///   again through [forSave]); a tick is an action and is written at once --
///   pass `onToggle: (id) => tasks.toggleChecklistItem(task, id)`. The
///   section still reports the ticked list through [onChanged] first, so the
///   editor's copy stays what the user sees; use [differsInContent] for the
///   "unsaved" check, which ignores ticks.
///
/// ## Empty
///
/// No items, no section: it draws nothing. The attribute bar's chip "Список"
/// starts the list -- `setState(() => list = ChecklistSection.withNewItem(list))`
/// -- and with [autofocusNew] the fresh empty item takes the caret. An item
/// left blank is dropped when it loses focus, so a list abandoned before its
/// first word disappears again.
///
/// ## Keys
///
/// Enter splits the item at the caret and moves on to the new item below (a
/// shopping list: type, Enter, type); Enter in an empty item ends the list
/// there. Pasting several lines makes one item per line, list markers
/// (`- `, `* `, `• `, `1.`) cut off. Backspace in an empty item (hardware
/// keyboard) removes it and goes to the item above; the focused row also has
/// a remove button, and any row can be swiped away.
class ChecklistSection extends StatefulWidget {
  const ChecklistSection({
    required this.items,
    required this.onChanged,
    this.onToggle,
    this.autofocusNew = true,
    this.enabled = true,
    super.key,
  });

  /// The list as the editor holds it, blank items included.
  final List<ChecklistItem> items;

  /// The whole next list after any change the user made here.
  final ValueChanged<List<ChecklistItem>> onChanged;

  /// Called with an item's id after it was ticked or unticked (and after
  /// [onChanged] reported the ticked list) -- for an existing task, where a
  /// tick is saved at once. Null for a new task.
  final ValueChanged<String>? onToggle;

  /// Give the caret to an empty item that appears from outside (the chip
  /// "Список"), and to the empty item the section first shows with.
  final bool autofocusNew;

  /// False shows the list read-only: no typing, ticking, moving or menu.
  final bool enabled;

  /// The server's limit on one item's text.
  static const int maxItemLength = 500;

  /// [items] with a new empty item at the end -- what the chip "Список" and
  /// "+ пункт" do.
  static List<ChecklistItem> withNewItem(List<ChecklistItem> items) =>
      <ChecklistItem>[...items, ChecklistItem.create('')];

  /// The list as it may be sent: texts trimmed and cut to [maxItemLength],
  /// blank items gone. Empty means "no checklist".
  static List<ChecklistItem> forSave(List<ChecklistItem> items) =>
      <ChecklistItem>[
        for (final item in items)
          if (item.text.trim().isNotEmpty)
            item.copyWith(text: _clamp(item.text.trim())),
      ];

  /// Whether [local] holds an edit not yet in [saved]: an item's text, an
  /// item added or removed, the order. Ticks do not count -- they are saved
  /// on their own ([onToggle]).
  static bool differsInContent(
    List<ChecklistItem> local,
    List<ChecklistItem>? saved,
  ) {
    final a = forSave(local);
    final b = forSave(saved ?? const <ChecklistItem>[]);
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].text != b[i].text) return true;
    }
    return false;
  }

  /// One item per non-blank line of pasted [text], list markers cut off.
  static List<String> splitLines(String text) => <String>[
    for (final line in text.split(RegExp(r'\r\n|\r|\n')))
      if (_stripMarker(line).isNotEmpty) _stripMarker(line),
  ];

  @override
  State<ChecklistSection> createState() => _ChecklistSectionState();
}

final RegExp _marker = RegExp(
  r'^\s*(?:[-*•–—]\s+|\[[ xX]?\]\s*|\d{1,3}[.)]\s+|[☐☑✓✔]\s*)',
);

String _stripMarker(String line) => line.replaceFirst(_marker, '').trim();

String _clamp(String text) => text.length <= ChecklistSection.maxItemLength
    ? text
    : text.substring(0, ChecklistSection.maxItemLength);

/// "2/5" over the items that have text: a blank item being typed is not yet
/// one to do.
String _progress(List<ChecklistItem> items) =>
    ChecklistItem.progressOf(ChecklistSection.forSave(items));

class _ChecklistSectionState extends State<ChecklistSection> {
  /// What is shown: [ChecklistSection.items], or the list just sent through
  /// `onChanged` until the editor passes it back. Lets a swiped row leave the
  /// tree in the frame it was dismissed even if the editor is a frame late.
  late List<ChecklistItem> _items = widget.items;

  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};
  final Map<String, FocusNode> _focus = <String, FocusNode>{};

  String? _focusAfterBuild;
  int _caretAfterBuild = 0;

  @override
  void initState() {
    super.initState();
    _syncControllers();
    if (widget.autofocusNew && widget.enabled) {
      final blank = _items.lastWhere(
        (item) => item.text.isEmpty,
        orElse: () => const ChecklistItem(id: '', text: 'x'),
      );
      if (blank.id.isNotEmpty) _focusAfterBuild = blank.id;
    }
  }

  @override
  void didUpdateWidget(ChecklistSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(widget.items, _items)) return;
    final before = <String>{for (final item in _items) item.id};
    _items = widget.items;
    _syncControllers();
    if (widget.autofocusNew && widget.enabled) {
      for (final item in _items) {
        if (!before.contains(item.id) && item.text.isEmpty) {
          _focusAfterBuild = item.id;
          _caretAfterBuild = 0;
        }
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }

  /// One controller and focus node per item id; texts follow the list
  /// unless the field already says the same.
  void _syncControllers() {
    final ids = <String>{for (final item in _items) item.id};
    for (final id in _controllers.keys.toList()) {
      if (ids.contains(id)) continue;
      _controllers.remove(id)!.dispose();
      _focus.remove(id)!.dispose();
    }
    for (final item in _items) {
      final controller = _controllers[item.id];
      if (controller == null) {
        _controllers[item.id] = TextEditingController(text: item.text);
        final node = FocusNode(debugLabel: 'checklist ${item.id}');
        node.addListener(() => _focusChanged(item.id, node));
        _focus[item.id] = node;
      } else if (controller.text != item.text) {
        controller.value = TextEditingValue(
          text: item.text,
          selection: TextSelection.collapsed(offset: item.text.length),
        );
      }
    }
  }

  void _emit(List<ChecklistItem> next) {
    setState(() {
      _items = next;
      _syncControllers();
    });
    widget.onChanged(next);
  }

  void _focusChanged(String id, FocusNode node) {
    if (mounted) setState(() {});
    if (node.hasFocus) return;
    // A blank item left behind goes away: the chip's first item never
    // typed into, or "+ пункт" tapped by mistake.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || node.hasFocus || !_focus.containsKey(id)) return;
      final index = _items.indexWhere((item) => item.id == id);
      if (index < 0 || _items[index].text.trim().isNotEmpty) return;
      _emit(<ChecklistItem>[..._items]..removeAt(index));
    });
  }

  void _requestFocus(String id, {int caret = 0}) {
    _focusAfterBuild = id;
    _caretAfterBuild = caret;
  }

  void _applyPendingFocus() {
    final id = _focusAfterBuild;
    if (id == null) return;
    _focusAfterBuild = null;
    final node = _focus[id];
    final controller = _controllers[id];
    if (node == null || controller == null) return;
    node.requestFocus();
    final caret = _caretAfterBuild.clamp(0, controller.text.length);
    controller.selection = TextSelection.collapsed(offset: caret);
  }

  // -- Edits ----------------------------------------------------------------

  void _textChanged(String id, String text) {
    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0) return;
    final old = _items[index].text;
    if (!text.contains('\n') && !text.contains('\r')) {
      _emit(
        <ChecklistItem>[..._items]
          ..[index] = _items[index].copyWith(text: text),
      );
      return;
    }

    final inserted = text.length - old.length;
    final next = <ChecklistItem>[..._items];
    final parts = text.split(RegExp(r'\r\n|\r|\n'));

    if (inserted == 1 && parts.length == 2) {
      // Enter. In an empty item: the list ends here.
      if (old.trim().isEmpty) {
        next.removeAt(index);
        _focus[id]?.unfocus();
        _emit(next);
        return;
      }
      final fresh = ChecklistItem.create(parts[1]);
      next[index] = _items[index].copyWith(text: parts[0]);
      next.insert(index + 1, fresh);
      _controllers[id]!.value = TextEditingValue(
        text: parts[0],
        selection: TextSelection.collapsed(offset: parts[0].length),
      );
      _requestFocus(fresh.id);
      _emit(next);
      return;
    }

    // A paste of several lines: one item per line, the first one staying in
    // this item.
    final lines = ChecklistSection.splitLines(text);
    if (lines.isEmpty) {
      next[index] = _items[index].copyWith(text: '');
      _controllers[id]!.text = '';
      _emit(next);
      return;
    }
    next[index] = _items[index].copyWith(text: lines.first);
    _controllers[id]!.value = TextEditingValue(
      text: lines.first,
      selection: TextSelection.collapsed(offset: lines.first.length),
    );
    final added = <ChecklistItem>[
      for (final line in lines.skip(1)) ChecklistItem.create(line),
    ];
    next.insertAll(index + 1, added);
    final last = added.isEmpty ? next[index] : added.last;
    _requestFocus(last.id, caret: last.text.length);
    _emit(next);
  }

  void _toggle(String id) {
    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0) return;
    HapticFeedback.lightImpact();
    final next = <ChecklistItem>[..._items]
      ..[index] = _items[index].copyWith(done: !_items[index].done);
    _emit(next);
    widget.onToggle?.call(id);
  }

  void _remove(String id, {bool focusAbove = false}) {
    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0) return;
    if (focusAbove && index > 0) {
      final above = _items[index - 1];
      _requestFocus(above.id, caret: above.text.length);
    }
    _emit(<ChecklistItem>[..._items]..removeAt(index));
  }

  void _addItem() {
    final next = ChecklistSection.withNewItem(_items);
    _requestFocus(next.last.id);
    _emit(next);
  }

  void _reorder(int from, int to) {
    final next = <ChecklistItem>[..._items];
    final moved = next.removeAt(from);
    next.insert(to > from ? to - 1 : to, moved);
    _emit(next);
  }

  KeyEventResult _onKey(String id, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey != LogicalKeyboardKey.backspace) {
      return KeyEventResult.ignored;
    }
    if (_controllers[id]?.text.isNotEmpty ?? true) {
      return KeyEventResult.ignored;
    }
    _remove(id, focusAbove: true);
    return KeyEventResult.handled;
  }

  // -- Build ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _applyPendingFocus();
    });

    return Column(
      key: const ValueKey<String>('checklist-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _header(),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          buildDefaultDragHandles: false,
          itemCount: _items.length,
          onReorder: _reorder,
          proxyDecorator: (child, index, animation) => Material(
            color: AppColors.voiceWell,
            elevation: 6,
            shadowColor: Colors.black,
            borderRadius: BorderRadius.circular(Radii.row),
            child: child,
          ),
          itemBuilder: (context, index) => _row(_items[index], index),
        ),
        if (widget.enabled) _addRow(),
      ],
    );
  }

  Widget _header() {
    final checked = _items.where((item) => item.done).isNotEmpty;
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            'СПИСОК · ${_progress(_items)}',
            key: const ValueKey<String>('checklist-progress'),
            style: const TextStyle(
              fontFamily: AppFonts.text,
              fontWeight: FontWeight.w600,
              fontSize: 13,
              letterSpacing: 0.4,
              color: AppColors.voiceMuted,
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ),
        if (widget.enabled)
          PopupMenuButton<_ListAction>(
            key: const ValueKey<String>('checklist-menu'),
            tooltip: 'Список',
            icon: const Icon(Icons.more_horiz, color: AppColors.voiceMuted),
            color: AppColors.voiceWell,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.chip),
              side: const BorderSide(color: AppColors.voiceLine),
            ),
            onSelected: (action) => switch (action) {
              _ListAction.clearChecked => _emit(<ChecklistItem>[
                for (final item in _items)
                  if (!item.done) item,
              ]),
              _ListAction.deleteList => _emit(const <ChecklistItem>[]),
            },
            itemBuilder: (context) => <PopupMenuEntry<_ListAction>>[
              PopupMenuItem<_ListAction>(
                value: _ListAction.clearChecked,
                enabled: checked,
                child: Text(
                  'Убрать отмеченные',
                  style: TextStyle(
                    color: checked ? AppColors.voiceInk : AppColors.voiceLine,
                  ),
                ),
              ),
              const PopupMenuItem<_ListAction>(
                value: _ListAction.deleteList,
                child: Text(
                  'Удалить список',
                  style: TextStyle(color: AppColors.voiceRecordingSoft),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _row(ChecklistItem item, int index) {
    final focused = _focus[item.id]?.hasFocus ?? false;
    final style = AppText.dictated.copyWith(
      fontSize: 17,
      height: 1.35,
      color: item.done ? AppColors.voiceMuted : AppColors.voiceInk,
      decoration: item.done ? TextDecoration.lineThrough : null,
      decorationColor: AppColors.voiceMuted,
    );

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _ChecklistBox(
            key: ValueKey<String>('checklist-box-${item.id}'),
            done: item.done,
            onTap: widget.enabled ? () => _toggle(item.id) : null,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: (_, event) => _onKey(item.id, event),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: item.done ? 0.75 : 1,
                  child: TextField(
                    key: ValueKey<String>('checklist-field-${item.id}'),
                    controller: _controllers[item.id],
                    focusNode: _focus[item.id],
                    enabled: widget.enabled,
                    style: style,
                    minLines: 1,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    cursorColor: AppColors.voiceBright,
                    decoration: const InputDecoration.collapsed(
                      hintText: 'Пункт',
                      hintStyle: TextStyle(color: AppColors.voiceLine),
                    ),
                    onChanged: (text) => _textChanged(item.id, text),
                  ),
                ),
              ),
            ),
          ),
          if (widget.enabled && focused)
            IconButton(
              key: ValueKey<String>('checklist-remove-${item.id}'),
              tooltip: 'Убрать пункт',
              icon: const Icon(Icons.close, size: 20),
              color: AppColors.voiceMuted,
              onPressed: () => _remove(item.id, focusAbove: true),
            ),
          if (widget.enabled)
            ReorderableDragStartListener(
              index: index,
              child: const SizedBox(
                width: Targets.minimum,
                height: Targets.minimum,
                child: Icon(
                  Icons.drag_indicator,
                  color: AppColors.voiceLine,
                  size: 22,
                ),
              ),
            ),
        ],
      ),
    );

    if (!widget.enabled) {
      return KeyedSubtree(key: ValueKey<String>(item.id), child: row);
    }
    return Dismissible(
      key: ValueKey<String>(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: Insets.gutter),
        decoration: BoxDecoration(
          color: AppColors.voiceWell,
          borderRadius: BorderRadius.circular(Radii.row),
        ),
        child: const Icon(
          Icons.delete_outline,
          color: AppColors.voiceRecordingSoft,
        ),
      ),
      onDismissed: (_) => _remove(item.id),
      child: row,
    );
  }

  Widget _addRow() {
    return InkWell(
      key: const ValueKey<String>('checklist-add'),
      borderRadius: BorderRadius.circular(Radii.row),
      onTap: _addItem,
      child: const SizedBox(
        height: Targets.minimum,
        child: Row(
          children: <Widget>[
            SizedBox(
              width: Targets.minimum,
              child: Icon(Icons.add, color: AppColors.voiceMuted, size: 22),
            ),
            SizedBox(width: 6),
            Text(
              'пункт',
              style: TextStyle(
                fontFamily: AppFonts.text,
                fontSize: 17,
                color: AppColors.voiceMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _ListAction { clearChecked, deleteList }

/// The checkbox: a rounded square that fills with the bright accent and
/// gives a short scale "pop" when ticked (§8: "галочка пункта — короткий
/// scale. Без конфетти").
class _ChecklistBox extends StatefulWidget {
  const _ChecklistBox({required this.done, required this.onTap, super.key});

  final bool done;
  final VoidCallback? onTap;

  @override
  State<_ChecklistBox> createState() => _ChecklistBoxState();
}

class _ChecklistBoxState extends State<_ChecklistBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  late final Animation<double> _scale =
      TweenSequence<double>(<TweenSequenceItem<double>>[
        TweenSequenceItem<double>(
          tween: Tween<double>(
            begin: 1,
            end: 0.8,
          ).chain(CurveTween(curve: Curves.easeOut)),
          weight: 30,
        ),
        TweenSequenceItem<double>(
          tween: Tween<double>(
            begin: 0.8,
            end: 1.15,
          ).chain(CurveTween(curve: Curves.easeOut)),
          weight: 40,
        ),
        TweenSequenceItem<double>(
          tween: Tween<double>(
            begin: 1.15,
            end: 1,
          ).chain(CurveTween(curve: Curves.easeIn)),
          weight: 30,
        ),
      ]).animate(_pop);

  @override
  void didUpdateWidget(_ChecklistBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.done && !oldWidget.done) _pop.forward(from: 0);
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final done = widget.done;
    return Semantics(
      checked: done,
      button: true,
      label: done ? 'Отмечено' : 'Не отмечено',
      child: InkResponse(
        onTap: widget.onTap,
        radius: 22,
        child: SizedBox(
          width: Targets.minimum,
          height: Targets.minimum,
          child: Center(
            child: ScaleTransition(
              scale: _scale,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: done ? AppColors.voiceLevelHigh : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: done
                        ? AppColors.voiceLevelHigh
                        : AppColors.voiceLine,
                    width: 2,
                  ),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  transitionBuilder: (child, animation) =>
                      ScaleTransition(scale: animation, child: child),
                  child: done
                      ? const Icon(
                          Icons.check_rounded,
                          key: ValueKey<bool>(true),
                          size: 18,
                          color: Colors.white,
                        )
                      : const SizedBox.shrink(key: ValueKey<bool>(false)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "☑ 2/5" for a task's row in the (light) task list. Nothing for a task
/// without a checklist; green once every item is ticked.
class ChecklistProgressBadge extends StatelessWidget {
  const ChecklistProgressBadge({required this.items, this.color, super.key});

  /// `Task.checklist`; null or empty draws nothing.
  final List<ChecklistItem>? items;

  /// Overrides the colour of an unfinished list (default [AppColors.muted]).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final list = items;
    if (list == null || list.isEmpty) return const SizedBox.shrink();
    final complete = list.every((item) => item.done);
    final tint = complete ? AppColors.done : (color ?? AppColors.muted);
    final progress = ChecklistItem.progressOf(list);
    return Semantics(
      label: 'Список: отмечено ${progress.replaceFirst('/', ' из ')}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            complete ? Icons.check_box : Icons.check_box_outlined,
            size: 14,
            color: tint,
          ),
          const SizedBox(width: 3),
          Text(progress, style: AppText.chip.copyWith(color: tint)),
        ],
      ),
    );
  }
}
