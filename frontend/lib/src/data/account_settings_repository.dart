import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

final accountSettingsRepositoryProvider = Provider<AccountSettingsRepository>((
  ref,
) {
  return AccountSettingsRepository(ref.watch(dioProvider));
});

final accountSettingsProvider = FutureProvider.autoDispose<AccountSettings>((
  ref,
) {
  return ref.watch(accountSettingsRepositoryProvider).get();
});

class AccountSettings {
  const AccountSettings({
    required this.citationStyle,
    required this.locale,
    required this.showConfidence,
  });
  final String citationStyle;
  final String locale;
  final bool showConfidence;
  factory AccountSettings.fromJson(Map<String, dynamic> json) =>
      AccountSettings(
        citationStyle: json['citation_style']?.toString() ?? 'apa7',
        locale: json['locale']?.toString() ?? 'id',
        showConfidence: json['show_confidence'] as bool? ?? true,
      );
  Map<String, dynamic> toJson() => {
    'citation_style': citationStyle,
    'locale': locale,
    'show_confidence': showConfidence,
  };
}

class AccountSettingsRepository {
  const AccountSettingsRepository(this._dio);
  final Dio _dio;
  Future<AccountSettings> get() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/account/settings',
    );
    return AccountSettings.fromJson(response.data!);
  }

  Future<AccountSettings> save(AccountSettings settings) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/api/v1/account/settings',
      data: settings.toJson(),
    );
    return AccountSettings.fromJson(response.data!);
  }
}
