import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/blueprint_colors.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  bool _busy = false;
  String? _message;
  bool _isError = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _message = null;
      _busy = true;
      _isError = false;
    });
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        _email.text.trim(),
      );
      setState(() {
        _message = 'Check your email for a reset link.';
      });
    } on AuthException catch (e) {
      setState(() {
        _message = e.message;
        _isError = true;
      });
    } catch (e) {
      setState(() {
        _message = e.toString();
        _isError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BlueprintColors.bg,
      appBar: AppBar(title: const Text('Forgot password')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: BlueprintColors.cream),
              decoration: InputDecoration(
                hintText: 'you@example.com',
                hintStyle: const TextStyle(color: BlueprintColors.muted),
                filled: true,
                fillColor: BlueprintColors.cardInner,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: BlueprintColors.border),
                ),
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 16),
              Text(
                _message!,
                style: TextStyle(
                  color: _isError
                      ? BlueprintColors.danger
                      : BlueprintColors.mint,
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed:
                    _busy || _email.text.trim().isEmpty ? null : _send,
                style: FilledButton.styleFrom(
                  backgroundColor: BlueprintColors.purple,
                ),
                child: _busy
                    ? const CircularProgressIndicator(color: BlueprintColors.cream)
                    : const Text('Send reset link'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
