import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../network/dio_client.dart';
import '../../config/constants/api_constants.dart';
import '../../data/models/user_model.dart';
import 'server_time_service.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  io.Socket? _socket;
  String? _userId;
  Function(UserModel)? onBalanceUpdated;

  final _notificationController = StreamController<dynamic>.broadcast();
  final _auctionEventController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _timeSyncController = StreamController<DateTime>.broadcast();

  Stream<dynamic> get notificationStream => _notificationController.stream;
  Stream<Map<String, dynamic>> get auctionEventStream =>
      _auctionEventController.stream;
  Stream<DateTime> get timeSyncStream => _timeSyncController.stream;

  bool get isConnected => _socket?.connected ?? false;

  void connect(String userId, {required String baseUrl}) {
    if (_socket?.connected == true) {
      disconnect();
    }

    _userId = userId;
    _socket = io.io(
      baseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setReconnectionAttempts(5)
          .setReconnectionDelay(2000)
          .build(),
    );

    _socket!.connect();

    _socket!.onConnect((_) {
      _socket!.emit('join_user_room', userId);
    });

    _socket!.on('balance_updated', (data) async {
      await fetchAndUpdateBalance();
    });

    _socket!.on('notification', (data) {
      _notificationController.add(data);
    });

    _socket!.on('server_time_sync', (data) {
      final iso = data is Map ? data['server_time']?.toString() : null;
      ServerTimeService().syncFromIso(iso);
      if (iso != null) {
        _timeSyncController.add(DateTime.parse(iso));
      }
    });

    for (final eventName in const [
      'new_bid',
      'bid_placed',
      'auction_started',
      'auction_ended',
      'auction_state_changed',
      'auction_settled',
      'user_outbid',
    ]) {
      _socket!.on(eventName, (data) {
        if (data is Map) {
          final payload = Map<String, dynamic>.from(data);
          payload['event_name'] = eventName;
          final iso = payload['server_time']?.toString();
          if (iso != null) {
            ServerTimeService().syncFromIso(iso);
          }
          _auctionEventController.add(payload);
        }
      });
    }

    _socket!.onReconnect((_) {
      if (_userId != null) {
        _socket!.emit('join_user_room', _userId);
      }
    });
  }

  Future<void> fetchAndUpdateBalance() async {
    try {
      final dio = DioClient();
      final response = await dio.get(ApiConstants.getUserProfile);
      if (response.statusCode == 200) {
        final user = UserModel.fromJson(response.data as Map<String, dynamic>);
        onBalanceUpdated?.call(user);
      }
    } catch (_) {
      // Ignore transient sync failures.
    }
  }

  void joinAuctionRoom(String auctionId) {
    if (_socket?.connected == true) {
      _socket!.emit('join_auction', auctionId);
    }
  }

  void leaveAuctionRoom(String auctionId) {
    if (_socket?.connected == true) {
      _socket!.emit('leave_auction', auctionId);
    }
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _userId = null;
  }
}
