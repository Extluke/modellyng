import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:modellyng/src/config/app_config.dart';

void main() {
  test('client configuration rejects privileged and malformed keys', () {
    String key(String role) =>
        'header.${base64Url.encode(utf8.encode(jsonEncode({'role': role})))}.signature';
    expect(AppConfig.isPublicClientKey(key('service_role')), isFalse);
    expect(AppConfig.isPublicClientKey(key('authenticated')), isFalse);
    expect(AppConfig.isPublicClientKey('sb_secret_test'), isFalse);
    expect(AppConfig.isPublicClientKey('invalid'), isFalse);
    expect(AppConfig.isPublicClientKey(key('anon')), isTrue);
  });
  test('beta rejects local or non-HTTPS service addresses', () {
    for (final value in [
      'http://service.example',
      'http://127.0.0.1:8000',
      'https://127.0.0.1',
      'https://[::ffff:127.0.0.1]',
      'https://localhost',
      'https://server.local',
      'https://user:password@service.example',
      'https://service.example?key=value',
      '',
    ]) {
      expect(AppConfig.isPublicHttps(value), isFalse, reason: value);
    }
    expect(AppConfig.isPublicHttps('https://beta.example.com'), isTrue);
  });
}
