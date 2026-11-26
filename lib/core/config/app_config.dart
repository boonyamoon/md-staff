/// Build-time configuration.
///
/// The API base URL is baked in at build time, exactly as the kiosk app bakes in
/// `kioskApiBaseUrl`: a handset in a shop must not be able to be pointed at another server from
/// its own UI. Override it per build:
///
/// ```sh
/// flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080/
/// flutter build apk --release --dart-define=API_BASE_URL=https://api.meedeepos.com/
/// ```
class AppConfig {
  const AppConfig._();

  static const String _rawBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.meedeepos.com/',
  );

  /// Always ends with a single `/`, so request paths can be written without a leading slash.
  static String get apiBaseUrl => _rawBaseUrl.endsWith('/') ? _rawBaseUrl : '$_rawBaseUrl/';

  static bool get isHttps => apiBaseUrl.startsWith('https://');

  /// How often a held table's lease is renewed. The server also returns its own
  /// `claim_renew_after_ms`, which wins when present — this is only the pre-config default.
  static const Duration defaultClaimRenewInterval = Duration(seconds: 60);

  // Nothing is polled. These are how old the offline copy may get before the next natural moment
  // — opening the app, returning to it, entering a screen — fetches it again. Pulling down
  // always fetches.

  /// The floor: other devices change it all through service.
  static const Duration floorMaxAge = Duration(seconds: 60);

  /// Which dishes are sold out, checked on entering the menu. The server checks again on send.
  static const Duration availabilityMaxAge = Duration(minutes: 2);

  /// The menu itself, which changes rarely.
  static const Duration menuMaxAge = Duration(hours: 6);
}
