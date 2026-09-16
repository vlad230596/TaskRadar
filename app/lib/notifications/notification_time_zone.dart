import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Resolves "which timezone is this device in", once, at startup.
///
/// ## Why this file exists at all
///
/// `zonedSchedule` wants a `TZDateTime`, and a `TZDateTime` wants a
/// [tz.Location]. The `timezone` package ships the whole IANA database but has
/// no way to find out which entry of it the phone is set to -- left alone,
/// `tz.local` is **UTC**. That default is the worst kind of bug: the code
/// compiles, the alarm is armed, `pendingNotificationRequests` looks right, and
/// the notification arrives at 12:00 instead of 09:00 for a user in UTC+3. It
/// would look exactly like the power-management problem this iteration is
/// supposed to be measuring.
///
/// So the device's zone name comes from `flutter_timezone` (a platform channel)
/// and is fed to `tz.setLocalLocation`.
class NotificationTimeZone {
  NotificationTimeZone._(this.location, this.source, this.detail);

  /// The zone every reminder is scheduled in.
  final tz.Location location;

  /// How [location] was arrived at -- shown on the bench screen, because
  /// "reminders are 3 hours off" and "we fell back to a fixed offset" are the
  /// same sentence said twice.
  final TimeZoneSource source;

  /// Human-readable extra (the raw identifier, or the error text).
  final String detail;

  String get name => location.name;

  /// Loads the tz database and picks the local zone. Idempotent.
  ///
  /// Never throws: a device that cannot report its zone should still get
  /// reminders at approximately the right hour rather than no reminders at all.
  static Future<NotificationTimeZone> resolve() async {
    // Loads the full IANA database into memory (a few hundred KB). `latest.dart`
    // rather than `latest_all.dart`: the former drops zones that are aliases of
    // others, which is all this app needs and roughly halves the payload.
    tz_data.initializeTimeZones();

    String? identifier;
    try {
      identifier = (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (error) {
      // Platform channel missing (unit tests, an unsupported desktop
      // configuration) or the platform answered something unparseable.
      debugPrint('Could not read the device timezone: $error');
    }

    if (identifier != null) {
      try {
        final location = tz.getLocation(identifier);
        tz.setLocalLocation(location);
        return NotificationTimeZone._(
          location,
          TimeZoneSource.device,
          identifier,
        );
      } on tz.LocationNotFoundException catch (error) {
        // The device named a zone the bundled database does not have -- happens
        // with vendor-specific or newly-created zone names.
        debugPrint('Unknown timezone "$identifier": $error');
      }
    }

    final fallback = _fixedOffsetLocation(DateTime.now().timeZoneOffset);
    tz.setLocalLocation(fallback);
    return NotificationTimeZone._(
      fallback,
      TimeZoneSource.fixedOffset,
      fallback.name,
    );
  }

  /// Builds a single-zone [tz.Location] pinned to the offset the Dart VM
  /// reports right now.
  ///
  /// This is a genuine degradation and is labelled as one. It gets the hour
  /// right today, and stays right for as long as the offset does -- which for
  /// Russia (no DST since 2014) is forever, and for a DST country is until the
  /// next transition, after which reminders scheduled *across* that transition
  /// are an hour out. An hour out beats UTC, which is up to twelve.
  static tz.Location _fixedOffsetLocation(Duration offset) {
    final sign = offset.isNegative ? '-' : '+';
    final absolute = offset.abs();
    final name =
        'UTC$sign${absolute.inHours.toString().padLeft(2, '0')}:'
        '${(absolute.inMinutes % 60).toString().padLeft(2, '0')}';

    return tz.Location(
      name,
      <int>[tz.minTime],
      <int>[0],
      <tz.TimeZone>[
        tz.TimeZone(offset, isDst: false, abbreviation: name),
      ],
    );
  }
}

/// Where the local [tz.Location] came from.
enum TimeZoneSource {
  /// The OS told us an IANA identifier and the database had it. Correct across
  /// DST transitions.
  device,

  /// We had to synthesise a fixed-offset zone. See
  /// [NotificationTimeZone._fixedOffsetLocation].
  fixedOffset,
}
