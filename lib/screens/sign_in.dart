import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _message;

  SupabaseClient get _db => Supabase.instance.client;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _go({required bool signUp}) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (signUp) {
        await _db.auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          // Confirmation email links back to wherever the app is running.
          emailRedirectTo: kIsWeb ? Uri.base.removeFragment().toString() : null,
        );
        if (_db.auth.currentSession == null) {
          _message = 'Check your email to confirm, then sign in.';
        }
      } else {
        await _db.auth.signInWithPassword(email: _email.text.trim(), password: _password.text);
      }
    } on AuthException catch (e) {
      _message = e.message;
    } catch (_) {
      _message = 'Couldn\'t reach the server — check your connection.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: AutofillGroup(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Budget', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 24),
                TextField(
                  controller: _email,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                ),
                TextField(
                  controller: _password,
                  decoration: const InputDecoration(labelText: 'Password'),
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  onSubmitted: (_) => _go(signUp: false),
                ),
                const SizedBox(height: 24),
                FilledButton(
                    onPressed: _busy ? null : () => _go(signUp: false),
                    child: const Text('Sign in')),
                TextButton(
                    onPressed: _busy ? null : () => _go(signUp: true),
                    child: const Text('Create account')),
                if (_message != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_message!, textAlign: TextAlign.center)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
