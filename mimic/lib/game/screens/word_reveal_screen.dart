// lib/game/screens/word_reveal_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/game_state.dart';

class WordRevealScreen extends ConsumerStatefulWidget {
  const WordRevealScreen({super.key});

  @override
  ConsumerState<WordRevealScreen> createState() => _WordRevealScreenState();
}

class _WordRevealScreenState extends ConsumerState<WordRevealScreen> {
  int _currentIndex = 0;
  bool _wordRevealed = false;
  Timer? _revealTimer;

  static const List<String> _realWords = [
    'Ocean',
    'Mountain',
    'Forest',
    'Desert',
    'River',
    'Castle',
    'Ocean',
    'Forest',
    'Castle',
    'Mountain',
  ];

  static const Map<String, String> _mimicWordMap = {
    'Ocean': 'Lake',
    'Mountain': 'Hill',
    'Forest': 'Grove',
    'Desert': 'Oasis',
    'River': 'Stream',
    'Castle': 'House',
  };

  @override
  void dispose() {
    _revealTimer?.cancel();
    super.dispose();
  }

  void _revealWord() {
    setState(() {
      _wordRevealed = true;
    });
    _revealTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _wordRevealed = false;
        });
      }
    });
  }

  void _nextPlayer() {
    _revealTimer?.cancel();
    final gameState = ref.read(gameStateProvider);
    if (_currentIndex < gameState.players.length - 1) {
      setState(() {
        _currentIndex++;
        _wordRevealed = false;
      });
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => const DiscussionScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final gameState = ref.watch(gameStateProvider);
    
    if (gameState.players.isEmpty) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F0F14),
        body: Center(child: Text('No players', style: TextStyle(color: Colors.white))),
      );
    }

    final currentPlayer = gameState.players[_currentIndex];
    final isMimic = currentPlayer.id == gameState.mimicId;
    final realWord = _realWords[_currentIndex % _realWords.length];
    final wordToShow = isMimic 
        ? _mimicWordMap[realWord] ?? 'Lake' 
        : realWord;

    final allPlayersViewed = _currentIndex >= gameState.players.length - 1 && !_wordRevealed;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          '${_currentIndex + 1}/${gameState.players.length}',
          style: const TextStyle(color: Color(0xFF7F77DD)),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              currentPlayer.name,
              style: const TextStyle(
                fontSize: 32,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 40),
            if (_wordRevealed)
              Text(
                wordToShow,
                style: const TextStyle(
                  fontSize: 48,
                  color: Color(0xFF7F77DD),
                  fontWeight: FontWeight.bold,
                ),
              )
            else
              Text(
                'Tap to reveal your word',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
            const SizedBox(height: 40),
            if (!_wordRevealed)
              ElevatedButton(
                onPressed: _revealWord,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7F77DD),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Reveal',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else
              ElevatedButton(
                onPressed: _nextPlayer,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7F77DD),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  allPlayersViewed ? 'Start Discussion' : 'Next Player',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class DiscussionScreen extends ConsumerStatefulWidget {
  const DiscussionScreen({super.key});

  @override
  ConsumerState<DiscussionScreen> createState() => _DiscussionScreenState();
}

class _DiscussionScreenState extends ConsumerState<DiscussionScreen> {
  late Timer _timer;
  int _secondsRemaining = 90;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() {
          _secondsRemaining--;
        });
      } else {
        timer.cancel();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const VotingScreen(),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String get _timeString {
    final minutes = _secondsRemaining ~/ 60;
    final seconds = _secondsRemaining % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final gameState = ref.watch(gameStateProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Discussion',
          style: TextStyle(color: Color(0xFF7F77DD)),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Text(
                _timeString,
                style: TextStyle(
                  fontSize: 72,
                  color: _secondsRemaining > 30 
                      ? const Color(0xFF7F77DD) 
                      : Colors.redAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.black26,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Players:',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: gameState.players.map((player) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Color(player.color).withOpacity(0.3),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        player.name,
                        style: const TextStyle(color: Colors.white),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class VotingScreen extends ConsumerWidget {
  const VotingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameState = ref.watch(gameStateProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Voting',
          style: TextStyle(color: Color(0xFF7F77DD)),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'Who do you think is the Mimic?',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: gameState.players.length,
                itemBuilder: (context, index) {
                  final player = gameState.players[index];
                  return ElevatedButton(
                    onPressed: () {
                      final isMimic = player.id == gameState.mimicId;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            isMimic 
                                ? 'Correct! ${player.name} was the Mimic!' 
                                : 'Wrong! ${player.name} was not the Mimic.',
                          ),
                          backgroundColor: isMimic 
                              ? const Color(0xFF1D9E75) 
                              : const Color(0xFFD85A30),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(player.color),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      player.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}