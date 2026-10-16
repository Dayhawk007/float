import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'main.dart';
import 'float_theme.dart';
import 'clipboard_history.dart';

class FloatOverlay extends StatefulWidget {
  const FloatOverlay({super.key});

  @override
  State<FloatOverlay> createState() => _FloatOverlayState();
}

class _FloatOverlayState extends State<FloatOverlay> {
  List<Snippet> _snippets = [];
  List<ClipboardEntry> _clipboardEntries = [];
  StreamSubscription<dynamic>? _updates;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _load();
    _updates = FlutterOverlayWindow.overlayListener.listen((event) {
      if (event == 'overlay-handle-tap' && !_expanded) {
        _expand();
        return;
      }
      _load();
    });
  }

  @override
  void dispose() {
    _updates?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    final raw = preferences.getString(snippetStorageKey);
    final snippets = raw == null
        ? <Snippet>[]
        : (jsonDecode(raw) as List<dynamic>)
              .map((item) => Snippet.fromJson(item as Map<String, dynamic>))
              .where((snippet) => snippet.pinned)
              .toList();
    final clipboardEntries = await readClipboardEntries();
    if (mounted) {
      setState(() {
        _snippets = snippets;
        _clipboardEntries = clipboardEntries;
      });
    }
  }

  Future<void> _expand() async {
    await FlutterOverlayWindow.resizeOverlay(340, 320, false);
    if (mounted) setState(() => _expanded = true);
  }

  Future<void> _collapse() async {
    await FlutterOverlayWindow.resizeOverlay(72, 72, true);
    if (mounted) setState(() => _expanded = false);
  }

  Future<void> _copy(Snippet snippet) async {
    await _copyText(snippet.body);
  }

  Future<void> _copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    await _collapse();
  }

  Future<void> _saveClipboard(ClipboardEntry entry) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(snippetStorageKey);
    final snippets = raw == null
        ? <Map<String, dynamic>>[]
        : (jsonDecode(raw) as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .toList();
    snippets.add({
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'title': 'Saved paste',
      'body': entry.text,
      'updatedAt': DateTime.now().toIso8601String(),
      'createdAt': DateTime.now().toIso8601String(),
      'pinned': false,
    });
    await preferences.setString(snippetStorageKey, jsonEncode(snippets));
    await FlutterOverlayWindow.shareData('clipboard-saved');
    await _load();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: FloatTheme.data,
    home: Material(
      color: Colors.transparent,
      child: AnimatedSwitcher(
        duration: FloatTheme.shortMotion,
        switchInCurve: FloatTheme.gentleCurve,
        child: _expanded
            ? _ExpandedOverlay(
                key: const ValueKey('expanded'),
                snippets: _snippets,
                clipboardEntries: _clipboardEntries,
                onCollapse: _collapse,
                onCopy: _copy,
                onCopyText: _copyText,
                onSaveClipboard: _saveClipboard,
              )
            : const _OverlayHandle(key: ValueKey('handle')),
      ),
    ),
  );
}

class _OverlayHandle extends StatelessWidget {
  const _OverlayHandle({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Material(
      color: FloatTheme.ink,
      elevation: 0,
      shape: const CircleBorder(),
      child: const SizedBox(
        width: 64,
        height: 64,
        child: Icon(Icons.notes_rounded, color: Colors.white, size: 25),
      ),
    ),
  );
}

class _ExpandedOverlay extends StatelessWidget {
  const _ExpandedOverlay({
    super.key,
    required this.snippets,
    required this.clipboardEntries,
    required this.onCollapse,
    required this.onCopy,
    required this.onCopyText,
    required this.onSaveClipboard,
  });
  final List<Snippet> snippets;
  final List<ClipboardEntry> clipboardEntries;
  final VoidCallback onCollapse;
  final Future<void> Function(Snippet snippet) onCopy;
  final Future<void> Function(String text) onCopyText;
  final Future<void> Function(ClipboardEntry entry) onSaveClipboard;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Material(
      color: FloatTheme.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: FloatTheme.ink),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: FloatTheme.ink,
            padding: const EdgeInsets.fromLTRB(18, 10, 8, 10),
            child: Row(
              children: [
                const Icon(Icons.notes_rounded, color: Colors.white, size: 19),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    snippets.isEmpty && clipboardEntries.isEmpty
                        ? 'FLOAT  ·  NOTHING SAVED YET'
                        : 'FLOAT  ·  TAP TO COPY',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Collapse',
                  color: Colors.white,
                  icon: const Icon(Icons.close_rounded, size: 19),
                  onPressed: onCollapse,
                ),
              ],
            ),
          ),
          Expanded(
            child: snippets.isEmpty && clipboardEntries.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Pin a note in Float\nto keep it here.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView(
                    children: [
                      if (snippets.isNotEmpty) ...[
                        const _OverlaySectionLabel('PINNED NOTES'),
                        for (final snippet in snippets)
                          ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 3,
                            ),
                            title: Text(
                              snippet.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            leading: Icon(
                              snippetKindIcon(snippetKind(snippet)),
                              size: 18,
                            ),
                            subtitle: Text(
                              snippet.body,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: FloatTheme.mutedInk,
                              ),
                            ),
                            trailing: const Icon(
                              Icons.content_copy_outlined,
                              size: 17,
                            ),
                            onTap: () => onCopy(snippet),
                          ),
                      ],
                      if (clipboardEntries.isNotEmpty) ...[
                        const _OverlaySectionLabel('LATEST PASTES'),
                        for (final entry in clipboardEntries)
                          ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 3,
                            ),
                            leading: const Icon(
                              Icons.content_paste_rounded,
                              size: 18,
                            ),
                            title: Text(
                              entry.text,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              tooltip: 'Save as note',
                              icon: const Icon(
                                Icons.bookmark_add_outlined,
                                size: 18,
                              ),
                              onPressed: () => onSaveClipboard(entry),
                            ),
                            onTap: () => onCopyText(entry.text),
                          ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    ),
  );
}

class _OverlaySectionLabel extends StatelessWidget {
  const _OverlaySectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 12, 18, 2),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 1,
      ),
    ),
  );
}
