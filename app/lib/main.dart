import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'clipboard_history.dart';
import 'overlay.dart';

const snippetStorageKey = 'float.snippets.v1';
const clipboardHistoryEnabledKey = 'float.clipboard-history-enabled.v1';

void main() => runApp(const FloatApp());

@pragma('vm:entry-point')
void overlayMain() => runApp(const FloatOverlay());

class Snippet {
  const Snippet({
    required this.id,
    required this.title,
    required this.body,
    required this.updatedAt,
    this.pinned = false,
  });
  final String id;
  final String title;
  final String body;
  final DateTime updatedAt;
  final bool pinned;

  Snippet copyWith({String? title, String? body, bool? pinned}) => Snippet(
    id: id,
    title: title ?? this.title,
    body: body ?? this.body,
    pinned: pinned ?? this.pinned,
    updatedAt: DateTime.now(),
  );
  Map<String, Object> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'updatedAt': updatedAt.toIso8601String(),
    'pinned': pinned,
  };
  factory Snippet.fromJson(Map<String, dynamic> json) => Snippet(
    id: json['id'] as String,
    title: json['title'] as String,
    body: json['body'] as String,
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    pinned: json['pinned'] as bool? ?? false,
  );
}

class FloatApp extends StatelessWidget {
  const FloatApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Float',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3157D5)),
      useMaterial3: true,
    ),
    home: const SnippetHome(),
  );
}

class SnippetHome extends StatefulWidget {
  const SnippetHome({super.key});
  @override
  State<SnippetHome> createState() => _SnippetHomeState();
}

class _SnippetHomeState extends State<SnippetHome> {
  final _searchController = TextEditingController();
  List<Snippet> _snippets = [];
  bool _loading = true;
  bool _clipboardHistoryEnabled = false;
  ClipboardHistoryService? _clipboardHistory;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _clipboardHistory?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(snippetStorageKey);
    if (raw != null) {
      _snippets = (jsonDecode(raw) as List<dynamic>)
          .map((item) => Snippet.fromJson(item as Map<String, dynamic>))
          .toList();
    }
    _clipboardHistoryEnabled =
        preferences.getBool(clipboardHistoryEnabledKey) ?? false;
    if (_clipboardHistoryEnabled) _startClipboardHistory();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async =>
      (await SharedPreferences.getInstance()).setString(
        snippetStorageKey,
        jsonEncode(_snippets.map((snippet) => snippet.toJson()).toList()),
      );

  Future<void> _upsert(Snippet snippet) async {
    final index = _snippets.indexWhere((item) => item.id == snippet.id);
    setState(() {
      if (index == -1) {
        _snippets.add(snippet);
      } else {
        _snippets[index] = snippet;
      }
    });
    await _save();
    try {
      if (await FlutterOverlayWindow.isActive()) {
        await FlutterOverlayWindow.shareData('snippets-changed');
      }
    } on MissingPluginException {
      // The overlay channel is Android-only and is unavailable in widget tests.
    }
  }

  Future<void> _delete(String id) async {
    setState(() => _snippets.removeWhere((snippet) => snippet.id == id));
    await _save();
  }

  void _startClipboardHistory() {
    _clipboardHistory ??= ClipboardHistoryService(
      onText: _captureClipboardText,
    );
  }

  Future<void> _setClipboardHistory(bool enabled) async {
    await (await SharedPreferences.getInstance()).setBool(
      clipboardHistoryEnabledKey,
      enabled,
    );
    if (enabled) _startClipboardHistory();
    if (!enabled) {
      await _clipboardHistory?.dispose();
      _clipboardHistory = null;
    }
    if (mounted) setState(() => _clipboardHistoryEnabled = enabled);
  }

  Future<void> _captureClipboardText(String text) async {
    if (!_clipboardHistoryEnabled ||
        _snippets.any(
          (snippet) =>
              snippet.body == text && snippet.title.startsWith('Clipboard'),
        )) {
      return;
    }
    await _upsert(
      Snippet(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: 'Clipboard • ${TimeOfDay.now().format(context)}',
        body: text,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> _showOverlay() async {
    final permitted = await FlutterOverlayWindow.isPermissionGranted();
    final granted =
        permitted || await FlutterOverlayWindow.requestPermission() == true;
    if (!granted) return;
    await FlutterOverlayWindow.showOverlay(
      height: 72,
      width: 72,
      alignment: OverlayAlignment.centerRight,
      enableDrag: false,
      positionGravity: PositionGravity.none,
      overlayTitle: 'Float overlay active',
      overlayContent: 'Pinned notes are ready to copy.',
    );
  }

  Future<void> _edit([Snippet? existing]) async {
    final result = await showDialog<Snippet>(
      context: context,
      builder: (_) => _SnippetEditorDialog(existing: existing),
    );
    if (result != null) await _upsert(result);
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final visible =
        _snippets
            .where(
              (snippet) =>
                  query.isEmpty ||
                  '${snippet.title}\n${snippet.body}'.toLowerCase().contains(
                    query,
                  ),
            )
            .toList()
          ..sort(
            (a, b) => a.pinned != b.pinned
                ? (b.pinned ? 1 : -1)
                : b.updatedAt.compareTo(a.updatedAt),
          );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Float'),
        actions: [
          IconButton(
            tooltip: 'Show floating overlay',
            onPressed: _showOverlay,
            icon: const Icon(Icons.layers_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _edit,
        icon: const Icon(Icons.add),
        label: const Text('New'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: SearchBar(
                    controller: _searchController,
                    hintText: 'Search your snippets',
                    leading: const Icon(Icons.search),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                SwitchListTile.adaptive(
                  value: _clipboardHistoryEnabled,
                  onChanged: _setClipboardHistory,
                  title: const Text('Save clipboard history'),
                  subtitle: const Text(
                    'Off by default. Saves copied plain text locally while Float is running.',
                  ),
                ),
                Expanded(
                  child: visible.isEmpty
                      ? _EmptyState(onCreate: () => _edit())
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                          itemCount: visible.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) => _SnippetCard(
                            snippet: visible[index],
                            onEdit: () => _edit(visible[index]),
                            onPin: () => _upsert(
                              visible[index].copyWith(
                                pinned: !visible[index].pinned,
                              ),
                            ),
                            onDelete: () => _delete(visible[index].id),
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}

class _SnippetEditorDialog extends StatefulWidget {
  const _SnippetEditorDialog({this.existing});

  final Snippet? existing;

  @override
  State<_SnippetEditorDialog> createState() => _SnippetEditorDialogState();
}

class _SnippetEditorDialogState extends State<_SnippetEditorDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.existing?.title);
    _bodyController = TextEditingController(text: widget.existing?.body);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    Navigator.pop(
      context,
      widget.existing?.copyWith(title: title, body: _bodyController.text) ??
          Snippet(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            title: title,
            body: _bodyController.text,
            updatedAt: DateTime.now(),
          ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.existing == null ? 'New snippet' : 'Edit snippet'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titleController,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bodyController,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Content',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save')),
    ],
  );
}

class _SnippetCard extends StatelessWidget {
  const _SnippetCard({
    required this.snippet,
    required this.onEdit,
    required this.onPin,
    required this.onDelete,
  });
  final Snippet snippet;
  final VoidCallback onEdit;
  final VoidCallback onPin;
  final VoidCallback onDelete;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      onTap: onEdit,
      title: Text(snippet.title),
      subtitle: Text(
        snippet.body,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      leading: Icon(
        snippet.pinned ? Icons.push_pin : Icons.note_outlined,
        color: snippet.pinned ? const Color(0xFF3157D5) : null,
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'edit') onEdit();
          if (value == 'pin') onPin();
          if (value == 'delete') onDelete();
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'edit', child: Text('Edit')),
          PopupMenuItem(
            value: 'pin',
            child: Text(snippet.pinned ? 'Unpin' : 'Pin'),
          ),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});
  final VoidCallback onCreate;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sticky_note_2_outlined, size: 56),
          const SizedBox(height: 16),
          Text(
            'Keep what you need within reach.',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Create a local snippet for an answer, link, template, or anything you copy often.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add),
            label: const Text('Create your first snippet'),
          ),
        ],
      ),
    ),
  );
}
