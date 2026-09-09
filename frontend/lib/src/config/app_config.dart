import 'dart:convert';

class AppConfig {
  const AppConfig._();

  static const betaBuild = bool.fromEnvironment('BETA_BUILD');

  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'http://127.0.0.1:18021',
  );

  // A publishable key is designed to be embedded in a client application.
  // Database access is still protected by Supabase Auth and RLS policies.
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH',
  );

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  static bool isPublicHttps(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment)
      return false;
    final host = uri.host.toLowerCase();
    return host.contains('.') &&
        !host.contains(':') &&
        !host.endsWith('.localhost') &&
        !host.endsWith('.local') &&
        !RegExp(r'^[\d.]+$').hasMatch(host);
  }

  static bool get validForBeta =>
      isPublicHttps(apiBaseUrl) &&
      isPublicHttps(supabaseUrl) &&
      isPublicClientKey(supabasePublishableKey);

  static bool isPublicClientKey(String key) {
    if (key.startsWith('sb_publishable_')) return key.length > 20;
    try {
      final parts = key.split('.');
      if (parts.length != 3) return false;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      return payload is Map && payload['role'] == 'anon';
    } catch (_) {
      return false;
    }
  }
}
