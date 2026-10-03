import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/component_revise_repository.dart';
import '../data/global_chat_repository.dart'; // Re-use GlobalChatMessage
import '../data/review_repository.dart'; // for submitting review & ReviewQueueItem
import '../theme/app_theme.dart';

class _RevisionMessage {
  const _RevisionMessage({
    required this.role,
    required this.content,
    this.isRevisionResult = false,
  });

  final String role;
  final String content;
  final bool isRevisionResult;
}

class ComponentRevisionScreen extends ConsumerStatefulWidget {
  const ComponentRevisionScreen({
    super.key,
    required this.projectId,
    required this.component,
  });

  final String projectId;
  final ReviewQueueItem component;

  @override
  ConsumerState<ComponentRevisionScreen> createState() =>
      _ComponentRevisionScreenState();
}

class _ComponentRevisionScreenState
    extends ConsumerState<ComponentRevisionScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  final _messages = <_RevisionMessage>[];
  bool _sending = false;
  bool _showInputArea = true;

  @override
  void initState() {
    super.initState();
    _messages.add(
      _RevisionMessage(
        role: 'assistant',
        content:
            'Silakan berikan komentar — hasil seperti apa yang Anda inginkan untuk komponen **${widget.component.parameterLabel}** ini?',
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
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

    final userMessage = _RevisionMessage(role: 'user', content: text);
    setState(() {
      _messages.add(userMessage);
      _sending = true;
      _showInputArea = false;
      _controller.clear();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    try {
      final history = _messages
          .where((m) => m != userMessage && m.role != 'assistant')
          .map((m) => GlobalChatMessage(role: m.role, content: m.content))
          .toList();

      final evidenceQuotes = widget.component.evidence
          .map((e) => e.quote)
          .toList();

      final response = await ref
          .read(componentReviseRepositoryProvider)
          .reviseComponent(
            widget.projectId,
            widget.component.componentId,
            widget.component.parameter,
            widget.component.aiValue,
            evidenceQuotes,
            text,
            history,
          );

      if (!mounted) return;
      setState(() {
        _messages.add(
          _RevisionMessage(
            role: 'assistant',
            content: response.revisedContent,
            isRevisionResult: true,
          ),
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _showInputArea = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal merevisi: $e'),
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

  Future<void> _approveRevision(String revisedText) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      await ref
          .read(reviewRepositoryProvider)
          .submitDecision(
            componentId: widget.component.componentId,
            decision: ReviewDecision.edit,
            correctedValue: revisedText,
            note: 'Diperbarui melalui AI Chatbot',
          );

      if (!mounted) return;
      Navigator.of(context).pop(); // Tutup loading
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Komponen berhasil diperbarui!'),
          backgroundColor: AppColors.green,
        ),
      );
      // Kembali ke halaman sebelumnya (kemungkinan PaperResultScreen atau Review Tab)
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // Tutup loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal menyimpan revisi: $e'),
          backgroundColor: AppColors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Revisi Komponen (AI)'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      backgroundColor: const Color(0xFFF8F9FA),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Teks Asli (${widget.component.parameterLabel})',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  widget.component.aiValue,
                  style: const TextStyle(color: AppColors.ink, height: 1.5),
                  maxLines: 4,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(20),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final isUser = message.role == 'user';

                if (message.isRevisionResult) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: AppColors.primary),
                      ),
                      color: AppColors.primarySoft,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(
                                  Icons.auto_awesome,
                                  color: AppColors.primary,
                                  size: 20,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Hasil Revisi AI',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primaryDark,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: SelectableText(
                                message.content,
                                style: const TextStyle(
                                  color: AppColors.ink,
                                  height: 1.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () {
                                    // User wants to reject again, show input and focus
                                    setState(() {
                                      _showInputArea = true;
                                    });
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          _focusNode.requestFocus();
                                          _scrollToBottom();
                                        });
                                  },
                                  icon: const Icon(Icons.close),
                                  label: const Text('Tolak Lagi'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.red,
                                    side: const BorderSide(
                                      color: AppColors.redSoft,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                FilledButton.icon(
                                  onPressed: () =>
                                      _approveRevision(message.content),
                                  icon: const Icon(Icons.check),
                                  label: const Text('Setujui'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

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
                            color: isUser ? AppColors.primary : Colors.white,
                            border: isUser
                                ? null
                                : Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: SelectableText(
                            message.content,
                            style: TextStyle(
                              color: isUser ? Colors.white : AppColors.ink,
                              height: 1.5,
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
          if (_showInputArea)
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
                      focusNode: _focusNode,
                      controller: _controller,
                      enabled: !_sending,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText:
                            'Misal: Gunakan bahasa yang lebih akademik...',
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
            )
          else if (_sending)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'AI sedang memproses revisi...',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
