import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'main.dart';
import 'float_theme.dart';

const overlayPageSize = 5;

class FloatOverlay extends StatefulWidget {
  const FloatOverlay({super.key});

  @override
  State<FloatOverlay> createState() => _FloatOverlayState();
}

class _FloatOverlayState extends State<FloatOverlay> {
  List<Snippet> _snippets = [];
  StreamSubscription<dynamic>? _updates;
  final _scrollController = ScrollController();
  bool _expanded = false;
  int _visibleSnippetCount = overlayPageSize;
  String _query = '';
  String? _selectedGroup;

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
    _scrollController.dispose();
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
    if (mounted) {
      setState(() {
        _snippets = snippets;
      });
    }
  }

  Future<void> _expand() async {
    await FlutterOverlayWindow.updateFlag(OverlayFlag.focusPointer);
    await FlutterOverlayWindow.resizeOverlay(340, 440, false);
    if (mounted) setState(() => _expanded = true);
  }

  void _showMore() {
    setState(() => _visibleSnippetCount += overlayPageSize);
  }

  Future<void> _collapse() async {
    await FlutterOverlayWindow.resizeOverlay(72, 72, true);
    await FlutterOverlayWindow.updateFlag(OverlayFlag.defaultFlag);
    if (mounted) setState(() => _expanded = false);
  }

  void _setQuery(String value) {
    setState(() {
      _query = value.trim();
      _visibleSnippetCount = overlayPageSize;
    });
  }

  void _setGroup(String? value) {
    setState(() {
      _selectedGroup = value;
      _visibleSnippetCount = overlayPageSize;
    });
  }

  Future<void> _copy(Snippet snippet) async {
    await FlutterOverlayWindow.copyToClipboard(snippet.body);
    await _collapse();
  }

  @override
  Widget build(BuildContext context) {
    final groups = _snippets.map((snippet) => snippet.group).toSet().toList()
      ..sort();
    final visible = _snippets
        .where(
          (snippet) =>
              (_selectedGroup == null || snippet.group == _selectedGroup) &&
              snippetMatchesQuery(snippet, _query),
        )
        .toList();
    return MaterialApp(
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
                  snippets: visible.take(_visibleSnippetCount).toList(),
                  totalSnippetCount: visible.length,
                  hasMore: _visibleSnippetCount < visible.length,
                  scrollController: _scrollController,
                  onCollapse: _collapse,
                  onCopy: _copy,
                  onShowMore: _showMore,
                  query: _query,
                  onQueryChanged: _setQuery,
                  groups: groups,
                  selectedGroup: _selectedGroup,
                  onGroupChanged: _setGroup,
                )
              : const _OverlayHandle(key: ValueKey('handle')),
        ),
      ),
    );
  }
}

class _OverlayHandle extends StatelessWidget {
  const _OverlayHandle({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Material(
            color: FloatTheme.ink,
            elevation: 0,
            shape: CircleBorder(),
            child: SizedBox(width: 64, height: 64),
          ),
          const Icon(Icons.layers_rounded, color: Colors.white, size: 29),
          Positioned(
            right: 9,
            top: 18,
            bottom: 18,
            child: Container(
              width: 3,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.all(Radius.circular(3)),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ExpandedOverlay extends StatelessWidget {
  const _ExpandedOverlay({
    super.key,
    required this.snippets,
    required this.totalSnippetCount,
    required this.hasMore,
    required this.scrollController,
    required this.onCollapse,
    required this.onCopy,
    required this.onShowMore,
    required this.query,
    required this.onQueryChanged,
    required this.groups,
    required this.selectedGroup,
    required this.onGroupChanged,
  });
  final List<Snippet> snippets;
  final int totalSnippetCount;
  final bool hasMore;
  final ScrollController scrollController;
  final VoidCallback onCollapse;
  final Future<void> Function(Snippet snippet) onCopy;
  final VoidCallback onShowMore;
  final String query;
  final ValueChanged<String> onQueryChanged;
  final List<String> groups;
  final String? selectedGroup;
  final ValueChanged<String?> onGroupChanged;

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
                    snippets.isEmpty
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
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: TextField(
              onChanged: onQueryChanged,
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search pinned notes',
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
              ),
            ),
          ),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(14, 2, 14, 4),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: const Text('ALL'),
                    selected: selectedGroup == null,
                    onSelected: (_) => onGroupChanged(null),
                  ),
                ),
                for (final group in groups)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(group),
                      selected: selectedGroup == group,
                      onSelected: (_) => onGroupChanged(group),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: snippets.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Pin a note in Float\nto keep it here.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : Scrollbar(
                    controller: scrollController,
                    thumbVisibility: true,
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.only(right: 8),
                      children: [
                        if (snippets.isNotEmpty) ...[
                          for (final entry in _groupedSnippets(
                            snippets,
                          ).entries) ...[
                            _OverlaySectionLabel(entry.key.toUpperCase()),
                            for (final snippet in entry.value)
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
                                subtitle: Text(
                                  [
                                        snippet.body,
                                        if (snippet.tags.isNotEmpty)
                                          snippet.tags
                                              .map((tag) => '#$tag')
                                              .join(' '),
                                      ]
                                      .where((value) => value.isNotEmpty)
                                      .join(' · '),
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
                          if (hasMore)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
                              child: OutlinedButton(
                                onPressed: onShowMore,
                                child: Text(
                                  'MORE · ${snippets.length} OF $totalSnippetCount',
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    ),
  );
}

Map<String, List<Snippet>> _groupedSnippets(List<Snippet> snippets) {
  final groups = <String, List<Snippet>>{};
  for (final snippet in snippets) {
    groups.putIfAbsent(snippet.group, () => []).add(snippet);
  }
  return groups;
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
