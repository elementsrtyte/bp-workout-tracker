import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';
import '../../theme/blueprint_colors.dart';
import 'auth_constants.dart';
import 'forgot_password_screen.dart';
import 'signup_screen.dart';

/// Mirrors `AuthLoginView` (email/password, saved email).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSavedEmail();
  }

  Future<void> _loadSavedEmail() async {
    final p = await SharedPreferences.getInstance();
    _email.text = p.getString(AuthConstants.supabaseSavedEmailKey) ?? '';
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _email.text.trim().isNotEmpty && _password.text.length >= 8;

  Future<void> _signIn() async {
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
      final p = await SharedPreferences.getInstance();
      await p.setString(AuthConstants.supabaseSavedEmailKey, _email.text.trim());
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BlueprintColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'BLUEPRINT',
                style: TextStyle(
                  color: BlueprintColors.purple,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.6,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Welcome back',
                style: TextStyle(
                  color: BlueprintColors.cream,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Sign in to sync workouts and programs, and to use AI import and suggestions.',
                style: TextStyle(
                  color: BlueprintColors.mutedLight,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 24),
              _fieldLabel('Email'),
              _field(_email, hint: 'you@example.com', obscure: false),
              const SizedBox(height: 16),
              _fieldLabel('Password'),
              _field(_password, hint: 'Password', obscure: true),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: BlueprintColors.danger,
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy || !_canSubmit ? null : () => _signIn(),
                  style: FilledButton.styleFrom(
                    backgroundColor: BlueprintColors.purple,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _busy
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: BlueprintColors.cream,
                          ),
                        )
                      : const Text('Sign in', style: TextStyle(fontSize: 17)),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SignUpScreen(),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: BlueprintColors.lavender,
                  side: const BorderSide(color: BlueprintColors.border),
                  minimumSize: const Size(double.infinity, 48),
                ),
                icon: const Icon(Icons.person_add_outlined),
                label: const Text('Create account'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ForgotPasswordScreen(),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: BlueprintColors.muted,
                  side: const BorderSide(color: BlueprintColors.border),
                  minimumSize: const Size(double.infinity, 48),
                ),
                icon: const Icon(Icons.key_outlined),
                label: const Text('Forgot password?'),
              ),
              const SizedBox(height: 20),
              _configCallouts(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _configCallouts() {
    final needSupabase = !Env.isSupabaseConfigured;
    final needApi = !Env.isApiConfigured;
    if (!needSupabase && !needApi) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (needSupabase)
          const Text(
            'Sign-in requires SUPABASE_URL and SUPABASE_ANON_KEY (dart-define or environment).',
            style: TextStyle(color: BlueprintColors.amber, fontSize: 12),
          ),
        if (needApi) ...[
          if (needSupabase) const SizedBox(height: 8),
          const Text(
            'Catalog refresh and workout sync need BLUEPRINT_API_URL pointing at your Blueprint API.',
            style: TextStyle(color: BlueprintColors.amber, fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _fieldLabel(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          t,
          style: const TextStyle(
            color: BlueprintColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  Widget _field(
    TextEditingController c, {
    required String hint,
    required bool obscure,
  }) {
    return TextField(
      controller: c,
      obscureText: obscure,
      autocorrect: false,
      style: const TextStyle(color: BlueprintColors.cream),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: BlueprintColors.muted),
        filled: true,
        fillColor: BlueprintColors.cardInner,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: BlueprintColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: BlueprintColors.border),
        ),
      ),
      onChanged: (_) => setState(() {}),
    );
  }
}
