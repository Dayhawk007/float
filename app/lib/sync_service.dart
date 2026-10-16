import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class FloatAccountSession {
  const FloatAccountSession({
    required this.apiUrl,
    required this.accessToken,
    required this.email,
    required this.expiresAt,
  });

  final String apiUrl;
  final String accessToken;
  final String email;
  final String expiresAt;

  Map<String, String> toJson() => {
    'apiUrl': apiUrl,
    'accessToken': accessToken,
    'email': email,
    'expiresAt': expiresAt,
  };

  factory FloatAccountSession.fromJson(Map<String, dynamic> json) =>
      FloatAccountSession(
        apiUrl: json['apiUrl'] as String,
        accessToken: json['accessToken'] as String,
        email: json['email'] as String,
        expiresAt: json['expiresAt'] as String,
      );
}

class SyncService {
  static const _sessionKey = 'float.account-session.v1';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<FloatAccountSession?> session() async {
    try {
      final raw = await _storage.read(key: _sessionKey);
      if (raw == null) return null;
      return FloatAccountSession.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<FloatAccountSession> register({
    required String apiUrl,
    required String email,
    required String password,
  }) => _authenticate('register', apiUrl, email, password);

  Future<FloatAccountSession> login({
    required String apiUrl,
    required String email,
    required String password,
  }) => _authenticate('login', apiUrl, email, password);

  Future<List<Map<String, dynamic>>> listSnippets(
    FloatAccountSession session,
  ) async {
    final response = await http.get(
      Uri.parse('${_baseUrl(session.apiUrl)}/v1/snippets'),
      headers: _headers(session),
    );
    final data = _response(response) as Map<String, dynamic>;
    return (data['snippets'] as List<dynamic>)
        .map((snippet) => snippet as Map<String, dynamic>)
        .toList();
  }

  Future<void> upsertSnippet(
    FloatAccountSession session,
    Map<String, Object> snippet,
  ) async {
    final response = await http.put(
      Uri.parse(
        '${_baseUrl(session.apiUrl)}/v1/snippets/${Uri.encodeComponent(snippet['id'] as String)}',
      ),
      headers: _headers(session),
      body: jsonEncode(snippet),
    );
    _response(response);
  }

  Future<void> deleteSnippet(FloatAccountSession session, String id) async {
    final response = await http.delete(
      Uri.parse(
        '${_baseUrl(session.apiUrl)}/v1/snippets/${Uri.encodeComponent(id)}',
      ),
      headers: _headers(session),
    );
    _response(response);
  }

  Future<void> logout() => _storage.delete(key: _sessionKey);

  Future<FloatAccountSession> _authenticate(
    String action,
    String apiUrl,
    String email,
    String password,
  ) async {
    final baseUrl = _baseUrl(apiUrl);
    final response = await http.post(
      Uri.parse('$baseUrl/v1/auth/$action'),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    final data = _response(response) as Map<String, dynamic>;
    final session = FloatAccountSession(
      apiUrl: baseUrl,
      accessToken: data['accessToken'] as String,
      email: (data['user'] as Map<String, dynamic>)['email'] as String,
      expiresAt: data['expiresAt'] as String,
    );
    await _storage.write(key: _sessionKey, value: jsonEncode(session.toJson()));
    return session;
  }

  Map<String, String> _headers(FloatAccountSession session) => {
    'authorization': 'Bearer ${session.accessToken}',
    'content-type': 'application/json',
  };

  String _baseUrl(String value) {
    final url = value.trim().replaceFirst(RegExp(r'/+$'), '');
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      throw const FormatException(
        'Enter a full server URL, including https://.',
      );
    }
    return url;
  }

  dynamic _response(http.Response response) {
    final body = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) return body;
    if (body is Map<String, dynamic> && body['error'] is String) {
      throw Exception(body['error']);
    }
    throw Exception('Sync server returned ${response.statusCode}.');
  }
}
