import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const clipboardEntriesStorageKey = 'float.clipboard-entries.v1';

class ClipboardEntry {
  const ClipboardEntry({
    required this.id,
    required this.text,
    required this.capturedAt,
  });

  final String id;
  final String text;
  final DateTime capturedAt;

  Map<String, Object> toJson() => {
    'id': id,
    'text': text,
    'capturedAt': capturedAt.toIso8601String(),
  };

  factory ClipboardEntry.fromJson(Map<String, dynamic> json) => ClipboardEntry(
    id: json['id'] as String,
    text: json['text'] as String,
    capturedAt: DateTime.parse(json['capturedAt'] as String),
  );
}

Future<List<ClipboardEntry>> readClipboardEntries() async {
  final preferences = await SharedPreferences.getInstance();
  final raw = preferences.getString(clipboardEntriesStorageKey);
  if (raw == null) return [];
  try {
    return (jsonDecode(raw) as List<dynamic>)
        .map((item) => ClipboardEntry.fromJson(item as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return [];
  }
}

Future<void> writeClipboardEntries(List<ClipboardEntry> entries) async {
  final preferences = await SharedPreferences.getInstance();
  await preferences.setString(
    clipboardEntriesStorageKey,
    jsonEncode(entries.map((entry) => entry.toJson()).toList()),
  );
}

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
