import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/auth_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

enum AuthMode { signIn, signUp }

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  AuthMode _mode = AuthMode.signIn;
  bool _obscurePassword = true;
  bool _submitting = false;
  String? _errorMessage;
  String? _informationMessage;

  @override
  void dispose() {
    _displayNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _submitting = true;
      _errorMessage = null;
      _informationMessage = null;
    });

    try {
      final repository = ref.read(authRepositoryProvider);
      if (_mode == AuthMode.signIn) {
        await repository.signIn(
          email: _emailController.text,
          password: _passwordController.text,
        );
      } else {
        final response = await repository.signUp(
          displayName: _displayNameController.text,
          email: _emailController.text,
          password: _passwordController.text,
        );
        if (response.session == null && mounted) {
          setState(() {
            _informationMessage =
                'Akun dibuat. Buka email pengujian Anda untuk melakukan konfirmasi.';
          });
        }
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage =
              'Tidak dapat terhubung ke layanan login. Pastikan Supabase lokal masih berjalan.';
        });
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _switchMode(AuthMode mode) {
    if (_submitting) return;
    setState(() {
      _mode = mode;
      _errorMessage = null;
      _informationMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final signingIn = _mode == AuthMode.signIn;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton.filledTonal(
                      tooltip: 'Kembali',
                      onPressed: () => context.go('/welcome'),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Center(child: BrandLockup()),
                  const SizedBox(height: 28),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              signingIn
                                  ? 'Masuk ke Modellyng'
                                  : 'Buat akun pilot',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              signingIn
                                  ? 'Lanjutkan workspace riset Anda.'
                                  : 'Mulai mengelola paper dalam workspace privat.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppColors.muted),
                            ),
                            const SizedBox(height: 24),
                            SegmentedButton<AuthMode>(
                              segments: const [
                                ButtonSegment(
                                  value: AuthMode.signIn,
                                  label: Text('Masuk'),
                                  icon: Icon(Icons.login_rounded),
                                ),
                                ButtonSegment(
                                  value: AuthMode.signUp,
                                  label: Text('Daftar'),
                                  icon: Icon(Icons.person_add_alt_1_rounded),
                                ),
                              ],
                              selected: {_mode},
                              onSelectionChanged: (selection) =>
                                  _switchMode(selection.first),
                            ),
                            const SizedBox(height: 24),
                            if (!signingIn) ...[
                              TextFormField(
                                controller: _displayNameController,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.name],
                                decoration: const InputDecoration(
                                  labelText: 'Nama lengkap',
                                  prefixIcon: Icon(
                                    Icons.person_outline_rounded,
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null ||
                                      value.trim().length < 3) {
                                    return 'Masukkan nama lengkap minimal 3 karakter.';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 14),
                            ],
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.email],
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                prefixIcon: Icon(Icons.email_outlined),
                              ),
                              validator: (value) {
                                final email = value?.trim() ?? '';
                                if (!email.contains('@') ||
                                    !email.contains('.')) {
                                  return 'Masukkan alamat email yang valid.';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.done,
                              autofillHints: signingIn
                                  ? const [AutofillHints.password]
                                  : const [AutofillHints.newPassword],
                              onFieldSubmitted: (_) => _submit(),
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(
                                  Icons.lock_outline_rounded,
                                ),
                                suffixIcon: IconButton(
                                  tooltip: _obscurePassword
                                      ? 'Tampilkan password'
                                      : 'Sembunyikan password',
                                  onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword,
                                  ),
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.length < 8) {
                                  return 'Password minimal 8 karakter.';
                                }
                                return null;
                              },
                            ),
                            if (_errorMessage != null) ...[
                              const SizedBox(height: 16),
                              _MessagePanel(
                                message: _errorMessage!,
                                color: AppColors.red,
                                background: AppColors.redSoft,
                                icon: Icons.error_outline_rounded,
                              ),
                            ],
                            if (_informationMessage != null) ...[
                              const SizedBox(height: 16),
                              _MessagePanel(
                                message: _informationMessage!,
                                color: AppColors.primary,
                                background: AppColors.primarySoft,
                                icon: Icons.mark_email_read_outlined,
                              ),
                            ],
                            const SizedBox(height: 22),
                            FilledButton.icon(
                              key: const Key('auth-submit-button'),
                              onPressed: _submitting ? null : _submit,
                              icon: _submitting
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Icon(
                                      signingIn
                                          ? Icons.login_rounded
                                          : Icons.person_add_alt_1_rounded,
                                    ),
                              label: Text(signingIn ? 'Masuk' : 'Buat akun'),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Data akun dan dokumen pada tahap ini tersimpan di Supabase lokal pada komputer pengembangan.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({
    required this.message,
    required this.color,
    required this.background,
    required this.icon,
  });

  final String message;
  final Color color;
  final Color background;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: TextStyle(color: color)),
          ),
        ],
      ),
    );
  }
}
