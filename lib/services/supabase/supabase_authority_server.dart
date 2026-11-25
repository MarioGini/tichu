import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:tichu/game/game_exceptions.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/services/local/local_table_service.dart';
import 'package:tichu/services/request_rejected_exception.dart';
import 'package:tichu/services/transport/dto/match_dto.dart' as match_dto;
import 'package:tichu/services/transport/dto/session_dto.dart' as session_dto;

part 'supabase_authority_handlers.dart';

class SupabaseAuthorityServer {
  SupabaseAuthorityServer({
    LocalGameTableService? tableService,
    this._proxySecret,
  }) : _tableService = tableService ?? LocalGameTableService();

  final LocalGameTableService _tableService;
  final String? _proxySecret;

  HttpServer? _server;

  Future<HttpServer> listen({
    Object address = '127.0.0.1',
    int port = 8081,
  }) async {
    final server = await HttpServer.bind(address, port);
    _server = server;
    unawaited(_serve(server));
    return server;
  }

  Future<void> close({bool force = false}) async {
    await _server?.close(force: force);
    _server = null;
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      unawaited(_handleRequest(request));
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
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
    } on IllegalActionException catch (error) {
      await _writeError(request.response, HttpStatus.badRequest, '$error');
    } on RequestRejectedException catch (error) {
      await _writeError(request.response, HttpStatus.badRequest, '$error');
    } on FormatException catch (error) {
      await _writeError(request.response, HttpStatus.badRequest, '$error');
    } on Object catch (error) {
      await _writeError(
        request.response,
        HttpStatus.internalServerError,
        '$error',
      );
    }
  }

  bool _isAuthorized(HttpRequest request) {
    final proxySecret = _proxySecret;
    if (proxySecret == null || proxySecret.isEmpty) {
      return true;
    }
    return request.headers.value('x-tichu-proxy-secret') == proxySecret;
  }

  Future<Map<String, dynamic>> _dispatch(
    String action,
    Map<String, dynamic> body, {
    String? authUserId,
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

  Future<Map<String, dynamic>> _readJsonBody(HttpRequest request) async {
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

  Map<String, dynamic> _requireMap(Map<String, dynamic> body, String key) {
    final value = body[key];
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    throw _ClientRequestError(
      HttpStatus.badRequest,
      'Missing or invalid "$key" object.',
    );
  }

  String _requireString(Map<String, dynamic> body, String key) {
    final value = body[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw _ClientRequestError(
      HttpStatus.badRequest,
      'Missing or invalid "$key" string.',
    );
  }

  int _requireInt(Map<String, dynamic> body, String key) {
    final value = body[key];
    if (value is num) {
      return value.toInt();
    }
    throw _ClientRequestError(
      HttpStatus.badRequest,
      'Missing or invalid "$key" number.',
    );
  }

  bool _requireBool(Map<String, dynamic> body, String key) {
    final value = body[key];
    if (value is bool) {
      return value;
    }
    throw _ClientRequestError(
      HttpStatus.badRequest,
      'Missing or invalid "$key" boolean.',
    );
  }

  String _requireAuthUserId(String? authUserId) {
    if (authUserId != null && authUserId.isNotEmpty) {
      return authUserId;
    }
    throw const _ClientRequestError(
      HttpStatus.unauthorized,
      'Missing authenticated Supabase user.',
    );
  }

  void _applyCorsHeaders(HttpResponse response) {
    response.headers
      ..set(HttpHeaders.accessControlAllowOriginHeader, '*')
      ..set(HttpHeaders.accessControlAllowHeadersHeader, '*')
      ..set(HttpHeaders.accessControlAllowMethodsHeader, 'GET, POST, OPTIONS');
  }

  Future<void> _writeJson(
    HttpResponse response,
    Map<String, dynamic> payload,
  ) async {
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(payload));
    await response.close();
  }

  Future<void> _writeError(
    HttpResponse response,
    int statusCode,
    String message,
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
