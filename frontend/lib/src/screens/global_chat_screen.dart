import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/global_chat_cache_service.dart';
import '../data/global_chat_repository.dart';
import '../theme/app_theme.dart';

class _ChatMessage {
  const _ChatMessage({
    required this.role,
    required this.content,
    this.timestamp,
  });

  final String role;
  final String content;
  final DateTime? timestamp;
}

class GlobalChatScreen extends ConsumerStatefulWidget {
  const GlobalChatScreen({required this.userId, super.key});

  final String userId;

  @override
  ConsumerState<GlobalChatScreen> createState() => _GlobalChatScreenState();
}

class _GlobalChatScreenState extends ConsumerState<GlobalChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _messages = <_ChatMessage>[];
  bool _sending = false;
  bool _loadingHistory = true;

  bool get _hasUserPrompt => _messages.any((m) => m.role == 'user');

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final cached = await ref
          .read(globalChatCacheServiceProvider)
          .getValidHistory(widget.userId);

      if (!mounted) return;
      if (cached.isNotEmpty) {
        setState(() {
          _messages.addAll(
            cached.map(
              (m) => _ChatMessage(
                role: m.role,
                content: m.content,
                timestamp: m.timestamp,
              ),
            ),
          );
          _loadingHistory = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        return;
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _messages.add(
        _ChatMessage(
          role: 'assistant',
          content:
              'Halo! Saya adalah asisten AI Modellyng. Ada yang bisa saya bantu terkait penggunaan aplikasi ini, atau apakah Anda ingin berdiskusi mengenai penelitian secara umum?',
          timestamp: DateTime.now(),
        ),
      );
      _loadingHistory = false;
    });
  }

  void _saveToCache() {
    final toSave = _messages
        .map(
          (m) => GlobalChatMessage(
            role: m.role,
            content: m.content,
            timestamp: m.timestamp ?? DateTime.now(),
          ),
        )
        .toList(growable: false);
    ref.read(globalChatCacheServiceProvider).saveHistory(widget.userId, toSave);
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Riwayat Chat?'),
        content: const Text(
          'Percakapan sementara Anda akan dihapus dari penyimpanan perangkat.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await ref.read(globalChatCacheServiceProvider).clearHistory(widget.userId);

    if (!mounted) return;
    setState(() {
      _messages.clear();
      _messages.add(
        _ChatMessage(
          role: 'assistant',
          content:
              'Halo! Saya adalah asisten AI Modellyng. Ada yang bisa saya bantu terkait penggunaan aplikasi ini, atau apakah Anda ingin berdiskusi mengenai penelitian secara umum?',
          timestamp: DateTime.now(),
        ),
      );
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Riwayat percakapan berhasil dibersihkan.')),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    final now = DateTime.now();
    final userMessage = _ChatMessage(
      role: 'user',
      content: text,
      timestamp: now,
    );
    setState(() {
      _messages.add(userMessage);
      _sending = true;
      _controller.clear();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    _saveToCache();

    try {
      final history = _messages
          .where((m) => m != userMessage && m.role != 'assistant')
          .map(
            (m) => GlobalChatMessage(
              role: m.role,
              content: m.content,
              timestamp: m.timestamp,
            ),
          )
          .toList();

      final response = await ref
          .read(globalChatRepositoryProvider)
          .sendQuestion(text, history);

      if (!mounted) return;
      setState(() {
        _messages.add(
          _ChatMessage(
            role: 'assistant',
            content: response.answer,
            timestamp: DateTime.now(),
          ),
        );
      });
      _saveToCache();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal mengirim pesan: $e'),
          backgroundColor: AppColors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Asisten Modellyng'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        actions: [
          IconButton(
            key: const Key('clear-chat-history-button'),
            tooltip: 'Hapus riwayat chat',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: _messages.length <= 1 ? null : _clearHistory,
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: Column(
        children: [
          if (!_loadingHistory && !_hasUserPrompt)
            Container(
              key: const Key('chat-cache-banner'),
              width: double.infinity,
              color: AppColors.primarySoft,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: const Row(
                children: [
                  Icon(
                    Icons.history_rounded,
                    size: 18,
                    color: AppColors.primaryDark,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Sistem akan menghapus riwayat chat dalam waktu 1x24 jam.',
                      style: TextStyle(
                        color: AppColors.primaryDark,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loadingHistory
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(20),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final isUser = message.role == 'user';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: isUser
                              ? MainAxisAlignment.end
                              : MainAxisAlignment.start,
                          children: [
                            if (!isUser) ...[
                              const CircleAvatar(
                                radius: 16,
                                backgroundColor: AppColors.primary,
                                child: Icon(
                                  Icons.auto_awesome,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: isUser
                                      ? AppColors.primarySoft
                                      : Colors.white,
                                  border: isUser
                                      ? null
                                      : Border.all(color: AppColors.border),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: MarkdownBody(
                                  data: message.content,
                                  selectable: true,
                                  styleSheet: MarkdownStyleSheet(
                                    p: TextStyle(
                                      color: isUser
                                          ? AppColors.primaryDark
                                          : AppColors.ink,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (isUser) ...[
                              const SizedBox(width: 12),
                              const CircleAvatar(
                                radius: 16,
                                backgroundColor: AppColors.border,
                                child: Icon(
                                  Icons.person,
                                  color: AppColors.muted,
                                  size: 16,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: !_sending,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: 'Tanyakan sesuatu...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FloatingActionButton(
                  key: const Key('send-chat-button'),
                  elevation: 0,
                  onPressed: _sending ? null : _send,
                  backgroundColor: _sending
                      ? AppColors.border
                      : AppColors.primary,
                  foregroundColor: Colors.white,
                  child: _sending
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
