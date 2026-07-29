import 'package:cookie_jar/cookie_jar.dart';
import 'package:path_provider/path_provider.dart';

/// Creates and returns a [PersistCookieJar] that saves cookies to the
/// app documents directory. The jar is shared across auth Dio instances
/// so all Riot cookies are persisted across app restarts.
Future<PersistCookieJar> createCookieJar() async {
  final appDocDir = await getApplicationDocumentsDirectory();
  final cookieJar = PersistCookieJar(
    // ignoreExpires: true keeps cookies Riot marks as session-only
    ignoreExpires: true,
    storage: FileStorage('${appDocDir.path}/.cookies/'),
  );
  return cookieJar;
}
