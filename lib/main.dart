// lib/main.dart — Budget Tracker starter
// Proves the chain works: sign in -> seed defaults -> read your budget.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const supabaseUrl = 'https://riigbbhzyszajdjqvxmo.supabase.co';
const supabasePublishableKey = 'sb_publishable_9nA8gGXX1H0mYfA-cUd8UQ_BeiQkIkg';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabasePublishableKey);
  runApp(const BudgetApp());
}

final supabase = Supabase.instance.client;

class BudgetApp extends StatelessWidget {
  const BudgetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Budget',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: StreamBuilder<AuthState>(
        stream: supabase.auth.onAuthStateChange,
        builder: (context, _) =>
            supabase.auth.currentSession == null ? const SignInScreen() : const HomeScreen(),
      ),
    );
  }
}

// ---------------------------------------------------------------- sign in

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

  Future<void> _go({required bool signUp}) async {
    setState(() { _busy = true; _message = null; });
    try {
      if (signUp) {
        await supabase.auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          // Confirmation email links back to wherever the app is running.
          emailRedirectTo: kIsWeb ? Uri.base.removeFragment().toString() : null,
        );
        if (supabase.auth.currentSession == null) {
          _message = 'Check your email to confirm, then sign in.';
        }
      } else {
        await supabase.auth.signInWithPassword(email: _email.text.trim(), password: _password.text);
      }
    } on AuthException catch (e) {
      _message = e.message;
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
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Budget', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 24),
              TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress),
              TextField(controller: _password, decoration: const InputDecoration(labelText: 'Password'),
                  obscureText: true),
              const SizedBox(height: 24),
              FilledButton(onPressed: _busy ? null : () => _go(signUp: false), child: const Text('Sign in')),
              TextButton(onPressed: _busy ? null : () => _go(signUp: true), child: const Text('Create account')),
              if (_message != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_message!)),
            ]),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- home (test)

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final Future<Map<String, dynamic>> _data = _load();

  Future<Map<String, dynamic>> _load() async {
    await supabase.rpc('seed_defaults'); // first sign-in only; does nothing afterwards
    final config = await supabase
        .from('budget_config')
        .select('weekly_amount_cents, budget_split(percent, category_group(name, sort_order))')
        .isFilter('deleted_at', null)
        .order('effective_from', ascending: false)
        .limit(1)
        .single();
    final accounts = await supabase.from('account').select('id').isFilter('deleted_at', null);
    final jars = await supabase.from('jar').select('name').isFilter('deleted_at', null);
    return {'config': config, 'accounts': accounts.length, 'jars': jars};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('This week'), actions: [
        IconButton(icon: const Icon(Icons.logout), onPressed: () => supabase.auth.signOut()),
      ]),
      body: FutureBuilder(
        future: _data,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final config = snap.data!['config'] as Map<String, dynamic>;
          final weekly = (config['weekly_amount_cents'] as int) / 100;
          final splits = (config['budget_split'] as List)
            ..sort((a, b) => (a['category_group']['sort_order'] as int)
                .compareTo(b['category_group']['sort_order'] as int));
          final jars = (snap.data!['jars'] as List).map((j) => j['name']).join(', ');
          return ListView(padding: const EdgeInsets.all(24), children: [
            Text('\$${weekly.toStringAsFixed(0)} / week',
                style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: 16),
            for (final s in splits)
              ListTile(
                title: Text(s['category_group']['name']),
                trailing: Text('${s['percent']}%  ·  '
                    '\$${(weekly * (s['percent'] as num) / 100).toStringAsFixed(0)}'),
              ),
            const Divider(),
            ListTile(title: const Text('Accounts'), trailing: Text('${snap.data!['accounts']}')),
            ListTile(title: const Text('Jars'), subtitle: Text(jars)),
          ]);
        },
      ),
    );
  }
}
