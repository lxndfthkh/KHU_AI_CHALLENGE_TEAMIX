/// Override the full base URL (ending in /) for a local Functions emulator.
/// Authentication/Firestore emulators must be configured separately by the app.
abstract final class FunctionsConfig {
  static const region = 'asia-northeast3';
  static const baseOverride = String.fromEnvironment('TEAMIX_FUNCTIONS_BASE');
  static Uri base(String projectId) {
    final uri = Uri.parse(baseOverride.isEmpty
      ? 'https://$region-$projectId.cloudfunctions.net/' : baseOverride);
    if (!uri.hasAuthority || !['http', 'https'].contains(uri.scheme) || !uri.path.endsWith('/')) {
      throw ArgumentError('Functions 주소는 HTTP(S) 주소이며 /로 끝나야 합니다.');
    }
    return uri;
  }
}
