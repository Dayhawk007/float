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
const syncPollInterval = Duration(minutes: 1);
const notesPageSize = 20;
const defaultSnippetGroup = 'General';
const suggestedSnippetGroups = [
  defaultSnippetGroup,
  'Jobs',
  'Cold posting',
  'Profile',
  'Preferences',
];

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
    this.group = defaultSnippetGroup,
  });
  final String id;
  final String title;
  final String body;
  final DateTime updatedAt;
  final bool pinned;
  final String group;

  Snippet copyWith({
    String? title,
    String? body,
    bool? pinned,
    String? group,
  }) => Snippet(
    id: id,
    title: title ?? this.title,
    body: body ?? this.body,
    pinned: pinned ?? this.pinned,
    group: group ?? this.group,
    updatedAt: DateTime.now(),
  );
  Map<String, Object> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'updatedAt': updatedAt.toIso8601String(),
    'createdAt': updatedAt.toIso8601String(),
    'pinned': pinned,
    'group': group,
  };
  factory Snippet.fromJson(Map<String, dynamic> json) => Snippet(
    id: json['id'] as String,
    title: json['title'] as String,
    body: json['body'] as String,
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    pinned: json['pinned'] as bool? ?? false,
    group: snippetGroup(json['group'] as String?),
  );
}

String snippetGroup(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty
      ? defaultSnippetGroup
      : normalized;
}

bool snippetMatchesQuery(Snippet snippet, String query) =>
    query.isEmpty ||
    '${snippet.title}\n${snippet.body}\n${snippet.group}'
        .toLowerCase()
        .contains(query.toLowerCase());

enum SnippetKind { linkedin, link, template, code, text }

SnippetKind snippetKind(Snippet snippet) {
  final value = '${snippet.title}\n${snippet.body}'.toLowerCase();
  final uri = Uri.tryParse(snippet.body.trim());
  if (uri != null && uri.hasScheme && uri.host.contains('linkedin.com')) {
    return SnippetKind.linkedin;
  }
  if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
    return SnippetKind.link;
  }
  if (value.contains('template') ||
      value.contains('{{') ||
      value.contains('\${') ||
      value.contains('[[')) {
    return SnippetKind.template;
  }
  if (value.contains('```') ||
      value.contains('function ') ||
      value.contains('const ')) {
    return SnippetKind.code;
  }
  return SnippetKind.text;
}

String snippetKindLabel(SnippetKind kind) => switch (kind) {
  SnippetKind.linkedin => 'LINKEDIN',
  SnippetKind.link => 'LINK',
  SnippetKind.template => 'TEMPLATE',
  SnippetKind.code => 'CODE',
  SnippetKind.text => 'NOTE',
};

IconData snippetKindIcon(SnippetKind kind) => switch (kind) {
  SnippetKind.linkedin => Icons.work_outline_rounded,
  SnippetKind.link => Icons.link_rounded,
  SnippetKind.template => Icons.dashboard_customize_outlined,
  SnippetKind.code => Icons.data_object_rounded,
  SnippetKind.text => Icons.note_outlined,
};

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
  final _notesScrollController = ScrollController();
  List<Snippet> _snippets = [];
  List<ClipboardEntry> _clipboardEntries = [];
  bool _loading = true;
  bool _clipboardHistoryEnabled = false;
  ClipboardHistoryService? _clipboardHistory;
  final _pairedSync = PairedSyncService();
  PairedDevice? _pairedDevice;
  bool _syncing = false;
  Timer? _syncTimer;
  int _visibleNoteCount = notesPageSize;
  String? _selectedGroup;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _clipboardHistory?.dispose();
    _syncTimer?.cancel();
    _searchController.dispose();
    _notesScrollController.dispose();
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
    _clipboardEntries = await readClipboardEntries();
    _clipboardHistoryEnabled =
        preferences.getBool(clipboardHistoryEnabledKey) ?? false;
    if (_clipboardHistoryEnabled) {
      _startClipboardHistory();
      unawaited(_captureCurrentClipboard());
    }
    if (mounted) setState(() => _loading = false);
    unawaited(_restorePairedDevice());
  }

  Future<void> _restorePairedDevice() async {
    try {
      final device = await _pairedSync.device();
      if (!mounted || device == null) return;
      setState(() => _pairedDevice = device);
      _startSyncPolling();
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
    await _notifyOverlay();
  }

  Future<void> _notifyOverlay() async {
    try {
      if (await FlutterOverlayWindow.isActive()) {
        await FlutterOverlayWindow.shareData('snippets-changed');
      }
    } on MissingPluginException {
      // The overlay channel is Android-only and is unavailable in widget tests.
    }
  }

  void _startSyncPolling() {
    _syncTimer ??= Timer.periodic(
      syncPollInterval,
      (_) => _syncNow(silent: true),
    );
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
    var device = _pairedDevice;
    if (device == null || _syncing) return;
    if (mounted) setState(() => _syncing = true);
    try {
      device = await _pairedSync.refreshAgentIdentity(device);
      if (mounted) setState(() => _pairedDevice = device);
      List<Map<String, dynamic>> remote;
      try {
        remote = await _pairedSync.list(device);
      } catch (_) {
        final recovered = await _pairedSync.rediscover(device);
        if (recovered == null) rethrow;
        device = recovered;
        if (mounted) setState(() => _pairedDevice = recovered);
        remote = await _pairedSync.list(recovered);
      }
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
      await _notifyOverlay();
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
      _startSyncPolling();
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
    if (mounted) setState(() => _clipboardHistoryEnabled = enabled);
    if (enabled) {
      _startClipboardHistory();
      await _captureCurrentClipboard();
    }
    if (!enabled) {
      await _clipboardHistory?.dispose();
      _clipboardHistory = null;
    }
  }

  Future<void> _captureClipboardText(String text) async {
    if (!_clipboardHistoryEnabled || text.trim().isEmpty) return;
    final trimmed = text.trim();
    _clipboardEntries.removeWhere((entry) => entry.text == trimmed);
    _clipboardEntries.insert(
      0,
      ClipboardEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        text: trimmed,
        capturedAt: DateTime.now(),
      ),
    );
    if (_clipboardEntries.length > 20) {
      _clipboardEntries = _clipboardEntries.take(20).toList();
    }
    await writeClipboardEntries(_clipboardEntries);
    debugPrint(
      '[FloatClipboard] shelf.updated count=${_clipboardEntries.length} length=${trimmed.length}',
    );
    if (mounted) setState(() {});
  }

  Future<void> _captureCurrentClipboard() async {
    try {
      final text = await FloatClipboard.read();
      debugPrint(
        '[FloatClipboard] clipboard.read hasText=${text?.isNotEmpty ?? false}',
      );
      if (text != null) await _captureClipboardText(text);
    } on MissingPluginException {
      // Clipboard reads are only available on Android devices.
    }
  }

  Future<void> _saveClipboardEntry(ClipboardEntry entry) async {
    await _upsert(
      Snippet(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: 'Saved paste',
        body: entry.text,
        updatedAt: DateTime.now(),
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saved to Float notes.')));
    }
  }

  Future<void> _showClipboardShelf() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: FloatTheme.paper,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: FloatTheme.line),
        ),
        title: const Text('Latest pastes'),
        content: SizedBox(
          width: 420,
          height: 380,
          child: _ClipboardShelf(
            entries: _clipboardEntries,
            onCopy: (entry) => FloatClipboard.copy(entry.text),
            onSave: _saveClipboardEntry,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _showOverlay() async {
    final permitted = await FlutterOverlayWindow.isPermissionGranted();
    final granted =
        permitted || await FlutterOverlayWindow.requestPermission() == true;
    if (!granted) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Allow Float over other apps'),
          content: const Text(
            'Float needs Android’s “Display over other apps” permission to keep the note handle visible.\n\nOpen Settings → Apps → Special app access → Display over other apps → Float, then turn on “Allow display over other apps”.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await const MethodChannel(
                  'float/system',
                ).invokeMethod<void>('openOverlaySettings');
              },
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
      return;
    }
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

  void _showMoreNotes() {
    setState(() => _visibleNoteCount += notesPageSize);
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim();
    final groups = <String>{
      for (final snippet in _snippets) snippet.group,
    }.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final visible =
        _snippets
            .where(
              (snippet) =>
                  (_selectedGroup == null || snippet.group == _selectedGroup) &&
                  snippetMatchesQuery(snippet, query),
            )
            .toList()
          ..sort(
            (a, b) => a.pinned != b.pinned
                ? (b.pinned ? 1 : -1)
                : b.updatedAt.compareTo(a.updatedAt),
          );
    final pagedNotes = visible.take(_visibleNoteCount).toList();
    final hasMoreNotes = pagedNotes.length < visible.length;
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
                    onChanged: (_) =>
                        setState(() => _visibleNoteCount = notesPageSize),
                  ),
                ),
                if (groups.isNotEmpty)
                  SizedBox(
                    height: 42,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      children: [
                        ChoiceChip(
                          label: const Text('ALL'),
                          selected: _selectedGroup == null,
                          onSelected: (_) => setState(() {
                            _selectedGroup = null;
                            _visibleNoteCount = notesPageSize;
                          }),
                        ),
                        for (final group in groups) ...[
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: Text(group.toUpperCase()),
                            selected: _selectedGroup == group,
                            onSelected: (_) => setState(() {
                              _selectedGroup = _selectedGroup == group
                                  ? null
                                  : group;
                              _visibleNoteCount = notesPageSize;
                            }),
                          ),
                        ],
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: _ClipboardSetting(
                    enabled: _clipboardHistoryEnabled,
                    onChanged: _setClipboardHistory,
                    onOpen: _showClipboardShelf,
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
                        : Scrollbar(
                            controller: _notesScrollController,
                            thumbVisibility: true,
                            child: ListView.separated(
                              key: const ValueKey('notes'),
                              controller: _notesScrollController,
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                4,
                                28,
                                108,
                              ),
                              itemCount:
                                  pagedNotes.length + (hasMoreNotes ? 1 : 0),
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                if (index == pagedNotes.length) {
                                  return _PaginationControl(
                                    shown: pagedNotes.length,
                                    total: visible.length,
                                    onShowMore: _showMoreNotes,
                                  );
                                }
                                final snippet = pagedNotes[index];
                                return _SnippetCard(
                                  snippet: snippet,
                                  onEdit: () => _edit(snippet),
                                  onPin: () => _upsert(
                                    snippet.copyWith(pinned: !snippet.pinned),
                                  ),
                                  onDelete: () => _delete(snippet.id),
                                );
                              },
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
  late final TextEditingController _groupController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.existing?.title);
    _bodyController = TextEditingController(text: widget.existing?.body);
    _groupController = TextEditingController(
      text: widget.existing?.group ?? defaultSnippetGroup,
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _groupController.dispose();
    super.dispose();
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    Navigator.pop(
      context,
      widget.existing?.copyWith(
            title: title,
            body: _bodyController.text,
            group: snippetGroup(_groupController.text),
          ) ??
          Snippet(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            title: title,
            body: _bodyController.text,
            updatedAt: DateTime.now(),
            group: snippetGroup(_groupController.text),
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
          const SizedBox(height: 12),
          TextField(
            controller: _groupController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Group',
              hintText: suggestedSnippetGroups.skip(1).join(', '),
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
                  snippetKindIcon(snippetKind(snippet)),
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
                    const SizedBox(height: 8),
                    _SnippetKindBadge(kind: snippetKind(snippet)),
                    const SizedBox(height: 6),
                    Text(
                      snippet.group.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.9,
                        color: snippet.pinned
                            ? const Color(0xFFD7D7D2)
                            : FloatTheme.mutedInk,
                      ),
                    ),
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

class _PaginationControl extends StatelessWidget {
  const _PaginationControl({
    required this.shown,
    required this.total,
    required this.onShowMore,
  });

  final int shown;
  final int total;
  final VoidCallback onShowMore;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onShowMore,
    icon: const Icon(Icons.expand_more_rounded),
    label: Text('SHOW MORE · $shown OF $total'),
  );
}

class _SnippetKindBadge extends StatelessWidget {
  const _SnippetKindBadge({required this.kind});

  final SnippetKind kind;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: FloatTheme.soft,
      borderRadius: BorderRadius.circular(7),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(snippetKindIcon(kind), size: 12),
          const SizedBox(width: 4),
          Text(
            snippetKindLabel(kind),
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: .7,
            ),
          ),
        ],
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
  const _ClipboardSetting({
    required this.enabled,
    required this.onChanged,
    required this.onOpen,
  });

  final bool enabled;
  final ValueChanged<bool> onChanged;
  final VoidCallback onOpen;

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
                'Keeps recent text while Float is open; save only what you need.',
                style: TextStyle(fontSize: 12, color: FloatTheme.mutedInk),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Latest pastes',
          onPressed: enabled ? onOpen : null,
          icon: const Icon(Icons.content_paste_search_rounded, size: 20),
        ),
        Switch.adaptive(value: enabled, onChanged: onChanged),
      ],
    ),
  );
}

class _ClipboardShelf extends StatelessWidget {
  const _ClipboardShelf({
    required this.entries,
    required this.onCopy,
    required this.onSave,
  });

  final List<ClipboardEntry> entries;
  final ValueChanged<ClipboardEntry> onCopy;
  final ValueChanged<ClipboardEntry> onSave;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: FloatTheme.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(14, 12, 14, 4),
          child: Text(
            'LATEST PASTES',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? const Center(
                  child: Text(
                    'Copy text while Float is open\nto see it here.',
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
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
                      onTap: () => onCopy(entry),
                      trailing: IconButton(
                        tooltip: 'Save as note',
                        icon: const Icon(Icons.add_rounded, size: 21),
                        onPressed: () => onSave(entry),
                      ),
                    );
                  },
                ),
        ),
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
