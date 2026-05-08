import 'dart:async';

import 'package:flutter/material.dart';
import 'package:frontend/config/routes/app_routes.dart';
import 'package:frontend/core/services/notification_popup_service.dart';
import 'package:frontend/core/services/socket_service.dart';
import 'package:go_router/go_router.dart';

class GlobalSocketListener extends StatefulWidget {
  final Widget child;

  const GlobalSocketListener({super.key, required this.child});

  @override
  State<GlobalSocketListener> createState() => _GlobalSocketListenerState();
}

class _GlobalSocketListenerState extends State<GlobalSocketListener> {
  final SocketService _socketService = SocketService();
  StreamSubscription<dynamic>? _notificationSubscription;

  @override
  void initState() {
    super.initState();
    _notificationSubscription = _socketService.notificationStream.listen((
      data,
    ) {
      if (!mounted || data is! Map) {
        return;
      }

      final payload = Map<String, dynamic>.from(data);
      NotificationPopupService.show(
        context: context,
        title: payload['title']?.toString() ?? 'Thong bao moi',
        message: payload['message']?.toString() ?? '',
        onTap: () => context.push(AppRoutes.notifications),
      );
    });
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
