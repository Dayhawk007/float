import 'dart:async';

import 'package:flutter/services.dart';

class ClipboardHistoryService {
  ClipboardHistoryService({required this.onText})
    : _subscription = _events.receiveBroadcastStream().listen((event) {
        final text = event is String ? event.trim() : '';
        if (text.isNotEmpty) onText(text);
      });

  static const _events = EventChannel('float/clipboard_history');
  final void Function(String text) onText;
  final StreamSubscription<dynamic> _subscription;

  Future<void> dispose() => _subscription.cancel();
}
