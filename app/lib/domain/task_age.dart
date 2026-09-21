import 'package:flutter/foundation.dart';

/// How long something has been sitting there, and when that stops being normal
/// (F12).
///
/// ## What "возраст" means before F11 lands
///
/// The spec is explicit that the honest answer needs the event journal
/// (`task_events`): *"сколько провисела в blocked"* cannot be derived from the
/// two timestamps a row carries. Until that journal exists this file computes
/// the one thing that **is** derivable -- days since the row last moved
/// (`updatedAt`), falling back to `createdAt` -- and says so in its name.
///
/// That is not a placeholder to be deleted. "Last movement" stays a real number
/// once the journal arrives; what the journal adds is the *breakdown* (four days
/// queued, one in progress, three waiting), which is a second fact shown beside
/// this one. See the "жизнь задачи" section of the task screen, whose shape is
/// already the shape the journal will fill.
///
/// ## Why the arithmetic is on calendar days and not on elapsed hours
///
/// The number is read as "сколько дней это висит", and a person counting that
/// counts midnights, not 24-hour blocks. A task touched at 23:50 yesterday is
/// "1 д" this morning, not "0 д" -- and a `Duration.inDays` on the instants
/// says 0 for another eight hours. Everything below therefore reduces both
/// sides to a local calendar date first, which is the same rule
/// `domain/reminders.dart` follows for exactly the same reason.

/// Days between [iso] and [now], counted in local midnights. Null when [iso]
/// cannot be read.
///
/// A malformed timestamp answers null rather than 0: zero is a fact ("touched
/// today") and printing it for a string nobody could parse would be a quiet
/// lie. Callers draw nothing instead.
int? daysSince(String? iso, {DateTime? now}) {
  if (iso == null) return null;

  final parsed = DateTime.tryParse(iso);
  if (parsed == null) {
    debugPrint('Unreadable timestamp: $iso');
    return null;
  }

  final then = parsed.toLocal();
  final today = (now ?? DateTime.now()).toLocal();

  final from = DateTime(then.year, then.month, then.day);
  final to = DateTime(today.year, today.month, today.day);

  final days = to.difference(from).inDays;
  // A row whose timestamp is in the future -- clock skew between the phone and
  // the server, which is a matter of seconds in practice and a whole day
  // across a midnight -- reads as "today" rather than as "-1 д".
  return days < 0 ? 0 : days;
}

/// Days since a row last moved: [updatedAt] if it can be read, else
/// [createdAt].
///
/// The fallback matters for the cached board: a snapshot written by an older
/// build can be missing a field that the current model requires, and a project
/// row that draws no age at all looks like a project with nothing wrong with
/// it.
int? daysSinceMovement(
  String? updatedAt, {
  String? createdAt,
  DateTime? now,
}) {
  return daysSince(updatedAt, now: now) ?? daysSince(createdAt, now: now);
}

/// Past this many days, an age stops being a fact and becomes a complaint --
/// the chip goes warm (`AppColors.waitingChip` / `AppColors.waitingInk`)
/// instead of grey.
///
/// Three, because three days is the first number that has survived a weekend:
/// something last touched on Friday and still untouched on Monday is the
/// smallest gap that actually means "это лежит", and anything shorter fires on
/// every normal two-day pause. The reference pages agree at both ends -- 1 д and
/// 2 д are drawn grey there, 4 д and 5 д warm.
const int kStaleAfterDays = 3;

/// See [kStaleAfterDays].
bool isStaleAge(int? days) => days != null && days >= kStaleAfterDays;

/// "2 д". The short form, for a chip that must not wrap or shrink.
///
/// Deliberately not "2 дня": the chip sits at the right-hand end of a row whose
/// left-hand end is a project name of unknown length, and the spec pins that
/// chip as `flex-shrink: 0` with no wrapping *because it already broke on a
/// phone*. A label whose width depends on Russian plural rules ("1 день", "2
/// дня", "5 дней") is a label that changes the row's arithmetic as the number
/// counts up.
String formatAgeShort(int days) => '$days д';

/// "2 дня" / "5 дней" / "1 день". The long form, for the few places that are a
/// sentence rather than a chip -- "не разобрано 3 дня", "лежит 3 дня".
String formatDays(int days) {
  final lastTwo = days % 100;
  final last = days % 10;

  // The standard Russian rule, written out rather than pulled in as a
  // dependency: 11-14 are the exception that catches every naive version.
  if (lastTwo >= 11 && lastTwo <= 14) return '$days дней';
  if (last == 1) return '$days день';
  if (last >= 2 && last <= 4) return '$days дня';
  return '$days дней';
}
