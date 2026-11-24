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

  /// Sold-out polling on the menu screen, matching the kiosk's ~20 s availability poll.
  static const Duration menuAvailabilityPollInterval = Duration(seconds: 20);
}
