import 'package:flutter/material.dart';
import 'package:tichu/game/player_control.dart';
import '../game/game_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const List<int> _scoreOptions = [500, 1000, 1500, 2000];
  int _targetScore = 1000;
  PlayerControlMode _selfControlMode = PlayerControlMode.manual;

  @override
  Widget build(BuildContext context) {
    final sliderValue = _scoreOptions.indexOf(_targetScore).toDouble();
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0B4A30), Color(0xFF0F5D3D), Color(0xFF134E4A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                margin: const EdgeInsets.all(24),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 32,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                        child: const Icon(
                          Icons.style,
                          size: 56,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Single Player Mode',
                        style: Theme.of(context).textTheme.headlineMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Play locally against three automated opponents and fine-tune your tactics.',
                        style: Theme.of(context).textTheme.bodyLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Match length',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'First team to $_targetScore points',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      Slider(
                        value: sliderValue,
                        min: 0,
                        max: (_scoreOptions.length - 1).toDouble(),
                        divisions: _scoreOptions.length - 1,
                        label: '$_targetScore',
                        onChanged: (value) {
                          setState(() {
                            _targetScore =
                                _scoreOptions[value.round().clamp(0, 3)];
                          });
                        },
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: _scoreOptions
                            .map(
                              (score) => Text(
                                score.toString(),
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 24),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Your player control',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<PlayerControlMode>(
                        segments: const [
                          ButtonSegment<PlayerControlMode>(
                            value: PlayerControlMode.manual,
                            label: Text('Manual'),
                            icon: Icon(Icons.person),
                          ),
                          ButtonSegment<PlayerControlMode>(
                            value: PlayerControlMode.ai,
                            label: Text('AI'),
                            icon: Icon(Icons.smart_toy),
                          ),
                        ],
                        selected: {_selfControlMode},
                        showSelectedIcon: false,
                        onSelectionChanged: (selection) {
                          final selected = selection.first;
                          setState(() {
                            _selfControlMode = selected;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _selfControlMode == PlayerControlMode.manual
                            ? 'You play manually; opponents are AI.'
                            : 'AI controls your seat too so you can watch full AI play.',
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => GameScreen(
                                  targetScore: _targetScore,
                                  playerControlModes: {
                                    'player-0': _selfControlMode,
                                  },
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Single Player Mode'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
