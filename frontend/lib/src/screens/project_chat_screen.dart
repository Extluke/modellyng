import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/paper_result_repository.dart';
import '../data/project_chat_repository.dart';
import '../models/research_models.dart';
import '../theme/app_theme.dart';
import 'paper_result_screen.dart';

class ProjectChatScreen extends ConsumerStatefulWidget {
  const ProjectChatScreen({required this.project, super.key});
  final ResearchProject project;

  @override
  ConsumerState<ProjectChatScreen> createState() => _ProjectChatScreenState();
}

class _ProjectChatScreenState extends ConsumerState<ProjectChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _messages = <_ChatMessage>[];
  bool _sending = false;
  bool _loadingHistory = true;
  String? _historyError;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadHistory);
  }

  Future<void> _loadHistory() async {
    if (mounted) {
      setState(() {
        _loadingHistory = true;
        _historyError = null;
      });
    }
    try {
      final history = await ref
          .read(projectChatRepositoryProvider)
          .getHistory(widget.project.id);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(history.map(_ChatMessage.stored));
        _loadingHistory = false;
      });
      _scrollToEnd();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingHistory = false;
        _historyError = ProjectChatRepository.readableError(error);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send([String? suggestedQuestion]) async {
    final question = (suggestedQuestion ?? _controller.text).trim();
    if (question.length < 2 || _sending) return;
    final history = _messages
        .map(
          (message) => ChatHistoryMessage(
            role: message.isUser ? 'user' : 'assistant',
            content: message.content,
          ),
        )
        .toList(growable: false);
    setState(() {
      _messages.add(_ChatMessage.user(question));
      _sending = true;
      _controller.clear();
    });
    _scrollToEnd();
    try {
      final answer = await ref
          .read(projectChatRepositoryProvider)
          .ask(
            projectId: widget.project.id,
            question: question,
            history: history.length > 10
                ? history.sublist(history.length - 10)
                : history,
          );
      if (!mounted) return;
      setState(() => _messages.add(_ChatMessage.assistant(answer)));
      _warmEvidencePdfs(answer.sources);
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _messages.add(
          _ChatMessage.error(ProjectChatRepository.readableError(error)),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _scrollToEnd();
      }
    }
  }

  void _warmEvidencePdfs(List<ProjectChatSource> sources) {
    final paperIds = <String>{};
    for (final source in sources) {
      if (!paperIds.add(source.paperId)) continue;
      unawaited(
        ref
            .read(
              paperPdfProvider((
                projectId: widget.project.id,
                paperId: source.paperId,
              )).future,
            )
            .then<void>((_) {}, onError: (_) {}),
      );
      // Bound speculative memory/network use for answers citing many papers.
      if (paperIds.length >= 2) break;
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _openSource(ProjectChatSource source) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PaperResultScreen(
          projectId: widget.project.id,
          paperId: source.paperId,
          initialPage: source.pageNumber ?? 1,
          initialHighlightText: source.quote,
          initialBlockId: source.blockId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Diskusi dengan AI'),
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
          child: Text(
            'Konteks: ${widget.project.title}. Jawaban hanya memakai teks PDF '
            'yang sudah selesai diekstrak dan menyertakan sumber halaman.',
          ),
        ),
        Expanded(
          child: _loadingHistory
              ? const Center(child: CircularProgressIndicator())
              : _historyError != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_historyError!),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: _loadHistory,
                        child: const Text('Coba lagi'),
                      ),
                    ],
                  ),
                )
              : _messages.isEmpty
              ? _StarterPrompts(onPrompt: _send)
              : ListView.separated(
                  key: const Key('project-chat-messages'),
                  controller: _scrollController,
                  padding: const EdgeInsets.all(20),
                  itemCount: _messages.length + (_sending ? 1 : 0),
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    if (index == _messages.length) {
                      return const _ThinkingBubble();
                    }
                    return _MessageBubble(
                      message: _messages[index],
                      onOpenSource: _openSource,
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('project-chat-input'),
                    controller: _controller,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      hintText: 'Tanyakan isi PDF dalam proyek ini...',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filled(
                  key: const Key('send-chat-button'),
                  tooltip: 'Kirim pertanyaan',
                  onPressed: _sending || _loadingHistory ? null : _send,
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _StarterPrompts extends StatelessWidget {
  const _StarterPrompts({required this.onPrompt});
  final ValueChanged<String> onPrompt;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Column(
          children: [
            const Icon(
              Icons.forum_outlined,
              size: 48,
              color: AppColors.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'Diskusikan hasil proyek',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Pilih contoh pertanyaan atau tulis pertanyaan sendiri. Chatbot '
              'menolak menjawab jika informasi tidak ditemukan dalam PDF.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            for (final prompt in const [
              'Apa perbedaan metodologi antar paper?',
              'Temuan mana yang paling konsisten?',
              'Kandidat research gap apa yang didukung evidence?',
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton.icon(
                  onPressed: () => onPrompt(prompt),
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: Text(prompt),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.onOpenSource});
  final _ChatMessage message;
  final ValueChanged<ProjectChatSource> onOpenSource;

  @override
  Widget build(BuildContext context) => Align(
    alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: message.isUser
              ? AppColors.primary
              : message.isError
              ? AppColors.redSoft
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: message.isUser ? null : Border.all(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message.content,
                style: TextStyle(
                  color: message.isUser ? Colors.white : AppColors.ink,
                ),
              ),
              if (message.sources.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(),
                const Text(
                  'Evidence yang dipakai',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                ),
                const SizedBox(height: 5),
                for (final source in message.sources)
                  TextButton.icon(
                    key: Key('chat-source-${source.sourceId}'),
                    onPressed: () => onOpenSource(source),
                    icon: const Icon(Icons.link_rounded, size: 17),
                    label: Text(
                      '${source.sourceId} · ${source.paperTitle}'
                      '${source.pageNumber == null ? '' : ' · hal. ${source.pageNumber}'}',
                    ),
                  ),
              ],
              if (message.reviewNotice?.isNotEmpty == true) ...[
                const SizedBox(height: 8),
                Text(
                  message.reviewNotice!,
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();
  @override
  Widget build(BuildContext context) => const Align(
    alignment: Alignment.centerLeft,
    child: Card(
      child: Padding(
        padding: EdgeInsets.all(14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text('Menyusun jawaban dari evidence...'),
          ],
        ),
      ),
    ),
  );
}

class _ChatMessage {
  const _ChatMessage({
    required this.isUser,
    required this.content,
    required this.sources,
    this.reviewNotice,
    this.isError = false,
  });

  factory _ChatMessage.user(String content) =>
      _ChatMessage(isUser: true, content: content, sources: const []);

  factory _ChatMessage.assistant(ProjectChatAnswer answer) => _ChatMessage(
    isUser: false,
    content: answer.answer,
    sources: answer.sources,
    reviewNotice: answer.reviewNotice,
  );

  factory _ChatMessage.stored(StoredProjectChatMessage message) => _ChatMessage(
    isUser: message.role == 'user',
    content: message.content,
    sources: message.sources,
    reviewNotice: message.reviewNotice,
  );

  factory _ChatMessage.error(String content) => _ChatMessage(
    isUser: false,
    content: content,
    sources: const [],
    isError: true,
  );

  final bool isUser;
  final String content;
  final List<ProjectChatSource> sources;
  final String? reviewNotice;
  final bool isError;
}
