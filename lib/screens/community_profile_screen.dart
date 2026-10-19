import 'package:flutter/material.dart';

import '../services/community_service.dart';
import '../services/movie_library.dart';
import '../services/profile_data.dart';
import 'library_screen.dart';
import 'profile_collections_screen.dart';
import 'watch_together_screen.dart';
import '../theme/app_theme.dart';
import '../utils/l10n.dart';
import '../widgets/community_widgets.dart';

/// A member's public profile: how active they are, their last movie tweet,
/// their last recommendation and everything else they posted.
class CommunityProfileScreen extends StatefulWidget {
  final String email;
  final String? name;
  final String? photoUrl;
  const CommunityProfileScreen(
      {super.key, required this.email, this.name, this.photoUrl});

  @override
  State<CommunityProfileScreen> createState() => _CommunityProfileScreenState();
}

class _CommunityProfileScreenState extends State<CommunityProfileScreen> {
  CommunityProfile? _profile;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await CommunityService.instance.profile(widget.email);
      if (mounted) {
        setState(() {
          _profile = p;
          _error = null;
        });
      }
    } on CommunityException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(
        backgroundColor: Ui.bg,
        title: Text((p?.mine ?? false ? 'My posts' : 'Profile').tr,
            style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: p == null ? _loading() : _content(p),
    );
  }

  Widget _loading() {
    if (_error != null) {
      return CommunityMessage(
        icon: Icons.cloud_off_rounded,
        title: 'Could not load this profile',
        hint: _error!,
        action: 'Try again',
        onAction: () {
          setState(() => _error = null);
          _load();
        },
      );
    }
    return Column(
      children: [
        const SizedBox(height: 8),
        _header(
            widget.name ?? '', widget.photoUrl ?? '', null, posts: 0, likes: 0),
        const Expanded(child: Center(child: CircularProgressIndicator())),
      ],
    );
  }

  Widget _header(String name, String photo, String? bio,
      {required int posts, required int likes, String? email, bool badges = false}) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Ui.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Ui.glassLine),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CommunityAvatar(url: photo, name: name, radius: 34),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name.isEmpty ? '…' : name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -.3)),
                    if (email != null && email.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Ui.muted, fontSize: 13)),
                    ],
                    if (badges)
                      ListenableBuilder(
                        listenable: ProfileData.instance,
                        builder: (_, __) => Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(children: [
                            Icon(Icons.workspace_premium_rounded,
                                size: 16, color: Colors.amber),
                            const SizedBox(width: 6),
                            Text(
                                '${ProfileData.instance.badgesEarned}/10 ${'Badges'.tr}',
                                style: TextStyle(
                                    color: Ui.muted,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700)),
                          ]),
                        ),
                      ),
                    if (bio != null && bio.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(bio,
                          style: TextStyle(color: Ui.muted, fontSize: 13)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _stat(Icons.forum_rounded, '$posts', 'Posts'),
              const SizedBox(width: 10),
              _stat(Icons.favorite_rounded, '$likes', 'Likes received'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Ui.glassLine),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Ui.redSoft),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w900)),
                  Text(label.tr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Ui.muted, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }


  // ---- Profile grid (own profile only) ----------------------------------

  void _open(Widget screen) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => screen));

  void _openLibrary(int tab) => _open(LibraryScreen(initialTab: tab));

  Widget _statGrid() {
    final lib = MovieLibrary.instance;
    final data = ProfileData.instance;
    lib.load();
    data.load();
    return ListenableBuilder(
      listenable: Listenable.merge([lib, data]),
      builder: (context, _) {
        final tiles = <Widget>[
          _tile(Icons.star_rounded, 'Ratings', data.ratings.length,
              () => _open(const RatingsScreen())),
          _tile(Icons.history_rounded, 'Watch history', lib.history.length,
              () => _openLibrary(1)),
          _tile(Icons.category_rounded, 'Interests', data.interests.length,
              () => _open(const InterestsScreen())),
          _tile(Icons.bookmark_rounded, 'Watchlist', lib.saved.length,
              () => _openLibrary(0)),
          _tile(Icons.rate_review_rounded, 'Reviews', data.reviews.length,
              () => _open(const ReviewsScreen())),
          _tile(Icons.workspace_premium_rounded, 'Badges', data.badgesEarned,
              () => _open(const BadgesScreen())),
          _tile(Icons.format_list_bulleted_rounded, 'Lists', data.lists.length,
              () => _open(const ListsScreen())),
          _tile(Icons.check_circle_outline_rounded, 'Check-ins', data.checkIns.length,
              () => _open(const CheckInsScreen())),
          _tile(Icons.people_alt_rounded, 'Favorite people', data.people.length,
              () => _open(const FavoritePeopleScreen())),
        ];
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: GridView.count(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: .98,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: tiles,
          ),
        );
      },
    );
  }

  Widget _tile(IconData icon, String label, int count, VoidCallback onTap) {
    return Material(
      color: Ui.card,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Ui.glassLine),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 28, color: Ui.redSoft),
              const SizedBox(height: 8),
              Text(label.tr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('$count',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700, color: Ui.muted)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String title, IconData icon) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Ui.redSoft),
            const SizedBox(width: 8),
            Text(title.tr,
                style: const TextStyle(
                    fontSize: 15.5, fontWeight: FontWeight.w900)),
          ],
        ),
      );

  Widget _content(CommunityProfile p) {
    final others = p.posts
        .where((x) => x.id != p.lastTweet?.id && x.id != p.lastRecommendation?.id)
        .toList();
    return RefreshIndicator(
      color: Ui.red,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _header(p.name, p.photoUrl, p.bio,
              posts: p.postCount,
              likes: p.likeCount,
              email: p.mine ? p.email : null,
              badges: p.mine),
          if (p.mine) _statGrid(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => WatchTogetherScreen(
                      inviteEmail: p.mine ? null : p.email),
                )),
                icon: const Icon(Icons.groups_rounded),
                label: const Text('Watch Together'),
                style: FilledButton.styleFrom(
                  backgroundColor: Ui.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
              ),
            ),
          ),
          _section('Last movie tweet', Icons.chat_bubble_rounded),
          _slot(p.lastTweet, 'No movie tweets yet.'),
          _section('Last recommendation', Icons.thumb_up_alt_rounded),
          _slot(p.lastRecommendation, 'No recommendations yet.'),
          if (others.isNotEmpty) ...[
            _section('Earlier posts', Icons.history_rounded),
            for (final post in others)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: PostCard(post: post, showAuthor: false),
              ),
          ],
        ],
      ),
    );
  }

  Widget _slot(CommunityPost? post, String empty) {
    if (post == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
        child: Text(empty.tr, style: TextStyle(color: Ui.muted)),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: PostCard(post: post, showAuthor: false),
    );
  }
}

/// Everyone in the community, most active first, with a search box.
class CommunityPeopleScreen extends StatefulWidget {
  const CommunityPeopleScreen({super.key});

  @override
  State<CommunityPeopleScreen> createState() => _CommunityPeopleScreenState();
}

class _CommunityPeopleScreenState extends State<CommunityPeopleScreen> {
  List<CommunityPerson>? _people;
  String? _error;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await CommunityService.instance.people();
      if (mounted) {
        setState(() {
          _people = list;
          _error = null;
        });
      }
    } on CommunityException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = _people;
    final list = all == null
        ? const <CommunityPerson>[]
        : all
            .where((p) => p.name.toLowerCase().contains(_q.trim().toLowerCase()))
            .toList();
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(
        backgroundColor: Ui.bg,
        title: Text('Movie fans'.tr,
            style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(
                hintText: 'Search people'.tr,
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: Colors.white.withValues(alpha: .06),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: all == null
                ? (_error != null
                    ? CommunityMessage(
                        icon: Icons.cloud_off_rounded,
                        title: 'Could not load people',
                        hint: _error!,
                        action: 'Try again',
                        onAction: _load)
                    : const Center(child: CircularProgressIndicator()))
                : list.isEmpty
                    ? const CommunityMessage(
                        icon: Icons.people_outline_rounded,
                        title: 'Nobody found',
                        hint: 'Try another name.')
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 24),
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final p = list[i];
                          return ListTile(
                            onTap: () => openCommunityProfile(context, p.email,
                                name: p.name, photoUrl: p.photoUrl),
                            leading: CommunityAvatar(
                                url: p.photoUrl, name: p.name, radius: 21),
                            title: Text(p.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800)),
                            subtitle: Text(
                                '${p.postCount} ${'posts'.tr}',
                                style:
                                    TextStyle(color: Ui.muted, fontSize: 12)),
                            trailing: Icon(Icons.chevron_right_rounded,
                                color: Ui.dim),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
