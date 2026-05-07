import '../services/server_time_service.dart';

String resolveAuctionStatus({
  required String status,
  DateTime? startTime,
  required DateTime endTime,
  DateTime? now,
}) {
  final normalizedStatus = status.toUpperCase();
  final currentTime = now ?? ServerTimeService().now;

  if (normalizedStatus == 'ACTIVE' && !currentTime.isBefore(endTime)) {
    return 'ENDED';
  }

  if (normalizedStatus == 'APPROVED' && startTime != null) {
    if (!currentTime.isBefore(endTime)) {
      return 'ENDED';
    }

    if (!currentTime.isBefore(startTime)) {
      return 'ACTIVE';
    }
  }

  return normalizedStatus;
}
