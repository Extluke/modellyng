import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import 'auth_repository.dart';

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Accept': 'application/json'},
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        options.headers.remove('Authorization');
        final session = ref.read(authRepositoryProvider).currentSession;
        if (session == null) {
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.cancel,
              error: 'Authentication session is not ready',
            ),
          );
          return;
        }
        options.headers['Authorization'] = 'Bearer ${session.accessToken}';
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          try {
            await ref.read(authRepositoryProvider).signOut();
          } catch (_) {}
        }
        handler.next(error);
      },
    ),
  );

  return dio;
});
