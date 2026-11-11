/// Inline smart tokens: the date, `#проект` and `/категория` pieces the task
/// editor recognises while the user types (task-editor spec, section 2).
///
/// Pure Dart: no Flutter, no clock, no zone. [parseSmartTokens] takes `now` as
/// a **local wall-clock** `DateTime` and reads only its
/// year/month/day/hour/minute fields -- the same contract as
/// `localTodayCalendarDate` in `reminders.dart` -- so a test that passes
/// `DateTime(2026, 11, 11, 23, 0)` gets the same answer on any machine, in any
/// zone. Calendar arithmetic is done on `DateTime.utc` built from those fields,
/// which has no DST, so "через 3 часа" at 23:00 is 02:00 the next day and
/// "через 2 дня" is two calendar days even across a clock change. The result is
/// what the server stores: `remindAt` via [calendarDateForApi] (a bare
/// `YYYY-MM-DD`, see the trap described in `reminders.dart`) and `remindTime`
/// as `HH:MM` or null.
///
/// ## What the editor does with this
///
/// It re-runs [parseSmartTokens] on every change, highlights each returned
/// token's `[start, end)` range, writes its value into the matching chip, and
/// on save calls [stripTokens] to cut the active ones out of the title.
/// "Не дата" adds the token's range to [SmartContext.dismissed]; ranges are kept
/// aligned with later edits by [shiftRangesForEdit]. An existing task opened in
/// the editor dismisses every range [findAllTokenRanges] reports, so text saved
/// before this feature never silently moves a reminder.
library;

import 'reminders.dart';

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// What a recognised piece of text assigns.
enum TokenKind {
  /// A date and maybe a time: fills [SmartToken.remindAt] and
  /// [SmartToken.remindTime].
  date,

  /// `#проект`: fills [SmartToken.projectId] (or [SmartToken.candidates] when
  /// the prefix fits several projects).
  project,

  /// `/категория`: fills [SmartToken.categoryId] (or [SmartToken.candidates]).
  category,
}

/// A recognised piece of the text, `[start, end)` in UTF-16 code units of the
/// string that was parsed (what `TextEditingValue` and `TextSpan` use).
class SmartToken {
  const SmartToken({
    required this.kind,
    required this.start,
    required this.end,
    this.remindAt,
    this.remindTime,
    this.projectId,
    this.categoryId,
    this.past = false,
    this.candidates = const [],
  });

  final TokenKind kind;
  final int start;
  final int end;

  /// [TokenKind.date] only: `YYYY-MM-DD`, from [calendarDateForApi].
  final String? remindAt;

  /// [TokenKind.date] only: `HH:MM` local wall clock, or null for "the day
  /// only" (the reminder then fires at the settings hour).
  final String? remindTime;

  /// [TokenKind.project] only: the matched project, or null while the prefix
  /// is ambiguous (see [candidates]).
  final String? projectId;

  /// [TokenKind.category] only: the matched category, or null while the
  /// prefix is ambiguous (see [candidates]).
  final String? categoryId;

  /// [TokenKind.date] only: the moment has already gone by ("сегодня в 9" at
  /// 15:00). Still a valid reminder; the chip is painted `alarm` with
  /// «уже прошло».
  final bool past;

  /// [TokenKind.project] / [TokenKind.category]: every id whose name starts
  /// with what was typed, in the order of the list given in [SmartContext].
  /// With more than one entry and a null id the editor shows the pick-one
  /// popup under the cursor; with an id set (an exact name match won) the list
  /// still holds the alternatives. Empty for dates.
  final List<String> candidates;

  /// The range this token covers, e.g. to add it to [SmartContext.dismissed].
  SmartRange get range => SmartRange(start, end);

  /// True when the token assigns a value now (not an ambiguous prefix).
  bool get isResolved => switch (kind) {
    TokenKind.date => remindAt != null,
    TokenKind.project => projectId != null,
    TokenKind.category => categoryId != null,
  };

  @override
  bool operator ==(Object other) =>
      other is SmartToken &&
      other.kind == kind &&
      other.start == start &&
      other.end == end &&
      other.remindAt == remindAt &&
      other.remindTime == remindTime &&
      other.projectId == projectId &&
      other.categoryId == categoryId &&
      other.past == past &&
      _sameList(other.candidates, candidates);

  @override
  int get hashCode => Object.hash(
    kind,
    start,
    end,
    remindAt,
    remindTime,
    projectId,
    categoryId,
    past,
    Object.hashAll(candidates),
  );

  @override
  String toString() {
    final value = switch (kind) {
      TokenKind.date =>
        '$remindAt ${remindTime ?? '--:--'}${past ? ' past' : ''}',
      TokenKind.project => '${projectId ?? '?'} $candidates',
      TokenKind.category => '${categoryId ?? '?'} $candidates',
    };
    return 'SmartToken(${kind.name} [$start, $end) $value)';
  }
}

/// A `[start, end)` range of the text: a dismissed token, or a link.
class SmartRange {
  const SmartRange(this.start, this.end);

  final int start;
  final int end;

  bool overlaps(int otherStart, int otherEnd) =>
      start < otherEnd && otherStart < end;

  @override
  bool operator ==(Object other) =>
      other is SmartRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'SmartRange($start, $end)';
}

/// A link found by [findLinks].
class LinkSpan {
  const LinkSpan({required this.start, required this.end, required this.url});

  final int start;
  final int end;

  /// What to open: the text as typed, with `https://` put in front of a bare
  /// `www.` address.
  final String url;

  @override
  bool operator ==(Object other) =>
      other is LinkSpan &&
      other.start == start &&
      other.end == end &&
      other.url == url;

  @override
  int get hashCode => Object.hash(start, end, url);

  @override
  String toString() => 'LinkSpan([$start, $end) $url)';
}

/// A project `#…` can point at.
class SmartProject {
  const SmartProject({required this.id, required this.name, this.categories});

  final String id;
  final String name;

  /// This project's categories, when the caller has them. If a `#проект`
  /// token in the same text resolves to this project, `/категория` is matched
  /// against these instead of [SmartContext.categories].
  final List<SmartCategory>? categories;
}

/// A category `/…` can point at.
class SmartCategory {
  const SmartCategory({required this.id, required this.name});

  final String id;
  final String name;
}

/// Everything the parser needs besides the text and the clock.
class SmartContext {
  const SmartContext({
    this.projects = const [],
    this.categories = const [],
    this.dismissed = const [],
  });

  /// Projects `#…` matches against. Pass an empty list for an existing task
  /// (it cannot change project): no project tokens are produced then.
  final List<SmartProject> projects;

  /// Categories of the currently selected project, for `/…`.
  final List<SmartCategory> categories;

  /// Ranges the user dismissed («Не дата», Backspace after a token, or the
  /// scan on opening an existing task). A candidate overlapping one of these
  /// is plain text, and the scan goes on after it.
  final List<SmartRange> dismissed;
}

// ---------------------------------------------------------------------------
// Public functions
// ---------------------------------------------------------------------------

/// Recognises the smart tokens in [text]: at most one [TokenKind.date] (the
/// **first** date expression -- rule 8), one [TokenKind.project] and one
/// [TokenKind.category] (the first that matches anything), sorted by start.
///
/// [now] is the local wall clock; only its date and hour/minute are read.
List<SmartToken> parseSmartTokens(
  String text, {
  required DateTime now,
  required SmartContext ctx,
}) {
  final scan = _Scan(text, now, ctx);
  final result = <SmartToken>[];

  final project = scan.tags.where(
    (t) => t.kind == TokenKind.project && !scan.isDismissed(t.start, t.end),
  );
  final category = scan.tags.where(
    (t) => t.kind == TokenKind.category && !scan.isDismissed(t.start, t.end),
  );
  final date = scan.dates.where((t) => !scan.isDismissed(t.start, t.end));

  if (date.isNotEmpty) result.add(date.first);
  if (project.isNotEmpty) result.add(project.first);
  if (category.isNotEmpty) result.add(category.first);
  result.sort((a, b) => a.start.compareTo(b.start));
  return result;
}

/// Every range that **could** be a token in [text], including the second and
/// later date expressions and already-dismissed ones.
///
/// For opening an existing task: put all of these into
/// [SmartContext.dismissed] once, so only text typed in this session is live.
List<SmartRange> findAllTokenRanges(
  String text, {
  required DateTime now,
  required SmartContext ctx,
}) {
  final scan = _Scan(
    text,
    now,
    SmartContext(projects: ctx.projects, categories: ctx.categories),
  );
  final ranges = [
    for (final t in scan.dates) t.range,
    for (final t in scan.tags) t.range,
  ]..sort((a, b) => a.start.compareTo(b.start));
  return ranges;
}

/// `http(s)://…` and `www.…` links in [text]. Trailing punctuation and an
/// unbalanced closing bracket are not part of the link.
List<LinkSpan> findLinks(String text) {
  final links = <LinkSpan>[];
  for (final m in _linkPattern.allMatches(text)) {
    if (m.start > 0 && _isWordChar(text.codeUnitAt(m.start - 1))) continue;
    var end = m.end;
    while (end > m.start) {
      final c = text[end - 1];
      if ('.,;:!?…\'"»'.contains(c)) {
        end--;
        continue;
      }
      if (c == ')' || c == ']') {
        final open = c == ')' ? '(' : '[';
        final body = text.substring(m.start, end);
        final opens = open.allMatches(body).length;
        final closes = c.allMatches(body).length;
        if (closes > opens) {
          end--;
          continue;
        }
      }
      break;
    }
    final raw = text.substring(m.start, end);
    final lower = raw.toLowerCase();
    if (lower == 'www.' || lower.endsWith('://')) continue;
    final url = lower.startsWith('www.') ? 'https://$raw' : raw;
    links.add(LinkSpan(start: m.start, end: end, url: url));
  }
  return links;
}

/// The title to save: [text] with every token in [tokens] cut out, plus the
/// cleanup from the spec -- a preposition left hanging right before a cut
/// piece goes with it («купить корм на завтра» → «купить корм»), runs of
/// spaces collapse, a space before punctuation and doubled commas go, and
/// dangling prepositions/conjunctions/commas at either end are trimmed. If the
/// text started with a capital letter and the cut removed its beginning, the
/// new first letter is capitalised.
///
/// Pass only the tokens that are active (resolved and not dismissed). If
/// cutting would leave nothing, [text] is returned trimmed but otherwise
/// untouched: a task needs a title, and «завтра в 10» on its own is one.
String stripTokens(String text, Iterable<SmartToken> tokens) {
  final cuts = [for (final t in tokens) SmartRange(t.start, t.end)]
    ..sort((a, b) => b.start.compareTo(a.start));
  if (cuts.isEmpty) return text.trim();

  final norm = _normalize(text);
  var out = text;
  var cutAtStart = false;
  for (final cut in cuts) {
    if (cut.start < 0 || cut.end > out.length || cut.start >= cut.end) {
      continue;
    }
    var start = cut.start;
    // A standalone preposition right before the cut goes with it.
    var i = start;
    while (i > 0 && _isSpace(out.codeUnitAt(i - 1))) {
      i--;
    }
    var w = i;
    while (w > 0 && _isWordChar(out.codeUnitAt(w - 1))) {
      w--;
    }
    if (w < i &&
        i < start &&
        (w == 0 || !_isWordChar(out.codeUnitAt(w - 1))) &&
        _hangingWords.contains(norm.substring(w, i))) {
      start = w;
    }
    if (start == 0) cutAtStart = true;
    out = out.substring(0, start) + out.substring(cut.end);
  }

  out = _tidy(out);
  if (out.isEmpty) return text.trim();
  if (cutAtStart && _isUpper(text.trimLeft()) && !_isUpper(out)) {
    out = out[0].toUpperCase() + out.substring(1);
  }
  return out;
}

/// Moves [ranges] (dismissed tokens) along with an edit that turned [before]
/// into [after]: ranges before the edit stay, ranges after it shift by the
/// length change, ranges the edit touched are dropped (their text changed, so
/// "this piece in this position" no longer exists).
///
/// The edit is found as the part between the common prefix and the common
/// suffix, which is exact for a single insertion, deletion or replacement --
/// what one `TextEditingValue` change is.
List<SmartRange> shiftRangesForEdit(
  List<SmartRange> ranges,
  String before,
  String after,
) {
  if (before == after) return ranges;
  var prefix = 0;
  final minLen = before.length < after.length ? before.length : after.length;
  while (prefix < minLen &&
      before.codeUnitAt(prefix) == after.codeUnitAt(prefix)) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < minLen - prefix &&
      before.codeUnitAt(before.length - 1 - suffix) ==
          after.codeUnitAt(after.length - 1 - suffix)) {
    suffix++;
  }
  final editEnd = before.length - suffix;
  final delta = after.length - before.length;

  return [
    for (final r in ranges)
      if (r.end <= prefix)
        r
      else if (r.start >= editEnd)
        SmartRange(r.start + delta, r.end + delta),
  ];
}

// ---------------------------------------------------------------------------
// Scanner
// ---------------------------------------------------------------------------

class _Scan {
  _Scan(this.text, this.now, this.ctx) : norm = _normalize(text) {
    links = findLinks(text);
    tags = _findTags();
    dates = _findDates();
  }

  final String text;
  final String norm;
  final DateTime now;
  final SmartContext ctx;

  late final List<LinkSpan> links;
  late final List<SmartToken> tags;
  late final List<SmartToken> dates;

  bool isDismissed(int start, int end) =>
      ctx.dismissed.any((d) => d.overlaps(start, end));

  bool _inLink(int start, int end) =>
      links.any((l) => l.start < end && start < l.end);

  bool _inTag(int start, int end) =>
      tags.any((t) => t.start < end && start < t.end);

  // ---- #проект and /категория ----------------------------------------------

  List<SmartToken> _findTags() {
    final found = <SmartToken>[];
    List<SmartCategory> categories = ctx.categories;
    var projectSeen = false;

    // Projects first: a resolved project decides which categories `/` sees.
    for (final m in _tagPattern.allMatches(norm)) {
      if (!_tagCanStart(m.start) || _inLink(m.start, m.end)) continue;
      if (norm[m.start] != '#') continue;
      final token = _matchTag(m, TokenKind.project, [
        for (final p in ctx.projects) _Named(p.id, p.name),
      ]);
      if (token == null) continue;
      found.add(token);
      if (!projectSeen &&
          !isDismissed(token.start, token.end) &&
          token.projectId != null) {
        projectSeen = true;
        final p = ctx.projects.firstWhere((p) => p.id == token.projectId);
        if (p.categories != null) categories = p.categories!;
      }
    }
    for (final m in _tagPattern.allMatches(norm)) {
      if (!_tagCanStart(m.start) || _inLink(m.start, m.end)) continue;
      if (norm[m.start] != '/') continue;
      if (found.any((t) => t.start < m.end && m.start < t.end)) continue;
      final token = _matchTag(m, TokenKind.category, [
        for (final c in categories) _Named(c.id, c.name),
      ]);
      if (token != null) found.add(token);
    }
    found.sort((a, b) => a.start.compareTo(b.start));
    return found;
  }

  bool _tagCanStart(int i) {
    if (i == 0) return true;
    final prev = text.codeUnitAt(i - 1);
    return _isSpace(prev) || '([{«"„'.contains(String.fromCharCode(prev));
  }

  SmartToken? _matchTag(RegExpMatch m, TokenKind kind, List<_Named> names) {
    if (names.isEmpty) return null;
    final normNames = [
      for (final n in names) (n, _collapse(_normalize(n.name))),
    ];

    final quoted = m.group(1);
    String typed;
    var end = m.end;
    if (quoted != null) {
      typed = _collapse(quoted);
      if (typed.isEmpty) return null;
    } else {
      typed = m.group(2)!;
      // «по совпадению первых слов»: take the next word too while some name
      // still starts with the longer phrase.
      var probe = end;
      while (true) {
        final next = _followingWord.matchAsPrefix(norm, probe);
        if (next == null) break;
        final longer = '$typed ${next.group(1)}';
        if (!normNames.any((n) => n.$2.startsWith(longer))) break;
        typed = longer;
        probe = next.end;
        end = next.end;
      }
    }

    final matches = [
      for (final n in normNames)
        if (n.$2.startsWith(typed)) n,
    ];
    if (matches.isEmpty) return null;
    final exact = [
      for (final n in matches)
        if (n.$2 == typed) n,
    ];
    final String? id = matches.length == 1
        ? matches.single.$1.id
        : exact.length == 1
        ? exact.single.$1.id
        : null;
    return SmartToken(
      kind: kind,
      start: m.start,
      end: end,
      projectId: kind == TokenKind.project ? id : null,
      categoryId: kind == TokenKind.category ? id : null,
      candidates: [for (final n in matches) n.$1.id],
    );
  }

  // ---- dates ---------------------------------------------------------------

  List<SmartToken> _findDates() {
    final parts = <_Part>[];
    var i = 0;
    while (i < norm.length) {
      if (!_canStartWord(i)) {
        i++;
        continue;
      }
      final part = _longestPart(i);
      if (part == null ||
          _inLink(part.start, part.end) ||
          _inTag(part.start, part.end)) {
        i = _nextWordStart(i);
        continue;
      }
      parts.add(part);
      i = part.end;
    }

    final tokens = <SmartToken>[];
    var g = 0;
    while (g < parts.length) {
      final group = <_Part>[parts[g]];
      var j = g + 1;
      while (j < parts.length &&
          _onlySpaces(group.last.end, parts[j].start) &&
          !group.any((p) => p.conflicts(parts[j]))) {
        group.add(parts[j]);
        j++;
      }
      g = j;
      final token = _resolve(group);
      if (token != null) tokens.add(token);
    }
    return tokens;
  }

  bool _canStartWord(int i) {
    final c = norm.codeUnitAt(i);
    if (!_isWordChar(c)) return false;
    if (i == 0) return true;
    final prev = norm.codeUnitAt(i - 1);
    if (_isWordChar(prev)) return false;
    // "1.15.11", "#завтра", "/завтра" -- not the start of a date.
    return !'.:/#@_-'.contains(String.fromCharCode(prev));
  }

  int _nextWordStart(int i) {
    var j = i;
    while (j < norm.length && _isWordChar(norm.codeUnitAt(j))) {
      j++;
    }
    return j == i ? i + 1 : j;
  }

  bool _onlySpaces(int from, int to) {
    for (var k = from; k < to; k++) {
      if (!_isSpace(norm.codeUnitAt(k))) return false;
    }
    return true;
  }

  _Part? _longestPart(int i) {
    _Part? best;
    for (final reader in _readers) {
      final part = reader(this, i);
      if (part != null && (best == null || part.end > best.end)) best = part;
    }
    return best;
  }

  static final List<_Part? Function(_Scan, int)> _readers = [
    (s, i) => s._relative(i),
    (s, i) => s._namedDate(i),
    (s, i) => s._numericDate(i),
    (s, i) => s._time(i),
    (s, i) => s._bareTime(i),
    (s, i) => s._weekdayTo(i),
    (s, i) => s._weekdayIn(i),
    (s, i) => s._day(i),
  ];

  _Part? _day(int i) {
    final m = _dayPattern.matchAsPrefix(norm, i);
    if (m == null) return null;
    final offset = switch (m.group(1)) {
      'сегодня' => 0,
      'завтра' => 1,
      _ => 2,
    };
    return _Part.day(i, m.end, _today.add(Duration(days: offset)));
  }

  _Part? _weekdayIn(int i) {
    final m = _weekdayInPattern.matchAsPrefix(norm, i);
    if (m == null) return null;
    final hasIn = m.group(1) != null;
    final next = m.group(2) != null;
    final name = m.group(3)!;
    final weekday = _weekdayOf(name);
    // Abbreviations and the common noun «среда» need a preposition, «следующ…»
    // or a time next to them (resolved in [_resolve]).
    final weak =
        !hasIn && !next && (name.length == 2 || name.startsWith('сред'));
    return _Part.weekday(i, m.end, weekday, next: next, weak: weak);
  }

  _Part? _weekdayTo(int i) {
    final m = _weekdayToPattern.matchAsPrefix(norm, i);
    if (m == null) return null;
    return _Part.weekday(
      i,
      m.end,
      _weekdayOf(m.group(2)!),
      next: m.group(1) != null,
      weak: false,
    );
  }

  _Part? _namedDate(int i) {
    final m = _namedDatePattern.matchAsPrefix(norm, i);
    if (m == null) return null;
    final day = int.parse(m.group(1)!);
    final month = _monthOf(m.group(2)!);
    final year = m.group(3) == null ? null : int.parse(m.group(3)!);
    return _calendarPart(i, m.end, day, month, year);
  }

  _Part? _numericDate(int i) {
    final m = _numericDatePattern.matchAsPrefix(norm, i);
    if (m == null) return null;
    final day = int.parse(m.group(1)!);
    final month = int.parse(m.group(3)!);
    final year = m.group(4) == null ? null : int.parse(m.group(4)!);
    return _calendarPart(i, m.end, day, month, year);
  }

  _Part? _calendarPart(int start, int end, int day, int month, int? year) {
    DateTime? valid(int y) {
      if (month < 1 || month > 12 || day < 1) return null;
      final d = DateTime.utc(y, month, day);
      return d.month == month && d.day == day ? d : null;
    }

    if (year != null) {
      final d = valid(year);
      return d == null ? null : _Part.day(start, end, d);
    }
    var d = valid(_today.year);
    if (d != null && d.isBefore(_today)) d = valid(_today.year + 1);
    // 29 февраля: the next year that has one.
    if (d == null) {
      for (var y = _today.year; y <= _today.year + 8; y++) {
        final c = valid(y);
        if (c != null && !c.isBefore(_today)) {
          d = c;
          break;
        }
      }
    }
    return d == null ? null : _Part.day(start, end, d);
  }

  _Part? _time(int i) {
    final m = _timePattern.matchAsPrefix(norm, i);
    if (m == null) return null;
    // Groups: 1 полдень, 2 hour, 3 minutes, 4 «час…», 5 «утра/дня/…».
    if (m.group(1) != null) {
      return _Part.time(i, m.end, 12, 0, weak: false);
    }
    final h = int.parse(m.group(2)!);
    final minutes = m.group(3) == null ? 0 : int.parse(m.group(3)!);
    if (h > 23 || minutes > 59) return null;
    final unit = m.group(4);
    final meridiem = m.group(5);
    // «в 15 ноября»: the number belongs to a date, not to a time.
    if (m.group(3) == null && unit == null && meridiem == null) {
      final hourAt = norm.indexOf(m.group(2)!, i);
      if (_namedDatePattern.matchAsPrefix(norm, hourAt) != null) return null;
    }
    final hour = _hour24(h, meridiem);
    final strong =
        m.group(3) != null ||
        unit != null ||
        meridiem != null ||
        _endsClause(m.end);
    return _Part.time(i, m.end, hour, minutes, weak: !strong);
  }

  _Part? _bareTime(int i) {
    final m = _bareTimePattern.matchAsPrefix(norm, i);
    if (m == null) return null;
    final h = int.parse(m.group(1)!);
    final minutes = int.parse(m.group(2)!);
    if (h > 23 || minutes > 59) return null;
    // Without «в/к» a clock time only counts next to a day.
    return _Part.time(i, m.end, _hour24(h, null), minutes, weak: true);
  }

  _Part? _relative(int i) {
    final m = _relativePattern.matchAsPrefix(norm, i);
    if (m == null) return null;
    final countWord = m.group(1);
    final unit = m.group(2)!;
    int? count = countWord == null ? null : _countOf(countWord);
    if (unit == 'полчаса') {
      if (count != null) return null;
      return _Part.moment(i, m.end, _wallNow.add(const Duration(minutes: 30)));
    }
    if (count == null) {
      // Bare unit: «через час», «через неделю», «через месяц», «через минуту».
      if (!const {
        'час',
        'неделю',
        'месяц',
        'минуту',
        'день',
        'сутки',
      }.contains(unit)) {
        return null;
      }
      count = 1;
    }
    if (unit.startsWith('мин')) {
      return _Part.moment(i, m.end, _wallNow.add(Duration(minutes: count)));
    }
    if (unit == 'ч' || unit.startsWith('час')) {
      return _Part.moment(i, m.end, _wallNow.add(Duration(hours: count)));
    }
    final t = _today;
    if (unit.startsWith('нед')) {
      return _Part.day(
        i,
        m.end,
        DateTime.utc(t.year, t.month, t.day + 7 * count),
      );
    }
    if (unit.startsWith('мес')) {
      return _Part.day(i, m.end, _addMonths(t, count));
    }
    return _Part.day(i, m.end, DateTime.utc(t.year, t.month, t.day + count));
  }

  /// True when nothing but punctuation or the end follows a bare «в N»: that
  /// is what makes «купить в 5» a time and «в 2 этапа» not.
  bool _endsClause(int end) {
    var k = end;
    while (k < norm.length && (norm[k] == ' ' || norm[k] == '\t')) {
      k++;
    }
    if (k >= norm.length) return true;
    return ',.;:!?)]»"…—–-\n\r'.contains(norm[k]);
  }

  DateTime get _today => DateTime.utc(now.year, now.month, now.day);

  DateTime get _wallNow =>
      DateTime.utc(now.year, now.month, now.day, now.hour, now.minute);

  int get _nowMinutes => now.hour * 60 + now.minute;

  SmartToken? _resolve(List<_Part> group) {
    final day = group.where((p) => p.hasDay).firstOrNull;
    final time = group.where((p) => p.hasTime).firstOrNull;
    // A guarded piece needs a confident partner.
    for (final p in group) {
      if (!p.weak) continue;
      final partner = p.isTimeOnly ? day : time;
      if (partner == null || partner.weak) return null;
    }

    final start = group.first.start;
    final end = group.last.end;

    if (day != null && day.moment != null) {
      final m = day.moment!;
      return _token(
        start,
        end,
        DateTime.utc(m.year, m.month, m.day),
        m.hour,
        m.minute,
      );
    }

    final hour = time?.hour;
    final minute = time?.minute;
    DateTime date;
    if (day == null) {
      // «Только время»: today if it is still ahead, else tomorrow.
      final ahead = hour! * 60 + minute! > _nowMinutes;
      date = ahead ? _today : _today.add(const Duration(days: 1));
    } else if (day.weekday != null) {
      date = _weekdayDate(
        day.weekday!,
        next: day.next,
        hour: hour,
        minute: minute,
      );
    } else {
      date = day.date!;
    }
    return _token(start, end, date, hour, minute);
  }

  DateTime _weekdayDate(
    int weekday, {
    required bool next,
    int? hour,
    int? minute,
  }) {
    final today = _today;
    if (next) {
      final nextMonday = today.add(Duration(days: 8 - today.weekday));
      return nextMonday.add(Duration(days: weekday - 1));
    }
    var delta = (weekday - today.weekday) % 7;
    if (delta == 0 && hour != null && hour * 60 + minute! <= _nowMinutes) {
      delta = 7;
    }
    return today.add(Duration(days: delta));
  }

  SmartToken _token(int start, int end, DateTime date, int? hour, int? minute) {
    final today = _today;
    final bool past;
    if (date.isBefore(today)) {
      past = true;
    } else if (date == today && hour != null) {
      past = hour * 60 + minute! <= _nowMinutes;
    } else {
      past = false;
    }
    return SmartToken(
      kind: TokenKind.date,
      start: start,
      end: end,
      remindAt: calendarDateForApi(date),
      remindTime: hour == null ? null : reminderTimeForApi(hour, minute!),
      past: past,
    );
  }
}

class _Named {
  const _Named(this.id, this.name);
  final String id;
  final String name;
}

/// One piece of a date expression; whitespace-adjacent pieces are combined
/// into one token (rule 7).
class _Part {
  _Part.day(this.start, this.end, DateTime this.date)
    : weekday = null,
      next = false,
      hour = null,
      minute = null,
      moment = null,
      weak = false;

  _Part.weekday(
    this.start,
    this.end,
    int this.weekday, {
    required this.next,
    required this.weak,
  }) : date = null,
       hour = null,
       minute = null,
       moment = null;

  _Part.time(
    this.start,
    this.end,
    int this.hour,
    int this.minute, {
    required this.weak,
  }) : date = null,
       weekday = null,
       next = false,
       moment = null;

  /// «через N минут/часов»: a date **and** a time, combines with nothing.
  _Part.moment(this.start, this.end, DateTime this.moment)
    : date = null,
      weekday = null,
      next = false,
      hour = null,
      minute = null,
      weak = false;

  final int start;
  final int end;
  final DateTime? date;
  final int? weekday;
  final bool next;
  final int? hour;
  final int? minute;
  final DateTime? moment;
  final bool weak;

  bool get hasDay => date != null || weekday != null || moment != null;
  bool get hasTime => hour != null || moment != null;
  bool get isTimeOnly => hour != null;

  bool conflicts(_Part other) =>
      (hasDay && other.hasDay) || (hasTime && other.hasTime);
}

// ---------------------------------------------------------------------------
// Vocabulary
// ---------------------------------------------------------------------------

/// Not followed by a letter or digit, nor by `.5`, `:30`, `/11`, `,5`, `-6` (a
/// longer number, a version, a decimal, a range).
const String _end = r'(?![\p{L}\p{N}]|[.:/,\-]\p{N})';

final RegExp _dayPattern = RegExp(
  '(сегодня|завтра|послезавтра)$_end',
  unicode: true,
);

const String _weekdayNames =
    'понедельник|вторник|среду|среда|четверг|пятницу|пятница|субботу|суббота|'
    'воскресенье|пн|вт|ср|чт|пт|сб|вс';

const String _nextAdj = r'следующ(?:ий|ую|ее|ая|ей|его|ему)';

final RegExp _weekdayInPattern = RegExp(
  '(?:(во?)\\s+)?(?:($_nextAdj)\\s+)?($_weekdayNames)$_end',
  unicode: true,
);

final RegExp _weekdayToPattern = RegExp(
  '(?:к|до)\\s+(?:($_nextAdj)\\s+)?'
  '(понедельник[ау]|вторник[ау]|сред[еы]|четверг[ау]|пятниц[еы]|'
  'суббот[еы]|воскресень[яю])$_end',
  unicode: true,
);

const String _months =
    'января|янв|февраля|февр|фев|марта|мар|апреля|апр|мая|июня|июн|июля|июл|'
    'августа|авг|сентября|сент|сен|октября|окт|ноября|нояб|ноя|декабря|дек';

final RegExp _namedDatePattern = RegExp(
  '(?:(?:к|до)\\s+)?(\\d{1,2})\\s+($_months)$_end(?:\\s+(\\d{4})$_end)?',
  unicode: true,
);

final RegExp _numericDatePattern = RegExp(
  '(?:(?:к|до)\\s+)?(\\d{1,2})([./])(\\d{2})(?:\\2(\\d{4}))?$_end',
  unicode: true,
);

final RegExp _timePattern = RegExp(
  '(?:в|во|к)\\s+(?:(полдень)|(\\d{1,2})(?:[:.](\\d{2}))?'
  '(?:\\s*(часов|часам|часа|час|ч)(?!\\p{L}))?'
  '(?:\\s+(утра|дня|вечера|ночи))?)$_end',
  unicode: true,
);

final RegExp _bareTimePattern = RegExp(
  '(\\d{1,2}):(\\d{2})$_end',
  unicode: true,
);

final RegExp _relativePattern = RegExp(
  'через\\s+(?:(\\d{1,3}|один|одну|одна|два|две|три|четыре|пять|шесть|семь|'
  'восемь|девять|десять|пару)\\s+)?'
  '(минуты|минуту|минут|мин|часов|часа|час|ч|полчаса|дней|дня|день|сутки|'
  'недель|недели|неделю|месяцев|месяца|месяц)$_end',
  unicode: true,
);

final RegExp _tagPattern = RegExp(
  r'[#/](?:"([^"\n]*)"|([\p{L}\p{N}_\-]+))',
  unicode: true,
);

final RegExp _followingWord = RegExp(
  r'[ \t]+([\p{L}\p{N}_\-]+)',
  unicode: true,
);

final RegExp _linkPattern = RegExp(
  r'(?:https?://|www\.)[^\s<>"«»]+',
  caseSensitive: false,
);

/// Words that hang when the token after them is cut, or at the ends of a
/// cleaned title.
const Set<String> _hangingWords = {
  'в', 'во', 'на', 'к', 'ко', 'до', 'с', 'со', 'по', 'за', 'от', 'у', //
};

const Set<String> _edgeWords = {..._hangingWords, 'и', 'а'};

int _weekdayOf(String name) {
  if (name.startsWith('пон') || name == 'пн') return DateTime.monday;
  if (name.startsWith('вт')) return DateTime.tuesday;
  if (name.startsWith('ср')) return DateTime.wednesday;
  if (name.startsWith('чет') || name == 'чт') return DateTime.thursday;
  if (name.startsWith('пят') || name == 'пт') return DateTime.friday;
  if (name.startsWith('суб') || name == 'сб') return DateTime.saturday;
  return DateTime.sunday;
}

int _monthOf(String name) {
  const stems = [
    'янв', 'фев', 'мар', 'апр', 'ма', 'июн', //
    'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
  ];
  for (var k = 0; k < stems.length; k++) {
    if (name.startsWith(stems[k])) return k + 1;
  }
  throw ArgumentError.value(name, 'name', 'not a month');
}

int _countOf(String word) => switch (word) {
  'один' || 'одну' || 'одна' => 1,
  'два' || 'две' || 'пару' => 2,
  'три' => 3,
  'четыре' => 4,
  'пять' => 5,
  'шесть' => 6,
  'семь' => 7,
  'восемь' => 8,
  'девять' => 9,
  'десять' => 10,
  _ => int.parse(word),
};

/// Spoken hour to 24h. Without a qualifier 1–7 is the evening («в 5» is
/// 17:00 in a task list), 8–23 and 0 are as said.
int _hour24(int h, String? meridiem) => switch (meridiem) {
  'утра' => h == 12 ? 0 : h,
  'ночи' => h == 12 ? 0 : h,
  'дня' => h >= 1 && h <= 6 ? h + 12 : h,
  'вечера' => h >= 1 && h <= 11 ? h + 12 : h,
  _ => h >= 1 && h <= 7 ? h + 12 : h,
};

DateTime _addMonths(DateTime d, int months) {
  final first = DateTime.utc(d.year, d.month + months, 1);
  final lastDay = DateTime.utc(first.year, first.month + 1, 0).day;
  return DateTime.utc(
    first.year,
    first.month,
    d.day > lastDay ? lastDay : d.day,
  );
}

// ---------------------------------------------------------------------------
// Text helpers
// ---------------------------------------------------------------------------

/// Lower case with `ё` → `е`, **keeping every offset**: one code unit in, one
/// out, so a match position in the normalised string is the position in the
/// original.
String _normalize(String s) {
  final out = List<int>.filled(s.length, 0);
  for (var k = 0; k < s.length; k++) {
    var c = s.codeUnitAt(k);
    if (c >= 0x41 && c <= 0x5A) {
      c += 0x20; // A-Z
    } else if (c >= 0x410 && c <= 0x42F) {
      c += 0x20; // А-Я
    } else if (c == 0x401 || c == 0x451) {
      c = 0x435; // Ё ё → е
    }
    out[k] = c;
  }
  return String.fromCharCodes(out);
}

String _collapse(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

final RegExp _wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);

bool _isWordChar(int c) {
  if (c < 0x80) {
    return (c >= 0x30 && c <= 0x39) ||
        (c >= 0x41 && c <= 0x5A) ||
        (c >= 0x61 && c <= 0x7A);
  }
  if (c >= 0xD800 && c <= 0xDFFF) return false;
  return _wordChar.hasMatch(String.fromCharCode(c));
}

bool _isSpace(int c) => c == 0x20 || c == 0x09 || c == 0xA0;

bool _isUpper(String s) =>
    s.isNotEmpty && s[0] != s[0].toLowerCase() && s[0] == s[0].toUpperCase();

/// The cleanup after cutting tokens out (see [stripTokens]).
String _tidy(String s) {
  var out = s
      .replaceAll(RegExp(r'[ \t ]+'), ' ')
      .replaceAll(RegExp(r' *\n *'), '\n')
      .replaceAllMapped(RegExp(r' +([,.;:!?)\]»…])'), (m) => m[1]!)
      .replaceAll(RegExp(r',(\s*,)+'), ',')
      .replaceAll(RegExp(r',\s*(?=[.;:!?]|$)', multiLine: true), '')
      .replaceAllMapped(RegExp(r'([(\[«]) +'), (m) => m[1]!)
      .replaceAll(RegExp(r'\(\s*\)|\[\s*\]'), '')
      .replaceAll(RegExp(r' {2,}'), ' ');

  final edgePunct = RegExp(r'^[\s,;:—–-]+|[\s,;:—–-]+$');
  while (true) {
    final before = out;
    out = out.replaceAll(edgePunct, '');
    final words = out.split(' ');
    if (words.length > 1 && _edgeWords.contains(_normalize(words.first))) {
      out = words.skip(1).join(' ');
    }
    final tail = out.split(' ');
    if (tail.length > 1) {
      final last = tail.last;
      final bare = last.replaceAll(RegExp(r'[.!?…]+$'), '');
      if (_edgeWords.contains(_normalize(bare))) {
        final mark = last.substring(bare.length);
        out = tail.take(tail.length - 1).join(' ') + mark;
      }
    }
    if (out == before) break;
  }
  return out.trim();
}

bool _sameList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var k = 0; k < a.length; k++) {
    if (a[k] != b[k]) return false;
  }
  return true;
}
