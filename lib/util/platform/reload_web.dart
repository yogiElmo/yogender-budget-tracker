import 'package:web/web.dart' as web;

/// The `v` query parameter the page was opened with, if any.
String? currentVersionParam() => Uri.parse(web.window.location.href).queryParameters['v'];

/// Opens the app at a URL the browser hasn't cached yet, so it loads the new version.
void reloadToVersion(String version) {
  final uri = Uri.parse(web.window.location.href);
  final next = uri.replace(queryParameters: {...uri.queryParameters, 'v': version}, fragment: '');
  web.window.location.replace(next.toString());
}
