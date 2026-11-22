/// The exact build the user is running (ADR-019).
///
/// The release scripts pass the current git short hash via
/// `--dart-define=BUILD_ID=...`; plain `flutter run` builds show
/// `dev`. Displayed in the connection header and stamped into
/// the input-debug-log banner, so a screenshot or a log file
/// identifies its build unambiguously — after four rounds of
/// typing fixes, "which build produced this report?" must never
/// be a matter of guesswork again.
const buildId = String.fromEnvironment('BUILD_ID', defaultValue: 'dev');
