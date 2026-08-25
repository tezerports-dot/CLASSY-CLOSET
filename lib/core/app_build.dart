/// Which build of the app this is.
///
/// A shop that has been told three times that something is fixed needs a way
/// to check whether it is running the build that fixes it. Without a stamp the
/// only answer to "did the new version install?" is a shrug, and a stale
/// `ClassyClosetSetup.exe` looks exactly like a fix that never worked.
///
/// The values are compiled in: CI passes the commit and the date it built, and
/// a developer machine that passes nothing falls back to a label that says so.
class AppBuild {
  const AppBuild._();

  /// The marketing version, from `pubspec.yaml`.
  static const version = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.1.0',
  );

  /// The commit this build came from, shortened.
  static const commit = String.fromEnvironment(
    'APP_COMMIT',
    defaultValue: 'local',
  );

  /// The date CI built it, `YYYY-MM-DD`.
  static const builtOn = String.fromEnvironment(
    'APP_BUILT_ON',
    defaultValue: '',
  );

  /// One line for the rail footer and the settings page — the string a shop is
  /// asked to read back when something looks wrong.
  static String get label {
    final parts = <String>[
      'v$version',
      if (commit.isNotEmpty) commit,
      if (builtOn.isNotEmpty) builtOn,
    ];
    return parts.join(' · ');
  }
}
