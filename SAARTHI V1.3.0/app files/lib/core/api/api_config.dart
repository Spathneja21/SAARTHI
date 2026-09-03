import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Where the AURA backend lives, per platform.
///
/// "localhost" means something different on every target, which is the single
/// most common cause of a Flutter app that works on one device and silently
/// fails to connect on another:
///
///   * iOS Simulator and desktop share the host's network stack, so
///     `localhost` resolves to the developer's machine.
///   * The Android emulator runs behind its own NAT. `localhost` there is the
///     *emulator itself*, so the host must be reached at the special alias
///     `10.0.2.2` — the request otherwise fails with "connection refused"
///     rather than anything that hints at the real problem.
///   * A physical phone is on the LAN and needs the machine's actual LAN IP;
///     neither `localhost` nor `10.0.2.2` can reach it.
///
/// Override at build time to point at a LAN IP or a deployed server:
///   flutter run --dart-define=AURA_API_BASE_URL=http://192.168.1.7:8000
class ApiConfig {
  ApiConfig._();

  static const String _override =
      String.fromEnvironment('AURA_API_BASE_URL', defaultValue: '');

  static const int _port = 8000;

  static String get baseUrl {
    if (_override.isNotEmpty) {
      return _override;
    }
    // kIsWeb must be checked first. `defaultTargetPlatform` reports the
    // underlying OS even in a browser, so a Chrome tab on an Android device
    // would otherwise be handed the emulator's 10.0.2.2 alias.
    //
    // Platform detection deliberately uses `defaultTargetPlatform` rather than
    // `dart:io`'s `Platform`: `dart:io` does not exist on web, and importing it
    // breaks the web build at compile time even when every use of it is guarded
    // behind `kIsWeb`.
    if (kIsWeb) {
      return 'http://localhost:$_port';
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:$_port';
    }
    // iOS Simulator, macOS, Windows, Linux.
    return 'http://localhost:$_port';
  }

  /// How long to wait before giving up on a request.
  ///
  /// Generous because `POST /schedule/cpsat` runs the CP-SAT solver, which has
  /// its own 3-second budget per solve and can take longer across a full
  /// seven-day horizon with many tasks.
  static const Duration timeout = Duration(seconds: 30);
}
