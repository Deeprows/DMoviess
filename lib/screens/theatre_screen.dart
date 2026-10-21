import '../utils/l10n.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/movie.dart';
import '../services/auth_service.dart';
import '../services/community_service.dart';
import '../theme/app_theme.dart';
import 'movie_player_screen.dart';

const _velvet = Color(0xFF7A0F1E);
const _velvetDark = Color(0xFF2A0509);
const _gold = Color(0xFFFFC857);

/// Dark halo behind text that floats over the movie, so it reads on any scene.
const _chatShadow = [
  Shadow(color: Color(0xE6000000), blurRadius: 3),
  Shadow(color: Color(0xE6000000), blurRadius: 8),
  Shadow(color: Color(0x99000000), blurRadius: 14),
];

/// The movie stored in a Watch Together room (the Worker keeps `title`,
/// Movie.fromJson reads `name`).
Movie? roomMovie(Map<String, dynamic> room) {
  final raw = room['movie'];
  if (raw is! Map) return null;
  final m = Map<String, dynamic>.from(raw);
  m['name'] = m['name'] ?? m['title'] ?? '';
  // With a TMDB id the player link is rebuilt from this app's own settings.
  if (int.tryParse('${m['tmdbId'] ?? ''}') != null) m.remove('url');
  try {
    return Movie.fromJson(m);
  } catch (_) {
    return null;
  }
}

String roomTitle(Map<String, dynamic> room) {
  final raw = room['movie'];
  if (raw is Map && '${raw['title'] ?? ''}'.trim().isNotEmpty) {
    return '${raw['title']}'.trim();
  }
  return roomMovie(room)?.title ?? 'a movie';
}

class _Seat {
  final String email;
  final String name;
  final String photo;
  final String state; // host | accepted | pending | declined
  const _Seat(this.email, this.name, this.photo, this.state);
}

class _Msg {
  final int seq;
  final String name;
  final String email;
  final String text;
  const _Msg(this.seq, this.name, this.email, this.text);
}

class _Float {
  final String emoji;
  final double x; // 0..1 across the screen
  final Key key;
  _Float(this.emoji, this.x) : key = UniqueKey();
}

/// A cinema room for two (or more): velvet curtains, a glowing screen with
/// the movie, seats for everybody, live reactions and chat. The host starts
/// the show; everyone gets the same 3-2-1 countdown and the player opens.
class TheatreScreen extends StatefulWidget {
  final Map<String, dynamic> room;
  const TheatreScreen({super.key, required this.room});

  @override
  State<TheatreScreen> createState() => _TheatreScreenState();
}

class _TheatreScreenState extends State<TheatreScreen>
    with SingleTickerProviderStateMixin {
  final _svc = CommunityService.instance;
  late Map<String, dynamic> _room;
  final List<_Msg> _msgs = [];
  final List<_Float> _floats = [];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  late final AnimationController _glow;
  Timer? _roomTimer;
  Timer? _eventTimer;
  int _since = 0;
  int? _startedAge; // seconds since the host pressed start (server clock)
  bool _started = false;
  int _countdown = 0; // 3..1 while counting down, 0 otherwise
  Timer? _countTimer;
  bool _playerOn = false; // the movie plays inside this room
  bool _immersive = false; // player is fullscreen / landscape
  final _handle = PlayerHandle();
  bool _floatChat = false; // floating chat over the fullscreen movie
  Timer? _floatTimer;
  bool _chatOpen = true;
  bool _busy = false;
  final _rnd = math.Random();

  String get _id => '${_room['id']}';
  String get _me => AuthService.instance.user?.email.trim().toLowerCase() ?? '';
  bool get _isHost => '${_room['hostEmail']}'.toLowerCase() == _me;

  @override
  void initState() {
    super.initState();
    _room = Map<String, dynamic>.from(widget.room);
    _glow =
        AnimationController(vsync: this, duration: const Duration(seconds: 4))
          ..repeat(reverse: true);
    _pollEvents(first: true);
    _roomTimer = Timer.periodic(const Duration(seconds: 4), (_) => _pollRoom());
    _eventTimer = Timer.periodic(
        const Duration(milliseconds: 2500), (_) => _pollEvents());
  }

  @override
  void dispose() {
    _roomTimer?.cancel();
    _eventTimer?.cancel();
    _countTimer?.cancel();
    _floatTimer?.cancel();
    _glow.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------- polling

  Future<void> _pollRoom() async {
    try {
      final r = await _svc.watchRoom(_id);
      if (mounted) setState(() => _room = r);
    } catch (_) {}
  }

  bool _polling = false;

  Future<void> _pollEvents({bool first = false}) async {
    if (_polling) return;
    _polling = true;
    try {
      final d = await _svc.watchEvents(_id, _since);
      if (!mounted) return;
      final list = d['events'] is List ? d['events'] as List : [];
      final startedAt = (d['startedAt'] as num?)?.toInt();
      final now = (d['now'] as num?)?.toInt() ?? 0;
      var gotMsg = false;
      for (final e in list) {
        if (e is! Map) continue;
        final seq = (e['seq'] as num?)?.toInt() ?? 0;
        if (seq > _since) _since = seq;
        final kind = '${e['kind']}';
        final email = '${e['email']}'.toLowerCase();
        if (kind == 'msg') {
          _msgs.add(_Msg(seq, '${e['name']}', email, '${e['text']}'));
          gotMsg = true;
        } else if (kind == 'react' && !first && email != _me) {
          _float('${e['text']}');
        }
      }
      if (_msgs.length > 80) _msgs.removeRange(0, _msgs.length - 80);
      if (startedAt != null && !_started) {
        _started = true;
        _startedAge = math.max(0, now - startedAt);
        // Fresh start (we were here when the host pressed it): count down.
        if (!first && _startedAge! <= 20) _beginCountdown();
      }
      setState(() {});
      if (gotMsg) _scrollDown();
      // Fullscreen: pop the chat up over the movie when somebody comments.
      if (gotMsg && !first && _immersive) _showFloatChat();
    } catch (_) {
    } finally {
      _polling = false;
    }
  }

  void _showFloatChat() {
    if (!mounted) return;
    _floatTimer?.cancel();
    setState(() => _floatChat = true);
    // Fades away by itself so it never hides the movie for long.
    _floatTimer = Timer(const Duration(seconds: 12), () {
      if (mounted) setState(() => _floatChat = false);
    });
  }

  void _hideFloatChat() {
    _floatTimer?.cancel();
    if (mounted) setState(() => _floatChat = false);
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
      }
    });
  }

  // ----------------------------------------------------------- actions

  void _float(String emoji) {
    final f = _Float(emoji, .1 + _rnd.nextDouble() * .8);
    setState(() => _floats.add(f));
    Future<void>.delayed(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _floats.remove(f));
    });
  }

  Future<void> _react(String emoji) async {
    _float(emoji);
    try {
      await _svc.watchEvent(_id, 'react', emoji);
    } catch (_) {}
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    try {
      await _svc.watchEvent(_id, 'msg', text);
      await _pollEvents();
    } on CommunityException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      final r = await _svc.respondWatchInvitation(_id, true);
      if (mounted) setState(() => _room = r);
    } on CommunityException catch (e) {
      _toast(e.message);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      await _svc.watchEvent(_id, 'start');
      await _pollEvents();
      // The host's own countdown starts right away.
      if (!_playerOn && _countdown == 0) _beginCountdown();
    } on CommunityException catch (e) {
      _toast(e.message);
    }
    if (mounted) setState(() => _busy = false);
  }

  void _beginCountdown() {
    if (_countdown > 0 || _playerOn) return;
    _countTimer?.cancel();
    setState(() => _countdown = 3);
    _countTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_countdown <= 1) {
        t.cancel();
        setState(() => _countdown = 0);
        _openPlayer();
      } else {
        setState(() => _countdown -= 1);
      }
    });
  }

  /// The movie now plays right here in the room (16:9, edge to edge), so everybody
  /// still sees the seats, who is watching, the reactions and the room chat.
  void _openPlayer() {
    final m = roomMovie(_room);
    if (m == null) {
      _toast('This movie could not be opened.');
      return;
    }
    setState(() => _playerOn = true);
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  // ----------------------------------------------------------- data

  List<_Seat> get _seats {
    final raw = _room['people'];
    if (raw is List && raw.isNotEmpty) {
      return [
        for (final p in raw)
          if (p is Map)
            _Seat('${p['email']}', '${p['name']}', '${p['photoUrl'] ?? ''}',
                '${p['state']}'),
      ];
    }
    return [
      _Seat('${_room['hostEmail']}', '${_room['hostName'] ?? 'Host'}', '',
          'host'),
    ];
  }

  String get _myState {
    for (final s in _seats) {
      if (s.email.toLowerCase() == _me) return s.state;
    }
    return 'pending';
  }

  // ----------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final movie = roomMovie(_room);
    final title = roomTitle(_room);
    final seats = _seats;
    final mine = _myState;
    final joined = mine == 'host' || mine == 'accepted';
    final guests =
        seats.where((s) => s.state == 'accepted' || s.state == 'host').length;

    return PopScope(
      canPop: !_immersive,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handle.exitImmersive?.call();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF07030A),
        body: Stack(
          children: [
            // Room: dark hall, curtains, light cone.
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _glow,
                builder: (_, __) => CustomPaint(
                  painter: _HallPainter(_glow.value),
                ),
              ),
            ),
            SafeArea(
              top: !_immersive,
              bottom: !_immersive,
              left: !_immersive,
              right: !_immersive,
              child: LayoutBuilder(
                builder: (context, box) {
                  final playerH =
                      _immersive ? box.maxHeight : box.maxWidth * 9 / 16;
                  return Column(
                    children: [
                      Visibility(visible: !_immersive, child: _topBar(title)),
                      _playerSlot(movie, title, seats, joined, playerH),
                      Expanded(
                        child: Visibility(
                          visible: !_immersive,
                          child: Column(
                            children: [
                              if (_playerOn) _playerStrip(),
                              Expanded(
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Column(
                                    children: [
                                      SizedBox(height: _playerOn ? 10 : 14),
                                      _statusLine(joined, guests, seats.length),
                                      SizedBox(height: 12),
                                      _playerOn
                                          ? _seatStrip(seats)
                                          : _seatRows(seats),
                                      SizedBox(height: 14),
                                      _controls(joined, mine),
                                    ],
                                  ),
                                ),
                              ),
                              _chat(joined),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            if (_immersive && _floatChat && _msgs.isNotEmpty) _floatingChat(),
            // Floating reactions.
            for (final f in _floats)
              _FloatingEmoji(key: f.key, emoji: f.emoji, x: f.x),
            if (_countdown > 0) _countdownOverlay(),
          ],
        ),
      ),
    );
  }

  /// The screen of the hall. Full width, drawn over the curtains on both sides.
  /// Shows the poster until the show starts, then the real player.
  Widget _playerSlot(Movie? movie, String title, List<_Seat> seats, bool joined,
      double height) {
    final on = _playerOn && movie != null;
    final watching =
        seats.where((s) => s.state == 'host' || s.state == 'accepted').toList();
    return AnimatedBuilder(
      animation: _glow,
      builder: (_, child) => Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.black,
          border: _immersive
              ? null
              : Border.symmetric(
                  horizontal: BorderSide(
                      color: _gold.withValues(alpha: .55), width: 1.2)),
          boxShadow: _immersive
              ? null
              : [
                  BoxShadow(
                      color: Ui.red.withValues(alpha: .25 + .25 * _glow.value),
                      blurRadius: 44 + 20 * _glow.value,
                      spreadRadius: 2),
                ],
        ),
        child: child,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (on)
            MoviePlayerScreen(
              movie: movie,
              embedded: true,
              handle: _handle,
              onImmersiveChanged: (v) {
                if (mounted && v != _immersive) setState(() => _immersive = v);
              },
            )
          else
            GestureDetector(
              onTap: (_started && joined) ? _beginCountdown : null,
              child: _poster(movie, title),
            ),
          if (on && !_immersive && watching.isNotEmpty)
            Positioned(
              top: 8,
              right: 10,
              child: IgnorePointer(child: _watchersChip(watching)),
            ),
        ],
      ),
    );
  }

  /// Chat bubble stack floating over the fullscreen movie. Comes up whenever
  /// somebody comments; the X closes it until the next comment.
  Widget _floatingChat() {
    final recent = _msgs.length > 3 ? _msgs.sublist(_msgs.length - 3) : _msgs;
    final w = MediaQuery.sizeOf(context).width;
    return Positioned(
      left: 0,
      bottom: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 0, 72),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: math.min(240, w * .38)),
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 4, 4, 8),
              // See-through card: no solid background, so the movie shows
              // through. Text shadows keep every message readable.
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.forum_rounded,
                          size: 14, color: _gold, shadows: _chatShadow),
                      SizedBox(width: 6),
                      Text('Room chat'.tr,
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w900,
                              shadows: _chatShadow,
                              color: Colors.white)),
                      const Spacer(),
                      InkWell(
                        onTap: _hideFloatChat,
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: EdgeInsets.all(5),
                          child: Icon(Icons.close_rounded,
                              size: 18,
                              color: Colors.white,
                              shadows: _chatShadow),
                        ),
                      ),
                    ],
                  ),
                  for (final m in recent)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text.rich(
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          TextSpan(children: [
                            TextSpan(
                                text: m.email == _me
                                    ? 'You  '
                                    : '${m.name.split(' ').first}  ',
                                style: TextStyle(
                                    color: m.email == _me ? _gold : Ui.redSoft,
                                    fontWeight: FontWeight.w900,
                                    shadows: _chatShadow,
                                    fontSize: 11.5)),
                            TextSpan(
                                text: m.text,
                                style: const TextStyle(
                                    shadows: _chatShadow,
                                    fontSize: 12,
                                    color: Colors.white)),
                          ])),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Small badge on the player so everyone can see it is a shared watch.
  Widget _watchersChip(List<_Seat> watching) {
    final shown = watching.take(3).toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(5, 4, 10, 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14.0 * (shown.length - 1) + 20,
            height: 20,
            child: Stack(
              children: [
                for (var i = 0; i < shown.length; i++)
                  Positioned(
                    left: i * 14.0,
                    child: CircleAvatar(
                      radius: 10,
                      backgroundColor: const Color(0xFF2B1A33),
                      foregroundImage: shown[i].photo.startsWith('http')
                          ? CachedNetworkImageProvider(shown[i].photo)
                          : null,
                      child: Text(
                          shown[i].name.isEmpty
                              ? '?'
                              : shown[i].name[0].toUpperCase(),
                          style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: Colors.white)),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(width: 6),
          Icon(Icons.circle, size: 7, color: Color(0xFF4ADE80)),
          SizedBox(width: 5),
          Text(
              watching.length > 1
                  ? '${watching.length} watching together'
                  : 'Watching',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  /// Reload / Switch / Rotate / Fullscreen / Cast for the embedded player.
  Widget _playerStrip() {
    Widget b(IconData icon, String label, VoidCallback? onTap) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 19, color: Colors.white),
                SizedBox(height: 3),
                Text(label,
                    style: const TextStyle(fontSize: 9, color: Colors.white70)),
              ],
            ),
          ),
        );
    return Container(
      color: Colors.black.withValues(alpha: .55),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          b(Icons.refresh_rounded, 'Reload', () => _handle.reload?.call()),
          b(Icons.swap_horiz_rounded, 'Switch',
              () => _handle.switchSource?.call()),
          b(Icons.screen_rotation_alt_rounded, 'Rotate',
              () => _handle.toggleLandscape?.call()),
          b(Icons.fullscreen_rounded, 'Fullscreen',
              () => _handle.toggleLandscape?.call()),
          b(Icons.cast_rounded, 'Cast', () => _handle.cast?.call()),
        ],
      ),
    );
  }

  /// One compact row of everybody in the room (used while the movie plays).
  Widget _seatStrip(List<_Seat> people) {
    bool here(_Seat p) => p.state == 'host' || p.state == 'accepted';
    final ordered = [
      ...people.where(here),
      ...people.where((p) => !here(p)),
    ];
    return SizedBox(
      height: 82,
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [for (final p in ordered) _seatWidget(p, 2)],
          ),
        ),
      ),
    );
  }

  Widget _topBar(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: Icon(Icons.arrow_back_rounded, color: Colors.white),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('NOW SHOWING'.tr,
                      style: TextStyle(
                          color: _gold.withValues(alpha: .9),
                          fontSize: 10.5,
                          letterSpacing: 2.4,
                          fontWeight: FontWeight.w900)),
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 17,
                          color: Colors.white,
                          fontWeight: FontWeight.w900)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                children: [
                  Icon(Icons.circle, size: 8, color: Color(0xFF4ADE80)),
                  SizedBox(width: 6),
                  Text('LIVE ROOM'.tr,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: .85),
                          fontSize: 10.5,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _poster(Movie? movie, String title) {
    final img = movie?.image ?? '';
    return Stack(
      fit: StackFit.expand,
      children: [
        if (img.startsWith('http'))
          CachedNetworkImage(
            imageUrl: img,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) =>
                const ColoredBox(color: Color(0xFF1B1424)),
          )
        else
          const ColoredBox(color: Color(0xFF1B1424)),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: .15),
                Colors.black.withValues(alpha: .78),
              ],
            ),
          ),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                  _started
                      ? Icons.play_circle_fill_rounded
                      : Icons.theaters_rounded,
                  size: 46,
                  color: Colors.white.withValues(alpha: .92)),
              SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: Colors.white)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statusLine(bool joined, int here, int total) {
    String text;
    if (!joined) {
      text = 'You are invited. Take a seat to join.';
    } else if (_started) {
      text = _playerOn
          ? 'Watching together · $here in the room'
          : 'The show has started.';
    } else if (_isHost) {
      text = here <= 1
          ? 'Waiting for your guest to take a seat…'
          : '$here of $total in their seats. Start when ready.';
    } else {
      text = 'Waiting for the host to start the movie…';
    }
    return Text(text,
        textAlign: TextAlign.center,
        style: TextStyle(
            color: Colors.white.withValues(alpha: .75),
            fontSize: 13,
            fontWeight: FontWeight.w600));
  }

  Widget _seatRows(List<_Seat> people) {
    // At least two rows of five seats so the hall looks full of seats.
    final count = math.max(10, ((people.length + 4) ~/ 5) * 5);
    final seats = List<_Seat?>.generate(
        count, (i) => i < people.length ? people[i] : null);
    // People sit in the front row first, centred.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: [
          for (var r = 0; r < count ~/ 5; r++)
            Padding(
              padding:
                  EdgeInsets.only(bottom: 8, left: r.isOdd ? 0 : 0, right: 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var c = 0; c < 5; c++) _seatWidget(seats[r * 5 + c], r),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _seatWidget(_Seat? p, int row) {
    final size = 52.0 - row * 3;
    if (p == null) {
      return SizedBox(
        width: size + 10,
        height: size + 18,
        child: Center(
          child: Icon(Icons.event_seat_rounded,
              size: size * .8, color: _velvet.withValues(alpha: .35)),
        ),
      );
    }
    final here = p.state == 'host' || p.state == 'accepted';
    final declined = p.state == 'declined';
    final color = here
        ? _gold
        : declined
            ? Colors.white24
            : Colors.white38;
    return SizedBox(
      width: size + 10,
      height: size + 34,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Icon(Icons.event_seat_rounded,
                  size: size,
                  color: here ? _velvet : _velvet.withValues(alpha: .4)),
              Positioned(
                bottom: size * .38,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 1.6),
                    boxShadow: here
                        ? [
                            BoxShadow(
                                color: _gold.withValues(alpha: .45),
                                blurRadius: 10),
                          ]
                        : null,
                  ),
                  child: Opacity(
                    opacity: here ? 1 : .55,
                    child: CircleAvatar(
                      radius: size * .3,
                      backgroundColor: const Color(0xFF2B1A33),
                      foregroundImage: p.photo.startsWith('http')
                          ? CachedNetworkImageProvider(p.photo)
                          : null,
                      child: Text(
                          p.name.isEmpty ? '?' : p.name[0].toUpperCase(),
                          style: TextStyle(
                              fontSize: size * .28,
                              fontWeight: FontWeight.w900,
                              color: Colors.white)),
                    ),
                  ),
                ),
              ),
            ],
          ),
          Text(p.email.toLowerCase() == _me ? 'You' : p.name.split(' ').first,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: here ? Colors.white : Colors.white54)),
          Text(
              p.state == 'host'
                  ? 'host'
                  : p.state == 'accepted'
                      ? 'seated'
                      : p.state == 'declined'
                          ? 'declined'
                          : 'invited',
              style: TextStyle(
                  fontSize: 9, color: Colors.white.withValues(alpha: .45))),
        ],
      ),
    );
  }

  Widget _controls(bool joined, String mine) {
    Widget big(String label, IconData icon, VoidCallback? onTap,
        {bool gold = true}) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy ? null : onTap,
            icon: _busy
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(icon),
            label: Text(label),
            style: FilledButton.styleFrom(
              backgroundColor: gold ? _gold : Colors.white12,
              foregroundColor: gold ? Colors.black : Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              textStyle:
                  const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
      );
    }

    if (!joined) {
      return big('Take a seat', Icons.event_seat_rounded, _accept);
    }
    final reactions = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final e in ['🍿', '😂', '😮', '😢', '❤️', '👏'])
          InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => _react(e),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(e, style: const TextStyle(fontSize: 25)),
            ),
          ),
      ],
    );
    return Column(
      children: [
        if (_isHost && !_started)
          big('Start the movie', Icons.play_arrow_rounded, _start)
        else if (_playerOn)
          const SizedBox.shrink()
        else if (_started)
          big(_isHost ? 'Back to the movie' : 'Join the movie',
              Icons.play_arrow_rounded, _beginCountdown)
        else
          big('Waiting for the host…', Icons.hourglass_top_rounded, null,
              gold: false),
        SizedBox(height: 8),
        reactions,
      ],
    );
  }

  Widget _chat(bool joined) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .72),
        border: const Border(top: BorderSide(color: Colors.white12)),
      ),
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom > 0 ? 0 : 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _chatOpen = !_chatOpen),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 12, 4),
              child: Row(
                children: [
                  Icon(Icons.forum_rounded, size: 16, color: _gold),
                  SizedBox(width: 8),
                  Text('Room chat'.tr,
                      style: TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 13.5)),
                  const Spacer(),
                  Icon(
                      _chatOpen
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_up_rounded,
                      color: Colors.white70),
                ],
              ),
            ),
          ),
          if (_chatOpen)
            SizedBox(
              height: MediaQuery.of(context).viewInsets.bottom > 0 ? 64 : 112,
              child: _msgs.isEmpty
                  ? Center(
                      child: Text('Say something to the room…'.tr,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: .45),
                              fontSize: 12.5)))
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _msgs.length,
                      itemBuilder: (_, i) {
                        final m = _msgs[i];
                        final mine = m.email == _me;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text.rich(TextSpan(children: [
                            TextSpan(
                                text: mine
                                    ? 'You  '
                                    : '${m.name.split(' ').first}  ',
                                style: TextStyle(
                                    color: mine ? _gold : Ui.redSoft,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12.5)),
                            TextSpan(
                                text: m.text,
                                style: const TextStyle(
                                    fontSize: 13, color: Colors.white)),
                          ])),
                        );
                      },
                    ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    enabled: joined,
                    maxLength: 300,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      counterText: '',
                      isDense: true,
                      hintText:
                          joined ? 'Message the room' : 'Take a seat to chat',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: .08),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide.none),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                IconButton.filled(
                  onPressed: joined ? _send : null,
                  style: IconButton.styleFrom(
                      backgroundColor: _gold, foregroundColor: Colors.black),
                  icon: Icon(Icons.send_rounded, size: 20),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _countdownOverlay() => Positioned.fill(
        child: ColoredBox(
          color: Colors.black.withValues(alpha: .82),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('THE SHOW BEGINS IN'.tr,
                    style: TextStyle(
                        color: _gold.withValues(alpha: .9),
                        letterSpacing: 3,
                        fontSize: 12,
                        fontWeight: FontWeight.w900)),
                SizedBox(height: 10),
                TweenAnimationBuilder<double>(
                  key: ValueKey(_countdown),
                  tween: Tween(begin: 1.6, end: 1),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutBack,
                  builder: (_, v, child) =>
                      Transform.scale(scale: v, child: child),
                  child: Text('$_countdown',
                      style: const TextStyle(
                          fontSize: 120,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          decoration: TextDecoration.none)),
                ),
                SizedBox(height: 6),
                Text('Press play together when the movie opens'.tr,
                    style: TextStyle(color: Colors.white60, fontSize: 12.5)),
              ],
            ),
          ),
        ),
      );
}

/// One emoji drifting up the screen and fading out.
class _FloatingEmoji extends StatelessWidget {
  final String emoji;
  final double x;
  const _FloatingEmoji({super.key, required this.emoji, required this.x});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Positioned(
      left: x * (size.width - 44),
      bottom: 0,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 2500),
          curve: Curves.easeOut,
          builder: (_, t, child) => Transform.translate(
            offset: Offset(math.sin(t * 6) * 14, -size.height * .5 * t - 120),
            child: Opacity(
                opacity: (1 - t).clamp(0.0, 1.0).toDouble(), child: child),
          ),
          child: Text(emoji,
              style: const TextStyle(
                  fontSize: 34, decoration: TextDecoration.none)),
        ),
      ),
    );
  }
}

/// Dark hall with velvet curtains on both sides, a valance on top and the
/// light cone of the projector, which breathes slowly.
class _HallPainter extends CustomPainter {
  final double t;
  _HallPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF12060E), Color(0xFF07030A)],
          ).createShader(Offset.zero & size));

    // Light cone from the top centre.
    final cone = Path()
      ..moveTo(w * .46, 0)
      ..lineTo(w * .54, 0)
      ..lineTo(w * .88, h * .55)
      ..lineTo(w * .12, h * .55)
      ..close();
    canvas.drawPath(
        cone,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: .07 + .04 * t),
              Colors.transparent,
            ],
          ).createShader(Rect.fromLTWH(0, 0, w, h * .55)));

    // Curtains.
    void curtain(bool left) {
      final cw = w * .15;
      final x0 = left ? 0.0 : w - cw;
      final rect = Rect.fromLTWH(x0, 0, cw, h);
      canvas.drawRect(
          rect,
          Paint()
            ..shader = LinearGradient(
              begin: left ? Alignment.centerLeft : Alignment.centerRight,
              end: left ? Alignment.centerRight : Alignment.centerLeft,
              colors: [
                _velvetDark,
                _velvet.withValues(alpha: .85),
                _velvetDark.withValues(alpha: 0)
              ],
              stops: [0, .6, 1],
            ).createShader(rect));
      // Folds.
      final fold = Paint()
        ..color = Colors.black.withValues(alpha: .28)
        ..strokeWidth = 2;
      for (var i = 1; i < 6; i++) {
        final x = x0 + cw * i / 6 + math.sin(i + t * 1.5) * 2;
        canvas.drawLine(Offset(x, 0), Offset(x + (left ? 6 : -6), h), fold);
      }
    }

    curtain(true);
    curtain(false);

    // Valance on top.
    final valance = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h * .045);
    const scallops = 7;
    for (var i = scallops; i > 0; i--) {
      final x1 = w * (i - .5) / scallops;
      final x2 = w * (i - 1) / scallops;
      valance.quadraticBezierTo(x1, h * .085, x2, h * .045);
    }
    valance.close();
    canvas.drawPath(
        valance,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_velvet, _velvetDark],
          ).createShader(Rect.fromLTWH(0, 0, w, h * .09)));
    canvas.drawPath(
        valance,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = _gold.withValues(alpha: .55));
  }

  @override
  bool shouldRepaint(_HallPainter old) => old.t != t;
}
