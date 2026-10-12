import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'global_chat_repository.dart';

final globalChatCacheServiceProvider = Provider<GlobalChatCacheService>((ref) {
  return const GlobalChatCacheService();
});

class GlobalChatCacheService {
  const GlobalChatCacheService({this.prefsFuture});

  final Future<SharedPreferences>? prefsFuture;

  static const Duration cacheTtl = Duration(hours: 24);
  static const String keyPrefix = 'global_chat_cache_24h_';

  Future<SharedPreferences> _getPrefs() async {
    return await (prefsFuture ?? SharedPreferences.getInstance());
  }

  static String cacheKey(String userId) => '$keyPrefix$userId';

  /// Returns valid cached messages for [userId] that are strictly less than 24 hours old.
  /// Any expired messages (> 24 hours old) are pruned automatically.
  Future<List<GlobalChatMessage>> getValidHistory(
    String userId, {
    DateTime? now,
  }) async {
    final currentTime = now ?? DateTime.now();
    try {
      final prefs = await _getPrefs();
      final raw = prefs.getString(cacheKey(userId));
      if (raw == null || raw.trim().isEmpty) return const [];

      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];

      final validMessages = <GlobalChatMessage>[];
      bool hadExpired = false;

      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          final msg = GlobalChatMessage.fromJson(item);
          final timestamp = msg.timestamp ?? currentTime;

          // Message is valid if elapsed duration <= 24 hours
          if (currentTime.difference(timestamp) <= cacheTtl &&
              !timestamp.isAfter(currentTime.add(const Duration(minutes: 5)))) {
            validMessages.add(msg);
          } else {
            hadExpired = true;
          }
        }
      }

      // Automatically prune expired messages from storage
      if (hadExpired) {
        if (validMessages.isEmpty) {
          await prefs.remove(cacheKey(userId));
        } else {
          await _saveRaw(prefs, userId, validMessages);
        }
      }

      return validMessages;
    } catch (_) {
      // In case of any corrupt data, gracefully fallback to empty list
      return const [];
    }
  }

  /// Saves the active chat messages for [userId] with timestamps into cache.
  Future<void> saveHistory(
    String userId,
    List<GlobalChatMessage> messages,
  ) async {
    try {
      final prefs = await _getPrefs();
      await _saveRaw(prefs, userId, messages);
    } catch (_) {}
  }

  Future<void> _saveRaw(
    SharedPreferences prefs,
    String userId,
    List<GlobalChatMessage> messages,
  ) async {
    final list = messages.map((m) => m.toJson()).toList(growable: false);
    await prefs.setString(cacheKey(userId), jsonEncode(list));
  }

  /// Manually clears cached history for [userId].
  Future<void> clearHistory(String userId) async {
    try {
      final prefs = await _getPrefs();
      await prefs.remove(cacheKey(userId));
    } catch (_) {}
  }
}
