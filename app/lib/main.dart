import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'clipboard_history.dart';
import 'float_theme.dart';
import 'overlay.dart';
import 'pairing_scanner.dart';
import 'paired_sync_service.dart';

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
    'createdAt': updatedAt.toIso8601String(),
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
  final _pairedSync = PairedSyncService();
  PairedDevice? _pairedDevice;
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
    unawaited(_restorePairedDevice());
  }

  Future<void> _restorePairedDevice() async {
    try {
      final device = await _pairedSync.device();
      if (!mounted || device == null) return;
      setState(() => _pairedDevice = device);
      await _syncNow(silent: true);
    } catch (_) {
      // Secure storage is unavailable in widget tests and unsupported clients.
    }
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
    final device = _pairedDevice;
    if (device != null) unawaited(_pairedSync.remove(device, id));
  }

  Future<void> _pushSnippet(Snippet snippet) async {
    final device = _pairedDevice;
    if (device == null) return;
    try {
      await _pairedSync.upsert(device, snippet.toJson());
    } catch (_) {}
  }

  Future<void> _syncNow({bool silent = false}) async {
    final device = _pairedDevice;
    if (device == null || _syncing) return;
    if (mounted) setState(() => _syncing = true);
    try {
      final remote = await _pairedSync.list(device);
      final local = {for (final snippet in _snippets) snippet.id: snippet};
      final remoteIds = <String>{};
      for (final item in remote) {
        final snippet = Snippet.fromJson(item);
        remoteIds.add(snippet.id);
        if (!local.containsKey(snippet.id) ||
            snippet.updatedAt.isAfter(local[snippet.id]!.updatedAt)) {
          local[snippet.id] = snippet;
        }
      }
      for (final snippet in local.values) {
        if (!remoteIds.contains(snippet.id) ||
            snippet.updatedAt.isAfter(
              (remote
                      .where((item) => item['id'] == snippet.id)
                      .map(Snippet.fromJson)
                      .first)
                  .updatedAt,
            )) {
          await _pairedSync.upsert(device, snippet.toJson());
        }
      }
      _snippets = local.values.toList();
      await _save();
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Synced with paired device.')),
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

  Future<void> _showPairing() async {
    if (_pairedDevice != null) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Paired device'),
          content: const Text(
            'This phone syncs only with the paired local Float agent while both are reachable on the same network.',
          ),
          actions: [
            TextButton(
              onPressed: _syncing ? null : _syncNow,
              child: Text(_syncing ? 'Syncing…' : 'Sync now'),
            ),
            TextButton(
              onPressed: () async {
                await _pairedSync.forget();
                if (mounted) setState(() => _pairedDevice = null);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('Forget device'),
            ),
          ],
        ),
      );
      return;
    }
    var attempt = await showDialog<_PairingAttempt>(
      context: context,
      builder: (_) => const _PairingDialog(),
    );
    if (attempt == null) {
      return;
    }
    if (attempt.scan) {
      if (!mounted) {
        return;
      }
      final pairingUri = await Navigator.of(
        context,
      ).push<String>(MaterialPageRoute(builder: (_) => const PairingScanner()));
      if (pairingUri == null) return;
      attempt = _PairingAttempt.qr(pairingUri);
    }
    try {
      final deviceId = 'android-${DateTime.now().microsecondsSinceEpoch}';
      final device = attempt.pairingUri != null
          ? await _pairedSync.pair(
              attempt.pairingUri!,
              deviceId: deviceId,
              deviceName: 'Float Android',
            )
          : await _pairedSync.pairWithCode(
              attempt.agentUrl!,
              attempt.manualCode!,
              deviceId: deviceId,
              deviceName: 'Float Android',
            );
      if (mounted) {
        setState(() => _pairedDevice = device);
      }
      await _syncNow();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Pairing failed: $error')));
      }
    }
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
                color: _pairedDevice == null
                    ? Colors.transparent
                    : FloatTheme.ink,
                border: Border.all(
                  color: _pairedDevice == null
                      ? FloatTheme.line
                      : FloatTheme.ink,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: IconButton(
                tooltip: _pairedDevice == null
                    ? 'Pair a local device'
                    : 'Paired device',
                onPressed: _showPairing,
                color: _pairedDevice == null ? FloatTheme.ink : Colors.white,
                icon: Icon(
                  _pairedDevice == null
                      ? Icons.link_rounded
                      : Icons.sync_rounded,
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

class _PairingAttempt {
  const _PairingAttempt.scan()
    : scan = true,
      pairingUri = null,
      agentUrl = null,
      manualCode = null;
  const _PairingAttempt.qr(this.pairingUri)
    : scan = false,
      agentUrl = null,
      manualCode = null;
  const _PairingAttempt.manual(this.agentUrl, this.manualCode)
    : scan = false,
      pairingUri = null;

  final bool scan;
  final String? pairingUri;
  final String? agentUrl;
  final String? manualCode;
}

class _PairingDialog extends StatefulWidget {
  const _PairingDialog();
  @override
  State<_PairingDialog> createState() => _PairingDialogState();
}

class _PairingDialogState extends State<_PairingDialog> {
  final _agentUrlController = TextEditingController();
  final _codeController = TextEditingController();
  @override
  void dispose() {
    _agentUrlController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: FloatTheme.paper,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: const BorderSide(color: FloatTheme.line),
    ),
    title: const Text('Pair a local device'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Run “float pair serve” on your computer. Scan its QR code, or enter the local agent address and eight-digit code it prints.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: FloatTheme.mutedInk),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () =>
                Navigator.pop(context, const _PairingAttempt.scan()),
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Text('Scan QR code'),
          ),
          const SizedBox(height: 18),
          const Text(
            'OR ENTER MANUALLY',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _agentUrlController,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'Local agent URL'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            maxLength: 8,
            decoration: const InputDecoration(labelText: '8-digit code'),
          ),
        ],
      ),
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          _PairingAttempt.manual(
            _agentUrlController.text,
            _codeController.text,
          ),
        ),
        child: const Text('Pair manually'),
      ),
    ],
  );
}
