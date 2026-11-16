import 'package:material_ui/material_ui.dart';
import 'package:tichu/game/game_session.dart';

/// What the create-game dialog returns.
class CreateGameResult {
  final String gameName;
  final int targetScore;
  final int preferredTeam;
  final GameLobbyVisibility visibility;

  const CreateGameResult({
    required this.gameName,
    required this.targetScore,
    required this.preferredTeam,
    required this.visibility,
  });
}

class CreateGameDialog extends StatefulWidget {
  const CreateGameDialog({super.key, required this.displayName});

  final String displayName;

  @override
  State<CreateGameDialog> createState() => _CreateGameDialogState();
}

class _CreateGameDialogState extends State<CreateGameDialog> {
  static const List<int> _scoreOptions = [500, 1000, 1500, 2000];

  late final TextEditingController _gameNameController = TextEditingController(
    text: "${widget.displayName}'s Game",
  );
  int _targetScore = 1000;
  int _preferredTeam = 0;
  GameLobbyVisibility _visibility = GameLobbyVisibility.public;

  @override
  void dispose() {
    _gameNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    final sliderValue = _scoreOptions.indexOf(_targetScore).toDouble();

    return AlertDialog(
      title: const Text('Create Game'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _gameNameController,
                decoration: const InputDecoration(
                  labelText: 'Game name',
                  hintText: 'Name your game',
                ),
              ),
              const SizedBox(height: 20),
              Text('Visibility', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<GameLobbyVisibility>(
                segments: const [
                  ButtonSegment<GameLobbyVisibility>(
                    value: GameLobbyVisibility.public,
                    label: Text('Public'),
                    icon: Icon(Icons.public),
                  ),
                  ButtonSegment<GameLobbyVisibility>(
                    value: GameLobbyVisibility.private,
                    label: Text('Private'),
                    icon: Icon(Icons.lock_outlined),
                  ),
                ],
                selected: <GameLobbyVisibility>{_visibility},
                showSelectedIcon: false,
                onSelectionChanged: (final selection) {
                  setState(() {
                    _visibility = selection.first;
                  });
                },
              ),
              if (_visibility == GameLobbyVisibility.private)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Private games need the join code to enter.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 20),
              Text(
                'Team preference',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment<int>(value: 0, label: Text('Team 1')),
                  ButtonSegment<int>(value: 1, label: Text('Team 2')),
                ],
                selected: <int>{_preferredTeam},
                showSelectedIcon: false,
                onSelectionChanged: (final selection) {
                  setState(() {
                    _preferredTeam = selection.first;
                  });
                },
              ),
              const SizedBox(height: 20),
              Text(
                'Match length',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text('First team to $_targetScore points'),
              Slider(
                value: sliderValue,
                max: (_scoreOptions.length - 1).toDouble(),
                divisions: _scoreOptions.length - 1,
                label: '$_targetScore',
                onChanged: (final value) {
                  setState(() {
                    _targetScore = _scoreOptions[value.round().clamp(0, 3)];
                  });
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              CreateGameResult(
                gameName: _gameNameController.text.trim(),
                targetScore: _targetScore,
                preferredTeam: _preferredTeam,
                visibility: _visibility,
              ),
            );
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}

class JoinPrivateDialog extends StatefulWidget {
  const JoinPrivateDialog({super.key});

  @override
  State<JoinPrivateDialog> createState() => _JoinPrivateDialogState();
}

class _JoinPrivateDialogState extends State<JoinPrivateDialog> {
  final TextEditingController _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) => AlertDialog(
    title: const Text('Join Private Game'),
    content: TextField(
      controller: _codeController,
      textCapitalization: TextCapitalization.characters,
      decoration: const InputDecoration(
        labelText: 'Join code',
        hintText: 'Enter the 5-digit game code',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final code = _codeController.text.trim().toUpperCase();
          Navigator.of(context).pop(code);
        },
        child: const Text('Join'),
      ),
    ],
  );
}
