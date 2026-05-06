class AppLocalizations {
  static String translateStatus(String? status) {
    switch ((status ?? '').toUpperCase()) {
      case 'PENDING_APPROVAL':
        return 'Chờ duyệt';
      case 'APPROVED':
        return 'Đã duyệt';
      case 'ACTIVE':
        return 'Đang diễn ra';
      case 'ENDED':
        return 'Đã kết thúc';
      case 'SETTLED':
        return 'Đã tất toán';
      case 'REJECTED':
        return 'Bị từ chối';
      case 'WAITING_CONFIRMATION':
        return 'Chờ xác nhận';
      case 'CONFIRMED':
        return 'Đã xác nhận';
      case 'SUCCESS':
      case 'COMPLETED':
      case 'PAID_DONE':
        return 'Thành công';
      case 'PENDING':
      case 'PENDING_PAYMENT':
      case 'PAID':
        return 'Đang xử lý';
      case 'FAILED':
        return 'Thất bại';
      case 'TIMEOUT':
        return 'Hết hạn';
      case 'VALID':
        return 'Hợp lệ';
      case 'WINNING':
        return 'Đang dẫn đầu';
      case 'OUTBID':
        return 'Bị vượt giá';
      case 'UNKNOWN':
        return 'Không xác định';
      default:
        return status?.trim().isNotEmpty == true ? status! : 'Không xác định';
    }
  }

  static String translateTransactionType(bool isDeposit) {
    return isDeposit ? 'Nạp tiền' : 'Rút tiền';
  }

  static String formatTimeLeft(DateTime endTime) {
    final difference = endTime.difference(DateTime.now());

    if (difference.isNegative) {
      return 'Đã kết thúc';
    }

    if (difference.inDays > 0) {
      final hours = difference.inHours % 24;
      return '${difference.inDays} ngày ${hours} giờ';
    }

    if (difference.inHours > 0) {
      final minutes = difference.inMinutes % 60;
      return '${difference.inHours} giờ ${minutes} phút';
    }

    if (difference.inMinutes > 0) {
      return '${difference.inMinutes} phút';
    }

    return '${difference.inSeconds} giây';
  }
}
