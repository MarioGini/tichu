import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/services/sound_effects.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sound effects methods are callable without throwing', () async {
    await SoundEffects.playDog();
    await SoundEffects.playBomb();
  });
}
