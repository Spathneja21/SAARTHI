/// Converting backend timestamps into the wall-clock times the UI should draw.
///
/// The backend is hardcoded to IST. `models/models.py` wraps every datetime
/// column in an `ISTDateTime` type that forces reads back to `Asia/Kolkata`, and
/// `core/tz.py` has a single module-level `IST` constant with no per-user
/// timezone anywhere (the `users.timezone` column exists but is never read). So
/// every timestamp arrives as e.g. `2026-09-03T15:50:00+05:30`, and the CP-SAT
/// scheduler chose that slot meaning *15:50 India time*.
///
/// `DateTime.parse` on a string with an offset returns a **UTC** `DateTime`
/// holding the correct instant — `2026-09-03T10:20:00Z` for the example above.
/// Calling `.toLocal()` then renders it in the *device's* timezone. On a phone
/// set to IST that happens to be right, which is exactly what makes this
/// dangerous: it works during development in India and silently shifts every
/// block on the timeline for a device set to any other zone.
///
/// Since the scheduler's intent is expressed in IST, the UI must render IST.
/// These helpers convert explicitly rather than relying on the device matching.
library;

/// India Standard Time: UTC+05:30, with no daylight saving to complicate it.
const Duration istOffset = Duration(hours: 5, minutes: 30);

/// Parse a backend timestamp into a `DateTime` whose *fields* read as IST
/// wall-clock time.
///
/// The result is deliberately flagged as local rather than UTC so that
/// `.hour`, `.minute` and `DateFormat` all read the IST values directly —
/// which is what the timeline's layout maths and every label need. Do not
/// call `.toLocal()` or `.toUtc()` on the result; treat it as a wall clock.
DateTime parseBackendTime(String iso) {
  // Shift the instant into IST, then rebuild from the resulting *field values*.
  //
  // The rebuild is the crucial step. `utc.add(istOffset)` already holds the
  // right numbers, but it is still flagged `isUtc`, so any later `.toLocal()`
  // — including the one Dart applies when formatting — would shift it a second
  // time. An earlier version of this function ended in `.toLocal()` and did
  // exactly that: on a machine already set to IST, 15:50 came out as 21:20.
  // Passing the fields through the plain `DateTime` constructor produces a
  // local-flagged value that no further conversion will move.
  final ist = DateTime.parse(iso).toUtc().add(istOffset);
  return DateTime(
    ist.year,
    ist.month,
    ist.day,
    ist.hour,
    ist.minute,
    ist.second,
    ist.millisecond,
  );
}

/// Nullable convenience for optional fields such as `deadline` and `started_at`.
DateTime? parseBackendTimeOrNull(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  return parseBackendTime(iso);
}

/// Serialize a wall-clock `DateTime` the user picked into the offset-bearing
/// ISO string the backend expects.
///
/// The explicit `+05:30` matters: a bare `toIso8601String()` on a local
/// `DateTime` emits no offset, and FastAPI would then interpret it as a naive
/// timestamp, mixing timezone-aware and naive values in the same comparison.
String formatBackendTime(DateTime wallClock) {
  final d = wallClock.isUtc ? wallClock.add(istOffset) : wallClock;
  final s = '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}T'
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}:'
      '${d.second.toString().padLeft(2, '0')}';
  return '$s+05:30';
}
