// Renders the game screen at real phone sizes and writes PNGs, so layout
// changes can be checked visually without a device:
//
//   flutter test tool/ui_preview/phone_screens_test.dart --update-goldens
//
// Output: tool/ui_preview/out/<device>_<scene>.png (git-ignored).
// Not part of the normal test run (lives under tool/).
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/screens/game/game_screen.dart';
import 'package:tichu/theme/app_theme.dart';

import '../../test/utils/test_game_fixtures.dart';
import '../../test/utils/test_game_match_service.dart';

/// Logical size and device pixel ratio of common portrait phones.
const devices = <String, (Size, double)>{
  'small_360x780': (Size(360, 780), 3.0),
  'pixel7_412x915': (Size(412, 915), 2.625),
  'large_430x932': (Size(430, 932), 3.0),
};

final fullHand = [
  Card(CardFace.mahJong, CardColor.special),
  Card(CardFace.two, CardColor.red),
  Card(CardFace.three, CardColor.blue),
  Card(CardFace.five, CardColor.green),
  Card(CardFace.five, CardColor.black),
  Card(CardFace.seven, CardColor.red),
  Card(CardFace.eight, CardColor.blue),
  Card(CardFace.nine, CardColor.green),
  Card(CardFace.ten, CardColor.black),
  Card(CardFace.jack, CardColor.red),
  Card(CardFace.queen, CardColor.blue),
  Card(CardFace.king, CardColor.green),
  Card(CardFace.ace, CardColor.black),
  Card(CardFace.dragon, CardColor.special),
];

Future<void> loadFonts() async {
  const dir = '/opt/flutter/bin/cache/artifacts/material_fonts';
  final roboto = FontLoader('Roboto');
  for (final f in ['Roboto-Regular', 'Roboto-Medium', 'Roboto-Bold']) {
    final file = File('$dir/$f.ttf');
    if (file.existsSync()) {
      roboto.addFont(
        Future.value(ByteData.sublistView(file.readAsBytesSync())),
      );
    }
  }
  await roboto.load();
  final icons = File('$dir/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    await (FontLoader(
          'MaterialIcons',
        )..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync()))))
        .load();
  }
}

void main() {
  setUpAll(loadFonts);

  final scenes = <String, PlayerSnapshot Function()>{
    'play_lead': () => buildPlayerSnapshot(
      currentPlayerId: testHumanId,
      hand: fullHand,
      canCallTichu: true,
    ),
    'play_follow': () => buildPlayerSnapshot(
      currentPlayerId: testHumanId,
      hand: fullHand.sublist(0, 10),
      opponentCardCounts: const {
        testOpponentLeftId: 9,
        testOpponentPartnerId: 4,
        testOpponentRightId: 11,
      },
      lastPlayedBy: testOpponentRightId,
      lastPlayedTurn: TichuTurn(TurnType.pair, [
        Card(CardFace.eight, CardColor.red),
        Card(CardFace.eight, CardColor.green),
      ]),
      deck: DeckState(
        TichuTurn(TurnType.pair, [
          Card(CardFace.eight, CardColor.red),
          Card(CardFace.eight, CardColor.green),
        ]),
        CardFace.none,
      ),
      trickPoints: 15,
      scoreState: ScoreState.initial().copyWith(
        teamOneTotal: 340,
        teamTwoTotal: 285,
        roundNumber: 4,
        tichuCalls: const {testOpponentPartnerId: TichuCall.tichu},
      ),
    ),
    'schupf': () => buildPlayerSnapshot(
      phase: GamePhase.schupf,
      currentPlayerId: testHumanId,
      hand: fullHand,
    ),
  };

  for (final device in devices.entries) {
    for (final scene in scenes.entries) {
      testWidgets('${device.key} ${scene.key}', (final tester) async {
        final (size, dpr) = device.value;
        tester.view
          ..physicalSize = size * dpr
          ..devicePixelRatio = dpr;
        addTearDown(tester.view.reset);

        final backend = FakeGameMatchService();
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: ThemeMode.dark,
            home: GameScreen(
              matchService: backend,
              sessionHandle: backend.sessionHandle,
            ),
          ),
        );
        backend.emit(scene.value());
        await tester.pump();
        // Decode card images.
        await tester.runAsync(() async {
          for (final element in find.byType(Image).evaluate()) {
            final widget = element.widget as Image;
            await precacheImage(widget.image, element);
          }
        });
        await tester.pump(const Duration(milliseconds: 300));
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('out/${device.key}_${scene.key}.png'),
        );
      });
    }
  }
}
