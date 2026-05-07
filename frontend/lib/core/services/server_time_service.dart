class ServerTimeService {
  ServerTimeService._();

  static final ServerTimeService _instance = ServerTimeService._();
  factory ServerTimeService() => _instance;

  Duration _offset = Duration.zero;

  DateTime get now => DateTime.now().toUtc().add(_offset).toLocal();

  void syncFromIso(String? isoString) {
    if (isoString == null || isoString.isEmpty) {
      return;
    }

    try {
      final serverTime = DateTime.parse(isoString).toUtc();
      final localUtcNow = DateTime.now().toUtc();
      _offset = serverTime.difference(localUtcNow);
    } catch (_) {
      // Ignore invalid server timestamps.
    }
  }
}
