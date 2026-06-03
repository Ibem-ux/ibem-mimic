// lib/game/state/game_state.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

class Player {
  final String id;
  final String name;
  final int color;

  Player({
    required this.id,
    required this.name,
    required this.color,
  });

  Player copyWith({String? name}) {
    return Player(
      id: id,
      name: name ?? this.name,
      color: color,
    );
  }
}

class GameState {
  final List<Player> players;
  final int currentRound;
  final Map<String, int> scores;
  final String? mimicId;
  final String? currentWord;

  GameState({
    this.players = const [],
    this.currentRound = 0,
    this.scores = const {},
    this.mimicId,
    this.currentWord,
  });

  GameState copyWith({
    List<Player>? players,
    int? currentRound,
    Map<String, int>? scores,
    String? mimicId,
    String? currentWord,
  }) {
    return GameState(
      players: players ?? this.players,
      currentRound: currentRound ?? this.currentRound,
      scores: scores ?? this.scores,
      mimicId: mimicId ?? this.mimicId,
      currentWord: currentWord ?? this.currentWord,
    );
  }
}

class GameStateNotifier extends StateNotifier<GameState> {
  GameStateNotifier() : super(GameState());

  void addPlayer(String name, int color) {
    if (state.players.length >= 8) return;
    
    final newPlayer = Player(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      color: color,
    );
    
    state = state.copyWith(
      players: [...state.players, newPlayer],
      scores: {...state.scores, newPlayer.id: 0},
    );
  }

  void removePlayer(String playerId) {
    state = state.copyWith(
      players: state.players.where((p) => p.id != playerId).toList(),
      scores: Map.from(state.scores)..remove(playerId),
    );
    
    if (state.mimicId == playerId) {
      state = state.copyWith(mimicId: null);
    }
  }

  void updatePlayerName(String playerId, String name) {
    final updatedPlayers = state.players.map((p) {
      if (p.id == playerId) {
        return p.copyWith(name: name);
      }
      return p;
    }).toList();
    
    state = state.copyWith(players: updatedPlayers);
  }

  void assignMimic() {
    if (state.players.isEmpty) return;
    
    final random = DateTime.now().millisecondsSinceEpoch % state.players.length;
    final mimicPlayer = state.players[random];
    
    state = state.copyWith(mimicId: mimicPlayer.id);
  }

  void updateScore(String playerId, int score) {
    state = state.copyWith(
      scores: {...state.scores, playerId: score},
    );
  }

  void setCurrentWord(String word) {
    state = state.copyWith(currentWord: word);
  }

  void nextRound() {
    state = state.copyWith(currentRound: state.currentRound + 1);
  }

  void resetGame() {
    state = GameState();
  }
}

final gameStateProvider = StateNotifierProvider<GameStateNotifier, GameState>((ref) {
  return GameStateNotifier();
});