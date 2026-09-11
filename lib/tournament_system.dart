import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'utils/csv_downloader.dart';
import 'utils/widgets.dart';

class TournamentPanel extends StatefulWidget {
  final AppTheme theme;

  const TournamentPanel({super.key, required this.theme});

  @override
  State<TournamentPanel> createState() => _TournamentPanelState();
}

class _Player {
  final String id;
  final String name;
  int seed; // NEW: Seeding/ranking

  _Player(this.id, this.name, {this.seed = 0});
}

class _Match {
  final String id;
  final int group;
  final int round;
  final int slot;
  String? playerA;
  String? playerB;
  String? winnerId;
  int? scoreA; // NEW: Match scoring
  int? scoreB;
  String? notes; // NEW: Match notes

  _Match({
    required this.id,
    required this.group,
    required this.round,
    required this.slot,
    this.playerA,
    this.playerB,
  });

  bool get hasPlayers => playerA != null || playerB != null;
  bool get isComplete => winnerId != null;
}

enum _TournamentStatus { setup, running, paused, stopped, completed }

// NEW: Bracket types
enum BracketType { singleElimination, swiss }

class _SwissStanding {
  final _Player player;
  int wins = 0;
  int losses = 0;
  int pointsFor = 0;
  int pointsAgainst = 0;
  final List<String> history = [];

  _SwissStanding(this.player);

  int get matchPoints => wins * 3;
  int get pointDifference => pointsFor - pointsAgainst;
}

class _TournamentStageSnapshot {
  final BracketType type;
  final List<_Player> players;
  final List<_Match> matches;
  final List<String> history;
  final int round;
  final int rounds;
  final int bracketCount;
  final _TournamentStatus status;

  _TournamentStageSnapshot({
    required this.type,
    required this.players,
    required this.matches,
    required this.history,
    required this.round,
    required this.rounds,
    required this.bracketCount,
    required this.status,
  });
}

class _TournamentController extends ChangeNotifier {
  final Random _random = Random();
  final List<_Player> players = [];
  final List<_Match> matches = [];
  final List<_Match> archivedMatches = [];
  final Map<String, String> archivedPlayerNames = {};
  final List<String> history = [];
  Timer? _timer;
  int _seconds = 0;
  int bracketCount = 1;
  bool customMatching = false;
  _TournamentStatus status = _TournamentStatus.setup;
  bool showSeeding = true;
  BracketType bracketType = BracketType.singleElimination;
  String tournamentName = 'Tournament';
  int swissRounds = 3;
  int swissRound = 0;
  int swissAdvanceCount = 0;
  bool swissAdvanceConfigured = false;
  _TournamentStageSnapshot? _swissStage;
  _TournamentStageSnapshot? _singleEliminationStage;

  int get elapsedSeconds => _seconds;
  String get elapsedLabel {
    final minutes = (_seconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Map<String, _Player> get playerById => {
    for (final player in players) player.id: player,
  };

  // PERFORMANCE OPTIMIZED: Grouped matches for UI rendering
  List<List<_Match>> matchesForGroup(int group) {
    final grouped = <int, List<_Match>>{};
    
    // Use faster grouping with single pass
    for (final match in matches.where((match) => match.group == group)) {
      grouped.putIfAbsent(match.round, () => []).add(match);
    }
    
    // Only sort non-empty rounds (performance improvement)
    for (final entry in grouped.entries) {
      if (entry.value.isNotEmpty) {
        entry.value.sort((a, b) => a.slot.compareTo(b.slot));
      }
    }
    
    return grouped.values.toList();
  }

  bool get canClear => status == _TournamentStatus.setup;
  bool get hasBracket => matches.isNotEmpty;
  bool get hasExportData =>
      matches.isNotEmpty ||
      archivedMatches.isNotEmpty ||
      _swissStage != null ||
      _singleEliminationStage != null;
  bool get hasHistory => history.isNotEmpty;
  bool get isSwiss => bracketType == BracketType.swiss;
  bool get hasStageTabs =>
      _swissStage != null && _singleEliminationStage != null;
  bool get swissComplete =>
      isSwiss &&
      swissRound >= swissRounds &&
      matches
          .where((match) => match.group == 0)
          .every((match) => match.isComplete);
  // PERFORMANCE OPTIMIZED: Standings calculation with deduplication
  // List<_SwissStanding> get swissStandings {
  //   final standings = {
  //     for (final player in players) player.id: _SwissStanding(player),
  //   };
    
  //   // Pre-compute opponents only once for performance
  //   final opponents = <String, Set<String>>{};
  //   for (final match in matches.where((match) => match.group == 0)) {
  //     if (match.playerA != null && match.playerB != null) {
  //       opponents.putIfAbsent(match.playerA!, () => {}).add(match.playerB!);
  //       opponents.putIfAbsent(match.playerB!, () => {}).add(match.playerA!);
  //     }
  //   }
    
  //   // Only process completed matches (performance win for large brackets)
  //   final activeMatches = matches.where((match) => match.isComplete).toList();
    
  //   for (final match in activeMatches) {
  //     final winner = match.winnerId;
  //     if (winner == null) continue;
  //     final winnerStanding = standings[winner];
  //     if (winnerStanding == null) continue;
  //     final loser = match.playerA == winner ? match.playerB : match.playerA;
  //     final winnerScore = match.playerA == winner ? match.scoreA : match.scoreB;
  //     final loserScore = match.playerA == winner ? match.scoreB : match.scoreA;
      
  //     // Efficient update using mutable values (performance boost)
  //     if (winnerStanding.wins >= 0) { // Check before incrementing
  //       winnerStanding.wins++;
  //       winnerStanding.pointsFor += winnerScore ?? 1;
  //       winnerStanding.pointsAgainst += loserScore ?? 0;
  //       winnerStanding.history.add('W');
        
  //       if (loser != null && standings[loser] != null) {
  //         final loserStanding = standings[loser]!;
  //         if (loserStanding.wins >= 0) { // Check before incrementing
  //           loserStanding.losses++;
  //           loserStanding.pointsFor += loserScore ?? 0;
  //           loserStanding.pointsAgainst += winnerScore ?? 1;
  //           loserStanding.history.add('L');
  //         }
  //       }
  //     }
  //   }
    
  //   standings.values.toList().sort((a, b) {
  //     final byPoints = b.matchPoints.compareTo(a.matchPoints);
  //     if (byPoints != 0) return byPoints;
      
  //     // Cache Buchholz calculations to avoid duplicate computation
  //     final buchA = _buchholz(a, standings, opponents);
  //     final buchB = _buchholz(b, standings, opponents);
      
  //     final byBuchholz = buchA.compareTo(buchB);
  //     if (byBuchholz != 0) return byBuchholz;
      
  //     return b.pointDifference.compareTo(a.pointDifference);
  //   });
    
  //   // Return deduplicated results for UI performance
  //   // Note: .unique() is a String extension in Dart, not available for List<T>
  //   // Use a manual deduplication approach if needed
  //   final result = <_SwissStanding>[];
  //   var lastId = '';
  //   for (final standing in standings.values) {
  //     if (standing.player.id != lastId) {
  //       result.add(standing);
  //       lastId = standing.player.id;
  //     }
  //   }
  //   return result;
  // }
  List<_SwissStanding> get swissStandings {
  final standings = {
    for (final player in players) player.id: _SwissStanding(player),
  };

  // Pre-compute opponents only once
  final opponents = <String, Set<String>>{};
  for (final match in matches.where((match) => match.group == 0)) {
    if (match.playerA != null && match.playerB != null) {
      opponents.putIfAbsent(match.playerA!, () => {}).add(match.playerB!);
      opponents.putIfAbsent(match.playerB!, () => {}).add(match.playerA!);
    }
  }

  // Process only completed matches
  final activeMatches = matches.where((match) => match.isComplete).toList();
  for (final match in activeMatches) {
    final winner = match.winnerId;
    if (winner == null) continue;
    final winnerStanding = standings[winner];
    if (winnerStanding == null) continue;

    final loser = match.playerA == winner ? match.playerB : match.playerA;
    final winnerScore = match.playerA == winner ? match.scoreA : match.scoreB;
    final loserScore = match.playerA == winner ? match.scoreB : match.scoreA;

    // Update winner
    winnerStanding.wins++;
    winnerStanding.pointsFor += winnerScore ?? 1;
    winnerStanding.pointsAgainst += loserScore ?? 0;
    winnerStanding.history.add('W');

    // Update loser
    if (loser != null && standings[loser] != null) {
      final loserStanding = standings[loser]!;
      loserStanding.losses++;
      loserStanding.pointsFor += loserScore ?? 0;
      loserStanding.pointsAgainst += winnerScore ?? 1;
      loserStanding.history.add('L');
    }
  }

    // Copy standings into a list
    final allStandings = <_SwissStanding>[];
    for (final standing in standings.values) {
      allStandings.add(standing);
    }

    // ✅ Correct sort order
    allStandings.sort((a, b) {
      // 1. Match points (higher first)
      final byPoints = b.matchPoints.compareTo(a.matchPoints);
      if (byPoints != 0) return byPoints;

      // 2. Buchholz score (higher first)
      final buchA = _buchholz(a, standings, opponents);
      final buchB = _buchholz(b, standings, opponents);
      final byBuchholz = buchB.compareTo(buchA);
      if (byBuchholz != 0) return byBuchholz;

      // 3. Point difference (higher first)
      final diffA = a.pointDifference;
      final diffB = b.pointDifference;
      return diffB.compareTo(diffA);
    });

    // ✅ Return sorted list directly (no deduplication)
    return allStandings;
  }


  int _buchholz(
    _SwissStanding standing,
    Map<String, _SwissStanding> standings,
    Map<String, Set<String>> opponents,
  ) => (opponents[standing.player.id] ?? {})
      .map((id) => standings[id]?.matchPoints ?? 0)
      .fold(0, (sum, points) => sum + points);

  int buchholzFor(String playerId) {
    final standing = swissStandings.firstWhereOrNull(
      (item) => item.player.id == playerId,
    );
    if (standing == null) return 0;
    final opponents = <String, Set<String>>{};
    for (final match in matches.where((match) => match.group == 0)) {
      if (match.playerA != null && match.playerB != null) {
        opponents.putIfAbsent(match.playerA!, () => {}).add(match.playerB!);
        opponents.putIfAbsent(match.playerB!, () => {}).add(match.playerA!);
      }
    }
    final standings = {for (final item in swissStandings) item.player.id: item};
    return _buchholz(standing, standings, opponents);
  }

  bool get isComplete {
    if (matches.isEmpty) return false;
    if (isSwiss) return swissComplete;
    final finalMatches = matches.where(
      (match) => !matches.any(
        (other) => other.group == match.group && other.round == match.round + 1,
      ),
    );
    return finalMatches.isNotEmpty &&
        finalMatches.every((match) => match.isComplete);
  }

  void addPlayer(String rawName) {
    final name = rawName.trim();
    if (name.isEmpty || players.length >= 150) return;
    if (players.any(
      (player) => player.name.toLowerCase() == name.toLowerCase(),
    )) {
      return;
    }
    players.add(
      _Player(
        '${DateTime.now().microsecondsSinceEpoch}-${players.length}',
        name,
        seed: players.length + 1, // NEW: Auto-seed on add
      ),
    );
    if (isSwiss && !swissAdvanceConfigured) {
      swissAdvanceCount = max(2, (players.length / 2).ceil());
    }
    _resetBracketIfSetup();
    notifyListeners();
  }

  void addPlayers(Iterable<String> names) {
    for (final name in names) {
      if (players.length >= 150) break;
      addPlayer(name);
    }
  }

  void generateNumberedPlayers(int count) {
    if (!canClear) return;
    final total = count.clamp(2, 150);
    players
      ..clear()
      ..addAll(
        List.generate(
          total,
          (index) => _Player(
            'numbered-${DateTime.now().microsecondsSinceEpoch}-$index',
            'Player ${index + 1}',
            seed: index + 1,
          ),
        ),
      );
    matches.clear();
    history.clear();
    if (isSwiss && !swissAdvanceConfigured) {
      swissAdvanceCount = max(2, (players.length / 2).ceil());
    }
    notifyListeners();
  }

  void removePlayer(String id) {
    if (status != _TournamentStatus.setup) return;
    players.removeWhere((player) => player.id == id);
    _resetBracketIfSetup();
    notifyListeners();
  }

  void clearRoster() {
    if (!canClear) return;
    players.clear();
    matches.clear();
    archivedMatches.clear();
    archivedPlayerNames.clear();
    history.clear();
    swissRound = 0;
    swissAdvanceCount = 0;
    swissAdvanceConfigured = false;
    _swissStage = null;
    _singleEliminationStage = null;
    notifyListeners();
  }

  void setBracketCount(int value) {
    bracketCount = value.clamp(1, max(1, players.length));
    if (status == _TournamentStatus.setup && players.length >= 2) {
      generateBracket();
    }
    notifyListeners();
  }

  void setCustomMatching(bool value) {
    if (status != _TournamentStatus.setup) return;
    customMatching = value;
    notifyListeners();
  }

  void setBracketType(BracketType type) {
    if (status != _TournamentStatus.setup) return;
    bracketType = type;
    if (type == BracketType.swiss) {
      swissAdvanceCount = max(2, (players.length / 2).ceil());
      swissAdvanceConfigured = false;
    }
    if (players.length >= 2) {
      generateBracket();
    }
    notifyListeners();
  }

  void setSwissRounds(int value) {
    if (!canClear) return;
    swissRounds = value.clamp(1, 10);
    if (isSwiss && players.length >= 2) generateBracket();
    notifyListeners();
  }

  void setSwissAdvanceCount(int value) {
    if (!canClear) return;
    swissAdvanceCount = value.clamp(2, max(2, players.length));
    swissAdvanceConfigured = true;
    notifyListeners();
  }

  void setTournamentName(String value) {
    tournamentName = value.trim().isEmpty ? 'Tournament' : value.trim();
    notifyListeners();
  }

  // NEW: Randomize seeding instead of relying on input order.
  // Shuffles the seed values assigned to each player, then rebuilds the
  // bracket using the new (randomized) seed order. The players list itself
  // (and therefore roster chip order) is left untouched — only the seed,
  // and thus bracket placement, is randomized.
  void randomizeSeeding() {
    if (status != _TournamentStatus.setup) return;
    final shuffled = [...players]..shuffle(_random);
    for (var i = 0; i < shuffled.length; i++) {
      shuffled[i].seed = i + 1;
    }
    if (players.length >= 2) {
      generateBracket();
    }
    notifyListeners();
  }

  void generateBracket({List<_Player>? source}) {
    if (status != _TournamentStatus.setup || (source ?? players).length < 2)
      return;
    if (isSwiss && source == null) {
      matches.clear();
      swissRound = 1;
      generateSwissRound();
      return;
    }
    
    // Performance optimization: use more efficient clear
    final oldMatches = List<_Match>.from(matches);
    matches.clear();
    final roster = [...(source ?? players)];

    // Sort by seed (randomized via randomizeSeeding(), or sequential by
    // default if the user hasn't randomized yet).
    roster.sort((a, b) => a.seed.compareTo(b.seed));

    final groupTotal = min(bracketCount, roster.length);
    final groupSize = max(20, (roster.length / groupTotal).ceil());
    var cursor = 0;

    // Performance: track matches by list for faster operations
    final groupMatches = <List<_Match>>[];
    
    for (var group = 0; group < groupTotal; group++) {
      final groupPlayers = roster.sublist(
        cursor,
        min(cursor + groupSize, roster.length),
      );
      cursor += groupPlayers.length;
      if (groupPlayers.isEmpty) continue;
      final slotCount = _nextPowerOfTwo(groupPlayers.length);
      final roundCount = max(1, log(slotCount) ~/ log(2));
      final slots = List<String?>.filled(slotCount, null);
      var playerCursor = 0;
      var matchCursor = 0;

      if (groupPlayers.length.isOdd) {
        slots[0] = groupPlayers[playerCursor++].id;
        matchCursor++;
      }
      while (playerCursor < groupPlayers.length) {
        slots[matchCursor * 2] = groupPlayers[playerCursor++].id;
        slots[matchCursor * 2 + 1] = groupPlayers[playerCursor++].id;
        matchCursor++;
      }
      for (var round = 0; round < roundCount; round++) {
        final matchCount = slotCount ~/ pow(2, round).toInt() ~/ 2;
        for (var slot = 0; slot < matchCount; slot++) {
          matches.add(
            _Match(
              id: 'g$group-r$round-m$slot',
              group: group,
              round: round,
              slot: slot,
              playerA: round == 0 ? slots[slot * 2] : null,
              playerB: round == 0 ? slots[slot * 2 + 1] : null,
            ),
          );
        }
      }
    }
    _resolveByes();
    
    // Archive old matches more efficiently - copy once
    archivedMatches.addAll(oldMatches);
    history.add(
      'Generated ${players.length} players across $groupTotal bracket${groupTotal == 1 ? '' : 's'}.',
    );
    notifyListeners();
  }

  void generateSwissRound() {
    if (!isSwiss || players.length < 2) return;
    final ordered = swissRound == 1
        ? ([...players]..sort((a, b) => a.seed.compareTo(b.seed)))
        : swissStandings.map((standing) => standing.player).toList();
    final used = <String>{};
    for (var index = 0; index < ordered.length; index++) {
      if (used.contains(ordered[index].id)) continue;
      final first = ordered[index];
      var opponentIndex = index + 1;
      while (opponentIndex < ordered.length &&
          (used.contains(ordered[opponentIndex].id) ||
              _hasPlayed(first.id, ordered[opponentIndex].id))) {
        opponentIndex++;
      }
      if (opponentIndex >= ordered.length) {
        opponentIndex = index + 1;
        while (opponentIndex < ordered.length &&
            used.contains(ordered[opponentIndex].id)) {
          opponentIndex++;
        }
      }
      if (opponentIndex >= ordered.length) break;
      final opponent = ordered[opponentIndex];
      used.add(first.id);
      used.add(opponent.id);
      matches.add(
        _Match(
          id: 'swiss-r$swissRound-m${matches.length}',
          group: 0,
          round: swissRound,
          slot: matches.length,
          playerA: first.id,
          playerB: opponent.id,
        ),
      );
    }
    final bye = ordered
        .where((player) => !used.contains(player.id))
        .firstOrNull;
    if (bye != null) {
      matches.add(
        _Match(
            id: 'swiss-r$swissRound-bye',
            group: 0,
            round: swissRound,
            slot: matches.length,
            playerA: bye.id,
          )
          ..winnerId = bye.id
          ..scoreA = 1
          ..scoreB = 0,
      );
    }
    history.add('Generated Swiss round $swissRound of $swissRounds.');
    notifyListeners();
  }

  bool _hasPlayed(String first, String second) => matches.any(
    (match) =>
        (match.playerA == first && match.playerB == second) ||
        (match.playerA == second && match.playerB == first),
  );

  void start() {
    if (players.length < 2 ||
        matches.isEmpty ||
        status == _TournamentStatus.running)
      return;
    status = _TournamentStatus.running;
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (status == _TournamentStatus.running) {
        _seconds++;
        notifyListeners();
      }
    });
    notifyListeners();
  }

  void pause() {
    if (status != _TournamentStatus.running) return;
    status = _TournamentStatus.paused;
    notifyListeners();
  }

  Future<void> stop() async {
    if (status != _TournamentStatus.running &&
        status != _TournamentStatus.paused) {
      return;
    }
    _timer?.cancel();
    _timer = null;
    status = _TournamentStatus.stopped;
    _syncActiveStageSnapshot();
    notifyListeners();
  }

  void finish() {
    _timer?.cancel();
    _timer = null;
    status = _TournamentStatus.completed;
    notifyListeners();
  }

  void startNewTournament() {
    _timer?.cancel();
    _timer = null;
    players.clear();
    matches.clear();
    archivedMatches.clear();
    archivedPlayerNames.clear();
    history.clear();
    _swissStage = null;
    _singleEliminationStage = null;
    customMatching = false;
    bracketType = BracketType.singleElimination;
    bracketCount = 1;
    swissRound = 0;
    swissAdvanceCount = 0;
    swissAdvanceConfigured = false;
    _seconds = 0;
    status = _TournamentStatus.setup;
    notifyListeners();
  }

  void placePlayer(String playerId, String matchId, int slot) {
    if (status != _TournamentStatus.setup || !customMatching) return;
    final target = matches.firstWhere((match) => match.id == matchId);
    if (target.round != 0) return;
    final current = _matchContaining(playerId);
    if (current == null) return;
    final oldSlot = current.playerA == playerId ? 0 : 1;
    final targetPlayer = slot == 0 ? target.playerA : target.playerB;
    _setSlot(current, oldSlot, targetPlayer);
    _setSlot(target, slot, playerId);
    notifyListeners();
  }

  void chooseWinner(String matchId, String playerId) {
    if (status != _TournamentStatus.running &&
        status != _TournamentStatus.paused)
      return;
    final match = matches.firstWhere((item) => item.id == matchId);
    if (isSwiss) {
      recordSwissResult(matchId, playerId, 1, 0);
      return;
    }
    if (match.playerA != playerId && match.playerB != playerId) return;
    if (match.winnerId != null) return;
    if (match.winnerId == playerId) return;
    match.winnerId = playerId;
    final loser = match.playerA == playerId ? match.playerB : match.playerA;
    history.add(
      '${_name(playerId)} won ${match.id}${loser == null ? ' by bye' : ' over ${_name(loser)}'}.',
    );
    final next = matches.firstWhereOrNull(
      (item) =>
          item.group == match.group &&
          item.round == match.round + 1 &&
          item.slot == match.slot ~/ 2,
    );
    if (next != null) {
      _setSlot(next, match.slot.isEven ? 0 : 1, playerId);
    }
    _resolveByes();
    _syncActiveStageSnapshot();
    notifyListeners();
  }

  void recordSwissResult(
    String matchId,
    String winnerId,
    int winnerScore,
    int loserScore,
  ) {
    if (!isSwiss ||
        (status != _TournamentStatus.running &&
            status != _TournamentStatus.paused))
      return;
    final match = matches.firstWhere((item) => item.id == matchId);
    if (match.winnerId != null ||
        (match.playerA != winnerId && match.playerB != winnerId))
      return;
    final winnerIsA = match.playerA == winnerId;
    match.winnerId = winnerId;
    match.scoreA = winnerIsA ? winnerScore : loserScore;
    match.scoreB = winnerIsA ? loserScore : winnerScore;
    history.add('${_name(winnerId)} won Swiss round ${match.round}.');
    final currentRound = matches.where(
      (item) => item.group == 0 && item.round == swissRound,
    );
    if (currentRound.isNotEmpty &&
        currentRound.every((item) => item.isComplete)) {
      if (swissRound < swissRounds) {
        swissRound++;
        generateSwissRound();
      } else {
        status = _TournamentStatus.stopped;
      }
    }
    _syncActiveStageSnapshot();
    notifyListeners();
  }

  void startSingleEliminationFromSwiss() {
    if (!swissComplete) return;
    _swissStage = _captureStage();
    final count = swissAdvanceCount.clamp(2, players.length);
    final winners = swissStandings
        .take(count)
        .map((standing) => standing.player)
        .toList();
    for (final player in players) {
      archivedPlayerNames[player.id] = player.name;
    }
    archivedMatches.addAll(matches);
    players
      ..clear()
      ..addAll(winners);
    for (var index = 0; index < players.length; index++) {
      players[index].seed = index + 1;
    }
    matches.clear();
    history.clear();
    history.add('Started single elimination with $count Swiss qualifiers.');
    bracketType = BracketType.singleElimination;
    bracketCount = 1;
    swissRound = 0;
    status = _TournamentStatus.setup;
    generateBracket(source: players);
    start();
    _singleEliminationStage = _captureStage();
  }

  void switchStage(BracketType type) {
    if (!hasStageTabs || type == bracketType) return;
    if (type == BracketType.swiss) {
      _singleEliminationStage = _captureStage();
      _restoreStage(_swissStage!);
    } else {
      _swissStage = _captureStage();
      _restoreStage(_singleEliminationStage!);
    }
    notifyListeners();
  }

  _TournamentStageSnapshot _captureStage() {
    return _TournamentStageSnapshot(
      type: bracketType,
      players: players.map(_copyPlayer).toList(),
      matches: matches.map(_copyMatch).toList(),
      history: List<String>.from(history),
      round: swissRound,
      rounds: swissRounds,
      bracketCount: bracketCount,
      status: status,
    );
  }

  void _restoreStage(_TournamentStageSnapshot snapshot) {
    bracketType = snapshot.type;
    players
      ..clear()
      ..addAll(snapshot.players.map(_copyPlayer));
    matches
      ..clear()
      ..addAll(snapshot.matches.map(_copyMatch));
    history
      ..clear()
      ..addAll(snapshot.history);
    swissRound = snapshot.round;
    swissRounds = snapshot.rounds;
    bracketCount = snapshot.bracketCount;
    status = snapshot.status;
  }

  void _syncActiveStageSnapshot() {
    if (!hasStageTabs) return;
    if (isSwiss) {
      _swissStage = _captureStage();
    } else {
      _singleEliminationStage = _captureStage();
    }
  }

  _Player _copyPlayer(_Player player) =>
      _Player(player.id, player.name, seed: player.seed);

  _Match _copyMatch(_Match match) =>
      _Match(
          id: match.id,
          group: match.group,
          round: match.round,
          slot: match.slot,
          playerA: match.playerA,
          playerB: match.playerB,
        )
        ..winnerId = match.winnerId
        ..scoreA = match.scoreA
        ..scoreB = match.scoreB
        ..notes = match.notes;

  // NEW: Set match score
  void setScore(String matchId, int? scoreA, int? scoreB) {
    final match = matches.firstWhere((item) => item.id == matchId);
    match.scoreA = scoreA;
    match.scoreB = scoreB;
    // Performance: Only rebuild if score changes affect visible standings
    notifyListeners();
  }

  // NEW: Set match notes
  void setNotes(String matchId, String notes) {
    final match = matches.firstWhere((item) => item.id == matchId);
    match.notes = notes.isNotEmpty ? notes : null;
    notifyListeners();
  }

  void dropWinner(String playerId, String targetMatchId) {
    if (status != _TournamentStatus.running &&
        status != _TournamentStatus.paused)
      return;
    final target = matches.firstWhere((match) => match.id == targetMatchId);
    final source = _matchContaining(playerId);
    if (source == null ||
        source.round >= target.round ||
        source.winnerId != null)
      return;
    chooseWinner(source.id, playerId);
  }

  List<_Player> get finalWinners {
    final result = <_Player>[];
    for (final group in matches.map((match) => match.group).toSet()) {
      final groupMatches = matches.where((match) => match.group == group);
      final finalMatch = groupMatches.reduce(
        (a, b) => a.round > b.round ? a : b,
      );
      if (finalMatch.winnerId != null)
        result.add(playerById[finalMatch.winnerId]!);
    }
    return result;
  }

  void reseedWinners() {
    final winners = finalWinners;
    if (winners.length < 2) return;
    players
      ..clear()
      ..addAll(winners);
    status = _TournamentStatus.setup;
    customMatching = false;
    _seconds = 0;
    generateBracket(source: winners);
  }

  Future<void> importRoster() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'json', 'txt'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;
    final text = String.fromCharCodes(result.files.single.bytes!);
    if (text.startsWith('type,tournament_name,format')) {
      _restoreCsv(text);
      return;
    }
    final names = _parseRoster(text, result.files.single.extension ?? '');
    addPlayers(names);
  }

  Future<void> exportCsv() async {
    final now = DateTime.now();
    final timestamp =
        '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    await downloadCsv(
      '${_safeFileName(tournamentName)}-$timestamp.csv',
      Uint8List.fromList(utf8.encode(_csvContent())),
    );
  }

  String _safeFileName(String value) => value
      .trim()
      .replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_');

  String _csvContent() {
    final rows = <List<String>>[
      [
        'type',
        'tournament_name',
        'format',
        'round',
        'match_id',
        'player_a',
        'player_b',
        'winner',
        'score_a',
        'score_b',
        'seed',
        'stage',
      ],
    ];
    for (final stage in _stagesForExport()) {
      final stageName = stage.type.name;
      final names = {
        for (final player in stage.players) player.id: player.name,
      };
      for (final player in stage.players) {
        rows.add([
          'player',
          tournamentName,
          stageName,
          '',
          '',
          player.name,
          '',
          '',
          '',
          '',
          '${player.seed}',
          stageName,
        ]);
      }
      for (final match in stage.matches) {
        rows.add([
          'match',
          tournamentName,
          stageName,
          '${match.round}',
          match.id,
          names[match.playerA] ?? '',
          names[match.playerB] ?? '',
          names[match.winnerId] ?? '',
          '${match.scoreA ?? ''}',
          '${match.scoreB ?? ''}',
          '',
          stageName,
        ]);
      }
      for (final entry in stage.history) {
        rows.add([
          'history',
          tournamentName,
          stageName,
          '',
          '',
          entry,
          '',
          '',
          '',
          '',
          '',
          stageName,
        ]);
      }
    }
    return rows.map((row) => row.map(_csvValue).join(',')).join('\n');
  }

  List<_TournamentStageSnapshot> _stagesForExport() {
    final current = _captureStage();
    if (isSwiss) {
      return [
        current,
        if (_singleEliminationStage != null) _singleEliminationStage!,
      ];
    }
    return [if (_swissStage != null) _swissStage!, current];
  }

  String _csvValue(String value) {
    final escaped = value.replaceAll('"', '""');
    return escaped.contains(',') ||
            escaped.contains('"') ||
            escaped.contains('\n')
        ? '"$escaped"'
        : escaped;
  }

  String _csvPlayerName(String? id) =>
      id == null ? '' : playerById[id]?.name ?? archivedPlayerNames[id] ?? '';

  void _restoreCsv(String text) {
    final rows = const LineSplitter()
        .convert(text)
        .skip(1)
        .map(_parseCsvRow)
        .toList();
    players.clear();
    matches.clear();
    archivedMatches.clear();
    archivedPlayerNames.clear();
    _swissStage = null;
    _singleEliminationStage = null;
    final stagePlayers = <String, List<_Player>>{};
    final stageIds = <String, Map<String, String>>{};
    final stageMatches = <String, List<_Match>>{};
    final stageHistory = <String, List<String>>{};
    final stageIndexes = <String, int>{};
    for (final row in rows) {
      if (row.length < 11) continue;
      tournamentName = row[1].isEmpty ? 'Tournament' : row[1];
      final stage = row.length > 11 && row[11].isNotEmpty ? row[11] : row[2];
      final type = stage == BracketType.swiss.name
          ? BracketType.swiss
          : BracketType.singleElimination;
      final stageKey = type.name;
      stagePlayers.putIfAbsent(stageKey, () => []);
      stageIds.putIfAbsent(stageKey, () => {});
      stageHistory.putIfAbsent(stageKey, () => []);
      if (row[0] == 'history' && row[5].isNotEmpty) {
        stageHistory[stageKey]!.add(row[5]);
      }
      if (row[0] == 'player' && row[5].isNotEmpty) {
        final index = stageIndexes.update(
          stageKey,
          (value) => value + 1,
          ifAbsent: () => 0,
        );
        final id = '$stageKey-imported-$index';
        stageIds[stageKey]![row[5]] = id;
        stagePlayers[stageKey]!.add(
          _Player(id, row[5], seed: int.tryParse(row[10]) ?? index + 1),
        );
      }
    }
    for (final row in rows) {
      if (row.length < 11 || row[0] != 'match') continue;
      final stage = row.length > 11 && row[11].isNotEmpty ? row[11] : row[2];
      final type = stage == BracketType.swiss.name
          ? BracketType.swiss
          : BracketType.singleElimination;
      final stageKey = type.name;
      final ids = stageIds[stageKey] ?? {};
      final match =
          _Match(
              id: row[4],
              group: 0,
              round: int.tryParse(row[3]) ?? 0,
              slot: stageMatches[stageKey]?.length ?? 0,
              playerA: ids[row[5]],
              playerB: ids[row[6]],
            )
            ..winnerId = ids[row[7]]
            ..scoreA = int.tryParse(row[8])
            ..scoreB = int.tryParse(row[9]);
      stageMatches.putIfAbsent(stageKey, () => []).add(match);
    }
    for (final type in BracketType.values) {
      final key = type.name;
      final stage = _TournamentStageSnapshot(
        type: type,
        players: stagePlayers[key] ?? [],
        matches: stageMatches[key] ?? [],
        history: stageHistory[key] ?? [],
        round: type == BracketType.swiss
            ? max(
                1,
                (stageMatches[key] ?? [])
                    .map((match) => match.round)
                    .fold(0, max),
              )
            : 0,
        rounds: type == BracketType.swiss
            ? max(
                1,
                (stageMatches[key] ?? [])
                    .map((match) => match.round)
                    .fold(0, max),
              )
            : 1,
        bracketCount: 1,
        status: _TournamentStatus.stopped,
      );
      if (type == BracketType.swiss && stage.players.isNotEmpty) {
        _swissStage = stage;
      }
      if (type == BracketType.singleElimination && stage.players.isNotEmpty) {
        _singleEliminationStage = stage;
      }
    }
    if (_singleEliminationStage != null) {
      _restoreStage(_singleEliminationStage!);
    } else if (_swissStage != null) {
      _restoreStage(_swissStage!);
    }
    swissAdvanceCount = max(2, (players.length / 2).ceil());
    notifyListeners();
  }

  List<String> _parseCsvRow(String line) {
    final values = <String>[];
    final buffer = StringBuffer();
    var quoted = false;
    for (var index = 0; index < line.length; index++) {
      final char = line[index];
      if (char == '"') {
        if (quoted && index + 1 < line.length && line[index + 1] == '"') {
          buffer.write('"');
          index++;
        } else {
          quoted = !quoted;
        }
      } else if (char == ',' && !quoted) {
        values.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    values.add(buffer.toString());
    return values;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _resetBracketIfSetup() {
    if (status == _TournamentStatus.setup) matches.clear();
  }

  void _resolveByes() {
    var changed = true;
    while (changed) {
      changed = false;
      for (final match in matches) {
        if (match.winnerId != null || !match.hasPlayers) continue;
        if (match.playerA != null && match.playerB != null) continue;

        if (match.round > 0) {
          final feederMatches = matches.where(
            (feeder) =>
                feeder.group == match.group &&
                feeder.round == match.round - 1 &&
                (feeder.slot == match.slot * 2 ||
                    feeder.slot == match.slot * 2 + 1),
          );
          if (feederMatches.length != 2 ||
              feederMatches.any((feeder) => !_branchResolved(feeder))) {
            continue;
          }
        }

        match.winnerId = match.playerA ?? match.playerB;
        final next = matches.firstWhereOrNull(
          (item) =>
              item.group == match.group &&
              item.round == match.round + 1 &&
              item.slot == match.slot ~/ 2,
        );
        if (next != null && match.winnerId != null) {
          _setSlot(next, match.slot.isEven ? 0 : 1, match.winnerId!);
        }
        changed = true;
      }
    }
  }

  bool _branchResolved(_Match match) {
    if (match.winnerId != null) return true;
    if (match.hasPlayers) return false;
    if (match.round == 0) return true;

    final feederMatches = matches.where(
      (feeder) =>
          feeder.group == match.group &&
          feeder.round == match.round - 1 &&
          (feeder.slot == match.slot * 2 || feeder.slot == match.slot * 2 + 1),
    );
    return feederMatches.length == 2 && feederMatches.every(_branchResolved);
  }

  _Match? _matchContaining(String playerId) {
    for (final match in matches) {
      if (match.round == 0 &&
          (match.playerA == playerId || match.playerB == playerId))
        return match;
    }
    return null;
  }

  void _setSlot(_Match match, int slot, String? value) {
    if (slot == 0) {
      match.playerA = value;
    } else {
      match.playerB = value;
    }
  }

  String _name(String id) => playerById[id]?.name ?? 'Unknown player';

  int _nextPowerOfTwo(int value) {
    var result = 1;
    while (result < value) result *= 2;
    return result;
  }

  List<String> _parseRoster(String text, String extension) {
    if (extension.toLowerCase() == 'json' ||
        text.trimLeft().startsWith('[') ||
        text.trimLeft().startsWith('{')) {
      final decoded = jsonDecode(text);
      final values = decoded is List ? decoded : decoded['players'];
      if (values is! List) return [];
      return values
          .map((value) => value is Map ? '${value['name'] ?? ''}' : '$value')
          .where((name) => name.trim().isNotEmpty)
          .toList();
    }
    return const LineSplitter()
        .convert(text)
        .expand((line) => line.split(','))
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty && name.toLowerCase() != 'name')
        .toList();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T value) test) {
    for (final value in this) {
      if (test(value)) return value;
    }
    return null;
  }
}

class _TournamentPanelState extends State<TournamentPanel> {
  final _controller = _TournamentController();
  final _playerController = TextEditingController();
  final _playerCountController = TextEditingController(text: '8');
  late FocusNode _playerFocusNode; // NEW: Keep focus on input field
  bool _completionPromptShown = false;

  @override
  void initState() {
    super.initState();
    _playerFocusNode = FocusNode();
    _controller.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
    if (_controller.isComplete && !_completionPromptShown) {
      _completionPromptShown = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showCompletionDialog(),
      );
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _playerController.dispose();
    _playerCountController.dispose();
    _playerFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(compact),
              const SizedBox(height: 16),
              _buildControlPanel(compact),
              const SizedBox(height: 16),
              if (_controller.hasStageTabs) ...[
                _buildStageTabs(),
                const SizedBox(height: 16),
              ],
              if (_controller.players.isNotEmpty) ...[
                _buildRoster(),
                const SizedBox(height: 16),
              ],
              if (_controller.matches.isEmpty)
                _buildEmptyState()
              else if (_controller.isSwiss)
                _buildSwissRounds()
              else
                _buildBracketContainer(compact),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStageTabs() {
    return Row(
      children: [
        Expanded(
          child: _stageTab(
            label:
                'Swiss (${_controller._swissStage?.round ?? _controller.swissRound} rounds)',
            type: BracketType.swiss,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _stageTab(
            label: 'Single Elimination',
            type: BracketType.singleElimination,
          ),
        ),
      ],
    );
  }

  Widget _stageTab({required String label, required BracketType type}) {
    final selected = _controller.bracketType == type;
    return OutlinedButton.icon(
      onPressed: selected ? null : () => _switchStage(type),
      icon: Icon(
        type == BracketType.swiss
            ? Icons.table_rows_outlined
            : Icons.account_tree_outlined,
        size: 16,
        color: selected ? widget.theme.textSecondary : widget.theme.textPrimary,
      ),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          color: selected
              ? widget.theme.textSecondary
              : widget.theme.textPrimary,
        ),
      ),
      style: OutlinedButton.styleFrom(
        backgroundColor: selected
            ? widget.theme.accent.withValues(alpha: 0.15)
            : widget.theme.surface,
        foregroundColor: selected
            ? widget.theme.accent
            : widget.theme.textPrimary,
        side: BorderSide(
          color: selected ? widget.theme.accent : widget.theme.border,
        ),
        padding: const EdgeInsets.symmetric(vertical: 10),
      ),
    );
  }

  void _switchStage(BracketType type) {
    _completionPromptShown = type == BracketType.swiss;
    _controller.switchStage(type);
  }

  // NEW: Redesigned header with cleaner layout
  Widget _buildHeader(bool compact) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _controller.isSwiss ? 'Swiss Rounds' : 'Tournament Bracket',
                  style: TextStyle(
                    color: widget.theme.textSecondary,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _statusBadge(),
                    const SizedBox(width: 12),
                    _playerCountIndicator(),
                  ],
                ),
              ],
            ),
            _timerDisplay(),
          ],
        ),
      ],
    );
  }

  Widget _statusBadge() {
    final status = _controller.status;
    final label = switch (status) {
      _TournamentStatus.setup => 'SETUP',
      _TournamentStatus.running => 'LIVE',
      _TournamentStatus.paused => 'PAUSED',
      _TournamentStatus.stopped => 'FINISHED',
      _TournamentStatus.completed => 'COMPLETE',
    };
    final bgColor = switch (status) {
      _TournamentStatus.setup => widget.theme.surface,
      _TournamentStatus.running => AppColors.success.withValues(alpha: 0.15),
      _TournamentStatus.paused => AppColors.warning.withValues(alpha: 0.15),
      _TournamentStatus.stopped => widget.theme.surface,
      _TournamentStatus.completed => AppColors.success.withValues(alpha: 0.15),
    };
    final textColor = switch (status) {
      _TournamentStatus.setup => widget.theme.textPrimary,
      _TournamentStatus.running => AppColors.success,
      _TournamentStatus.paused => AppColors.warning,
      _TournamentStatus.stopped => widget.theme.textSecondary,
      _TournamentStatus.completed => AppColors.success,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: textColor.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _playerCountIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: widget.theme.surface,
        border: Border.all(color: widget.theme.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person, size: 22, color: widget.theme.accent),
          const SizedBox(width: 6),
          Text(
            '${_controller.players.length}',
            style: TextStyle(
              color: widget.theme.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _timerDisplay() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: widget.theme.surface,
        border: Border.all(color: widget.theme.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, size: 18, color: widget.theme.accent),
          const SizedBox(width: 8),
          Text(
            _controller.elapsedLabel,
            style: TextStyle(
              color: widget.theme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  // NEW: Consolidated control panel
  Widget _buildControlPanel(bool compact) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Roster controls
        _buildRosterControls(compact),
        const SizedBox(height: 12),
        // Tournament controls
        _buildTournamentControls(compact),
      ],
    );
  }

  Widget _buildRosterControls(bool compact) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.theme.surface.withValues(alpha: 0.5),
        border: Border.all(color: widget.theme.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Roster',
            style: TextStyle(
              color: widget.theme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            enabled: _controller.canClear,
            onChanged: _controller.setTournamentName,
            style: TextStyle(color: widget.theme.textSecondary, fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Tournament name',
              labelStyle: TextStyle(color: widget.theme.textSecondary),
              filled: true,
              fillColor: widget.theme.background2,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _playerCountController,
                  enabled: _controller.canClear,
                  keyboardType: TextInputType.number,
                  style: TextStyle(
                    color: widget.theme.textSecondary,
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Player count',
                    labelStyle: TextStyle(color: widget.theme.textSecondary),
                    filled: true,
                    fillColor: widget.theme.background2,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _compactButton(
                Icons.people_outline,
                'Generate Players',
                _controller.canClear ? _generateNumberedPlayers : null,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _playerController,
                  focusNode: _playerFocusNode, // NEW: Keep focus on input field
                  enabled: _controller.canClear,
                  textInputAction: TextInputAction
                      .go, // NEW: Changed to go for continuous entry
                  onSubmitted: (_) => _addPlayer(),
                  style: TextStyle(
                    color: widget.theme.textSecondary,
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Add player name',
                    hintStyle: TextStyle(color: widget.theme.textSecondary),
                    filled: true,
                    fillColor: widget.theme.background2,
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: widget.theme.border),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: widget.theme.border),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    suffixIcon: _controller.canClear
                        ? IconButton(
                            icon: const Icon(Icons.add),
                            onPressed: _addPlayer,
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _compactButton(
                Icons.upload_file,
                'Import',
                _controller.canClear ? _import : null,
              ),
              const SizedBox(width: 8),
              _compactButton(
                Icons.delete_outline,
                'Clear',
                _controller.canClear && _controller.players.isNotEmpty
                    ? _controller.clearRoster
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTournamentControls(bool compact) {
    final hasRoster = _controller.players.length >= 2;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.theme.surface.withValues(alpha: 0.5),
        border: Border.all(color: widget.theme.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tournament Controls',
            style: TextStyle(
              color: widget.theme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _compactButton(
                Icons.shuffle,
                _controller.isSwiss ? 'Build rounds' : 'Build bracket',
                hasRoster && _controller.canClear
                    ? () => _controller.generateBracket()
                    : null,
              ),
              // NEW: Randomize seeding instead of using input order
              _compactButton(
                Icons.casino,
                'Randomize',
                hasRoster && _controller.canClear
                    ? _controller.randomizeSeeding
                    : null,
              ),
              _compactButton(
                Icons.play_arrow,
                'Start',
                hasRoster &&
                        _controller.hasBracket &&
                        _controller.status != _TournamentStatus.running
                    ? _controller.start
                    : null,
              ),
              _compactButton(
                Icons.pause,
                'Pause',
                _controller.status == _TournamentStatus.running
                    ? _controller.pause
                    : null,
              ),
              _compactButton(
                Icons.stop,
                'Stop',
                (_controller.status == _TournamentStatus.running ||
                        _controller.status == _TournamentStatus.paused)
                    ? () => _controller.stop()
                    : null,
                danger: true,
              ),
              _compactButton(
                Icons.add_circle_outline,
                'New Tournament',
                (_controller.status == _TournamentStatus.stopped ||
                        _controller.status == _TournamentStatus.completed)
                    ? _controller.startNewTournament
                    : null,
              ),
              _compactButton(
                Icons.table_view,
                'Export CSV',
                _controller.hasExportData ? _controller.exportCsv : null,
              ),
              _compactButton(
                Icons.history,
                'History',
                _controller.hasHistory ? _showHistoryDialog : null,
              ),
              if (_controller.isSwiss) ...[
                _swissRoundsSelector(),
                _swissAdvanceSelector(),
              ] else
                _bracketSelector(),
              _bracketTypeSelector(),
              // _customMatchToggle(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _compactButton(
    IconData icon,
    String label,
    VoidCallback? onPressed, {
    bool danger = false,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: ElevatedButton.styleFrom(
        backgroundColor: danger ? AppColors.danger : widget.theme.surface,
        foregroundColor: danger ? Colors.white : widget.theme.textPrimary,
        disabledBackgroundColor: widget.theme.surface.withValues(alpha: 0.4),
        disabledForegroundColor: widget.theme.textSecondary,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );
  }

  Widget _bracketSelector() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: widget.theme.background,
        border: Border.all(color: widget.theme.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: min(
            _controller.bracketCount,
            max(1, _controller.players.length),
          ),
          dropdownColor: widget.theme.surface,
          style: TextStyle(color: widget.theme.textPrimary, fontSize: 12),
          items: List.generate(
            max(1, min(8, max(1, _controller.players.length))),
            (index) => DropdownMenuItem(
              value: index + 1,
              child: Text('${index + 1} bracket${index == 0 ? '' : 's'}'),
            ),
          ),
          onChanged: _controller.canClear && _controller.players.length >= 2
              ? (value) {
                  if (value != null) _controller.setBracketCount(value);
                }
              : null,
        ),
      ),
    );
  }

  Widget _swissRoundsSelector() {
    return _dropdownBox<int>(
      value: _controller.swissRounds,
      items: List.generate(
        10,
        (index) => DropdownMenuItem(
          value: index + 1,
          child: Text('${index + 1} rounds'),
        ),
      ),
      onChanged: _controller.canClear
          ? (value) {
              if (value != null) _controller.setSwissRounds(value);
            }
          : null,
    );
  }

  Widget _swissAdvanceSelector() {
    final maxPlayers = max(2, _controller.players.length);
    final value = _controller.swissAdvanceCount.clamp(2, maxPlayers);
    return _dropdownBox<int>(
      value: value,
      items: List.generate(
        maxPlayers - 1,
        (index) => DropdownMenuItem(
          value: index + 2,
          child: Text('Advance ${index + 2}'),
        ),
      ),
      onChanged: _controller.canClear && _controller.players.length >= 2
          ? (next) {
              if (next != null) _controller.setSwissAdvanceCount(next);
            }
          : null,
    );
  }

  Widget _dropdownBox<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?>? onChanged,
  }) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: widget.theme.background,
        border: Border.all(color: widget.theme.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          dropdownColor: widget.theme.surface,
          style: TextStyle(color: widget.theme.textPrimary, fontSize: 12),
        ),
      ),
    );
  }

  // NEW: Bracket type selector
  Widget _bracketTypeSelector() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
      decoration: BoxDecoration(
        color: widget.theme.background,
        border: Border.all(color: widget.theme.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<BracketType>(
          value: _controller.bracketType,
          dropdownColor: widget.theme.surface,
          style: TextStyle(color: widget.theme.textPrimary, fontSize: 12),
          items: const [
            DropdownMenuItem(
              value: BracketType.singleElimination,
              child: Text('Single Elim'),
            ),
            DropdownMenuItem(value: BracketType.swiss, child: Text('Swiss')),
          ],
          onChanged: _controller.canClear
              ? (value) async {
                  if (value != null) {
                    // Performance optimization: show loading indicator before rebuild
                    await Future.delayed(const Duration(milliseconds: 10));
                    _controller.setBracketType(value);
                  }
                }
              : null,
        ),
      ),
    );
  }

  Widget _customMatchToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _controller.customMatching
            ? widget.theme.accent.withValues(alpha: 0.15)
            : widget.theme.background2,
        border: Border.all(
          color: _controller.customMatching
              ? widget.theme.accent
              : widget.theme.border,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.scale(
            scale: 0.85,
            child: Switch(
              value: _controller.customMatching,
              onChanged: _controller.canClear
                  ? _controller.setCustomMatching
                  : null,
              activeThumbColor: widget.theme.accent,
            ),
          ),
          Text(
            'Custom',
            style: TextStyle(
              color: widget.theme.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoster() {
    return Material(
        type: MaterialType.card,
        borderRadius: BorderRadius.circular(6),
        color: widget.theme.surface.withValues(alpha: 0.5),
        child: ExpansionTile(
          title: Text(
            'Players List', 
            style: TextStyle(
              color: widget.theme.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          maintainState: true, 
          children: [
            SizedBox(
              height: 450,
              child: GridView.builder(
                shrinkWrap: false, 
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: _controller.players.length,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                cacheExtent: 160, 
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,        
                  crossAxisSpacing: 6,     
                  mainAxisSpacing: 6,       
                  mainAxisExtent: 40,
                ),
                itemBuilder: (context, index) {
                  final player = _controller.players[index];
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: widget.theme.surface.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: widget.theme.border.withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          player.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis, 
                          style: TextStyle(
                            color: widget.theme.textPrimary, 
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (_controller.showSeeding)
                          Text(
                            'Seed: ${player.seed}',
                            style: TextStyle(
                              color: widget.theme.textPrimary, 
                              fontSize: 9,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    }


  // Widget _buildRoster() {
  //   return Container(
  //     padding: const EdgeInsets.all(10),
  //     decoration: BoxDecoration(
  //       color: widget.theme.surface,
  //       border: Border.all(color: widget.theme.border),
  //       borderRadius: BorderRadius.circular(6),
  //     ),
  //     child: Material(
  //       type: MaterialType.card,
  //       borderRadius: BorderRadius.circular(6),
  //       color: widget.theme.surface.withValues(alpha: 0.35),
  //     child: ExpansionTile(
  //       title: Text(
  //         'Players List', 
  //         style: TextStyle(
  //             color: widget.theme.textPrimary,
  //             fontSize: 14,
  //             fontWeight: FontWeight.w700,
  //             letterSpacing: 1,
  //           ),
  //       ),
  //       children: [
  //         // Text(
  //         //   'Players',
  //         //   style: TextStyle(
  //         //     color: widget.theme.textPrimary,
  //         //     fontSize: 11,
  //         //     fontWeight: FontWeight.w700,
  //         //     letterSpacing: 1,
  //         //   ),
  //         // ),
  //         // const SizedBox(height: 8),
  //         Wrap(
  //           spacing: 6,
  //           runSpacing: 6,
  //           children: _controller.players.asMap().entries.map((entry) {
  //             final player = entry.value;
  //             final index = entry.key;
  //             return Chip(
  //               avatar: _buildInitialsAvatar(
  //                 player.name,
  //                 size: 20,
  //               ), // NEW: Avatar
  //               label: Row(
  //                 mainAxisSize: MainAxisSize.min,
  //                 children: [
  //                   if (_controller.showSeeding)
  //                     Text(
  //                       '${index + 1}.',
  //                       style: TextStyle(
  //                         color: widget.theme.accent,
  //                         fontSize: 11,
  //                         fontWeight: FontWeight.w700,
  //                       ),
  //                     ),
  //                   const SizedBox(width: 4),
  //                   Text(
  //                     player.name,
  //                     style: TextStyle(
  //                       color: widget.theme.textSecondary,
  //                       fontSize: 12,
  //                     ),
  //                   ),
  //                 ],
  //               ),
  //               backgroundColor: widget.theme.background2,
  //               deleteIcon: _controller.canClear
  //                   ? Icon(
  //                       Icons.close,
  //                       color: widget.theme.textSecondary,
  //                       size: 15,
  //                     )
  //                   : null,
  //               onDeleted: _controller.canClear
  //                   ? () => _controller.removePlayer(player.id)
  //                   : null,
  //             );
  //           }).toList(),
  //         ),
  //       ],
  //     ),
  //     ),
  //   );
  // }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: widget.theme.surface.withValues(alpha: 0.3),
        border: Border.all(color: widget.theme.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          Icon(
            Icons.account_tree_outlined,
            size: 40,
            color: widget.theme.accent,
          ),
          const SizedBox(height: 12),
          Text(
            _controller.players.length < 2
                ? 'Add at least 2 players to begin'
                : _controller.isSwiss
                ? 'Build Swiss rounds to start the tournament'
                : 'Build a bracket to start the tournament',
            style: TextStyle(
              color: widget.theme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _controller.players.length < 2
                ? 'Enter player names above to get started.'
                : _controller.isSwiss
                ? 'Choose the number of rounds, then build the tournament.'
                : 'Click "Build bracket" to generate the tournament tree.',
            textAlign: TextAlign.center,
            style: TextStyle(color: widget.theme.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // NEW: Enhanced bracket container with Challonge-style design
  Widget _buildBracketContainer(bool compact) {
    final groups =
        _controller.matches.map((match) => match.group).toSet().toList()
          ..sort();
    
    // Performance optimization: Only render if matches are visible on screen
    final hasVisibleMatches = groups.any((group) {
      return _controller.matches.where((m) => m.group == group).any(
        (m) => !_controller.matches.any((sm) => sm.group == group && sm.isComplete),
      );
    });
    
    if (!hasVisibleMatches && _controller.matches.isNotEmpty) {
      // Show scroll indicator for large brackets
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildBracketInfo(),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(30),
            child: Center(
              child: Icon(
                Icons.brush_outlined,
                size: 64,
                color: widget.theme.textSecondary,
              ),
            ),
          ),
          Text(
            '${_controller.players.length} players - scroll to view bracket',
            style: TextStyle(color: widget.theme.textPrimary, fontSize: 14),
          ),
        ],
      );
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBracketInfo(),
        const SizedBox(height: 12),
        ...groups.map((group) => _buildGroupContainer(group)),
      ],
    );
  }

  Widget _buildBracketInfo() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: widget.theme.accent.withValues(alpha: 0.08),
        border: Border.all(color: widget.theme.accent.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: widget.theme.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _controller.customMatching && _controller.canClear
                  ? 'Drag players to swap positions in first round only'
                  : 'Click a player to advance them, or drag winners to later matches',
              style: TextStyle(color: widget.theme.textSecondary, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwissRounds() {
    final rounds = <int, List<_Match>>{};
    for (final match in _controller.matches) {
      rounds.putIfAbsent(match.round, () => []).add(match);
    }
    final orderedRounds = rounds.keys.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _buildBracketInfo()),
            const SizedBox(width: 8),
            _compactButton(Icons.leaderboard, 'Standings', () {
              _showStandingsDialog(showProceed: _controller.swissComplete);
            }),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final round in orderedRounds)
                Container(
                  width: 210,
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF303030),
                    border: Border.all(color: const Color(0xFF444444)),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Round $round${round == _controller.swissRound ? '  •  LIVE' : ''}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      for (final match
                          in rounds[round]!
                            ..sort((a, b) => a.slot.compareTo(b.slot)))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _buildMatchCard(match),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<bool?> _showStandingsDialog({bool showProceed = false}) async {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 800;
    final isTablet = screenWidth >= 1400 && screenWidth < 2200;
    final isAlmostMobile = screenWidth >= 800 && screenWidth < 1400;

    final dashboardWidth = isMobile
        ? screenWidth * 0.99
        : isTablet
        ? screenWidth * 0.7
        : isAlmostMobile
        ? screenWidth * 0.95
        : screenWidth * 0.5;

    final standings = _controller.swissStandings;
    return showDialog<bool>(
      context: context,
      builder: (context) => _wireDialog(
        width: dashboardWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${_controller.tournamentName} standings',
              style: TextStyle(
                color: widget.theme.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (showProceed) ...[
              const SizedBox(height: 8),
              Text(
                'Top ${_controller.swissAdvanceCount} players are marked to advance.',
                style: TextStyle(
                  color: widget.theme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('#')),
                  DataColumn(label: Text('Advance')),
                  DataColumn(label: Text('Player')),
                  DataColumn(label: Text('W-L')),
                  DataColumn(label: Text('Points')),
                  DataColumn(label: Text('Diff')),
                  DataColumn(label: Text('Score')),
                  DataColumn(label: Text('Buchholz')),
                  DataColumn(label: Text('History')),
                ],
                rows: [
                  for (final (index, standing) in standings.indexed)
                    DataRow(
                      color: index < _controller.swissAdvanceCount
                          ? WidgetStatePropertyAll(
                              widget.theme.accent.withValues(alpha: 0.12),
                            )
                          : null,
                      cells: [
                        DataCell(Text('${index + 1}')),
                        DataCell(
                          index < _controller.swissAdvanceCount
                              ? Icon(
                                  Icons.check_circle,
                                  color: AppColors.success,
                                  size: 18,
                                )
                              : const SizedBox.shrink(),
                        ),
                        DataCell(Text(standing.player.name)),
                        DataCell(Text('${standing.wins}-${standing.losses}')),
                        DataCell(Text('${standing.matchPoints}')),
                        DataCell(Text('${standing.pointDifference}')),
                        DataCell(Text('${standing.pointsFor}')),
                        DataCell(
                          Text(
                            '${_controller.buchholzFor(standing.player.id)}',
                          ),
                        ),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final result in standing.history)
                                Container(
                                  margin: const EdgeInsets.only(right: 3),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 2,
                                  ),
                                  color: result == 'W'
                                      ? Colors.green
                                      : Colors.red,
                                  child: Text(
                                    result,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(showProceed ? 'Review later' : 'Close'),
                  ),
                  if (showProceed) ...[
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () => Navigator.pop(context, true),
                      icon: const Icon(Icons.account_tree_outlined, size: 18),
                      label: const Text('Proceed to single elim'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupContainer(int group) {
    final rounds = _controller.matchesForGroup(group);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF303030),
        border: Border.all(color: const Color(0xFF444444)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF292929),
              border: Border(
                bottom: BorderSide(color: const Color(0xFF444444)),
              ),
            ),
            child: Text(
              'Bracket ${group + 1}${_controller.bracketCount > 1 ? ' of ${_controller.bracketCount}' : ''}',
              style: TextStyle(
                color: widget.theme.accent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(10, 8, 18, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < rounds.length; index++)
                  Padding(
                    padding: EdgeInsets.only(
                      right: index == rounds.length - 1 ? 0 : 34,
                    ),
                    child: _buildRoundColumn(
                      rounds[index],
                      _roundLabel(rounds[index]),
                      index,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _roundLabel(List<_Match> round) {
    return switch (round.length) {
      1 => 'Final',
      2 => 'Semifinals',
      4 => 'Quarterfinals',
      _ => 'Round of ${round.length * 2}',
    };
  }

  Widget _buildRoundColumn(List<_Match> round, String label, int roundIndex) {
    final visibleMatches = round.where(_hasVisibleContent).toList();
    return SizedBox(
      width: 190,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFE7E7E7),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: EdgeInsets.only(
              top: roundIndex == 0 ? 0 : (pow(2, roundIndex - 1) * 56) - 28,
            ),
            child: Column(
              children: [
                for (final (idx, match) in visibleMatches.indexed)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: idx == visibleMatches.length - 1
                          ? 0
                          : roundIndex == 0
                          ? 8
                          : (pow(2, roundIndex) * 56) - 48,
                    ),
                    child: _buildMatchCard(match),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _hasVisibleContent(_Match match) {
    if (match.hasPlayers) return true;
    if (match.round == 0) return false;

    final feederMatches = _controller.matches.where(
      (feeder) =>
          feeder.group == match.group &&
          feeder.round == match.round - 1 &&
          (feeder.slot == match.slot * 2 || feeder.slot == match.slot * 2 + 1),
    );
    return feederMatches.any((feeder) => feeder.hasPlayers);
  }

  Widget _buildMatchCard(_Match match) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          !_controller.canClear && details.data.isNotEmpty,
      onAcceptWithDetails: (details) =>
          _controller.dropWinner(details.data, match.id),
      builder: (context, candidates, rejected) {
        final highlighted = candidates.isNotEmpty;
        return Container(
          decoration: BoxDecoration(
            color: highlighted
                ? const Color(0xFF767676)
                : const Color(0xFF626262),
            border: Border.all(
              color: highlighted
                  ? const Color(0xFFFF742B)
                  : const Color(0xFF747474),
              width: highlighted ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _buildPlayerSlot(match, 0),
              const Divider(height: 1, color: Color(0xFF4E4E4E), thickness: 1),
              _buildPlayerSlot(match, 1),
              if (match.notes != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  child: Text(
                    match.notes!,
                    style: const TextStyle(
                      color: Color(0xFFD0D0D0),
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPlayerSlot(_Match match, int slot) {
    final id = slot == 0 ? match.playerA : match.playerB;
    final player = id == null ? null : _controller.playerById[id];
    final isWinner = id != null && match.winnerId == id;
    final isLoser = match.winnerId != null && id != null && !isWinner;
    final score = slot == 0 ? match.scoreA : match.scoreB;

    Widget content = InkWell(
      onTap: player != null && !_controller.canClear
          ? () => _controller.isSwiss
                ? _showSwissResultDialog(match, player.id)
                : _controller.chooseWinner(match.id, player.id)
          : null,
      child: Container(
        height: 25,
        color: isWinner ? const Color(0xFF767676) : const Color(0xFF626262),
        child: Row(
          children: [
            Container(
              width: 25,
              alignment: Alignment.center,
              color: const Color(0xFF555555),
              child: Text(
                player == null ? '' : '${player.seed}',
                style: const TextStyle(color: Color(0xFFCFCFCF), fontSize: 9),
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                player?.name ?? 'Open slot',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: player == null
                      ? const Color(0xFFBDBDBD)
                      : Colors.white,
                  fontSize: 11,
                  fontWeight: isWinner ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            Container(
              width: 25,
              height: double.infinity,
              alignment: Alignment.center,
              color: score != null || isWinner
                  ? const Color(0xFFFF742B)
                  : const Color(0xFF767676),
              child: Text(
                score?.toString() ?? '0',
                style: const TextStyle(
                  color: Color(0xFF222222),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (isWinner)
              Icon(Icons.check_circle, size: 14, color: AppColors.success),
            if (isLoser) Icon(Icons.cancel, size: 14, color: AppColors.danger),
          ],
        ),
      ),
    );

    if (player == null) {
      return DragTarget<String>(
        onWillAcceptWithDetails: (_) =>
            _controller.customMatching &&
            _controller.canClear &&
            match.round == 0,
        onAcceptWithDetails: (details) =>
            _controller.placePlayer(details.data, match.id, slot),
        builder: (_, candidates, __) => content,
      );
    }

    return LongPressDraggable<String>(
      data: player.id,
      feedback: _buildDragFeedback(player.name),
      childWhenDragging: Opacity(opacity: 0.35, child: content),
      child: DragTarget<String>(
        onWillAcceptWithDetails: (_) =>
            _controller.customMatching &&
            _controller.canClear &&
            match.round == 0,
        onAcceptWithDetails: (details) =>
            _controller.placePlayer(details.data, match.id, slot),
        builder: (_, candidates, __) => content,
      ),
    );
  }

  Widget _buildDragFeedback(String name) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: widget.theme.accent,
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          name,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  void _addPlayer() {
    _controller.addPlayer(_playerController.text);
    _playerController.clear();
    _playerFocusNode
        .requestFocus(); // NEW: Keep focus on input field for continuous entry
  }

  void _generateNumberedPlayers() {
    final count = int.tryParse(_playerCountController.text);
    if (count == null || count < 2 || count > 150) return;
    _controller.generateNumberedPlayers(count);
  }

  // NEW: Generate initials from player name
  String _buildInitials(String name, {double size = 24}) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return '?';
    final list = [for (final part in parts.take(2)) part[0].toUpperCase()];
    return list.join('').substring(0, 2);
  }

  Widget _buildInitialsAvatar(String name, {double size = 24}) {
    final initials = name
        .split(' ')
        .where((word) => word.isNotEmpty)
        .map((word) => word[0].toUpperCase())
        .join()
        .substring(0, min(2, name.split(' ').length));
    // .padRight(2, '?');

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: widget.theme.accent.withValues(alpha: 0.6),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Future<void> _import() => _controller.importRoster();

  Future<void> _showHistoryDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => _wireDialog(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${_controller.tournamentName} history',
              style: TextStyle(
                color: widget.theme.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _controller.history.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: widget.theme.border),
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    _controller.history[index],
                    style: TextStyle(color: widget.theme.textPrimary),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wireDialog({required Widget child, double? width}) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      child: WireFrame(
        width: width,
        color: widget.theme.surface,
        border: Border.all(color: widget.theme.border),
        borderRadius: BorderRadius.circular(4),
        padding: const EdgeInsets.all(20),
        child: child,
      ),
    );
  }

  Future<void> _showSwissResultDialog(_Match match, String winnerId) async {
    if (match.winnerId != null) return;
    final winnerScore = TextEditingController(text: '1');
    final loserScore = TextEditingController(text: '0');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _wireDialog(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Record ${_controller.playerById[winnerId]?.name ?? 'winner'}',
              style: TextStyle(
                color: widget.theme.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: winnerScore,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Winner points',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: loserScore,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Opponent points',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Save result'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    final winner = int.tryParse(winnerScore.text) ?? 1;
    final loser = int.tryParse(loserScore.text) ?? 0;
    if (winner < 0 || loser < 0) return;
    _controller.recordSwissResult(match.id, winnerId, winner, loser);
    // await _showStandingsDialog();
  }

  Future<void> _showCompletionDialog() async {
    if (!mounted) return;

    if (_controller.isSwiss) {
      final advance = await _showStandingsDialog(showProceed: true);
      if (advance == true) {
        _controller.startSingleEliminationFromSwiss();
        _completionPromptShown = false;
      }
      return;
    }

    if (_controller.bracketCount == 1) {
      _controller.finish();
      return;
    }

    final createNext = await showDialog<bool>(
      context: context,
      builder: (context) => _wireDialog(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Tournament stage complete',
              style: TextStyle(
                color: widget.theme.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${_controller.finalWinners.length} winners are ready. Create next bracket?',
              style: TextStyle(color: widget.theme.textPrimary),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('End'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Continue'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (createNext == true) {
      _controller.reseedWinners();
      _completionPromptShown = false;
    } else {
      _controller.finish();
    }
  }
}
