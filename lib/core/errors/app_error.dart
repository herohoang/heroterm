/// Typed, user-facing error model (FEATURE_SPEC section 9).
///
/// Errors must be actionable and must never carry secret values
/// (passwords, private-key material, auth payloads). Only sanitized
/// diagnostic text may be attached.
enum AppErrorCategory {
  network,
  authentication,
  hostKeyUnknown,
  hostKeyChanged,
  timeout,
  permissionDenied,
  remotePathMissing,
  fileCollision,
  transferInterrupted,
  unsupportedCapability,
  unknown,
}

final class AppError implements Exception {
  const AppError({
    required this.category,
    required this.userMessage,
    this.diagnostic,
  });

  final AppErrorCategory category;
  final String userMessage;

  /// Sanitized technical detail, safe to show in an expandable section
  /// and safe to log. Callers are responsible for redacting secrets
  /// before constructing an [AppError].
  final String? diagnostic;

  bool get isSecurityCritical =>
      category == AppErrorCategory.hostKeyChanged ||
      category == AppErrorCategory.hostKeyUnknown;

  @override
  String toString() => 'AppError(${category.name}): $userMessage';
}
