import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const _pairedDeviceKey = 'float.paired-device.v1';

class PairedDevice {
  const PairedDevice({
    required this.agentUrl,
    required this.deviceId,
    required this.deviceToken,
  });
  final String agentUrl;
  final String deviceId;
  final String deviceToken;

  Map<String, String> toJson() => {
    'agentUrl': agentUrl,
    'deviceId': deviceId,
    'deviceToken': deviceToken,
  };
  factory PairedDevice.fromJson(Map<String, dynamic> json) => PairedDevice(
    agentUrl: json['agentUrl'] as String,
    deviceId: json['deviceId'] as String,
    deviceToken: json['deviceToken'] as String,
  );
}

class PairedSyncService {
  PairedSyncService({http.Client? client, FlutterSecureStorage? storage})
    : _client = client ?? http.Client(),
      _storage = storage ?? const FlutterSecureStorage();

  final http.Client _client;
  final FlutterSecureStorage _storage;

  Future<PairedDevice?> device() async {
    final value = await _storage.read(key: _pairedDeviceKey);
    if (value == null) {
      return null;
    }
    return PairedDevice.fromJson(jsonDecode(value) as Map<String, dynamic>);
  }

  Future<PairedDevice> pair(
    String pairingCode, {
    required String deviceId,
    required String deviceName,
  }) async {
    final uri = Uri.parse(pairingCode.trim());
    if (uri.scheme != 'float' || uri.host != 'pair') {
      throw Exception('This is not a Float pairing code.');
    }
    final agentUrl = uri.queryParameters['url'];
    final pairingToken = uri.queryParameters['token'];
    if (agentUrl == null || pairingToken == null) {
      throw Exception('The pairing code is incomplete.');
    }
    final agent = Uri.parse(agentUrl);
    if (!agent.hasScheme || agent.host.isEmpty) {
      throw Exception('The pairing code has an invalid agent URL.');
    }
    final response = await _client.post(
      agent.replace(path: '/v1/pair'),
      headers: {
        'content-type': 'application/json',
        'x-float-pairing-token': pairingToken,
      },
      body: jsonEncode({'deviceId': deviceId, 'deviceName': deviceName}),
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 201) {
      throw Exception(payload['error'] ?? 'Could not pair with this device.');
    }
    final paired = PairedDevice(
      agentUrl: agentUrl,
      deviceId: deviceId,
      deviceToken: payload['deviceToken'] as String,
    );
    await _storage.write(
      key: _pairedDeviceKey,
      value: jsonEncode(paired.toJson()),
    );
    return paired;
  }

  Future<void> forget() => _storage.delete(key: _pairedDeviceKey);

  Future<List<Map<String, dynamic>>> list(PairedDevice device) async {
    final response = await _client.get(
      _endpoint(device, '/v1/snippets'),
      headers: _headers(device),
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(payload['error'] ?? 'Could not fetch notes.');
    }
    return (payload['snippets'] as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<void> upsert(PairedDevice device, Map<String, Object> snippet) async {
    final response = await _client.put(
      _endpoint(
        device,
        '/v1/snippets/${Uri.encodeComponent(snippet['id']! as String)}',
      ),
      headers: _headers(device),
      body: jsonEncode(snippet),
    );
    if (response.statusCode != 200) {
      throw Exception('Could not sync the note.');
    }
  }

  Future<void> remove(PairedDevice device, String id) async {
    final response = await _client.delete(
      _endpoint(device, '/v1/snippets/${Uri.encodeComponent(id)}'),
      headers: _headers(device),
    );
    if (response.statusCode != 204 && response.statusCode != 404) {
      throw Exception('Could not delete the synced note.');
    }
  }

  Uri _endpoint(PairedDevice device, String path) =>
      Uri.parse(device.agentUrl).replace(path: path);
  Map<String, String> _headers(PairedDevice device) => {
    'authorization': 'Bearer ${device.deviceToken}',
    'content-type': 'application/json',
  };
}
