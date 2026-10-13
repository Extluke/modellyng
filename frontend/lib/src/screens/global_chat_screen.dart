import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/global_chat_cache_service.dart';
import '../data/global_chat_repository.dart';
import '../data/paper_repository.dart';
import '../data/project_repository.dart';
import '../models/research_models.dart';
import '../theme/app_theme.dart';

class _ChatMessage {
  const _ChatMessage({
    required this.role,
    required this.content,
    this.timestamp,
    this.referencedProject,
    this.projectId,
    this.referencedPaper,
    this.paperId,
  });

  final String role;
  final String content;
  final DateTime? timestamp;
  final String? referencedProject;
  final String? projectId;
  final String? referencedPaper;
  final String? paperId;
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

  bool _showProjectPopup = false;
  String _projectQuery = '';
  int _atSymbolIndex = -1;
  String? _selectedProjectId;
  String? _selectedProjectTitle;

  bool _showPaperPopup = false;
  String _paperQuery = '';
  int _slashSymbolIndex = -1;
  String? _selectedPaperId;
  String? _selectedPaperTitle;

  bool get _hasUserPrompt => _messages.any((m) => m.role == 'user');

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _loadHistory();
  }

  void _onTextChanged() {
    final text = _controller.text;
    final selection = _controller.selection;
    final cursor = selection.baseOffset;

    if (cursor < 0 || text.isEmpty) {
      if (_showProjectPopup || _showPaperPopup) {
        setState(() {
          _showProjectPopup = false;
          _projectQuery = '';
          _atSymbolIndex = -1;
          _showPaperPopup = false;
          _paperQuery = '';
          _slashSymbolIndex = -1;
        });
      }
      return;
    }

    if (_selectedProjectId != null && !text.contains('@')) {
      setState(() {
        _selectedProjectId = null;
        _selectedProjectTitle = null;
        _selectedPaperId = null;
        _selectedPaperTitle = null;
      });
    }

    if (_selectedPaperId != null && !text.contains('/')) {
      setState(() {
        _selectedPaperId = null;
        _selectedPaperTitle = null;
      });
    }

    final textBeforeCursor = text.substring(0, cursor);
    final lastAtIndex = textBeforeCursor.lastIndexOf('@');
    final lastSlashIndex = textBeforeCursor.lastIndexOf('/');

    if (lastSlashIndex > lastAtIndex && lastSlashIndex != -1) {
      final isAtStartOrAfterSpace =
          lastSlashIndex == 0 ||
          textBeforeCursor[lastSlashIndex - 1] == ' ' ||
          textBeforeCursor[lastSlashIndex - 1] == '\n';

      final queryCandidate = textBeforeCursor.substring(lastSlashIndex + 1);
      final hasSpaceInQuery =
          queryCandidate.contains(' ') || queryCandidate.contains('\n');

      if (isAtStartOrAfterSpace && !hasSpaceInQuery) {
        if (!_showPaperPopup ||
            _paperQuery != queryCandidate ||
            _slashSymbolIndex != lastSlashIndex ||
            _showProjectPopup) {
          setState(() {
            _showProjectPopup = false;
            _showPaperPopup = true;
            _paperQuery = queryCandidate;
            _slashSymbolIndex = lastSlashIndex;
          });
        }
        return;
      }
    } else if (lastAtIndex != -1) {
      final isAtStartOrAfterSpace =
          lastAtIndex == 0 ||
          textBeforeCursor[lastAtIndex - 1] == ' ' ||
          textBeforeCursor[lastAtIndex - 1] == '\n';

      final queryCandidate = textBeforeCursor.substring(lastAtIndex + 1);
      final hasSpaceInQuery =
          queryCandidate.contains(' ') || queryCandidate.contains('\n');

      if (isAtStartOrAfterSpace && !hasSpaceInQuery) {
        if (!_showProjectPopup ||
            _projectQuery != queryCandidate ||
            _atSymbolIndex != lastAtIndex ||
            _showPaperPopup) {
          setState(() {
            _showPaperPopup = false;
            _showProjectPopup = true;
            _projectQuery = queryCandidate;
            _atSymbolIndex = lastAtIndex;
          });
        }
        return;
      }
    }

    if (_showProjectPopup || _showPaperPopup) {
      setState(() {
        _showProjectPopup = false;
        _projectQuery = '';
        _atSymbolIndex = -1;
        _showPaperPopup = false;
        _paperQuery = '';
        _slashSymbolIndex = -1;
      });
    }
  }

  void _selectProject(ResearchProject project) {
    final text = _controller.text;
    final atIndex = _atSymbolIndex;

    String newText;
    int newCursorPosition;

    if (atIndex != -1 && atIndex <= text.length) {
      final beforeAt = text.substring(0, atIndex);
      final cursor = _controller.selection.baseOffset;
      final afterCursor = (cursor >= atIndex && cursor <= text.length)
          ? text.substring(cursor)
          : '';
      final mention = '@${project.title} ';
      newText = '$beforeAt$mention$afterCursor';
      newCursorPosition = (beforeAt + mention).length;
    } else {
      newText = '@${project.title} ';
      newCursorPosition = newText.length;
    }

    _controller.text = newText;
    _controller.selection = TextSelection.collapsed(offset: newCursorPosition);

    setState(() {
      _selectedProjectId = project.id;
      _selectedProjectTitle = project.title;
      _showProjectPopup = false;
      _projectQuery = '';
      _atSymbolIndex = -1;
      _selectedPaperId = null;
      _selectedPaperTitle = null;
    });
  }

  void _selectPaper(ProjectPaper paper) {
    final text = _controller.text;
    final slashIndex = _slashSymbolIndex;
    final paperTitle = (paper.title != null && paper.title!.trim().isNotEmpty)
        ? paper.title!.trim()
        : paper.originalFilename;

    String newText;
    int newCursorPosition;

    if (slashIndex != -1 && slashIndex <= text.length) {
      final beforeSlash = text.substring(0, slashIndex);
      final cursor = _controller.selection.baseOffset;
      final afterCursor = (cursor >= slashIndex && cursor <= text.length)
          ? text.substring(cursor)
          : '';
      final mention = '/$paperTitle ';
      newText = '$beforeSlash$mention$afterCursor';
      newCursorPosition = (beforeSlash + mention).length;
    } else {
      newText = '$text/$paperTitle ';
      newCursorPosition = newText.length;
    }

    _controller.text = newText;
    _controller.selection = TextSelection.collapsed(offset: newCursorPosition);

    setState(() {
      _selectedPaperId = paper.id;
      _selectedPaperTitle = paperTitle;
      _showPaperPopup = false;
      _paperQuery = '';
      _slashSymbolIndex = -1;
    });
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
                referencedProject: m.referencedProject,
                projectId: m.projectId,
                referencedPaper: m.referencedPaper,
                paperId: m.paperId,
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
            referencedProject: m.referencedProject,
            projectId: m.projectId,
            referencedPaper: m.referencedPaper,
            paperId: m.paperId,
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
    _controller.removeListener(_onTextChanged);
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

    final linkedProjectId = _selectedProjectId;
    final linkedProjectTitle = _selectedProjectTitle;
    final linkedPaperId = _selectedPaperId;
    final linkedPaperTitle = _selectedPaperTitle;

    final now = DateTime.now();
    final userMessage = _ChatMessage(
      role: 'user',
      content: text,
      timestamp: now,
      referencedProject: linkedProjectTitle,
      projectId: linkedProjectId,
      referencedPaper: linkedPaperTitle,
      paperId: linkedPaperId,
    );
    setState(() {
      _messages.add(userMessage);
      _sending = true;
      _controller.clear();
      _showProjectPopup = false;
      _projectQuery = '';
      _atSymbolIndex = -1;
      _showPaperPopup = false;
      _paperQuery = '';
      _slashSymbolIndex = -1;
      _selectedProjectId = null;
      _selectedProjectTitle = null;
      _selectedPaperId = null;
      _selectedPaperTitle = null;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    _saveToCache();

    try {
      final history = buildChatHistory(
        _messages
            .where((m) => m != userMessage)
            .map((m) => GlobalChatMessage(role: m.role, content: m.content)),
      );

      final response = await ref
          .read(globalChatRepositoryProvider)
          .sendQuestion(
            text,
            history,
            projectId: linkedProjectId,
            paperId: linkedPaperId,
          );

      if (!mounted) return;
      setState(() {
        _messages.add(
          _ChatMessage(
            role: 'assistant',
            content: response.answer,
            timestamp: DateTime.now(),
            referencedProject: response.referencedProject ?? linkedProjectTitle,
            projectId: linkedProjectId,
            referencedPaper: response.referencedPaper ?? linkedPaperTitle,
            paperId: linkedPaperId,
          ),
        );
      });
      _saveToCache();
    } catch (error) {
      if (!mounted) return;
      // Pertanyaan yang tidak terjawab dilepas dari percakapan dan dikembalikan
      // ke kolom ketik: tidak mengotori riwayat, tidak ikut tersimpan 24 jam,
      // dan bisa dikirim ulang tanpa mengetik lagi.
      final restoreDraft = _controller.text.isEmpty;
      setState(() {
        _messages.remove(userMessage);
        if (restoreDraft) {
          _selectedProjectId = linkedProjectId;
          _selectedProjectTitle = linkedProjectTitle;
          _selectedPaperId = linkedPaperId;
          _selectedPaperTitle = linkedPaperTitle;
        }
      });
      if (restoreDraft) {
        // Di luar setState: mengubah teks memicu listener yang memanggil setState.
        _controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
      _saveToCache();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(chatErrorMessage(error)),
          backgroundColor: AppColors.red,
          // Melayang di atas baris input agar tombol kirim tetap bisa diketuk
          // untuk mencoba lagi selama pesan tampil.
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 104),
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

  Widget _buildLinkedProjectBadge() {
    return Container(
      key: const Key('linked-project-badge'),
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.link_rounded,
            size: 16,
            color: AppColors.primaryDark,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              children: [
                Text(
                  'Proyek: ${_selectedProjectTitle ?? ""}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (_selectedPaperTitle != null) ...[
                  const Text(
                    '•',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  const Icon(
                    Icons.picture_as_pdf_rounded,
                    size: 13,
                    color: AppColors.primaryDark,
                  ),
                  Text(
                    'PDF: $_selectedPaperTitle',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          InkWell(
            key: const Key('remove-linked-project-button'),
            onTap: () {
              setState(() {
                _selectedProjectId = null;
                _selectedProjectTitle = null;
                _selectedPaperId = null;
                _selectedPaperTitle = null;
              });
            },
            child: const Icon(
              Icons.close_rounded,
              size: 16,
              color: AppColors.primaryDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectMentionPopup(
    AsyncValue<List<ResearchProject>> projectsAsync,
  ) {
    return Container(
      key: const Key('project-mention-popup'),
      constraints: const BoxConstraints(maxHeight: 220),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                color: AppColors.canvas,
                borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.folder_open_rounded,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Pilih Proyek untuk Dijadikan Referensi',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: projectsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
                error: (err, _) => Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Gagal memuat proyek: $err',
                    style: const TextStyle(fontSize: 12, color: AppColors.red),
                  ),
                ),
                data: (projects) {
                  final query = _projectQuery.trim().toLowerCase();
                  final filtered = query.isEmpty
                      ? projects
                      : projects
                            .where((p) => p.title.toLowerCase().contains(query))
                            .toList();

                  if (filtered.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Tidak ada proyek yang sesuai.',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: AppColors.border),
                    itemBuilder: (context, index) {
                      final project = filtered[index];
                      return ListTile(
                        dense: true,
                        key: Key('project-mention-option-${project.id}'),
                        leading: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.primarySoft,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(
                            Icons.library_books_rounded,
                            size: 16,
                            color: AppColors.primary,
                          ),
                        ),
                        title: Text(
                          project.title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: project.description.isNotEmpty
                            ? Text(
                                project.description,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.muted,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              )
                            : null,
                        onTap: () => _selectProject(project),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaperMentionPopup() {
    if (_selectedProjectId == null) {
      return Container(
        key: const Key('paper-mention-popup-no-project'),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 10,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.orangeSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: AppColors.orange,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Pilih proyek menggunakan @ terlebih dahulu sebelum memilih dokumen PDF (/).',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final papersAsync = ref.watch(
      projectPapersProvider((
        userId: widget.userId,
        projectId: _selectedProjectId!,
      )),
    );

    return Container(
      key: const Key('paper-mention-popup'),
      constraints: const BoxConstraints(maxHeight: 220),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                color: AppColors.canvas,
                borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.picture_as_pdf_rounded,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Pilih PDF dari: ${_selectedProjectTitle ?? "Proyek"}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: papersAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
                error: (err, _) => Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Gagal memuat dokumen: $err',
                    style: const TextStyle(fontSize: 12, color: AppColors.red),
                  ),
                ),
                data: (papers) {
                  final query = _paperQuery.trim().toLowerCase();
                  final filtered = query.isEmpty
                      ? papers
                      : papers.where((p) {
                          final title = (p.title ?? '').toLowerCase();
                          final filename = p.originalFilename.toLowerCase();
                          return title.contains(query) ||
                              filename.contains(query);
                        }).toList();

                  if (filtered.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          papers.isEmpty
                              ? 'Belum ada PDF yang diunggah/diekstraksi di proyek ini.'
                              : 'Tidak ada PDF yang sesuai pencarian.',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: AppColors.border),
                    itemBuilder: (context, index) {
                      final paper = filtered[index];
                      final displayTitle =
                          (paper.title != null &&
                              paper.title!.trim().isNotEmpty)
                          ? paper.title!.trim()
                          : paper.originalFilename;

                      return ListTile(
                        dense: true,
                        key: Key('paper-mention-option-${paper.id}'),
                        leading: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.primarySoft,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(
                            Icons.picture_as_pdf_rounded,
                            size: 16,
                            color: AppColors.primary,
                          ),
                        ),
                        title: Text(
                          displayTitle,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          paper.originalFilename,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.muted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _selectPaper(paper),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final projectsAsync = ref.watch(projectsProvider(widget.userId));

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
                              child: Column(
                                crossAxisAlignment: isUser
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  if (message.referencedProject != null ||
                                      message.referencedPaper != null) ...[
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      alignment: isUser
                                          ? WrapAlignment.end
                                          : WrapAlignment.start,
                                      children: [
                                        if (message.referencedProject != null)
                                          Container(
                                            margin: const EdgeInsets.only(
                                              bottom: 6,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isUser
                                                  ? AppColors.primaryDark
                                                  : AppColors.primarySoft,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: isUser
                                                    ? AppColors.primaryDark
                                                    : AppColors.primary
                                                          .withValues(
                                                            alpha: 0.2,
                                                          ),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.folder_open_rounded,
                                                  size: 12,
                                                  color: isUser
                                                      ? Colors.white
                                                      : AppColors.primaryDark,
                                                ),
                                                const SizedBox(width: 4),
                                                Flexible(
                                                  child: Text(
                                                    'Proyek: ${message.referencedProject}',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: isUser
                                                          ? Colors.white
                                                          : AppColors
                                                                .primaryDark,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        if (message.referencedPaper != null)
                                          Container(
                                            margin: const EdgeInsets.only(
                                              bottom: 6,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isUser
                                                  ? const Color(0xFF0D9488)
                                                  : AppColors.blueSoft,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: isUser
                                                    ? const Color(0xFF0D9488)
                                                    : AppColors.blue.withValues(
                                                        alpha: 0.2,
                                                      ),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.picture_as_pdf_rounded,
                                                  size: 12,
                                                  color: isUser
                                                      ? Colors.white
                                                      : AppColors.blue,
                                                ),
                                                const SizedBox(width: 4),
                                                Flexible(
                                                  child: Text(
                                                    'PDF: ${message.referencedPaper}',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: isUser
                                                          ? Colors.white
                                                          : AppColors.blue,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                  Container(
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
                                ],
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
          if (_showProjectPopup) _buildProjectMentionPopup(projectsAsync),
          if (_showPaperPopup) _buildPaperMentionPopup(),
          if (!_showProjectPopup &&
              !_showPaperPopup &&
              _selectedProjectId != null)
            _buildLinkedProjectBadge(),
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
                      hintText: '@ /',
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
