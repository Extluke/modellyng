import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
                      const CircleAvatar(
                        radius: 30,
                        backgroundColor: AppColors.primarySoft,
                        child: Text(
                          'AS',
                          style: TextStyle(
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
                              'Aditya Saputra',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const Text('aditya@kampus.ac.id'),
                          ],
                        ),
                      ),
                      OutlinedButton(
                        onPressed: () {},
                        child: const Text('Edit profil'),
                      ),
                    ],
                  ),
                ),
              ),
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
                              'Paket Student Pilot',
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
                        'Kuota dihitung berdasarkan halaman yang diproses agar biaya AI transparan.',
                      ),
                      const SizedBox(height: 18),
                      const Row(
                        children: [
                          Expanded(child: Text('186 dari 300 halaman')),
                          Text(
                            '62%',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const LinearProgressIndicator(
                        value: 0.62,
                        minHeight: 8,
                        borderRadius: BorderRadius.all(Radius.circular(99)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.shield_outlined),
                      title: Text('Privasi dokumen'),
                      subtitle: Text(
                        'File tersimpan dalam bucket privat dan hanya dapat diakses oleh anggota proyek.',
                      ),
                      trailing: Icon(Icons.chevron_right_rounded),
                    ),
                    Divider(height: 1),
                    ListTile(
                      leading: Icon(Icons.history_rounded),
                      title: Text('Audit log'),
                      subtitle: Text(
                        'Lihat riwayat analisis dan keputusan reviewer.',
                      ),
                      trailing: Icon(Icons.chevron_right_rounded),
                    ),
                    Divider(height: 1),
                    ListTile(
                      leading: Icon(
                        Icons.delete_outline_rounded,
                        color: AppColors.red,
                      ),
                      title: Text('Retensi & penghapusan data'),
                      subtitle: Text(
                        'Kelola berapa lama paper dan hasil analisis disimpan.',
                      ),
                      trailing: Icon(Icons.chevron_right_rounded),
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
