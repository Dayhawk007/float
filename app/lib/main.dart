import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'clipboard_history.dart';
import 'float_theme.dart';
import 'overlay.dart';
import 'sync_service.dart';

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
    theme: FloatTheme.data,
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
  final _syncService = SyncService();
  FloatAccountSession? _accountSession;
  bool _syncing = false;

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
    unawaited(_restoreAccountSession());
  }

  Future<void> _restoreAccountSession() async {
    final session = await _syncService.session();
    if (!mounted || session == null) return;
    setState(() => _accountSession = session);
    await _syncNow(silent: true);
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
    unawaited(_pushSnippet(snippet));
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
    final session = _accountSession;
    if (session != null) {
      try {
        await _syncService.deleteSnippet(session, id);
      } catch (_) {}
    }
  }

  Future<void> _pushSnippet(Snippet snippet) async {
    final session = _accountSession;
    if (session == null) return;
    try {
      await _syncService.upsertSnippet(session, snippet.toJson());
    } catch (_) {}
  }

  Future<void> _syncNow({bool silent = false}) async {
    final session = _accountSession;
    if (session == null || _syncing) return;
    if (mounted) setState(() => _syncing = true);
    try {
      final remote = await _syncService.listSnippets(session);
      final localById = {for (final snippet in _snippets) snippet.id: snippet};
      final remoteById = <String, Snippet>{};
      for (final data in remote) {
        final snippet = Snippet.fromJson(data);
        remoteById[snippet.id] = snippet;
        final local = localById[snippet.id];
        if (local == null || snippet.updatedAt.isAfter(local.updatedAt)) {
          localById[snippet.id] = snippet;
        }
      }
      for (final snippet in localById.values) {
        final remoteSnippet = remoteById[snippet.id];
        if (remoteSnippet == null ||
            snippet.updatedAt.isAfter(remoteSnippet.updatedAt)) {
          await _syncService.upsertSnippet(session, snippet.toJson());
        }
      }
      _snippets = localById.values.toList();
      await _save();
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Synced securely to your account.')),
        );
      }
    } catch (error) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Sync failed: $error')));
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _showAccount() async {
    final session = _accountSession;
    if (session == null) {
      final result = await showDialog<FloatAccountSession>(
        context: context,
        builder: (_) => _AccountDialog(syncService: _syncService),
      );
      if (result != null && mounted) {
        setState(() => _accountSession = result);
        await _syncNow();
      }
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Account sync'),
        content: Text(
          'Signed in as ${session.email}. Notes sync while Float is open.',
        ),
        actions: [
          TextButton(
            onPressed: _syncing ? null : _syncNow,
            child: Text(_syncing ? 'Syncing…' : 'Sync now'),
          ),
          TextButton(
            onPressed: () async {
              await _syncService.logout();
              if (mounted) setState(() => _accountSession = null);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
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
    if (!mounted) return;
    final initialSize = (72 * MediaQuery.devicePixelRatioOf(context)).round();
    await FlutterOverlayWindow.showOverlay(
      height: initialSize,
      width: initialSize,
      alignment: OverlayAlignment.centerRight,
      enableDrag: true,
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
        toolbarHeight: 82,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'FLOAT',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.8,
              ),
            ),
            SizedBox(height: 3),
            Text(
              'A local shelf for what matters',
              style: TextStyle(fontSize: 12, color: FloatTheme.mutedInk),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _accountSession == null
                    ? Colors.transparent
                    : FloatTheme.ink,
                border: Border.all(
                  color: _accountSession == null
                      ? FloatTheme.line
                      : FloatTheme.ink,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: IconButton(
                tooltip: _accountSession == null
                    ? 'Set up account sync'
                    : 'Account sync',
                onPressed: _showAccount,
                color: _accountSession == null ? FloatTheme.ink : Colors.white,
                icon: Icon(
                  _accountSession == null
                      ? Icons.person_outline_rounded
                      : Icons.cloud_done_outlined,
                  size: 19,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: FloatTheme.line),
                borderRadius: BorderRadius.circular(12),
              ),
              child: IconButton(
                tooltip: 'Show floating overlay',
                onPressed: _showOverlay,
                icon: const Icon(Icons.open_in_new_rounded, size: 19),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _edit,
        icon: const Icon(Icons.add),
        label: const Text(
          'NEW NOTE',
          style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1.1),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'Search notes',
                      prefixIcon: Icon(Icons.search_rounded, size: 20),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: _ClipboardSetting(
                    enabled: _clipboardHistoryEnabled,
                    onChanged: _setClipboardHistory,
                  ),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: FloatTheme.shortMotion,
                    switchInCurve: FloatTheme.gentleCurve,
                    switchOutCurve: Curves.easeIn,
                    child: visible.isEmpty
                        ? _EmptyState(
                            key: const ValueKey('empty'),
                            onCreate: () => _edit(),
                          )
                        : ListView.separated(
                            key: const ValueKey('notes'),
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 108),
                            itemCount: visible.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
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
    backgroundColor: FloatTheme.paper,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: const BorderSide(color: FloatTheme.line),
    ),
    title: Text(widget.existing == null ? 'New note' : 'Edit note'),
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
  Widget build(BuildContext context) => AnimatedContainer(
    duration: FloatTheme.shortMotion,
    curve: FloatTheme.gentleCurve,
    decoration: BoxDecoration(
      color: snippet.pinned ? FloatTheme.ink : Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: snippet.pinned ? FloatTheme.ink : FloatTheme.line,
      ),
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Icon(
                  snippet.pinned ? Icons.push_pin_rounded : Icons.note_outlined,
                  color: snippet.pinned ? Colors.white : FloatTheme.ink,
                  size: 19,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      snippet.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: snippet.pinned ? Colors.white : FloatTheme.ink,
                      ),
                    ),
                    if (snippet.body.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        snippet.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.3,
                          color: snippet.pinned
                              ? const Color(0xFFD7D7D2)
                              : FloatTheme.mutedInk,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                iconColor: snippet.pinned ? Colors.white : FloatTheme.ink,
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
            ],
          ),
        ),
      ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({super.key, required this.onCreate});
  final VoidCallback onCreate;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sticky_note_2_outlined, size: 48),
          const SizedBox(height: 16),
          Text(
            'A calmer place for your notes.',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Keep an answer, link, template, or anything you reach for often — only on this device.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add),
            label: const Text('Create your first note'),
          ),
        ],
      ),
    ),
  );
}

class _ClipboardSetting extends StatelessWidget {
  const _ClipboardSetting({required this.enabled, required this.onChanged});

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: FloatTheme.shortMotion,
    padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
    decoration: BoxDecoration(
      color: enabled ? FloatTheme.soft : Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: enabled ? FloatTheme.ink : FloatTheme.line),
    ),
    child: Row(
      children: [
        const Icon(Icons.content_paste_outlined, size: 19),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Clipboard history',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 2),
              Text(
                'Optional and saved locally.',
                style: TextStyle(fontSize: 12, color: FloatTheme.mutedInk),
              ),
            ],
          ),
        ),
        Switch.adaptive(value: enabled, onChanged: onChanged),
      ],
    ),
  );
}

class _AccountDialog extends StatefulWidget {
  const _AccountDialog({required this.syncService});

  final SyncService syncService;

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  final _apiController = TextEditingController(text: 'http://10.0.2.2:8787');
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _register = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _apiController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final session = _register
          ? await widget.syncService.register(
              apiUrl: _apiController.text,
              email: _emailController.text,
              password: _passwordController.text,
            )
          : await widget.syncService.login(
              apiUrl: _apiController.text,
              email: _emailController.text,
              password: _passwordController.text,
            );
      if (mounted) Navigator.pop(context, session);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: FloatTheme.paper,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: const BorderSide(color: FloatTheme.line),
    ),
    title: Text(_register ? 'Create account' : 'Account sync'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Your notes stay on this device and sync whenever Float is open.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: FloatTheme.mutedInk),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _apiController,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'Sync server URL'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Password (8+ characters)',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(color: FloatTheme.ink, fontSize: 12),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _submitting
            ? null
            : () => setState(() => _register = !_register),
        child: Text(
          _register ? 'I already have an account' : 'Create an account',
        ),
      ),
      FilledButton(
        onPressed: _submitting ? null : _submit,
        child: Text(
          _submitting
              ? 'Connecting…'
              : _register
              ? 'Create account'
              : 'Sign in',
        ),
      ),
    ],
  );
}
