import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'main.dart';

class FloatOverlay extends StatefulWidget {
  const FloatOverlay({super.key});

  @override
  State<FloatOverlay> createState() => _FloatOverlayState();
}

class _FloatOverlayState extends State<FloatOverlay> {
  List<Snippet> _snippets = [];
  StreamSubscription<dynamic>? _updates;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _load();
    _updates = FlutterOverlayWindow.overlayListener.listen((_) => _load());
  }

  @override
  void dispose() {
    _updates?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final raw = (await SharedPreferences.getInstance()).getString(
      snippetStorageKey,
    );
    final snippets = raw == null
        ? <Snippet>[]
        : (jsonDecode(raw) as List<dynamic>)
              .map((item) => Snippet.fromJson(item as Map<String, dynamic>))
              .where((snippet) => snippet.pinned)
              .toList();
    if (mounted) setState(() => _snippets = snippets);
  }

  Future<void> _expand() async {
    await FlutterOverlayWindow.resizeOverlay(340, 320, true);
    if (mounted) setState(() => _expanded = true);
  }

  Future<void> _collapse() async {
    await FlutterOverlayWindow.resizeOverlay(64, 64, true);
    if (mounted) setState(() => _expanded = false);
  }

  Future<void> _copy(Snippet snippet) async {
    await Clipboard.setData(ClipboardData(text: snippet.body));
    await _collapse();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Material(
      color: Colors.transparent,
      child: _expanded
          ? _ExpandedOverlay(
              snippets: _snippets,
              onCollapse: _collapse,
              onCopy: _copy,
            )
          : _OverlayHandle(onTap: _expand),
    ),
  );
}

class _OverlayHandle extends StatelessWidget {
  const _OverlayHandle({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Center(
    child: Material(
      color: const Color(0xFF3157D5),
      elevation: 8,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox(
          width: 56,
          height: 56,
          child: Icon(Icons.sticky_note_2_outlined, color: Colors.white),
        ),
      ),
    ),
  );
}

class _ExpandedOverlay extends StatelessWidget {
  const _ExpandedOverlay({
    required this.snippets,
    required this.onCollapse,
    required this.onCopy,
  });
  final List<Snippet> snippets;
  final VoidCallback onCollapse;
  final Future<void> Function(Snippet snippet) onCopy;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Card(
      margin: const EdgeInsets.all(8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            dense: true,
            leading: const Icon(Icons.sticky_note_2_outlined),
            title: const Text('Float'),
            subtitle: Text(
              snippets.isEmpty
                  ? 'Pin notes in Float to see them here'
                  : 'Tap a note to copy',
            ),
            trailing: IconButton(
              tooltip: 'Collapse',
              icon: const Icon(Icons.chevron_right),
              onPressed: onCollapse,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: snippets.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No pinned snippets yet.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: snippets.length,
                    itemBuilder: (context, index) => ListTile(
                      dense: true,
                      title: Text(
                        snippets[index].title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        snippets[index].body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => onCopy(snippets[index]),
                    ),
                  ),
          ),
        ],
      ),
    ),
  );
}
