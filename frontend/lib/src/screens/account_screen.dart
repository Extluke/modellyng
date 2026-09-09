import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/account_settings_card.dart';
import '../widgets/common_widgets.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({this.onOpenAuditLog, super.key});

  final VoidCallback? onOpenAuditLog;

  Future<void> _showPrivacy(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Privasi dokumen'),
      content: const Text(
        'PDF disimpan privat dan akses aplikasi dibatasi untuk pemilik. Teks dokumen dan pertanyaan dikirim ke Gemini untuk analisis. Pada layanan Gemini gratis, input dan output dapat digunakan untuk pengembangan produk dan ditinjau manusia. Beta ini hanya untuk dokumen publik yang boleh diproses; jangan unggah informasi pribadi atau rahasia. Server beta bergantung pada komputer pengelola yang tetap menyala.',
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Mengerti'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authRepositoryProvider).currentUser;
    final email = user?.email ?? 'Pengguna lokal';
    final metadataName = user?.userMetadata?['display_name'] as String?;
    final displayName = metadataName?.trim().isNotEmpty == true
        ? metadataName!.trim()
        : email.split('@').first;
    final initials = displayName
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PageHeading(
                title: 'Akun & penggunaan',
                subtitle:
                    'Kelola profil, kuota pemrosesan, dan keamanan dokumen.',
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: AppColors.primarySoft,
                        child: Text(
                          initials.isEmpty ? 'ML' : initials,
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            Text(email),
                          ],
                        ),
                      ),
                      OutlinedButton.icon(
                        key: const Key('sign-out-button'),
                        onPressed: () async {
                          await ref.read(authRepositoryProvider).signOut();
                          ref.invalidate(authSessionProvider);
                        },
                        icon: const Icon(Icons.logout_rounded),
                        label: const Text('Keluar'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const AccountSettingsCard(),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Paket Free Pilot',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          const StatusBadge(
                            label: 'Aktif',
                            color: AppColors.green,
                            background: AppColors.greenSoft,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Beta memakai kuota bersama: maksimal 20 permintaan analisis dan 50 pesan chat per hari (reset UTC). Kuota Gemini dapat habis lebih dahulu.',
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Sisa kuota belum ditampilkan. Aplikasi akan memberi tahu saat batas tercapai.',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.shield_outlined),
                      title: const Text('Privasi dokumen'),
                      subtitle: const Text(
                        'File tersimpan dalam bucket privat dan dilindungi Row Level Security.',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _showPrivacy(context),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.history_rounded),
                      title: const Text('Audit log'),
                      subtitle: const Text(
                        'Riwayat analisis dan keputusan reviewer akan tersimpan.',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: onOpenAuditLog,
                    ),
                    const Divider(height: 1),
                    const ListTile(
                      enabled: false,
                      leading: Icon(
                        Icons.delete_outline_rounded,
                        color: AppColors.red,
                      ),
                      title: Text('Retensi & penghapusan data'),
                      subtitle: Text(
                        'Belum tersedia pada pilot lokal. Tidak ada data yang dihapus otomatis.',
                      ),
                      trailing: StatusBadge(
                        label: 'Segera',
                        color: AppColors.muted,
                        background: AppColors.border,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
