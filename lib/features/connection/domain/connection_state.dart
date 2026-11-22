/// Connection lifecycle states (ARCHITECTURE state model,
/// FEATURE_SPEC section 2).
enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
  disconnecting,
  failed,
}

/// Operation lifecycle for remote operations (transfers, listings...).
enum OperationStatus { idle, running, succeeded, failed, cancelled }
