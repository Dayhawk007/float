import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'main.dart';

class FloatOverlay extends StatefulWidget {
  const FloatOverlay({super.key});

  @override
  State<FloatOverlay> createState() => _FloatOverlayState();
}

class _FloatOverlayState extends State<FloatOverlay> {
  List<Snippet> _snippets = [];

  @override
  void initState() {
    super.initState();
    _load();
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

  Future<void> _copy(Snippet snippet) async {
    await Clipboard.setData(ClipboardData(text: snippet.body));
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Card(
          margin: const EdgeInsets.all(8),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              ListTile(
                dense: true,
                leading: const Icon(Icons.layers_outlined),
                title: const Text('Float'),
                subtitle: Text(
                  _snippets.isEmpty
                      ? 'Pin notes in Float to see them here'
                      : 'Tap a note to copy',
                ),
              ),
              Expanded(
                child: _snippets.isEmpty
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
                        itemCount: _snippets.length,
                        itemBuilder: (context, index) => ListTile(
                          dense: true,
                          title: Text(
                            _snippets[index].title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            _snippets[index].body,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _copy(_snippets[index]),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
