import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/nn/feature_encoder.dart';
import 'package:tichu/agents/nn/mlp.dart';
import 'package:tichu/agents/nn/value_model.dart';
import 'package:tichu/game/turn/tichu_data.dart';

import 'ai_test_fixtures.dart';
import 'feature_encoder_fixtures.dart';

void main() {
  test('value features: state features, then the true holders one-hot', () {
    final snap = fxSnapshot(
      mine: [c(CardFace.two), c(CardFace.ace)],
      others: {
        aiTestLeftId: [c(CardFace.king, CardColor.red)],
        aiTestPartnerId: [c(CardFace.dragon)],
        aiTestRightId: [c(CardFace.five, CardColor.green), c(CardFace.dog)],
      },
    );
    final x = encodeValueFeatures(snap, aiTestSelfId);
    expect(x.length, valueFeatureCount);
    expect(
      x.sublist(0, stateFeatureCount),
      encodeStateFeatures(snapshot: snap, playerId: aiTestSelfId),
    );
    final holders = x.sublist(stateFeatureCount);
    int at(Card card, int k) => cardSlot(card) * 3 + k;
    expect(holders[at(c(CardFace.king, CardColor.red), 0)], 1);
    expect(holders[at(c(CardFace.dragon), 1)], 1);
    expect(holders[at(c(CardFace.five, CardColor.green), 2)], 1);
    expect(holders[at(c(CardFace.dog), 2)], 1);
    // My own cards are in the state features, not among the holders.
    expect(holders.where((v) => v != 0).length, 4);
  });

  test('estimate: points scaled, heads are distributions', () {
    final model = ValueModel(
      Mlp(layerSizes: [valueFeatureCount, 8, valueOutputCount], seed: 3),
      scale: 50,
    );
    final snap = fxSnapshot(
      mine: [c(CardFace.two)],
      others: {
        aiTestLeftId: [c(CardFace.king)],
        aiTestPartnerId: [c(CardFace.dragon)],
        aiTestRightId: [c(CardFace.dog)],
      },
    );
    final e = model.estimate(snap, aiTestSelfId);
    final raw = model.network.predictAll(
      encodeValueFeatures(snap, aiTestSelfId),
    );
    expect(e.us, closeTo(raw[0] * 50, 1e-9));
    expect(e.them, closeTo(raw[1] * 50, 1e-9));
    expect(e.firstOut.reduce((a, b) => a + b), closeTo(1, 1e-9));
    expect(e.doubleWin.reduce((a, b) => a + b), closeTo(1, 1e-9));
  });

  test('rejects nets of the wrong shape', () {
    expect(
      () => ValueModel(Mlp(layerSizes: [stateFeatureCount, valueOutputCount])),
      throwsArgumentError,
    );
    expect(
      () => ValueModel(Mlp(layerSizes: [valueFeatureCount, 1])),
      throwsArgumentError,
    );
  });
}
