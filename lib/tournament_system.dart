import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/app_theme.dart';
import 'utils/csv_downloader.dart';

class TournamentPanel extends StatefulWidget {
  const TournamentPanel({super.key});

  @override
  State<TournamentPanel> createState() => _TournamentPanelState();
}

class _Player {
  final String id;
  final String name;
  int seed;

  _Player(this.id, this.name, {this.seed = 0});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'seed': seed};

  factory _Player.fromJson(Map<String, dynamic> json) {
    return _Player(
      json['id'] as String,
      json['name'] as String,
      seed: json['seed'] as int? ?? 0,
    );
  }
}

class _Match {
  final String id;
  final int group;
  final int round;
  final int slot;
  String? playerA;
  String? playerB;
  String? winnerId;
  int? scoreA;
  int? scoreB;
  String? notes;

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

  Map<String, dynamic> toJson() => {
        'id': id,
        'group': group,
        'round': round,
        'slot': slot,
        'playerA': playerA,
        'playerB': playerB,
        'winnerId': winnerId,
        'scoreA': scoreA,
        'scoreB': scoreB,
        'notes': notes,
      };

  factory _Match.fromJson(Map<String, dynamic> json) {
    return _Match(
      id: json['id'] as String,
      group: json['group'] as int,
      round: json['round'] as int,
      slot: json['slot'] as int,
      playerA: json['playerA'] as String?,
      playerB: json['playerB'] as String?,
    )
      ..winnerId = json['winnerId'] as String?
      ..scoreA = json['scoreA'] as int?
      ..scoreB = json['scoreB'] as int?
      ..notes = json['notes'] as String?;
  }
}

enum _TournamentStatus { setup, running, paused, stopped, completed }

enum BracketType { singleElimination, swiss }

enum ByeMode { none, automatic, custom }

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
  final BracketType? type;
  final List<_Player> players;
  final List<_Match> matches;
  final List<String> history;
  final int round;
  final int rounds;
  final int bracketCount;
  final _TournamentStatus status;
  final ByeMode byeMode;
  final int customByeCount;

  _TournamentStageSnapshot({
    required this.type,
    required this.players,
    required this.matches,
    required this.history,
    required this.round,
    required this.rounds,
    required this.bracketCount,
    required this.status,
    required this.byeMode,
    required this.customByeCount,
  });

  Map<String, dynamic> toJson() => {
        'type': type?.name,
        'players': players.map((p) => p.toJson()).toList(),
        'matches': matches.map((m) => m.toJson()).toList(),
        'history': history,
        'round': round,
        'rounds': rounds,
        'bracketCount': bracketCount,
        'status': status.name,
        'byeMode': byeMode.name,
        'customByeCount': customByeCount,
      };

  factory _TournamentStageSnapshot.fromJson(Map<String, dynamic> json) {
    return _TournamentStageSnapshot(
      type: json['type'] != null
          ? BracketType.values.firstWhere((e) => e.name == json['type'])
          : null,
      players: (json['players'] as List)
          .map((p) => _Player.fromJson(p as Map<String, dynamic>))
          .toList(),
      matches: (json['matches'] as List)
          .map((m) => _Match.fromJson(m as Map<String, dynamic>))
          .toList(),
      history: List<String>.from(json['history'] as List),
      round: json['round'] as int,
      rounds: json['rounds'] as int,
      bracketCount: json['bracketCount'] as int,
      status: _TournamentStatus.values
          .firstWhere((e) => e.name == json['status']),
      byeMode: json['byeMode'] != null
          ? ByeMode.values.firstWhere(
              (e) => e.name == json['byeMode'],
              orElse: () => ByeMode.automatic,
            )
          : ByeMode.automatic,
      customByeCount: json['customByeCount'] as int? ?? 0,
    );
  }
}

class _TournamentController extends ChangeNotifier {
  static const String _sessionKey = 'tournament_session_state';

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
  BracketType? bracketType;
  String tournamentName = 'Tournament';
  int swissRounds = 3;
  int swissRound = 0;
  int swissAdvanceCount = 0;
  bool swissAdvanceConfigured = false;

  ByeMode byeMode = ByeMode.automatic;
  int customByeCount = 0;

  _TournamentStageSnapshot? _swissStage;
  _TournamentStageSnapshot? _singleEliminationStage;

  _TournamentController() {
    _loadState();
  }

  void _persistState() async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> stateData = {
      'players': players.map((p) => p.toJson()).toList(),
      'matches': matches.map((m) => m.toJson()).toList(),
      'archivedMatches': archivedMatches.map((m) => m.toJson()).toList(),
      'archivedPlayerNames': archivedPlayerNames,
      'history': history,
      'seconds': _seconds,
      'bracketCount': bracketCount,
      'customMatching': customMatching,
      'status': status.name,
      'showSeeding': showSeeding,
      'bracketType': bracketType?.name,
      'tournamentName': tournamentName,
      'swissRounds': swissRounds,
      'swissRound': swissRound,
      'swissAdvanceCount': swissAdvanceCount,
      'swissAdvanceConfigured': swissAdvanceConfigured,
      'byeMode': byeMode.name,
      'customByeCount': customByeCount,
      'swissStage': _swissStage?.toJson(),
      'singleEliminationStage': _singleEliminationStage?.toJson(),
    };
    await prefs.setString(_sessionKey, jsonEncode(stateData));
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionKey);
    if (raw == null) return;

    try {
      final Map<String, dynamic> data = jsonDecode(raw);

      players.clear();
      if (data['players'] != null) {
        players.addAll((data['players'] as List)
            .map((p) => _Player.fromJson(p as Map<String, dynamic>)));
      }

      matches.clear();
      if (data['matches'] != null) {
        matches.addAll((data['matches'] as List)
            .map((m) => _Match.fromJson(m as Map<String, dynamic>)));
      }

      archivedMatches.clear();
      if (data['archivedMatches'] != null) {
        archivedMatches.addAll((data['archivedMatches'] as List)
            .map((m) => _Match.fromJson(m as Map<String, dynamic>)));
      }

      archivedPlayerNames.clear();
      if (data['archivedPlayerNames'] != null) {
        archivedPlayerNames.addAll(
          Map<String, String>.from(data['archivedPlayerNames'] as Map),
        );
      }

      history.clear();
      if (data['history'] != null) {
        history.addAll(List<String>.from(data['history'] as List));
      }

      _seconds = data['seconds'] as int? ?? 0;
      bracketCount = data['bracketCount'] as int? ?? 1;
      customMatching = data['customMatching'] as bool? ?? false;
      showSeeding = data['showSeeding'] as bool? ?? true;
      tournamentName = data['tournamentName'] as String? ?? 'Tournament';
      swissRounds = data['swissRounds'] as int? ?? 3;
      swissRound = data['swissRound'] as int? ?? 0;
      swissAdvanceCount = data['swissAdvanceCount'] as int? ?? 0;
      swissAdvanceConfigured = data['swissAdvanceConfigured'] as bool? ?? false;

      if (data['byeMode'] != null) {
        byeMode = ByeMode.values.firstWhere(
          (e) => e.name == data['byeMode'],
          orElse: () => ByeMode.automatic,
        );
      }
      customByeCount = data['customByeCount'] as int? ?? 0;

      if (data['status'] != null) {
        status = _TournamentStatus.values
            .firstWhere((e) => e.name == data['status']);
      }

      if (data['bracketType'] != null) {
        bracketType = BracketType.values
            .firstWhere((e) => e.name == data['bracketType']);
      }

      if (data['swissStage'] != null) {
        _swissStage = _TournamentStageSnapshot.fromJson(
            data['swissStage'] as Map<String, dynamic>);
      }

      if (data['singleEliminationStage'] != null) {
        _singleEliminationStage = _TournamentStageSnapshot.fromJson(
            data['singleEliminationStage'] as Map<String, dynamic>);
      }

      if (status == _TournamentStatus.running) {
        _startTimer();
      }

      notifyListeners();
    } catch (_) {}
  }

  void _startTimer() {
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (status == _TournamentStatus.running) {
        _seconds++;
        notifyListeners();
      }
    });
  }

  int get elapsedSeconds => _seconds;
  String get elapsedLabel {
    final minutes = (_seconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Map<String, _Player> get playerById => {
        for (final player in players) player.id: player,
      };

  List<List<_Match>> matchesForGroup(int group) {
    final grouped = <int, List<_Match>>{};

    for (final match in matches.where((match) => match.group == group)) {
      grouped.putIfAbsent(match.round, () => []).add(match);
    }

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

  List<_SwissStanding> get swissStandings {
    final standings = {
      for (final player in players) player.id: _SwissStanding(player),
    };

    final opponents = <String, Set<String>>{};
    for (final match in matches.where((match) => match.group == 0)) {
      if (match.playerA != null && match.playerB != null) {
        opponents.putIfAbsent(match.playerA!, () => {}).add(match.playerB!);
        opponents.putIfAbsent(match.playerB!, () => {}).add(match.playerA!);
      }
    }

    final activeMatches = matches.where((match) => match.isComplete).toList();
    for (final match in activeMatches) {
      final winner = match.winnerId;
      if (winner == null) continue;
      final winnerStanding = standings[winner];
      if (winnerStanding == null) continue;

      final loser = match.playerA == winner ? match.playerB : match.playerA;
      final winnerScore = match.playerA == winner ? match.scoreA : match.scoreB;
      final loserScore = match.playerA == winner ? match.scoreB : match.scoreA;

      winnerStanding.wins++;
      winnerStanding.pointsFor += winnerScore ?? 1;
      winnerStanding.pointsAgainst += loserScore ?? 0;
      winnerStanding.history.add('W');

      if (loser != null && standings[loser] != null) {
        final loserStanding = standings[loser]!;
        loserStanding.losses++;
        loserStanding.pointsFor += loserScore ?? 0;
        loserStanding.pointsAgainst += winnerScore ?? 1;
        loserStanding.history.add('L');
      }
    }

    final allStandings = <_SwissStanding>[];
    for (final standing in standings.values) {
      allStandings.add(standing);
    }

    allStandings.sort((a, b) {
      final byPoints = b.matchPoints.compareTo(a.matchPoints);
      if (byPoints != 0) return byPoints;

      final buchA = _buchholz(a, standings, opponents);
      final buchB = _buchholz(b, standings, opponents);
      final byBuchholz = buchB.compareTo(buchA);
      if (byBuchholz != 0) return byBuchholz;

      final diffA = a.pointDifference;
      final diffB = b.pointDifference;
      return diffB.compareTo(diffA);
    });

    return allStandings;
  }

  int _buchholz(
    _SwissStanding standing,
    Map<String, _SwissStanding> standings,
    Map<String, Set<String>> opponents,
  ) =>
      (opponents[standing.player.id] ?? {})
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

  int get automaticByeCount {
    if (players.length < 2) return 0;
    final nextPow2 = _nextPowerOfTwo(players.length);
    return nextPow2 - players.length;
  }

  void setByeMode(ByeMode mode) {
    if (!canClear) return;
    byeMode = mode;
    if (mode == ByeMode.custom) {
      if (customByeCount <= 0 || customByeCount >= players.length) {
        customByeCount = min(players.length - 1, automaticByeCount);
      }
    }
    if (players.length >= 2) generateBracket();
    notifyListeners();
  }

  void setCustomByeCount(int count) {
    if (!canClear) return;
    customByeCount = count.clamp(0, max(0, players.length - 1));
    if (byeMode == ByeMode.custom && players.length >= 2) {
      generateBracket();
    }
    notifyListeners();
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
        seed: players.length + 1,
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

  void setBracketType(BracketType? type) {
    if (status != _TournamentStatus.setup || type == null) return;
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
    if (status != _TournamentStatus.setup || (source ?? players).length < 2) {
      return;
    }
    if (isSwiss && source == null) {
      matches.clear();
      swissRound = 1;
      generateSwissRound();
      return;
    }

    archivedMatches.addAll(matches);
    matches.clear();
    final roster = [...(source ?? players)];

    roster.sort((a, b) => a.seed.compareTo(b.seed));

    final groupTotal = min(bracketCount, roster.length);
    final groupSize = (roster.length / groupTotal).ceil();
    var cursor = 0;

    for (var group = 0; group < groupTotal; group++) {
      final groupPlayers = roster.sublist(
        cursor,
        min(cursor + groupSize, roster.length),
      );
      cursor += groupPlayers.length;
      if (groupPlayers.isEmpty) continue;

      int effectiveByeCount = 0;
      if (byeMode == ByeMode.automatic) {
        final nextPow2 = _nextPowerOfTwo(groupPlayers.length);
        effectiveByeCount = nextPow2 - groupPlayers.length;
      } else if (byeMode == ByeMode.custom) {
        effectiveByeCount = customByeCount.clamp(0, groupPlayers.length - 1);
      }

      final slotCount = _nextPowerOfTwo(groupPlayers.length + (byeMode == ByeMode.none ? 0 : effectiveByeCount));
      final roundCount = max(1, log(slotCount) ~/ log(2));

      for (var round = 0; round < roundCount; round++) {
        final matchCount = slotCount ~/ pow(2, round).toInt() ~/ 2;
        for (var slot = 0; slot < matchCount; slot++) {
          matches.add(
            _Match(
              id: 'g$group-r$round-m$slot',
              group: group,
              round: round,
              slot: slot,
            ),
          );
        }
      }

      if (effectiveByeCount > 0 && byeMode != ByeMode.none) {
        final byes = [
          ...groupPlayers.sublist(0, min(effectiveByeCount, groupPlayers.length)),
        ];
        final unseededPlayers = groupPlayers.sublist(min(effectiveByeCount, groupPlayers.length));

        final realMatchPairs = <List<_Player>>[];
        var idx = 0;
        while (idx + 1 < unseededPlayers.length) {
          realMatchPairs.add([unseededPlayers[idx], unseededPlayers[idx + 1]]);
          idx += 2;
        }
        if (idx < unseededPlayers.length) {
          byes.add(unseededPlayers[idx]);
        }

        _Match round1At(int slot) => matches.firstWhere(
              (m) => m.group == group && m.round == 1 && m.slot == slot,
            );
        _Match round0At(int slot) => matches.firstWhere(
              (m) => m.group == group && m.round == 0 && m.slot == slot,
            );

        final pairedCount = min(byes.length, realMatchPairs.length);
        var round1Slot = 0;
        for (var i = 0; i < pairedCount; i++) {
          round1At(round1Slot).playerA = byes[i].id;
          final feeder = round0At(round1Slot * 2 + 1);
          feeder.playerA = realMatchPairs[i][0].id;
          feeder.playerB = realMatchPairs[i][1].id;
          round1Slot++;
        }

        for (var i = pairedCount; i < byes.length; i += 2) {
          final target = round1At(round1Slot);
          target.playerA = byes[i].id;
          if (i + 1 < byes.length) target.playerB = byes[i + 1].id;
          round1Slot++;
        }

        for (var i = pairedCount; i < realMatchPairs.length; i += 2) {
          final feederA = round0At(round1Slot * 2);
          feederA.playerA = realMatchPairs[i][0].id;
          feederA.playerB = realMatchPairs[i][1].id;
          if (i + 1 < realMatchPairs.length) {
            final feederB = round0At(round1Slot * 2 + 1);
            feederB.playerA = realMatchPairs[i + 1][0].id;
            feederB.playerB = realMatchPairs[i + 1][1].id;
          }
          round1Slot++;
        }
      } else {
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

        for (var match in matches.where((m) => m.group == group && m.round == 0)) {
          match.playerA = slots[match.slot * 2];
          match.playerB = slots[match.slot * 2 + 1];
        }
      }
    }
    _resolveByes();

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
    final bye =
        ordered.where((player) => !used.contains(player.id)).firstOrNull;
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
        status == _TournamentStatus.running) return;
    status = _TournamentStatus.running;
    _startTimer();
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
    bracketType = null;
    bracketCount = 1;
    swissRound = 0;
    swissAdvanceCount = 0;
    swissAdvanceConfigured = false;
    _seconds = 0;
    status = _TournamentStatus.setup;
    byeMode = ByeMode.automatic;
    customByeCount = 0;
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
        status != _TournamentStatus.paused) return;
    final match = matches.firstWhere((item) => item.id == matchId);
    if (match.playerA != playerId && match.playerB != playerId) return;
    if (match.winnerId != null) return;
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

  void recordSwissScores(
    String matchId,
    int scoreA,
    int scoreB,
  ) {
    if (!isSwiss ||
        (status != _TournamentStatus.running &&
            status != _TournamentStatus.paused)) return;
    final match = matches.firstWhere((item) => item.id == matchId);
    if (match.winnerId != null ||
        match.playerA == null ||
        match.playerB == null) return;

    match.scoreA = scoreA;
    match.scoreB = scoreB;

    if (scoreA > scoreB) {
      match.winnerId = match.playerA;
    } else if (scoreB > scoreA) {
      match.winnerId = match.playerB;
    } else {
      match.winnerId = match.playerA;
    }

    history.add(
      '${_name(match.winnerId!)} won Swiss round ${match.round} ($scoreA - $scoreB).',
    );

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
      byeMode: byeMode,
      customByeCount: customByeCount,
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
    byeMode = snapshot.byeMode;
    customByeCount = snapshot.customByeCount;
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

  _Match _copyMatch(_Match match) => _Match(
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

  void setScore(String matchId, int? scoreA, int? scoreB) {
    final match = matches.firstWhere((item) => item.id == matchId);
    match.scoreA = scoreA;
    match.scoreB = scoreB;
    notifyListeners();
  }

  void setNotes(String matchId, String notes) {
    final match = matches.firstWhere((item) => item.id == matchId);
    match.notes = notes.isNotEmpty ? notes : null;
    notifyListeners();
  }

  void dropWinner(String playerId, String targetMatchId) {
    if (status != _TournamentStatus.running &&
        status != _TournamentStatus.paused) return;
    final target = matches.firstWhere((match) => match.id == targetMatchId);
    final source = _matchContaining(playerId);
    if (source == null ||
        source.round >= target.round ||
        source.winnerId != null) return;
    chooseWinner(source.id, playerId);
  }

  List<_Player> get finalWinners {
    final result = <_Player>[];
    for (final group in matches.map((match) => match.group).toSet()) {
      final groupMatches = matches.where((match) => match.group == group);
      final finalMatch = groupMatches.reduce(
        (a, b) => a.round > b.round ? a : b,
      );
      if (finalMatch.winnerId != null) {
        result.add(playerById[finalMatch.winnerId]!);
      }
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
      final stageName = stage.type?.name ?? '';
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
      final match = _Match(
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
        byeMode: ByeMode.automatic,
        customByeCount: 0,
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
  void notifyListeners() {
    _persistState();
    super.notifyListeners();
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
        if (match.winnerId != null) continue;

        if (match.round > 0) {
          final feederMatches = matches.where(
            (feeder) =>
                feeder.group == match.group &&
                feeder.round == match.round - 1 &&
                (feeder.slot == match.slot * 2 ||
                    feeder.slot == match.slot * 2 + 1),
          ).toList();

          if (feederMatches.length == 2) {
            final f0 = feederMatches.firstWhere((f) => f.slot == match.slot * 2);
            final f1 = feederMatches.firstWhere((f) => f.slot == match.slot * 2 + 1);

            if (f0.winnerId != null && match.playerA == null) {
              match.playerA = f0.winnerId;
              changed = true;
            }
            if (f1.winnerId != null && match.playerB == null) {
              match.playerB = f1.winnerId;
              changed = true;
            }
          }
        }

        if (!match.hasPlayers) continue;
        if (match.playerA != null && match.playerB != null) continue;

        if (match.round > 0) {
          final feederMatches = matches.where(
            (feeder) =>
                feeder.group == match.group &&
                feeder.round == match.round - 1 &&
                (feeder.slot == match.slot * 2 ||
                    feeder.slot == match.slot * 2 + 1),
          );
          if (feederMatches.length == 2 &&
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
          (match.playerA == playerId || match.playerB == playerId)) {
        return match;
      }
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

// ─────────────────────────────────────────────────────────────────────────────
// UI
// ─────────────────────────────────────────────────────────────────────────────

class _TournamentPanelState extends State<TournamentPanel> {
  final _controller = _TournamentController();
  final _playerController = TextEditingController();
  final _playerCountController = TextEditingController(text: '8');
  late FocusNode _playerFocusNode;
  bool _completionPromptShown = false;

  // Bracket geometry. A match card is two 30px slots + 2px divider + 4px border.
  static const double _slotHeight = 30;
  static const double _matchHeight = 66;
  static const double _matchUnit = 76; // card height + vertical gap

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

  // ── Design primitives ──────────────────────────────────────────────────────

  BoxDecoration _brut({
    Color color = AppColors.white,
    double shadow = 4,
    double border = 2,
    Color borderColor = AppColors.ink,
  }) {
    return BoxDecoration(
      color: color,
      border: Border.all(color: borderColor, width: border),
      boxShadow: shadow > 0
          ? [BoxShadow(color: AppColors.ink, offset: Offset(shadow, shadow))]
          : null,
    );
  }

  Widget _eyebrow(String text, {Color color = AppColors.muted}) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: color,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.4,
      ),
    );
  }

  InputDecoration _input({String? label, String? hint, Widget? suffixIcon}) {
    const side = BorderSide(color: AppColors.ink, width: 2);
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: AppColors.muted),
      hintStyle: const TextStyle(color: AppColors.muted),
      filled: true,
      fillColor: AppColors.white,
      isDense: true,
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: side,
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: side,
      ),
      disabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: AppColors.line, width: 2),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: AppColors.ink, width: 3),
      ),
    );
  }

  Widget _btn(
    IconData icon,
    String label,
    VoidCallback? onPressed, {
    bool primary = false,
    bool danger = false,
  }) {
    final enabled = onPressed != null;
    final bg = !enabled
        ? AppColors.paper
        : danger
            ? AppColors.coral
            : primary
                ? AppColors.lime
                : AppColors.white;
    final fg = !enabled
        ? AppColors.muted
        : danger
            ? AppColors.white
            : AppColors.ink;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: enabled ? AppColors.ink : AppColors.line,
          width: 2,
        ),
        boxShadow: enabled
            ? const [BoxShadow(color: AppColors.ink, offset: Offset(3, 3))]
            : null,
      ),
      child: Material(
        color: bg,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dropdownBox<T>({
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?>? onChanged,
    String? hint,
  }) {
    final enabled = onChanged != null;
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: enabled ? AppColors.white : AppColors.paper,
        border: Border.all(
          color: enabled ? AppColors.ink : AppColors.line,
          width: 2,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: hint == null
              ? null
              : Text(
                  hint,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
          items: items,
          onChanged: onChanged,
          dropdownColor: AppColors.white,
          iconEnabledColor: AppColors.ink,
          iconDisabledColor: AppColors.line,
          style: const TextStyle(
            color: AppColors.ink,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _dialog({required Widget child, double? width}) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(AppSpacing.md),
      child: Container(
        width: width,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: _brut(shadow: 6, border: 3),
        child: child,
      ),
    );
  }

  Widget _dialogTitle(String text) => Text(
        text,
        style: const TextStyle(
          color: AppColors.ink,
          fontSize: 22,
          height: 1.05,
          fontWeight: FontWeight.w900,
        ),
      );

  // ── Layout ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        return Container(
          color: AppColors.paper,
          child: SingleChildScrollView(
            padding: EdgeInsets.all(compact ? AppSpacing.sm : AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(compact),
                const SizedBox(height: AppSpacing.md),
                _buildControlPanel(compact),
                const SizedBox(height: AppSpacing.md),
                if (_controller.hasStageTabs) ...[
                  _buildStageTabs(),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (_controller.players.isNotEmpty) ...[
                  _buildRoster(),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (_controller.matches.isEmpty)
                  _buildEmptyState()
                else if (_controller.isSwiss)
                  _buildSwissRounds()
                else
                  _buildBracketContainer(compact),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
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
        const SizedBox(width: AppSpacing.sm),
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
    final fg = selected ? AppColors.white : AppColors.ink;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.ink, width: 2),
        boxShadow: selected
            ? null
            : const [BoxShadow(color: AppColors.ink, offset: Offset(3, 3))],
      ),
      child: Material(
        color: selected ? AppColors.ink : AppColors.white,
        child: InkWell(
          onTap: selected ? null : () => _switchStage(type),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  type == BracketType.swiss
                      ? Icons.table_rows_outlined
                      : Icons.account_tree_outlined,
                  size: 16,
                  color: selected ? AppColors.lime : fg,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _switchStage(BracketType type) {
    _completionPromptShown = type == BracketType.swiss;
    _controller.switchStage(type);
  }

  Widget _buildHeader(bool compact) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _eyebrow(_controller.tournamentName),
              const SizedBox(height: 4),
              Text(
                _controller.isSwiss ? 'Swiss Rounds' : 'Tournament Bracket',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: compact ? 26 : 34,
                  height: 1.0,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [_statusBadge(), _playerCountIndicator()],
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        _timerDisplay(),
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
    final bg = switch (status) {
      _TournamentStatus.setup => AppColors.white,
      _TournamentStatus.running => AppColors.lime,
      _TournamentStatus.paused => AppColors.coral,
      _TournamentStatus.stopped => AppColors.ink,
      _TournamentStatus.completed => AppColors.lime,
    };
    final fg = switch (status) {
      _TournamentStatus.paused || _TournamentStatus.stopped => AppColors.white,
      _ => AppColors.ink,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: _brut(color: bg, shadow: 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == _TournamentStatus.running) ...[
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppColors.coral,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _playerCountIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: _brut(shadow: 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.person, size: 18, color: AppColors.ink),
          const SizedBox(width: 6),
          Text(
            '${_controller.players.length}',
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _timerDisplay() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: _brut(color: AppColors.ink, shadow: 4, borderColor: AppColors.ink)
          .copyWith(
        boxShadow: const [
          BoxShadow(color: AppColors.lime, offset: Offset(4, 4)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_outlined, size: 18, color: AppColors.lime),
          const SizedBox(width: 8),
          Text(
            _controller.elapsedLabel,
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel(bool compact) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildRosterControls(compact),
        const SizedBox(height: AppSpacing.sm),
        _buildTournamentControls(compact),
      ],
    );
  }

  Widget _buildRosterControls(bool compact) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: _brut(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _eyebrow('Roster'),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            enabled: _controller.canClear,
            onChanged: _controller.setTournamentName,
            style: const TextStyle(color: AppColors.ink, fontSize: 14),
            decoration: _input(label: 'Tournament name'),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 130,
                child: TextField(
                  controller: _playerCountController,
                  enabled: _controller.canClear,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: AppColors.ink, fontSize: 14),
                  decoration: _input(label: 'Player count'),
                ),
              ),
              _btn(
                Icons.people_outline,
                'Generate Players',
                _controller.canClear ? _generateNumberedPlayers : null,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  controller: _playerController,
                  focusNode: _playerFocusNode,
                  enabled: _controller.canClear,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _addPlayer(),
                  style: const TextStyle(color: AppColors.ink, fontSize: 14),
                  decoration: _input(
                    hint: 'Add player name',
                    suffixIcon: _controller.canClear
                        ? IconButton(
                            icon: const Icon(Icons.add, color: AppColors.ink),
                            onPressed: _addPlayer,
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _btn(
                Icons.upload_file,
                'Import',
                _controller.canClear ? _import : null,
              ),
              const SizedBox(width: AppSpacing.sm),
              _btn(
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
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: _brut(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _eyebrow('Tournament Controls'),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _btn(
                Icons.shuffle,
                _controller.isSwiss ? 'Build rounds' : 'Build bracket',
                hasRoster && _controller.canClear
                    ? () => _controller.generateBracket()
                    : null,
              ),
              _btn(
                Icons.casino,
                'Randomize',
                hasRoster && _controller.canClear
                    ? _controller.randomizeSeeding
                    : null,
              ),
              _btn(
                Icons.play_arrow,
                'Start',
                hasRoster &&
                        _controller.hasBracket &&
                        _controller.status != _TournamentStatus.running
                    ? _controller.start
                    : null,
                primary: true,
              ),
              _btn(
                Icons.pause,
                'Pause',
                _controller.status == _TournamentStatus.running
                    ? _controller.pause
                    : null,
              ),
              _btn(
                Icons.stop,
                'Stop',
                (_controller.status == _TournamentStatus.running ||
                        _controller.status == _TournamentStatus.paused)
                    ? () => _controller.stop()
                    : null,
                danger: true,
              ),
              _btn(
                Icons.add_circle_outline,
                'New Tournament',
                (_controller.status == _TournamentStatus.stopped ||
                        _controller.status == _TournamentStatus.completed)
                    ? _controller.startNewTournament
                    : null,
              ),
              _btn(
                Icons.table_view,
                'Export CSV',
                _controller.hasExportData ? _controller.exportCsv : null,
              ),
              _btn(
                Icons.history,
                'History',
                _controller.hasHistory ? _showHistoryDialog : null,
              ),
              _bracketTypeSelector(),
              if (_controller.isSwiss) ...[
                _swissRoundsSelector(),
                _swissAdvanceSelector(),
              ] else ...[
                _byeModeSelector(),
                if (_controller.byeMode == ByeMode.custom)
                  _customByeSelector(),
              ],
            ],
          ),
        ],
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

  Widget _byeModeSelector() {
    return _dropdownBox<ByeMode>(
      value: _controller.byeMode,
      items: const [
        DropdownMenuItem(value: ByeMode.none, child: Text('No Byes')),
        DropdownMenuItem(value: ByeMode.automatic, child: Text('Auto Byes')),
        DropdownMenuItem(value: ByeMode.custom, child: Text('Custom Byes')),
      ],
      onChanged: _controller.canClear
          ? (value) {
              if (value != null) _controller.setByeMode(value);
            }
          : null,
    );
  }

  Widget _customByeSelector() {
    final maxByes = max(1, _controller.players.length - 1);
    final currentVal = _controller.customByeCount.clamp(0, maxByes);

    return _dropdownBox<int>(
      value: currentVal,
      items: List.generate(
        maxByes + 1,
        (index) => DropdownMenuItem(
          value: index,
          child: Text('$index Bye${index == 1 ? '' : 's'}'),
        ),
      ),
      onChanged: _controller.canClear && _controller.players.length >= 2
          ? (value) {
              if (value != null) _controller.setCustomByeCount(value);
            }
          : null,
    );
  }

  Widget _bracketTypeSelector() {
    return _dropdownBox<BracketType>(
      value: _controller.bracketType,
      hint: 'Select Format',
      items: const [
        DropdownMenuItem(
          value: BracketType.singleElimination,
          child: Text('Single Elim'),
        ),
        DropdownMenuItem(value: BracketType.swiss, child: Text('Swiss')),
      ],
      onChanged: _controller.canClear && _controller.players.length >= 2
          ? (value) async {
              if (value != null) {
                await Future.delayed(const Duration(milliseconds: 10));
                _controller.setBracketType(value);
              }
            }
          : null,
    );
  }

  Widget _buildRoster() {
    return Container(
      decoration: _brut(),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          iconColor: AppColors.ink,
          collapsedIconColor: AppColors.ink,
          tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          title: _eyebrow('Players List', color: AppColors.ink),
          maintainState: true,
          children: [
            Container(height: 2, color: AppColors.ink),
            SizedBox(
              height: 450,
              child: GridView.builder(
                shrinkWrap: false,
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: _controller.players.length,
                padding: const EdgeInsets.all(AppSpacing.sm),
                cacheExtent: 160,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  mainAxisExtent: 44,
                ),
                itemBuilder: (context, index) {
                  final player = _controller.players[index];
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: _brut(
                      color: AppColors.paper,
                      shadow: 0,
                      border: 1.5,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          player.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.ink,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (_controller.showSeeding)
                          Text(
                            'SEED ${player.seed}',
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
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
      ),
    );
  }

  Widget _buildEmptyState() {
    final needsPlayers = _controller.players.length < 2;
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.xl,
        horizontal: AppSpacing.md,
      ),
      decoration: _brut(),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: _brut(color: AppColors.lime, shadow: 3),
            child: const Icon(
              Icons.account_tree_outlined,
              size: 32,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            needsPlayers
                ? 'Add at least 2 players to begin'
                : _controller.isSwiss
                    ? 'Build Swiss rounds to start the tournament'
                    : 'Build a bracket to start the tournament',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            needsPlayers
                ? 'Enter player names above to get started.'
                : _controller.isSwiss
                    ? 'Choose the number of rounds, then build the tournament.'
                    : 'Click "Build bracket" to generate the tournament tree.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildBracketContainer(bool compact) {
    final groups =
        _controller.matches.map((match) => match.group).toSet().toList()
          ..sort();

    final hasVisibleMatches = groups.any((group) {
      return _controller.matches
          .where((m) => m.group == group)
          .any(_hasVisibleContent);
    });

    if (!hasVisibleMatches && _controller.matches.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildBracketInfo(),
          const SizedBox(height: AppSpacing.sm),
          const Padding(
            padding: EdgeInsets.all(30),
            child: Center(
              child: Icon(Icons.brush_outlined, size: 64, color: AppColors.muted),
            ),
          ),
          Text(
            '${_controller.players.length} players - scroll to view bracket',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.ink, fontSize: 14),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBracketInfo(),
        const SizedBox(height: AppSpacing.sm),
        ...groups.map((group) => _buildGroupContainer(group)),
      ],
    );
  }

  Widget _buildBracketInfo() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: _brut(color: AppColors.lime, shadow: 0),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: AppColors.ink),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _controller.customMatching && _controller.canClear
                  ? 'Drag players to swap positions in first round only'
                  : 'Click a player to advance them, or drag winners to later matches',
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
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
            const SizedBox(width: AppSpacing.sm),
            _btn(Icons.leaderboard, 'Standings', () {
              _showStandingsDialog(showProceed: _controller.swissComplete);
            }),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(right: 6, bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final round in orderedRounds)
                Container(
                  width: 214,
                  margin: const EdgeInsets.only(right: AppSpacing.sm),
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: _brut(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          _eyebrow('Round $round', color: AppColors.ink),
                          const SizedBox(width: 8),
                          if (round == _controller.swissRound)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              color: AppColors.lime,
                              child: const Text(
                                'LIVE',
                                style: TextStyle(
                                  color: AppColors.ink,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      for (final match
                          in rounds[round]!
                            ..sort((a, b) => a.slot.compareTo(b.slot)))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
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
      builder: (context) => _dialog(
        width: dashboardWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _dialogTitle('${_controller.tournamentName} standings'),
            if (showProceed) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Top ${_controller.swissAdvanceCount} players are marked to advance.',
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.ink, width: 2),
              ),
              height: MediaQuery.of(context).size.height * 0.5,
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor:
                        const WidgetStatePropertyAll(AppColors.ink),
                    headingTextStyle: const TextStyle(
                      color: AppColors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                    dataTextStyle: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 13,
                    ),
                    dividerThickness: 1,
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
                          color: WidgetStatePropertyAll(
                            index < _controller.swissAdvanceCount
                                ? AppColors.lime.withValues(alpha: 0.5)
                                : AppColors.white,
                          ),
                          cells: [
                            DataCell(Text('${index + 1}')),
                            DataCell(
                              index < _controller.swissAdvanceCount
                                  ? const Icon(
                                      Icons.check_box,
                                      color: AppColors.ink,
                                      size: 18,
                                    )
                                  : const SizedBox.shrink(),
                            ),
                            DataCell(
                              Text(
                                standing.player.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            DataCell(
                              Text('${standing.wins}-${standing.losses}'),
                            ),
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
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: result == 'W'
                                            ? AppColors.lime
                                            : AppColors.coral,
                                        border: Border.all(
                                          color: AppColors.ink,
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Text(
                                        result,
                                        style: TextStyle(
                                          color: result == 'W'
                                              ? AppColors.ink
                                              : AppColors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w900,
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
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                alignment: WrapAlignment.end,
                children: [
                  _btn(
                    Icons.close,
                    showProceed ? 'Review later' : 'Close',
                    () => Navigator.pop(context, false),
                  ),
                  if (showProceed)
                    _btn(
                      Icons.account_tree_outlined,
                      'Proceed to single elim',
                      () => Navigator.pop(context, true),
                      primary: true,
                    ),
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
      margin: const EdgeInsets.only(bottom: AppSpacing.md, right: 4),
      decoration: _brut(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: AppColors.ink,
            child: Text(
              'BRACKET ${group + 1}${_controller.bracketCount > 1 ? ' OF ${_controller.bracketCount}' : ''}',
              style: const TextStyle(
                color: AppColors.lime,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.6,
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(14, 14, 22, 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < rounds.length; index++)
                  Padding(
                    padding: EdgeInsets.only(
                      right: index == rounds.length - 1 ? 0 : 36,
                    ),
                    child: _buildRoundColumn(
                      rounds[index],
                      _roundLabel(rounds[index]),
                      index,
                      rounds,
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

  Widget _buildRoundColumn(
    List<_Match> round,
    String label,
    int roundIndex,
    List<List<_Match>> allRounds,
  ) {
    final visibleMatches = round.where(_hasVisibleContent).toList();

    final bool isThisRoundComplete =
        visibleMatches.isNotEmpty && visibleMatches.every((m) => m.isComplete);

    int finishedPrecedingRounds = 0;
    for (int r = 0; r < roundIndex; r++) {
      final precedingMatches = allRounds[r].where(_hasVisibleContent).toList();
      if (precedingMatches.isNotEmpty &&
          precedingMatches.every((m) => m.isComplete)) {
        finishedPrecedingRounds++;
      } else {
        break;
      }
    }

    final double topMargin;
    final double matchSpacing;

    if (isThisRoundComplete || finishedPrecedingRounds == roundIndex) {
      topMargin = 0;
      matchSpacing = _matchUnit - _matchHeight;
    } else {
      final effectivePowerIndex = roundIndex - finishedPrecedingRounds;
      topMargin = (pow(2, effectivePowerIndex - 1) * _matchUnit) -
          (_matchUnit / 2);
      matchSpacing = (pow(2, effectivePowerIndex) * _matchUnit) - _matchHeight;
    }

    return SizedBox(
      width: 200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _eyebrow(label, color: AppColors.ink),
          const SizedBox(height: 10),
          Padding(
            padding: EdgeInsets.only(top: topMargin),
            child: Column(
              children: [
                for (final (idx, match) in visibleMatches.indexed)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: idx == visibleMatches.length - 1 ? 0 : matchSpacing,
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
    if (match.hasPlayers || match.isComplete) return true;
    if (match.round == 0) return false;

    final feederMatches = _controller.matches.where(
      (feeder) =>
          feeder.group == match.group &&
          feeder.round == match.round - 1 &&
          (feeder.slot == match.slot * 2 || feeder.slot == match.slot * 2 + 1),
    );
    return feederMatches.any((feeder) => feeder.hasPlayers || feeder.isComplete);
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
            color: AppColors.white,
            border: Border.all(
              color: highlighted ? AppColors.coral : AppColors.ink,
              width: highlighted ? 3 : 2,
            ),
            boxShadow: const [
              BoxShadow(color: AppColors.ink, offset: Offset(3, 3)),
            ],
          ),
          clipBehavior: Clip.none,
          child: Column(
            children: [
              _buildPlayerSlot(match, 0),
              Container(height: 2, color: AppColors.ink),
              _buildPlayerSlot(match, 1),
              if (match.notes != null)
                Container(
                  width: double.infinity,
                  color: AppColors.paper,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  child: Text(
                    match.notes!,
                    style: const TextStyle(
                      color: AppColors.muted,
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

  bool _isMatchReady(_Match match) {
    if (match.isComplete) return false;
    if (match.playerA != null && match.playerB != null) return true;

    final feederMatches = _controller.matches.where(
      (feeder) =>
          feeder.group == match.group &&
          feeder.round == match.round - 1 &&
          (feeder.slot == match.slot * 2 || feeder.slot == match.slot * 2 + 1),
    );

    if (feederMatches.isEmpty) return match.hasPlayers;
    return feederMatches.every((feeder) => _controller._branchResolved(feeder));
  }

  Widget _buildPlayerSlot(_Match match, int slot) {
    final id = slot == 0 ? match.playerA : match.playerB;
    final player = id == null ? null : _controller.playerById[id];
    final isWinner = id != null && match.winnerId == id;
    final isLoser = match.winnerId != null && id != null && !isWinner;
    final score = slot == 0 ? match.scoreA : match.scoreB;
    final bool matchReady = _isMatchReady(match);

    final nameColor = player == null
        ? AppColors.line
        : isLoser
            ? AppColors.muted
            : matchReady || isWinner
                ? AppColors.ink
                : AppColors.muted;

    Widget content = InkWell(
      onTap: (!_controller.canClear && matchReady)
          ? () {
              if (_controller.isSwiss) {
                _showSwissResultDialog(match);
              } else if (player != null) {
                _controller.chooseWinner(match.id, player.id);
              }
            }
          : null,
      child: Container(
        height: _slotHeight,
        color: isWinner ? AppColors.lime : AppColors.white,
        child: Row(
          children: [
            Container(
              width: 26,
              height: double.infinity,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.paper,
                border: Border(
                  right: BorderSide(color: AppColors.ink, width: 2),
                ),
              ),
              child: Text(
                player == null ? '' : '${player.seed}',
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                player?.name ?? 'Open slot',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: nameColor,
                  fontSize: 12,
                  fontWeight: player == null ? FontWeight.w500 : FontWeight.w800,
                  decoration: isLoser ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            if (isWinner)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.check, size: 14, color: AppColors.ink),
              ),
            Container(
              width: 28,
              height: double.infinity,
              alignment: Alignment.center,
              color: isWinner ? AppColors.ink : AppColors.paper,
              child: Text(
                score?.toString() ?? '0',
                style: TextStyle(
                  color: isWinner ? AppColors.lime : AppColors.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.lime,
          border: Border.all(color: AppColors.ink, width: 2),
          boxShadow: const [
            BoxShadow(color: AppColors.ink, offset: Offset(4, 4)),
          ],
        ),
        child: Text(
          name,
          style: const TextStyle(
            color: AppColors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  // ── Actions & dialogs ──────────────────────────────────────────────────────

  void _addPlayer() {
    _controller.addPlayer(_playerController.text);
    _playerController.clear();
    _playerFocusNode.requestFocus();
  }

  void _generateNumberedPlayers() {
    final count = int.tryParse(_playerCountController.text);
    if (count == null || count < 2 || count > 150) {
      showDialog(
        context: context,
        builder: (context) => _dialog(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _dialogTitle('Invalid player count'),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Number of players must be between 2 and 150.',
                style: TextStyle(color: AppColors.ink, fontSize: 14),
              ),
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerRight,
                child: _btn(
                  Icons.check,
                  'OK',
                  () => Navigator.of(context).pop(),
                  primary: true,
                ),
              ),
            ],
          ),
        ),
      );
      return;
    }
    _controller.generateNumberedPlayers(count);
  }

  Future<void> _import() => _controller.importRoster();

  Future<void> _showHistoryDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => _dialog(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _dialogTitle('${_controller.tournamentName} history'),
            const SizedBox(height: AppSpacing.md),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.ink, width: 2),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _controller.history.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: AppColors.line),
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 12,
                    ),
                    child: Text(
                      _controller.history[index],
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerRight,
              child: _btn(Icons.close, 'Close', () => Navigator.pop(context)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSwissResultDialog(_Match match) async {
    if (match.winnerId != null ||
        match.playerA == null ||
        match.playerB == null) return;

    final playerAName =
        _controller.playerById[match.playerA!]?.name ?? 'Player A';
    final playerBName =
        _controller.playerById[match.playerB!]?.name ?? 'Player B';

    final scoreAController =
        TextEditingController(text: '${match.scoreA ?? 0}');
    final scoreBController =
        TextEditingController(text: '${match.scoreB ?? 0}');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _dialog(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _dialogTitle('Record match scores'),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: scoreAController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: AppColors.ink),
                    decoration: _input(label: playerAName),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: scoreBController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: AppColors.ink),
                    decoration: _input(label: playerBName),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _btn(Icons.close, 'Cancel', () => Navigator.pop(context, false)),
                const SizedBox(width: AppSpacing.sm),
                _btn(
                  Icons.check,
                  'Save result',
                  () => Navigator.pop(context, true),
                  primary: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final scoreA = int.tryParse(scoreAController.text) ?? 0;
    final scoreB = int.tryParse(scoreBController.text) ?? 0;
    scoreAController.dispose();
    scoreBController.dispose();

    if (confirmed != true) return;
    if (scoreA < 0 || scoreB < 0) return;

    _controller.recordSwissScores(match.id, scoreA, scoreB);
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
      builder: (context) => _dialog(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _dialogTitle('Tournament stage complete'),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${_controller.finalWinners.length} winners are ready. Create next bracket?',
              style: const TextStyle(color: AppColors.ink, fontSize: 14),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _btn(Icons.flag, 'End', () => Navigator.pop(context, false)),
                const SizedBox(width: AppSpacing.sm),
                _btn(
                  Icons.arrow_forward,
                  'Continue',
                  () => Navigator.pop(context, true),
                  primary: true,
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