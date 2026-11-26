import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_match.dart';
import 'package:tichu/services/local/local_match_runtime.dart';
import 'package:tichu/services/local/local_table_service.dart';
import 'package:tichu/services/request_rejected_exception.dart';

import 'local_table_fixtures.dart';

void main() {
  group('LocalGameTableService multiplayer contract', () {
    late StaticMultiplayerEngine engine;
    late LocalGameTableService service;

    setUp(() {
      engine = StaticMultiplayerEngine();
      service = LocalGameTableService(
        runtimeFactory: () => LocalMatchRuntime(engine: engine),
        projectionEngine: engine,
      );
    });

    test('streams player-specific match views for multiple humans', () async {
      final handles = await createHumanTable(service);
      final host = handles[0];
      final partner = handles[2];
      final matchId = host.matchId!;

      final hostView = await service
          .watchMatch(matchId, accessToken: host.accessToken)
          .first;
      final partnerView = await service
          .watchMatch(matchId, accessToken: partner.accessToken)
          .first;

      expect(hostView.selfPlayerId, host.playerId);
      expect(partnerView.selfPlayerId, partner.playerId);
      expect(hostView.snapshot.hand, isNotEmpty);
      expect(partnerView.snapshot.hand, isNotEmpty);
      expect(hostView.snapshot.hand, isNot(partnerView.snapshot.hand));
      expect(hostView.snapshot.players, hasLength(4));
      expect(partnerView.snapshot.opponentCardCounts[host.playerId], 1);
    });

    test(
      'rejects stale expected revisions after another player moves',
      () async {
        final handles = await createHumanTable(service);
        final host = handles[0];
        final nextPlayer = handles[1];
        final matchId = host.matchId!;

        final initialView = await service
            .watchMatch(matchId, accessToken: host.accessToken)
            .first;
        final staleRevision = initialView.revision;

        await service.submitAction(
          matchId,
          GameActionSubmission(
            clientActionId: 'host-pass-1',
            action: PassAction(playerId: host.playerId),
            expectedRevision: staleRevision,
          ),
          accessToken: host.accessToken,
        );

        final updatedView = await service
            .watchMatch(matchId, accessToken: nextPlayer.accessToken)
            .first;
        expect(updatedView.revision, greaterThan(staleRevision));

        await expectLater(
          () => service.submitAction(
            matchId,
            GameActionSubmission(
              clientActionId: 'next-pass-stale',
              action: PassAction(playerId: nextPlayer.playerId),
              expectedRevision: staleRevision,
            ),
            accessToken: nextPlayer.accessToken,
          ),
          throwsA(isA<RequestRejectedException>()),
        );
      },
    );

    test('deduplicates repeated client action ids', () async {
      final handles = await createHumanTable(service);
      final host = handles[0];
      final matchId = host.matchId!;

      final initialView = await service
          .watchMatch(matchId, accessToken: host.accessToken)
          .first;

      await service.submitAction(
        matchId,
        GameActionSubmission(
          clientActionId: 'retryable-pass',
          action: PassAction(playerId: host.playerId),
          expectedRevision: initialView.revision,
        ),
        accessToken: host.accessToken,
      );

      final afterFirstSubmit = await service
          .watchMatch(matchId, accessToken: host.accessToken)
          .first;

      await service.submitAction(
        matchId,
        GameActionSubmission(
          clientActionId: 'retryable-pass',
          action: PassAction(playerId: host.playerId),
          expectedRevision: initialView.revision,
        ),
        accessToken: host.accessToken,
      );

      final afterDuplicateSubmit = await service
          .watchMatch(matchId, accessToken: host.accessToken)
          .first;

      expect(afterFirstSubmit.revision, greaterThan(initialView.revision));
      expect(afterDuplicateSubmit.revision, afterFirstSubmit.revision);
    });
  });
}
