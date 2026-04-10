import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:tichu/game/game_types.dart';
import 'package:tichu/services/local/local_table_service.dart';
import 'package:tichu/services/transport/dto/match_dto.dart' as match_dto;
import 'package:tichu/services/transport/dto/session_dto.dart' as session_dto;

class SupabaseAuthorityServer {
  SupabaseAuthorityServer({
    final LocalGameTableService? tableService,
    final String? proxySecret,
  }) : _tableService = tableService ?? LocalGameTableService(),
       _proxySecret = proxySecret;

  final LocalGameTableService _tableService;
  final String? _proxySecret;

  HttpServer? _server;

  Future<HttpServer> listen({
    final Object address = '127.0.0.1',
    final int port = 8081,
  }) async {
    final server = await HttpServer.bind(address, port);
    _server = server;
    unawaited(_serve(server));
    return server;
  }

  Future<void> close({final bool force = false}) async {
    await _server?.close(force: force);
    _server = null;
  }

  Future<void> _serve(final HttpServer server) async {
    await for (final request in server) {
      unawaited(_handleRequest(request));
    }
  }

  Future<void> _handleRequest(final HttpRequest request) async {
    try {
      _applyCorsHeaders(request.response);
      if (request.method == 'OPTIONS') {
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
        return;
      }

      if (!_isAuthorized(request)) {
        await _writeError(
          request.response,
          HttpStatus.unauthorized,
          'Missing or invalid proxy secret.',
        );
        return;
      }

      final action = request.uri.pathSegments.isEmpty
          ? ''
          : request.uri.pathSegments.last;
      if (request.method == 'GET' && action == 'health') {
        await _writeJson(request.response, <String, dynamic>{'status': 'ok'});
        return;
      }
      if (request.method != 'POST') {
        await _writeError(
          request.response,
          HttpStatus.methodNotAllowed,
          'Only POST requests are supported.',
        );
        return;
      }

      final body = await _readJsonBody(request);
      final response = await _dispatch(
        action,
        body,
        authUserId: request.headers.value('x-tichu-auth-user-id'),
      );
      await _writeJson(request.response, response);
    } on _ClientRequestError catch (error) {
      await _writeError(request.response, error.statusCode, error.message);
    } on StateError catch (error) {
      await _writeError(request.response, HttpStatus.badRequest, '$error');
    } on ArgumentError catch (error) {
      await _writeError(request.response, HttpStatus.badRequest, '$error');
    } on FormatException catch (error) {
      await _writeError(request.response, HttpStatus.badRequest, '$error');
    } catch (error) {
      await _writeError(
        request.response,
        HttpStatus.internalServerError,
        '$error',
      );
    }
  }

  bool _isAuthorized(final HttpRequest request) {
    final proxySecret = _proxySecret;
    if (proxySecret == null || proxySecret.isEmpty) {
      return true;
    }
    return request.headers.value('x-tichu-proxy-secret') == proxySecret;
  }

  Future<Map<String, dynamic>> _dispatch(
    final String action,
    final Map<String, dynamic> body, {
    final String? authUserId,
  }) async {
    switch (action) {
      case 'create-lobby':
        return _createLobby(body, authUserId: authUserId);
      case 'join-lobby':
        return _joinLobby(body, authUserId: authUserId);
      case 'list-games':
        return _listGames();
      case 'get-lobby':
        return _getLobby(body);
      case 'claim-seat':
        await _claimSeat(body);
        return const <String, dynamic>{'ok': true};
      case 'set-ready-state':
        await _setReadyState(body);
        return const <String, dynamic>{'ok': true};
      case 'start-match':
        await _startMatch(body);
        return const <String, dynamic>{'ok': true};
      case 'leave-lobby':
        await _leaveLobby(body);
        return const <String, dynamic>{'ok': true};
      case 'get-match-view':
        return _getMatchView(body);
      case 'get-match-connection':
        return _getMatchConnection(body);
      case 'submit-action':
        await _submitAction(body);
        return const <String, dynamic>{'ok': true};
      case 'acknowledge-round-summary':
        await _acknowledgeRoundSummary(body);
        return const <String, dynamic>{'ok': true};
      case 'leave-match':
        await _leaveMatch(body);
        return const <String, dynamic>{'ok': true};
      case 'heartbeat':
        await _heartbeat(body);
        return const <String, dynamic>{'ok': true};
      default:
        throw const _ClientRequestError(
          HttpStatus.notFound,
          'Unknown authority action.',
        );
    }
  }

  Future<Map<String, dynamic>> _createLobby(
    final Map<String, dynamic> body, {
    final String? authUserId,
  }) async {
    final resolvedAuthUserId = _requireAuthUserId(authUserId);
    final request = session_dto.CreateGameLobbyRequestDto.fromJson(
      _requireMap(body, 'request'),
    ).toDomain();
    final handle = await _tableService.createLobbyForAuthUser(
      request,
      authUserId: resolvedAuthUserId,
    );
    return session_dto.GameSessionHandleDto.fromDomain(handle).toJson();
  }

  Future<Map<String, dynamic>> _joinLobby(
    final Map<String, dynamic> body, {
    final String? authUserId,
  }) async {
    final resolvedAuthUserId = _requireAuthUserId(authUserId);
    final request = session_dto.JoinGameLobbyRequestDto.fromJson(
      _requireMap(body, 'request'),
    ).toDomain();
    final handle = await _tableService.joinLobbyForAuthUser(
      request,
      authUserId: resolvedAuthUserId,
    );
    return session_dto.GameSessionHandleDto.fromDomain(handle).toJson();
  }

  Future<Map<String, dynamic>> _listGames() async {
    final entries = await _tableService.listGames();
    return <String, dynamic>{
      'games': <Map<String, dynamic>>[
        for (final entry in entries)
          session_dto.GameLobbyListEntryDto.fromDomain(entry).toJson(),
      ],
    };
  }

  Future<Map<String, dynamic>> _getLobby(
    final Map<String, dynamic> body,
  ) async {
    final snapshot = await _tableService
        .watchLobby(
          _requireString(body, 'lobbyId'),
          accessToken: _requireString(body, 'accessToken'),
        )
        .first;
    return session_dto.GameLobbySnapshotDto.fromDomain(snapshot).toJson();
  }

  Future<void> _claimSeat(final Map<String, dynamic> body) {
    final typeName = (body['type'] as String?) ?? PlayerType.human.name;
    return _tableService.claimSeat(
      _requireString(body, 'lobbyId'),
      accessToken: _requireString(body, 'accessToken'),
      seat: _requireInt(body, 'seat'),
      type: PlayerType.values.byName(typeName),
      automatedDisplayName: body['automatedDisplayName'] as String?,
    );
  }

  Future<void> _setReadyState(final Map<String, dynamic> body) {
    return _tableService.setReadyState(
      _requireString(body, 'lobbyId'),
      accessToken: _requireString(body, 'accessToken'),
      isReady: _requireBool(body, 'isReady'),
    );
  }

  Future<void> _startMatch(final Map<String, dynamic> body) {
    return _tableService.startMatch(
      _requireString(body, 'lobbyId'),
      accessToken: _requireString(body, 'accessToken'),
    );
  }

  Future<void> _leaveLobby(final Map<String, dynamic> body) {
    return _tableService.leaveLobby(
      _requireString(body, 'lobbyId'),
      accessToken: _requireString(body, 'accessToken'),
    );
  }

  Future<Map<String, dynamic>> _getMatchView(
    final Map<String, dynamic> body,
  ) async {
    final view = await _tableService
        .watchMatch(
          _requireString(body, 'matchId'),
          accessToken: _requireString(body, 'accessToken'),
        )
        .first;
    return match_dto.GameMatchViewDto.fromDomain(view).toJson();
  }

  Future<Map<String, dynamic>> _getMatchConnection(
    final Map<String, dynamic> body,
  ) async {
    final snapshot = await _tableService
        .watchConnection(
          _requireString(body, 'matchId'),
          accessToken: _requireString(body, 'accessToken'),
        )
        .first;
    return match_dto.GameMatchConnectionSnapshotDto.fromDomain(
      snapshot,
    ).toJson();
  }

  Future<void> _submitAction(final Map<String, dynamic> body) {
    final submission = match_dto.GameActionSubmissionDto.fromJson(
      _requireMap(body, 'submission'),
    ).toDomain();
    return _tableService.submitAction(
      _requireString(body, 'matchId'),
      submission,
      accessToken: _requireString(body, 'accessToken'),
    );
  }

  Future<void> _acknowledgeRoundSummary(final Map<String, dynamic> body) {
    final acknowledgement = match_dto.RoundSummaryAcknowledgementDto.fromJson(
      _requireMap(body, 'acknowledgement'),
    ).toDomain();
    return _tableService.acknowledgeRoundSummary(
      _requireString(body, 'matchId'),
      acknowledgement,
      accessToken: _requireString(body, 'accessToken'),
    );
  }

  Future<void> _leaveMatch(final Map<String, dynamic> body) {
    return _tableService.leaveMatch(
      _requireString(body, 'matchId'),
      accessToken: _requireString(body, 'accessToken'),
    );
  }

  Future<void> _heartbeat(final Map<String, dynamic> body) {
    final accessToken = _requireString(body, 'accessToken');
    final lobbyId = body['lobbyId'] as String?;
    final matchId = body['matchId'] as String?;
    if (matchId != null && matchId.isNotEmpty) {
      return _tableService.sendMatchHeartbeat(
        matchId,
        accessToken: accessToken,
      );
    }
    if (lobbyId != null && lobbyId.isNotEmpty) {
      return _tableService.sendHeartbeat(lobbyId, accessToken: accessToken);
    }
    throw const _ClientRequestError(
      HttpStatus.badRequest,
      'heartbeat requires lobbyId or matchId.',
    );
  }

  Future<Map<String, dynamic>> _readJsonBody(final HttpRequest request) async {
    final rawBody = await utf8.decoder.bind(request).join();
    if (rawBody.trim().isEmpty) {
      return <String, dynamic>{};
    }
    final decoded = jsonDecode(rawBody);
    if (decoded is! Map) {
      throw const _ClientRequestError(
        HttpStatus.badRequest,
        'Request body must be a JSON object.',
      );
    }
    return Map<String, dynamic>.from(decoded);
  }

  Map<String, dynamic> _requireMap(
    final Map<String, dynamic> body,
    final String key,
  ) {
    final value = body[key];
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    throw _ClientRequestError(
      HttpStatus.badRequest,
      'Missing or invalid "$key" object.',
    );
  }

  String _requireString(final Map<String, dynamic> body, final String key) {
    final value = body[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw _ClientRequestError(
      HttpStatus.badRequest,
      'Missing or invalid "$key" string.',
    );
  }

  int _requireInt(final Map<String, dynamic> body, final String key) {
    final value = body[key];
    if (value is num) {
      return value.toInt();
    }
    throw _ClientRequestError(
      HttpStatus.badRequest,
      'Missing or invalid "$key" number.',
    );
  }

  bool _requireBool(final Map<String, dynamic> body, final String key) {
    final value = body[key];
    if (value is bool) {
      return value;
    }
    throw _ClientRequestError(
      HttpStatus.badRequest,
      'Missing or invalid "$key" boolean.',
    );
  }

  String _requireAuthUserId(final String? authUserId) {
    if (authUserId != null && authUserId.isNotEmpty) {
      return authUserId;
    }
    throw const _ClientRequestError(
      HttpStatus.unauthorized,
      'Missing authenticated Supabase user.',
    );
  }

  void _applyCorsHeaders(final HttpResponse response) {
    response.headers
      ..set(HttpHeaders.accessControlAllowOriginHeader, '*')
      ..set(HttpHeaders.accessControlAllowHeadersHeader, '*')
      ..set(HttpHeaders.accessControlAllowMethodsHeader, 'GET, POST, OPTIONS');
  }

  Future<void> _writeJson(
    final HttpResponse response,
    final Map<String, dynamic> payload,
  ) async {
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(payload));
    await response.close();
  }

  Future<void> _writeError(
    final HttpResponse response,
    final int statusCode,
    final String message,
  ) async {
    if (response.headers.value(HttpHeaders.contentTypeHeader) == null) {
      response.headers.contentType = ContentType.json;
    }
    response.statusCode = statusCode;
    response.write(jsonEncode(<String, dynamic>{'error': message}));
    await response.close();
  }
}

class _ClientRequestError implements Exception {
  const _ClientRequestError(this.statusCode, this.message);

  final int statusCode;
  final String message;
}
