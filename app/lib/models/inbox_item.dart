import 'package:freezed_annotation/freezed_annotation.dart';

part 'inbox_item.freezed.dart';
part 'inbox_item.g.dart';

/// One line of text in the sandbox, as `GET /inbox` returns it (F8).
///
/// ## What it deliberately does not have
///
/// No status, no position, no reminder date, no project -- and that absence is
/// the feature. `../../../README.md` is built around the cost of losing a
/// thought, and the cheapest moment to lose one is the moment where writing it
/// down costs a decision. An inbox item is what you can write while walking:
/// one sentence, no filing.
///
/// It becomes a [Task] the moment it is filed into a project, and from then on
/// it is an ordinary task. There is no way to complete, block or schedule an
/// item while it is here, on purpose: an item you can work on directly is an
/// item you never file, and an unsorted pile that has quietly become a second
/// task list is the failure this feature has to avoid.
///
/// Timestamps stay `String` for the same reason as everywhere else in this
/// client -- see the long note on [Project].
@freezed
abstract class InboxItem with _$InboxItem {
  const factory InboxItem({
    required String id,
    required String text,
    required String createdAt,
    required String updatedAt,
  }) = _InboxItem;

  factory InboxItem.fromJson(Map<String, dynamic> json) =>
      _$InboxItemFromJson(json);
}
