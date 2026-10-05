import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/global_chat_repository.dart';
import '../theme/app_theme.dart';

class _ChatMessage {
  const _ChatMessage({
    required this.role,
    required this.content,
  });

  final String role;
  final String content;
}

class GlobalChatScreen extends ConsumerStatefulWidget {
  const GlobalChatScreen({
    required this.userId,
    super.key,
  });

  final String userId;

  @override
  ConsumerState<GlobalChatScreen> createState() => _GlobalChatScreenState();
}

class _GlobalChatScreenState extends ConsumerState<GlobalChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _messages = <_ChatMessage>[];
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _messages.add(
      const _ChatMessage(
        role: 'assistant',
        content:
            'Halo! Saya adalah asisten AI Modellyng. Ada yang bisa saya bantu terkait penggunaan aplikasi ini, atau apakah Anda ingin berdiskusi mengenai penelitian secara umum?',
      ),
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

    final userMessage = _ChatMessage(role: 'user', content: text);
    setState(() {
      _messages.add(userMessage);
      _sending = true;
      _controller.clear();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    try {
      final history = _messages
          .where((m) => m != userMessage && m.role != 'assistant') // Simplified history
          .map((m) => GlobalChatMessage(role: m.role, content: m.content))
          .toList();

      final response = await ref.read(globalChatRepositoryProvider).sendQuestion(
            text,
            history,
          );

      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage(
          role: 'assistant',
          content: response.answer,
        ));
      });
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
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: AppColors.primarySoft,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: const Text(
              'Ini adalah asisten general. Percakapan ini tidak disimpan dan akan hilang saat Anda memuat ulang aplikasi.',
              style: TextStyle(color: AppColors.primaryDark),
            ),
          ),
          Expanded(
            child: ListView.builder(
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
                    mainAxisAlignment:
                        isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                    children: [
                      if (!isUser) ...[
                        const CircleAvatar(
                          radius: 16,
                          backgroundColor: AppColors.primary,
                          child: Icon(Icons.auto_awesome, color: Colors.white, size: 16),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isUser ? AppColors.primarySoft : Colors.white,
                            border: isUser ? null : Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: MarkdownBody(
                            data: message.content,
                            selectable: true,
                            styleSheet: MarkdownStyleSheet(
                              p: TextStyle(
                                color: isUser ? AppColors.primaryDark : AppColors.ink,
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
                          child: Icon(Icons.person, color: AppColors.muted, size: 16),
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
                  elevation: 0,
                  onPressed: _sending ? null : _send,
                  backgroundColor: _sending ? AppColors.border : AppColors.primary,
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
