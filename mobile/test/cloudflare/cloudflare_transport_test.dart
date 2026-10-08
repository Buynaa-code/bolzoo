import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/cloudflare/cloudflare_transport.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  Future<void> withResponse(
    String body,
    Future<void> Function(HttpCloudflareTransport) check,
  ) async {
    final client = HttpCloudflareTransport(
      Uri.parse('https://test.example'),
      client: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(body),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    try {
      await check(client);
    } finally {
      client.close();
    }
  }

  test('accepts a calendar or export page larger than 64 KiB', () async {
    final note = 'Хамтдаа ' * 10000;
    await withResponse(jsonEncode({'ok': true, 'note': note}), (client) async {
      final response = await client.send('POST', '/v1/account/export');
      expect(response.body['note'], note);
    });
  });

  test('rejects responses larger than one MiB', () async {
    await withResponse(jsonEncode({'ok': true, 'note': 'x' * (1024 * 1024)}), (
      client,
    ) async {
      await expectLater(
        client.send('POST', '/v1/account/export'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            'API response too large',
          ),
        ),
      );
    });
  });

  test('pins bearer to the API request and refuses redirects', () async {
    final client = HttpCloudflareTransport(
      Uri.parse('https://test.example'),
      client: MockClient((request) async {
        expect(request.url, Uri.parse('https://test.example/v1/auth/session'));
        expect(request.headers['authorization'], 'Bearer test-only');
        expect(request.headers['cache-control'], 'no-store');
        expect(request.followRedirects, isFalse);
        return http.Response('{"ok":true}', 200);
      }),
    );
    addTearDown(client.close);
    await client.send('GET', '/v1/auth/session', token: 'test-only');
    await expectLater(
      client.send('GET', 'https://other.example/v1/auth/session'),
      throwsArgumentError,
    );
  });

  test('malformed JSON errors do not expose response contents', () async {
    await withResponse('{"token":"private-response-token"', (client) async {
      await expectLater(
        client.send('GET', '/v1/auth/session'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.toString(),
            'safe error',
            isNot(contains('private-response-token')),
          ),
        ),
      );
    });
  });
}
