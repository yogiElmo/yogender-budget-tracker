// Keeps the web app current. GitHub Pages lets browsers cache files for
// 10 minutes, and phones keep home-screen apps even longer, so on start the
// app asks the server which version is live and reloads itself if it's behind.

import 'package:http/http.dart' as http;
import 'dart:convert';

import 'platform/reload_stub.dart' if (dart.library.js_interop) 'platform/reload_web.dart';

/// Set at build time with `--dart-define=APP_VERSION=<commit>`; "dev" when run locally.
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

Future<void> reloadIfOutdated() async {
  if (appVersion == 'dev') return;
  try {
    final res = await http.get(Uri.parse('version.json?t=${DateTime.now().millisecondsSinceEpoch}'));
    if (res.statusCode != 200) return;
    final live = (jsonDecode(res.body) as Map<String, dynamic>)['version'] as String?;
    if (live == null || live == appVersion) return;
    // Already tried this version and still got the old one: don't loop.
    if (currentVersionParam() == live) return;
    reloadToVersion(live);
  } catch (_) {
    // Offline or blocked: keep running the version we have.
  }
}
