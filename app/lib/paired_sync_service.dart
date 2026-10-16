import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const _pairedDeviceKey = 'float.paired-device.v1';

void _log(String event, [Map<String, Object?> details = const {}]) {
  developer.log(jsonEncode({'event': event, ...details}), name: 'FloatPair');
}

Map<String, dynamic> _responseBody(http.Response response) {
  try {
    final value = jsonDecode(response.body);
    return value is Map<String, dynamic> ? value : <String, dynamic>{};
  } on FormatException {
    return <String, dynamic>{};
  }
}

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
    _log('paired_device.read.started');
    final value = await _storage.read(key: _pairedDeviceKey);
    if (value == null) {
      _log('paired_device.read.empty');
      return null;
    }
    final device = PairedDevice.fromJson(
      jsonDecode(value) as Map<String, dynamic>,
    );
    _log('paired_device.read.succeeded', {'agentUrl': device.agentUrl});
    return device;
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
    _log('pair.qr.parsed');
    return _pair(
      agentUrl,
      deviceId: deviceId,
      deviceName: deviceName,
      pairingHeader: 'x-float-pairing-token',
      pairingCredential: pairingToken,
    );
  }

  Future<PairedDevice> pairWithCode(
    String agentUrl,
    String code, {
    required String deviceId,
    required String deviceName,
  }) => _pair(
    agentUrl.trim(),
    deviceId: deviceId,
    deviceName: deviceName,
    pairingHeader: 'x-float-pairing-code',
    pairingCredential: code.trim(),
  );

  Future<PairedDevice> _pair(
    String agentUrl, {
    required String deviceId,
    required String deviceName,
    required String pairingHeader,
    required String pairingCredential,
  }) async {
    final agent = Uri.parse(agentUrl);
    if (!agent.hasScheme || agent.host.isEmpty) {
      throw Exception('Enter a valid local agent URL.');
    }
    final stopwatch = Stopwatch()..start();
    _log('pair.request.started', {
      'agentUrl': agent.origin,
      'credentialType': pairingHeader == 'x-float-pairing-token'
          ? 'qr'
          : 'manual',
    });
    late http.Response response;
    try {
      response = await _client.post(
        agent.replace(path: '/v1/pair'),
        headers: {
          'content-type': 'application/json',
          pairingHeader: pairingCredential,
        },
        body: jsonEncode({'deviceId': deviceId, 'deviceName': deviceName}),
      );
    } catch (error) {
      _log('pair.request.network_failed', {
        'agentUrl': agent.origin,
        'elapsedMs': stopwatch.elapsedMilliseconds,
        'errorType': error.runtimeType.toString(),
      });
      throw Exception(
        'Could not reach ${agent.origin}. Keep “float pair serve” open and make sure both devices are on the same Wi-Fi.',
      );
    }
    final payload = _responseBody(response);
    _log('pair.request.completed', {
      'agentUrl': agent.origin,
      'status': response.statusCode,
      'elapsedMs': stopwatch.elapsedMilliseconds,
    });
    if (response.statusCode != 201) {
      throw Exception(
        'Pairing was rejected (${response.statusCode}): ${payload['error'] ?? 'Unknown server response.'}',
      );
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
    _log('pair.persisted', {'agentUrl': agent.origin});
    return paired;
  }

  Future<void> forget() async {
    _log('paired_device.forget.started');
    await _storage.delete(key: _pairedDeviceKey);
    _log('paired_device.forget.succeeded');
  }

  Future<List<Map<String, dynamic>>> list(PairedDevice device) async {
    final endpoint = _endpoint(device, '/v1/snippets');
    final stopwatch = Stopwatch()..start();
    _log('sync.pull.started', {'agentUrl': endpoint.origin});
    late http.Response response;
    try {
      response = await _client.get(endpoint, headers: _headers(device));
    } catch (error) {
      _log('sync.pull.network_failed', {
        'agentUrl': endpoint.origin,
        'elapsedMs': stopwatch.elapsedMilliseconds,
        'errorType': error.runtimeType.toString(),
      });
      throw Exception(
        'Could not reach the paired agent at ${endpoint.origin}.',
      );
    }
    final payload = _responseBody(response);
    _log('sync.pull.completed', {
      'agentUrl': endpoint.origin,
      'status': response.statusCode,
      'elapsedMs': stopwatch.elapsedMilliseconds,
    });
    if (response.statusCode != 200) {
      throw Exception(payload['error'] ?? 'Could not fetch notes.');
    }
    final snippets = (payload['snippets'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    _log('sync.pull.succeeded', {'count': snippets.length});
    return snippets;
  }

  Future<void> upsert(PairedDevice device, Map<String, Object> snippet) async {
    final endpoint = _endpoint(
      device,
      '/v1/snippets/${Uri.encodeComponent(snippet['id']! as String)}',
    );
    _log('sync.push.started', {'agentUrl': endpoint.origin});
    final response = await _client.put(
      endpoint,
      headers: _headers(device),
      body: jsonEncode(snippet),
    );
    if (response.statusCode != 200) {
      _log('sync.push.failed', {'status': response.statusCode});
      throw Exception('Could not sync the note.');
    }
    _log('sync.push.succeeded');
  }

  Future<void> remove(PairedDevice device, String id) async {
    final endpoint = _endpoint(
      device,
      '/v1/snippets/${Uri.encodeComponent(id)}',
    );
    _log('sync.delete.started', {'agentUrl': endpoint.origin});
    final response = await _client.delete(endpoint, headers: _headers(device));
    if (response.statusCode != 204 && response.statusCode != 404) {
      _log('sync.delete.failed', {'status': response.statusCode});
      throw Exception('Could not delete the synced note.');
    }
    _log('sync.delete.succeeded', {'status': response.statusCode});
  }

  Uri _endpoint(PairedDevice device, String path) =>
      Uri.parse(device.agentUrl).replace(path: path);
  Map<String, String> _headers(PairedDevice device) => {
    'authorization': 'Bearer ${device.deviceToken}',
    'content-type': 'application/json',
  };
}
