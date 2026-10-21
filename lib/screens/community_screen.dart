import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/community_service.dart';
import '../theme/app_theme.dart';
import '../utils/l10n.dart';
import '../widgets/community_widgets.dart';
import 'community_composer.dart';
import 'community_profile_screen.dart';
import 'watch_together_screen.dart';
import 'theatre_screen.dart';
import 'dart:async';

/// Movie Community: a feed of movie tweets and recommendations. Tap a name to
/// open that person's profile, tap a post to like and comment.
///
/// As a bottom tab it loads the first time it is shown ([active]); opened from
/// the menu it is [standalone] and has a back button.
class CommunityScreen extends StatefulWidget {
  final bool active;
  final bool standalone;
  const CommunityScreen(
      {super.key, this.active = true, this.standalone = false});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  final _svc = CommunityService.instance;
  bool _started = false;
  bool _showLive = false;
  List<Map<String, dynamic>> _liveRooms = [];
  Timer? _liveTimer;
  bool _liveBusy = false;
  String? _liveError;

  Future<void> _loadLive() async {
    if (_liveBusy) return;
    _liveBusy = true;
    try {
      final rooms = await _svc.publicWatchRooms();
      if (mounted) setState(() { _liveRooms = rooms; _liveError = null; });
    } catch (e) {
      if (mounted) setState(() => _liveError = 'Could not load live rooms. Update the Community Worker.');
    } finally { _liveBusy = false; }
  }

  Future<void> _joinLive(Map<String, dynamic> room) async {
    try {
      final joined = await _svc.joinPublicWatchRoom('${room['id']}');
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TheatreScreen(room: joined)));
      _loadLive();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unable to join room: $e')));
    }
  }

  Future<void> _createLive() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const WatchTogetherScreen(publicMode: true)));
    if (mounted) { setState(() => _showLive = true); _loadLive(); }
  }

  @override
  void dispose() { _liveTimer?.cancel(); super.dispose(); }


  @override
  void initState() {
    super.initState();
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(CommunityScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !_started) _start();
  }

  void _start() {
    _started = true;
    _svc.load();
    _loadLive();
    _liveTimer ??= Timer.periodic(const Duration(seconds: 12), (_) => _loadLive());
  }

  static const _filters = <(String, String)>[
    ('', 'All'),
    ('live', 'Watching Now'),
    ('tweet', 'Tweets'),
    ('recommendation', 'Recommended'),
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_svc, AuthService.instance]),
      builder: (context, _) {
        final posts = _svc.feed;
        return Scaffold(
          backgroundColor: Ui.bg,
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
          floatingActionButton: DecoratedBox(
            decoration: BoxDecoration(
              gradient: Ui.gradient,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                    color: Ui.red.withValues(alpha: .45),
                    blurRadius: 20,
                    offset: const Offset(0, 8)),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => showCommunityComposer(context),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit_rounded,
                          size: 20, color: Ui.palette.onAccent),
                      SizedBox(width: 8),
                      Text('Post'.tr,
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: Ui.palette.onAccent)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          body: SafeArea(
            bottom: false,
            child: RefreshIndicator(
              color: Ui.red,
              onRefresh: () => _svc.load(),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _header(context)),
                  SliverToBoxAdapter(child: _composerTeaser(context)),
                  SliverToBoxAdapter(child: _chips()),
                  if (_showLive) SliverToBoxAdapter(child: _liveSection()) else ...[
                    SliverToBoxAdapter(child: _livePreview()),
                    ..._body(context, posts),
                  ],
                  const SliverToBoxAdapter(child: SizedBox(height: 96)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _livePreview() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      OutlinedButton.icon(onPressed: _createLive, icon: const Icon(Icons.live_tv_rounded), label: const Text('Start Watching Now')),
      for (final room in _liveRooms.take(3)) ListTile(
        leading: const Icon(Icons.circle, color: Colors.green, size: 13),
        title: Text('LIVE · ${roomTitle(room)}'),
        subtitle: Text('${(room['people'] as List?)?.where((p) => p is Map && (p['state'] == 'host' || p['state'] == 'accepted')).length ?? 1} watching'),
        trailing: const Icon(Icons.play_arrow),
        onTap: () => _joinLive(room),
      ),
    ]),
  );

  Widget _liveSection() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FilledButton.icon(onPressed: _createLive, icon: const Icon(Icons.live_tv_rounded), label: const Text('Start Watching Now')),
        const SizedBox(height: 14),
        if (_liveError != null) Text(_liveError!, style: const TextStyle(color: Colors.orangeAccent)),
        if (_liveRooms.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No public rooms yet. Start one!'))),
        for (final room in _liveRooms) Card(
          child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [const Icon(Icons.circle, color: Colors.green, size: 12), const SizedBox(width: 8), const Text('WATCHING NOW', style: TextStyle(fontWeight: FontWeight.bold)), const Spacer(), Text('${(room['people'] as List?)?.where((p) => p is Map && (p['state'] == 'host' || p['state'] == 'accepted')).length ?? 1} watching')]),
            const SizedBox(height: 12),
            Text(roomTitle(room), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text('Hosted by ${room['hostName'] ?? 'Movie fan'}'),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () => _joinLive(room), icon: const Icon(Icons.play_arrow), label: const Text('Join Watch'))),
          ])),
        ),
      ]),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
      child: Row(
        children: [
          if (widget.standalone)
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: Icon(Icons.arrow_back_rounded),
            )
          else
            SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Community'.tr,
                    style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.5)),
                Text('Movie tweets & recommendations'.tr,
                    style: TextStyle(color: Ui.muted, fontSize: 12.5)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Movie fans'.tr,
            icon: Icon(Icons.people_alt_rounded),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const CommunityPeopleScreen())),
          ),
        ],
      ),
    );
  }

  Widget _composerTeaser(BuildContext context) {
    final user = AuthService.instance.user;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Material(
        color: Colors.white.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => showCommunityComposer(context),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Ui.glassLine),
            ),
            child: Row(
              children: [
                CommunityAvatar(
                    url: user?.photoUrl ?? '',
                    name: user?.name ?? '',
                    radius: 19),
                SizedBox(width: 12),
                Expanded(
                  child: Text('What are you watching?'.tr,
                      style: TextStyle(color: Ui.muted, fontSize: 14.5)),
                ),
                Icon(Icons.movie_filter_rounded, color: Ui.redSoft),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chips() {
    return SizedBox(
      height: 54,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        children: [
          for (final (kind, label) in _filters)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(label.tr),
                selected: kind == 'live' ? _showLive : (!_showLive && _svc.kind == kind),
                showCheckmark: false,
                selectedColor: Ui.red,
                backgroundColor: Colors.white.withValues(alpha: .06),
                side: BorderSide(color: Ui.glassLine),
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: (kind == 'live' ? _showLive : (!_showLive && _svc.kind == kind)) ? Ui.palette.onAccent : Ui.muted,
                ),
                onSelected: (_) { setState(() => _showLive = kind == 'live'); if (kind == 'live') { _loadLive(); } else { _svc.load(kind: kind); } },
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _body(BuildContext context, List<CommunityPost> posts) {
    if (!_svc.loaded || (_svc.loading && posts.isEmpty)) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_svc.error != null && posts.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: CommunityMessage(
            icon: Icons.cloud_off_rounded,
            title: 'Could not load the community',
            hint: _svc.error!,
            action: 'Try again',
            onAction: () => _svc.load(),
          ),
        ),
      ];
    }
    if (posts.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: CommunityMessage(
            icon: Icons.forum_outlined,
            title: 'No posts yet',
            hint: 'Be the first to share a movie tweet or recommendation.',
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        sliver: SliverList.separated(
          itemCount: posts.length,
          separatorBuilder: (_, __) => SizedBox(height: 12),
          itemBuilder: (_, i) => PostCard(post: posts[i]),
        ),
      ),
    ];
  }
}
