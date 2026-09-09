import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/account_settings_repository.dart';

class AccountSettingsCard extends ConsumerStatefulWidget {
  const AccountSettingsCard({super.key});
  @override
  ConsumerState<AccountSettingsCard> createState() =>
      _AccountSettingsCardState();
}

class _AccountSettingsCardState extends ConsumerState<AccountSettingsCard> {
  bool _open = false;
  bool _loaded = false;
  String _style = 'apa7';
  bool _showConfidence = true;

  @override
  Widget build(BuildContext context) {
    final settings = _open ? ref.watch(accountSettingsProvider) : null;
    return Card(
      child: ExpansionTile(
        initiallyExpanded: false,
        onExpansionChanged: (value) => setState(() => _open = value),
        leading: const Icon(Icons.tune_rounded),
        title: const Text('Settings & personalisasi'),
        subtitle: const Text('Gaya sitasi, bahasa, dan tampilan confidence'),
        children: [
          if (settings != null)
            settings.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
              error: (error, _) => const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Pengaturan belum dapat dimuat.'),
              ),
              data: (value) {
                if (!_loaded) {
                  _loaded = true;
                  _style = value.citationStyle;
                  _showConfidence = value.showConfidence;
                }
                return _form(context);
              },
            ),
        ],
      ),
    );
  }

  Widget _form(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _style,
          decoration: const InputDecoration(labelText: 'Gaya daftar pustaka'),
          items: const [
            DropdownMenuItem(value: 'apa7', child: Text('APA 7')),
            DropdownMenuItem(value: 'ieee', child: Text('IEEE')),
            DropdownMenuItem(value: 'harvard', child: Text('Harvard')),
            DropdownMenuItem(value: 'vancouver', child: Text('Vancouver')),
            DropdownMenuItem(value: 'chicago', child: Text('Chicago')),
          ],
          onChanged: (value) => setState(() => _style = value ?? 'apa7'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Tampilkan confidence AI'),
          value: _showConfidence,
          onChanged: (value) => setState(() => _showConfidence = value),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: () async {
              await ref
                  .read(accountSettingsRepositoryProvider)
                  .save(
                    AccountSettings(
                      citationStyle: _style,
                      locale: 'id',
                      showConfidence: _showConfidence,
                    ),
                  );
              ref.invalidate(accountSettingsProvider);
              if (context.mounted)
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Pengaturan disimpan.')),
                );
            },
            icon: const Icon(Icons.save_outlined),
            label: const Text('Simpan'),
          ),
        ),
      ],
    ),
  );
}
