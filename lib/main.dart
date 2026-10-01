// Budget Tracker — entry point.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/home.dart';
import 'screens/sign_in.dart';
import 'util/app_version.dart';

// The publishable key is meant to live in the app; row-level security protects the data.
const supabaseUrl = 'https://riigbbhzyszajdjqvxmo.supabase.co';
const supabasePublishableKey = 'sb_publishable_9nA8gGXX1H0mYfA-cUd8UQ_BeiQkIkg';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabasePublishableKey);
  runApp(const BudgetApp());
  reloadIfOutdated();
}

class BudgetApp extends StatelessWidget {
  const BudgetApp({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    return MaterialApp(
      title: 'Budget',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      darkTheme: ThemeData(
          colorSchemeSeed: Colors.teal, brightness: Brightness.dark, useMaterial3: true),
      home: StreamBuilder<AuthState>(
        stream: auth.onAuthStateChange,
        builder: (context, _) => auth.currentSession == null
            ? const SignInScreen()
            : HomeScreen(onSignOut: () => auth.signOut()),
      ),
    );
  }
}
