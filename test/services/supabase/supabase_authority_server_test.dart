import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/services/supabase/supabase_authority_server.dart';

void main() {
  group('SupabaseAuthorityServer', () {
    late SupabaseAuthorityServer authorityServer;
    late HttpServer listener;
    late Uri baseUri;

    setUp(() async {
      authorityServer = SupabaseAuthorityServer(proxySecret: 'test-secret');
      listener = await authorityServer.listen(port: 0);
      baseUri = Uri.parse(
        'http://${listener.address.address}:${listener.port}/',
      );
    });

    tearDown(() async {
      await authorityServer.close(force: true);
    });

    test(
      'creates a lobby, starts a match, and returns a player view',
      () async {
        final hostHandle = await _postJson(
          baseUri,
          'create-lobby',
          <String, dynamic>{
            'request': <String, dynamic>{
              'displayName': 'Host',
              'targetScore': 1000,
              'preferredTeam': 0,
            },
          },
          authUserId: '00000000-0000-0000-0000-000000000001',
        );
        final lobbyId = hostHandle['lobbyId'] as String;
        final accessToken = hostHandle['accessToken'] as String;

        await _postJson(
          baseUri,
          'set-ready-state',
          <String, dynamic>{
            'lobbyId': lobbyId,
            'accessToken': accessToken,
            'isReady': true,
          },
          authUserId: '00000000-0000-0000-0000-000000000001',
        );

        for (var seat = 1; seat < 4; seat++) {
          await _postJson(
            baseUri,
            'claim-seat',
            <String, dynamic>{
              'lobbyId': lobbyId,
              'accessToken': accessToken,
              'seat': seat,
              'type': 'automated',
              'automatedDisplayName': 'Bot ${seat + 1}',
            },
            authUserId: '00000000-0000-0000-0000-000000000001',
          );
        }

        await _postJson(baseUri, 'start-match', <String, dynamic>{
          'lobbyId': lobbyId,
          'accessToken': accessToken,
        }, authUserId: '00000000-0000-0000-0000-000000000001');

        final lobbySnapshot = await _postJson(
          baseUri,
          'get-lobby',
          <String, dynamic>{'lobbyId': lobbyId, 'accessToken': accessToken},
          authUserId: '00000000-0000-0000-0000-000000000001',
        );
        final matchId = lobbySnapshot['matchId'] as String;

        final matchView = await _postJson(
          baseUri,
          'get-match-view',
          <String, dynamic>{'matchId': matchId, 'accessToken': accessToken},
          authUserId: '00000000-0000-0000-0000-000000000001',
        );
        final connection = await _postJson(
          baseUri,
          'get-match-connection',
          <String, dynamic>{'matchId': matchId, 'accessToken': accessToken},
          authUserId: '00000000-0000-0000-0000-000000000001',
        );

        expect(matchView['matchId'], matchId);
        expect(matchView['selfPlayerId'], hostHandle['playerId']);
        expect((matchView['revision'] as num).toInt(), greaterThan(0));
        expect(connection['state'], 'live');
      },
    );

    test('rejects requests without the configured proxy secret', () async {
      final client = HttpClient();
      addTearDown(client.close);

      final request = await client.postUrl(baseUri.resolve('create-lobby'));
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode(<String, dynamic>{
          'request': <String, dynamic>{
            'displayName': 'Host',
            'targetScore': 1000,
          },
        }),
      );

      final response = await request.close();
      expect(response.statusCode, HttpStatus.unauthorized);
    });

    test('accepts heartbeat for a lobby', () async {
      final hostHandle = await _postJson(
        baseUri,
        'create-lobby',
        <String, dynamic>{
          'request': <String, dynamic>{
            'displayName': 'Host',
            'targetScore': 1000,
            'preferredTeam': 0,
          },
        },
        authUserId: '00000000-0000-0000-0000-000000000001',
      );

      final result = await _postJson(baseUri, 'heartbeat', <String, dynamic>{
        'lobbyId': hostHandle['lobbyId'] as String,
        'accessToken': hostHandle['accessToken'] as String,
      }, authUserId: '00000000-0000-0000-0000-000000000001');
      expect(result['ok'], isTrue);
    });

    test('accepts heartbeat for a match', () async {
      final hostHandle = await _postJson(
        baseUri,
        'create-lobby',
        <String, dynamic>{
          'request': <String, dynamic>{
            'displayName': 'Host',
            'targetScore': 1000,
            'preferredTeam': 0,
          },
        },
        authUserId: '00000000-0000-0000-0000-000000000001',
      );
      final lobbyId = hostHandle['lobbyId'] as String;
      final accessToken = hostHandle['accessToken'] as String;

      await _postJson(
        baseUri,
        'set-ready-state',
        <String, dynamic>{
          'lobbyId': lobbyId,
          'accessToken': accessToken,
          'isReady': true,
        },
        authUserId: '00000000-0000-0000-0000-000000000001',
      );

      for (var seat = 1; seat < 4; seat++) {
        await _postJson(baseUri, 'claim-seat', <String, dynamic>{
          'lobbyId': lobbyId,
          'accessToken': accessToken,
          'seat': seat,
          'type': 'automated',
          'automatedDisplayName': 'Bot ${seat + 1}',
        }, authUserId: '00000000-0000-0000-0000-000000000001');
      }

      await _postJson(baseUri, 'start-match', <String, dynamic>{
        'lobbyId': lobbyId,
        'accessToken': accessToken,
      }, authUserId: '00000000-0000-0000-0000-000000000001');

      final lobbySnapshot = await _postJson(
        baseUri,
        'get-lobby',
        <String, dynamic>{'lobbyId': lobbyId, 'accessToken': accessToken},
        authUserId: '00000000-0000-0000-0000-000000000001',
      );
      final matchId = lobbySnapshot['matchId'] as String;

      final result = await _postJson(baseUri, 'heartbeat', <String, dynamic>{
        'matchId': matchId,
        'accessToken': accessToken,
      }, authUserId: '00000000-0000-0000-0000-000000000001');
      expect(result['ok'], isTrue);
    });

    test('list-games returns open lobbies', () async {
      await _postJson(baseUri, 'create-lobby', <String, dynamic>{
        'request': <String, dynamic>{
          'displayName': 'Host',
          'gameName': 'Test Game',
          'targetScore': 1000,
        },
      }, authUserId: '00000000-0000-0000-0000-000000000001');

      final result = await _postJson(
        baseUri,
        'list-games',
        <String, dynamic>{},
        authUserId: '00000000-0000-0000-0000-000000000001',
      );
      final games = result['games'] as List<dynamic>;
      expect(games, hasLength(1));
      final game = games.first as Map<String, dynamic>;
      expect(game['gameName'], 'Test Game');
      expect(game['hostDisplayName'], 'Host');
    });
  });
}

Future<Map<String, dynamic>> _postJson(
  final Uri baseUri,
  final String action,
  final Map<String, dynamic> body, {
  final String? authUserId,
}) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(baseUri.resolve(action));
    request.headers.contentType = ContentType.json;
    request.headers.set('x-tichu-proxy-secret', 'test-secret');
    if (authUserId != null) {
      request.headers.set('x-tichu-auth-user-id', authUserId);
    }
    request.write(jsonEncode(body));

    final response = await request.close();
    final responseBody = await utf8.decoder.bind(response).join();
    expect(response.statusCode, HttpStatus.ok, reason: responseBody);
    return Map<String, dynamic>.from(jsonDecode(responseBody) as Map);
  } finally {
    client.close();
  }
}
