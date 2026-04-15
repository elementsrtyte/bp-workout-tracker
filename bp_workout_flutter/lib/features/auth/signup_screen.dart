import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/blueprint_colors.dart';
import 'auth_constants.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    final p = _password.text;
    return _email.text.trim().isNotEmpty &&
        p.length >= 8 &&
        p == _confirm.text;
  }

  Future<void> _signUp() async {
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      await Supabase.instance.client.auth.signUp(
        email: _email.text.trim(),
        password: _password.text,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AuthConstants.supabaseSavedEmailKey, _email.text.trim());
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted && _error == null) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BlueprintColors.bg,
      appBar: AppBar(title: const Text('Create account')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Use at least 8 characters. You’ll use this email to sign in on every device.',
              style: TextStyle(color: BlueprintColors.mutedLight),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              style: const TextStyle(color: BlueprintColors.cream),
              decoration: _decoration('Email'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              style: const TextStyle(color: BlueprintColors.cream),
              decoration: _decoration('Password (8+ characters)'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirm,
              obscureText: true,
              style: const TextStyle(color: BlueprintColors.cream),
              decoration: _decoration('Confirm password'),
              onChanged: (_) => setState(() {}),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: BlueprintColors.danger),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy || !_canSubmit ? null : _signUp,
                style: FilledButton.styleFrom(
                  backgroundColor: BlueprintColors.purple,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _busy
                    ? const CircularProgressIndicator(color: BlueprintColors.cream)
                    : const Text('Create account'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _decoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: BlueprintColors.muted),
        filled: true,
        fillColor: BlueprintColors.cardInner,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: BlueprintColors.border),
        ),
      );
}
