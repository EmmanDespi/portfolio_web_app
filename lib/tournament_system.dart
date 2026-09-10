import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

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

enum _TournamentStatus { setup, running, paused, stopped }

// NEW: Bracket types
enum BracketType {
  singleElimination,
  doubleElimination,
  roundRobin,
  swiss,
}

class _TournamentController extends ChangeNotifier {
  final Random _random = Random();
  final List<_Player> players = [];
  final List<_Match> matches = [];
  final List<String> history = [];
  Timer? _timer;
  int _seconds = 0;
  int bracketCount = 1;
  bool customMatching = false;
  _TournamentStatus status = _TournamentStatus.setup;
  bool showSeeding = true; // NEW: Toggle seeding display
  BracketType bracketType = BracketType.singleElimination; // NEW: Bracket type

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
    for (final round in grouped.values) {
      round.sort((a, b) => a.slot.compareTo(b.slot));
    }
    return grouped.entries.map((entry) => entry.value).toList();
  }

  bool get canClear => status == _TournamentStatus.setup;
  bool get hasBracket => matches.isNotEmpty;
  bool get isComplete {
    if (matches.isEmpty) return false;
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
    if (name.isEmpty || players.length >= 50) return;
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
    _resetBracketIfSetup();
    notifyListeners();
  }

  void addPlayers(Iterable<String> names) {
    for (final name in names) {
      if (players.length >= 50) break;
      addPlayer(name);
    }
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
    history.clear();
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
    if (players.length >= 2) {
      generateBracket();
    }
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
    matches.clear();
    final roster = [...(source ?? players)];
    
    // Sort by seed (randomized via randomizeSeeding(), or sequential by
    // default if the user hasn't randomized yet).
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
    history.add(
      'Generated ${players.length} players across $groupTotal bracket${groupTotal == 1 ? '' : 's'}.',
    );
    notifyListeners();
  }

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
    if (status == _TournamentStatus.setup) return;
    _timer?.cancel();
    _timer = null;
    status = _TournamentStatus.stopped;
    notifyListeners();

    if (history.isNotEmpty) {
      await exportHistory();
    }

    players.clear();
    matches.clear();
    history.clear();
    customMatching = false;
    _seconds = 0;
    status = _TournamentStatus.setup;
    notifyListeners();
  }

  void finish() {
    _timer?.cancel();
    _timer = null;
    status = _TournamentStatus.stopped;
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
    if (match.playerA != playerId && match.playerB != playerId) return;
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
    notifyListeners();
  }

  // NEW: Set match score
  void setScore(String matchId, int? scoreA, int? scoreB) {
    final match = matches.firstWhere((item) => item.id == matchId);
    match.scoreA = scoreA;
    match.scoreB = scoreB;
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
    final names = _parseRoster(text, result.files.single.extension ?? '');
    addPlayers(names);
  }

  Future<void> exportHistory() async {
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        build: (_) => [
          pw.Header(level: 0, text: 'Tournament History'),
          pw.Text('Duration: $elapsedLabel'),
          pw.SizedBox(height: 12),
          ...history.map(pw.Text.new),
        ],
      ),
    );
    await Printing.sharePdf(
      bytes: await document.save(),
      filename: 'tournament-history.pdf',
    );
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
              if (_controller.players.isNotEmpty) ...[
                _buildRoster(),
                const SizedBox(height: 16),
              ],
              if (_controller.matches.isEmpty)
                _buildEmptyState()
              else
                _buildBracketContainer(compact),
            ],
          ),
        );
      },
    );
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
                  'Tournament Bracket',
                  style: TextStyle(
                    color: widget.theme.textPrimary,
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
    };
    final bgColor = switch (status) {
      _TournamentStatus.setup => widget.theme.surface,
      _TournamentStatus.running => AppColors.success.withValues(alpha: 0.15),
      _TournamentStatus.paused => AppColors.warning.withValues(alpha: 0.15),
      _TournamentStatus.stopped => widget.theme.surface,
    };
    final textColor = switch (status) {
      _TournamentStatus.setup => widget.theme.textPrimary,
      _TournamentStatus.running => AppColors.success,
      _TournamentStatus.paused => AppColors.warning,
      _TournamentStatus.stopped => widget.theme.textSecondary,
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
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '${_controller.players.length}',
              style: TextStyle(
                color: widget.theme.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: ' / 50',
              style: TextStyle(
                color: widget.theme.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
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
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _playerController,
                  focusNode: _playerFocusNode, // NEW: Keep focus on input field
                  enabled: _controller.canClear,
                  textInputAction: TextInputAction.go, // NEW: Changed to go for continuous entry
                  onSubmitted: (_) => _addPlayer(),
                  style: TextStyle(color: widget.theme.textSecondary, fontSize: 13),
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
                'Build bracket',
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
                _controller.status != _TournamentStatus.setup
                    ? () => _controller.stop()
                    : null,
                danger: true,
              ),
              _compactButton(
                Icons.picture_as_pdf,
                'Export',
                _controller.history.isNotEmpty ? _export : null,
              ),
              _bracketSelector(),
              _bracketTypeSelector(), // NEW: Bracket type selector
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
        backgroundColor:
            danger ? AppColors.danger : widget.theme.surface,
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
          style: TextStyle(
            color: widget.theme.textPrimary,
            fontSize: 12,
          ),
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
          style: TextStyle(
            color: widget.theme.textPrimary,
            fontSize: 12,
          ),
          items: const [
            DropdownMenuItem(
              value: BracketType.singleElimination,
              child: Text('Single Elim'),
            ),
            DropdownMenuItem(
              value: BracketType.doubleElimination,
              child: Text('Double Elim'),
            ),
            DropdownMenuItem(
              value: BracketType.roundRobin,
              child: Text('Round Robin'),
            ),
            DropdownMenuItem(
              value: BracketType.swiss,
              child: Text('Swiss'),
            ),
          ],
          onChanged: _controller.canClear
              ? (value) {
                  if (value != null) _controller.setBracketType(value);
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
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: widget.theme.surface.withValues(alpha: 0.35),
        border: Border.all(color: widget.theme.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Players',
            style: TextStyle(
              color: widget.theme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _controller.players
                .asMap()
                .entries
                .map((entry) {
                  final player = entry.value;
                  final index = entry.key;
                  return Chip(
                    avatar: _buildInitialsAvatar(player.name, size: 20), // NEW: Avatar
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_controller.showSeeding)
                          Text(
                            '${index + 1}.',
                            style: TextStyle(
                              color: widget.theme.accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        const SizedBox(width: 4),
                        Text(
                          player.name,
                          style: TextStyle(
                            color: widget.theme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    backgroundColor: widget.theme.background2,
                    deleteIcon: _controller.canClear
                        ? Icon(
                            Icons.close,
                            color: widget.theme.textSecondary,
                            size: 15,
                          )
                        : null,
                    onDeleted: _controller.canClear
                        ? () => _controller.removePlayer(player.id)
                        : null,
                  );
                })
                .toList(),
          ),
        ],
      ),
    );
  }

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
                : 'Click "Build bracket" to generate the tournament tree.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: widget.theme.textSecondary,
              fontSize: 12,
            ),
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
              style: TextStyle(
                color: widget.theme.textSecondary,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupContainer(int group) {
    final rounds = _controller.matchesForGroup(group);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(color: widget.theme.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: widget.theme.surface.withValues(alpha: 0.6),
              border: Border(
                bottom: BorderSide(color: widget.theme.border),
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
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < rounds.length; index++)
                  Padding(
                    padding: EdgeInsets.only(
                      right: index == rounds.length - 1 ? 0 : 20,
                    ),
                    child: _buildRoundColumn(rounds[index], _roundLabel(rounds[index])),
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

  Widget _buildRoundColumn(List<_Match> round, String label) {
    final visibleMatches = round.where(_hasVisibleContent).toList();
    if (visibleMatches.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      width: 180,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: widget.theme.textSecondary,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          for (final (idx, match) in visibleMatches.indexed)
            Padding(
              padding: EdgeInsets.only(bottom: idx == visibleMatches.length - 1 ? 0 : 12),
              child: _buildMatchCard(match),
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

  // NEW: Enhanced match card design inspired by Challonge
  Widget _buildMatchCard(_Match match) {
    final ready = match.playerA != null && match.playerB != null;
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
                ? widget.theme.accent.withValues(alpha: 0.1)
                : widget.theme.background2,
            border: Border.all(
              color: highlighted
                  ? widget.theme.accent
                  : widget.theme.border,
              width: highlighted ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _buildPlayerSlot(match, 0),
              Divider(height: 0, color: widget.theme.border, thickness: 1),
              _buildPlayerSlot(match, 1),
              if (match.notes != null || (match.scoreA != null && match.scoreB != null))
                Divider(height: 0, color: widget.theme.border, thickness: 1),
              if (match.notes != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Text(
                    match.notes!,
                    style: TextStyle(
                      color: widget.theme.textSecondary,
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (match.winnerId != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  color: AppColors.success.withValues(alpha: 0.15),
                  child: Center(
                    child: Text(
                      'Winner Advances',
                      style: TextStyle(
                        color: AppColors.success,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              if (!ready && match.hasPlayers)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  color: widget.theme.surface,
                  child: Center(
                    child: Text(
                      'BYE',
                      style: TextStyle(
                        color: widget.theme.accent,
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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
          ? () => _controller.chooseWinner(match.id, player.id)
          : null,
      child: Container(
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        color: isWinner
            ? AppColors.success.withValues(alpha: 0.5)
            : isLoser
            ? AppColors.danger.withValues(alpha: 0.5)
            : widget.theme.background,
        child: Row(
          children: [
            // NEW: Show avatar if player exists
            if (player != null) ...[
              _buildInitialsAvatar(player.name, size: 28),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    player?.name ?? 'Open slot',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: player == null
                          ? widget.theme.textSecondary
                          : widget.theme.textPrimary,
                      fontSize: 14,
                      fontWeight: isWinner ? FontWeight.w700 : FontWeight.w600,
                      decoration: isLoser ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (score != null)
                    Text(
                      '$score ${isWinner ? '✓' : ''}',
                      style: TextStyle(
                        color: widget.theme.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                ],
              ),
            ),
            if (isWinner)
              Icon(Icons.check_circle, size: 14, color: AppColors.success),
            if (isLoser)
              Icon(Icons.cancel, size: 14, color: AppColors.danger),
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
    _playerFocusNode.requestFocus(); // NEW: Keep focus on input field for continuous entry
  }

  // NEW: Generate initials from player name
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
  Future<void> _export() => _controller.exportHistory();

  Future<void> _showCompletionDialog() async {
    if (!mounted) return;

    if (_controller.bracketCount == 1) {
      _controller.finish();
      await _controller.exportHistory();
      return;
    }

    await _controller.exportHistory();
    if (!mounted) return;

    final createNext = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tournament stage complete'),
        content: Text(
          '${_controller.finalWinners.length} winners are ready. Create next bracket?',
        ),
        actions: [
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
    );
    if (!mounted) return;
    if (createNext == true) {
      _controller.reseedWinners();
      _completionPromptShown = false;
    } else {
      await _controller.exportHistory();
    }
  }
}