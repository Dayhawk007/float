import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:multicast_dns/multicast_dns.dart';

const _serviceName = '_float._tcp.local';
const _discoveryTimeout = Duration(seconds: 4);
const _systemChannel = MethodChannel('float/system');

void _log(String event, [Map<String, Object?> details = const {}]) {
  final message = jsonEncode({'event': event, ...details});
  developer.log(message, name: 'FloatDiscovery');
}

class LocalAgentDiscovery {
  LocalAgentDiscovery({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  Future<String?> findUrl(String expectedAgentId) async {
    final client = MDnsClient();
    try {
      await _systemChannel.invokeMethod<void>('acquireMulticastLock');
      await client.start();
      _log('discovery.started', {'service': _serviceName});
      final pointers = await client
          .lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer(_serviceName),
            timeout: _discoveryTimeout,
          )
          .toList();
      for (final pointer in pointers) {
        final services = await client
            .lookup<SrvResourceRecord>(
              ResourceRecordQuery.service(pointer.domainName),
              timeout: _discoveryTimeout,
            )
            .toList();
        for (final service in services) {
          final addresses = await client
              .lookup<IPAddressResourceRecord>(
                ResourceRecordQuery.addressIPv4(service.target),
                timeout: _discoveryTimeout,
              )
              .toList();
          for (final address in addresses) {
            final url = 'http://${address.address.address}:${service.port}';
            if (await _hasExpectedIdentity(url, expectedAgentId)) {
              _log('discovery.recovered', {'agentUrl': url});
              return url;
            }
            _log('discovery.candidate_rejected', {'agentUrl': url});
          }
        }
      }
      _log('discovery.none');
      return null;
    } catch (error) {
      _log('discovery.failed', {'errorType': error.runtimeType.toString()});
      return null;
    } finally {
      client.stop();
      try {
        await _systemChannel.invokeMethod<void>('releaseMulticastLock');
      } catch (_) {
        // Releasing an unavailable Android lock must not affect normal sync.
      }
    }
  }

  Future<bool> _hasExpectedIdentity(String url, String expectedAgentId) async {
    try {
      final response = await _client
          .get(Uri.parse('$url/v1/health'))
          .timeout(const Duration(seconds: 2));
      if (response.statusCode != 200) return false;
      final payload = jsonDecode(response.body);
      return payload is Map<String, dynamic> &&
          payload['agentId'] == expectedAgentId;
    } catch (_) {
      return false;
    }
  }
}
