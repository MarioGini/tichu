import 'dart:async';
import 'dart:io';

import 'package:supabase/supabase.dart';
import 'package:tichu/services/local/local_table_service.dart';
import 'package:tichu/services/supabase/supabase_authority_server.dart';
import 'package:tichu/services/supabase/supabase_projection_schema_bootstrap.dart';
import 'package:tichu/services/supabase/supabase_table_projection_store.dart';

Future<void> main(final List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(_usage);
    return;
  }

  final host = _readStringArg(
    args,
    '--host',
    fallback:
        Platform.environment['TICHU_SUPABASE_AUTHORITY_HOST'] ?? '127.0.0.1',
  );
  final port = int.parse(
    _readStringArg(
      args,
      '--port',
      fallback: Platform.environment['TICHU_SUPABASE_AUTHORITY_PORT'] ?? '8081',
    ),
  );
  final proxySecret = _readOptionalStringArg(
    args,
    '--proxy-secret',
    fallback: Platform.environment['TICHU_AUTHORITY_PROXY_SECRET'],
  );

  final supabaseUrl = Platform.environment['SUPABASE_URL'];
  final supabaseServiceRoleKey =
      Platform.environment['SUPABASE_SERVICE_ROLE_KEY'];
  final supabaseDbUrl = Platform.environment['SUPABASE_DB_URL'];

  final tableService = LocalGameTableService(
    projectionStore: await _createProjectionStore(
      supabaseUrl: supabaseUrl,
      supabaseServiceRoleKey: supabaseServiceRoleKey,
      supabaseDbUrl: supabaseDbUrl,
    ),
  );

  final authorityServer = SupabaseAuthorityServer(
    proxySecret: proxySecret,
    tableService: tableService,
  );
  final server = await authorityServer.listen(address: host, port: port);

  stdout.writeln(
    'Tichu Supabase authority listening on '
    'http://${server.address.address}:${server.port}',
  );

  await Future.any(<Future<Object?>>[
    ProcessSignal.sigint.watch().first,
    ProcessSignal.sigterm.watch().first,
  ]);

  stdout.writeln('Shutting down authority server.');
  await authorityServer.close(force: true);
}

Future<SupabaseTableProjectionStore?> _createProjectionStore({
  required final String? supabaseUrl,
  required final String? supabaseServiceRoleKey,
  required final String? supabaseDbUrl,
}) async {
  if (supabaseUrl == null ||
      supabaseUrl.isEmpty ||
      supabaseServiceRoleKey == null ||
      supabaseServiceRoleKey.isEmpty) {
    return null;
  }

  if (supabaseDbUrl == null || supabaseDbUrl.isEmpty) {
    throw StateError(
      'SUPABASE_DB_URL is required when Postgres projection writes are enabled.',
    );
  }

  await SupabaseProjectionSchemaBootstrap(
    databaseUrl: supabaseDbUrl,
  ).ensureReady();

  return SupabaseTableProjectionStore(
    client: SupabaseClient(supabaseUrl, supabaseServiceRoleKey),
  );
}

String _readStringArg(
  final List<String> args,
  final String flag, {
  required final String fallback,
}) => _readOptionalStringArg(args, flag, fallback: fallback) ?? fallback;

String? _readOptionalStringArg(
  final List<String> args,
  final String flag, {
  final String? fallback,
}) {
  final flagIndex = args.indexOf(flag);
  if (flagIndex == -1) {
    return fallback;
  }
  if (flagIndex + 1 >= args.length) {
    throw ArgumentError('Missing value for $flag');
  }
  return args[flagIndex + 1];
}

const String _usage = '''
Run the local Tichu authority process used behind Supabase Edge Functions.

Usage:
  dart run tool/supabase_authority.dart [--host HOST] [--port PORT] [--proxy-secret SECRET]

Environment:
  TICHU_SUPABASE_AUTHORITY_HOST   Default host (default: 127.0.0.1)
  TICHU_SUPABASE_AUTHORITY_PORT   Default port (default: 8081)
  TICHU_AUTHORITY_PROXY_SECRET    Optional shared secret expected in x-tichu-proxy-secret
  SUPABASE_URL                    Optional Supabase project URL for Postgres projection writes
  SUPABASE_SERVICE_ROLE_KEY       Optional service-role key used by the authority to upsert view rows
  SUPABASE_DB_URL                 Direct Postgres URL used to bootstrap projection schema and RLS in code
''';
