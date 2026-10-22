import 'dart:io';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
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

  /// True when shown as the bottom-bar Profile tab (no back button).
  final bool asTab;

  /// For the tab: whether it is the selected one. The profile reloads each
  /// time it becomes visible so new posts and counts are up to date.
  final bool active;
  const CommunityProfileScreen(
      {super.key,
      required this.email,
      this.name,
      this.photoUrl,
      this.asTab = false,
      this.active = true});

  @override
  State<CommunityProfileScreen> createState() => _CommunityProfileScreenState();
}

class _CommunityProfileScreenState extends State<CommunityProfileScreen> {
  CommunityProfile? _profile;
  String? _error;
  String _nickname = '';
  String _avatarPath = '';
  Map<String, dynamic>? _publicData;
  String get _key =>
      widget.email.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
  bool get _mine {
    final own = AuthService.instance.user?.email.trim().toLowerCase();
    final viewed = widget.email.trim().toLowerCase();
    return own != null && own.isNotEmpty && own == viewed;
  }

  @override
  void initState() {
    super.initState();
    _load();
    _loadEdits();
    _loadPublicData();
  }

  @override
  void didUpdateWidget(covariant CommunityProfileScreen old) {
    super.didUpdateWidget(old);
    if (widget.asTab && widget.active && !old.active) {
      _load();
      _loadEdits();
      _loadPublicData();
      _loadPublicData();
    }
    if (widget.email != old.email) {
      _nickname = '';
      _avatarPath = '';
      _load();
      _loadEdits();
      _loadPublicData();
      _loadPublicData();
    }
  }

  Future<void> _loadPublicData() async {
    try {
      final data = await CommunityService.instance.profileData(widget.email);
      if (mounted) setState(() => _publicData = data);
    } catch (e) {
      debugPrint('Public profile load: $e');
    }
  }

  Future<void> _publishMyProfile() async {
    if (!_mine) return;
    try {
      await Future.wait([ProfileData.instance.load(), MovieLibrary.instance.load()]);
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('damimovies_profile_v1');
      final details = raw == null ? <String, dynamic>{} :
          Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final library = MovieLibrary.instance;
      details['watchlist'] = library.saved.map((m) => m.toJson()).toList();
      details['history'] = library.history.map((m) => m.toJson()).toList();
      details['badges'] = ProfileData.instance.badgesEarned;
      await CommunityService.instance.pushProfileData(details);
      if (mounted) setState(() => _publicData = details);
    } catch (e) {
      debugPrint('Public profile publish: $e');
    }
  }

  Future<void> _loadEdits() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _nickname = prefs.getString('movie_nick_$_key') ?? '';
      _avatarPath = prefs.getString('movie_avatar_$_key') ?? '';
    });
  }

  void _editError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _editNickname() async {
    if (!_mine) return;
    // The dialog owns its text field. Returning the entered value before
    // disposing the route avoids using a disposed TextEditingController.
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        var draft = _nickname;
        return AlertDialog(
          title: Text('Movie nickname'.tr),
          content: TextFormField(
            initialValue: _nickname,
            autofocus: true,
            maxLength: 24,
            textCapitalization: TextCapitalization.none,
            onChanged: (value) => draft = value,
            decoration: const InputDecoration(
              hintText: 'CinemaKing, MovieBuff...',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('Cancel'.tr),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, draft.trim()),
              child: Text('Save'.tr),
            ),
          ],
        );
      },
    );
    if (result == null || !mounted) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setString('movie_nick_$_key', result);
      if (!saved) throw StateError('Could not save nickname');
      if (mounted) {
        setState(() => _nickname = result);
        _editError('Movie nickname saved.');
      }
    } catch (error) {
      debugPrint('Profile nickname error: $error');
      _editError('Could not save movie nickname: $error');
    }
  }

  Future<void> _changeAvatar() async {
    if (!_mine) return;
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 900,
      );
      if (image == null) return;
      final dir = await getApplicationDocumentsDirectory();
      // A unique filename prevents Flutter's FileImage cache from displaying
      // the old avatar after the user chooses a different photo.
      final destination = File(
        '${dir.path}/avatar_${_key}_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      if (!await File(image.path).exists()) {
        throw StateError('Selected image is unavailable');
      }
      await File(image.path).copy(destination.path);
      final prefs = await SharedPreferences.getInstance();
      final previous = _avatarPath;
      final saved = await prefs.setString('movie_avatar_$_key', destination.path);
      if (!saved) throw StateError('Could not save avatar');
      if (!mounted) return;
      setState(() => _avatarPath = destination.path);
      _editError('Profile photo saved.');
      if (previous.isNotEmpty && previous != destination.path) {
        try {
          final oldFile = File(previous);
          if (await oldFile.exists()) await oldFile.delete();
        } catch (_) {}
      }
    } catch (error) {
      debugPrint('Profile photo error: $error');
      _editError('Could not update profile photo: $error');
    }
  }

  Future<void> _logout() async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text('Log out?'.tr),
              content: Text('You will need to sign in again.'.tr),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text('Cancel'.tr)),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text('Log out'.tr))
              ],
            ));
    if (yes == true) await AuthService.instance.signOut();
  }

  Future<void> _load() async {
    try {
      final p = await CommunityService.instance.profile(widget.email);
      if (p.mine) await _publishMyProfile();
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
        automaticallyImplyLeading: !widget.asTab,
        title: Text(
            (!widget.asTab && (p?.mine ?? false) ? 'My profile' : 'Profile').tr,
            style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: SafeArea(
          top: false,
          bottom: true,
          child: p == null ? _loading() : _content(p)),
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
        SizedBox(height: 8),
        _header(widget.name ?? '', widget.photoUrl ?? '', null,
            posts: 0, likes: 0),
        Expanded(child: Center(child: CircularProgressIndicator())),
      ],
    );
  }

  Widget _header(String name, String photo, String? bio,
      {required int posts,
      required int likes,
      String? email,
      bool badges = false}) {
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
              GestureDetector(
                onTap: _mine ? _changeAvatar : null,
                child: Stack(alignment: Alignment.bottomRight, children: [
                  if (_mine &&
                      _avatarPath.isNotEmpty &&
                      File(_avatarPath).existsSync())
                    CircleAvatar(
                        radius: 36,
                        backgroundImage: FileImage(File(_avatarPath)))
                  else
                    CommunityAvatar(
                        url: _mine ? '' : photo, name: name, radius: 34),
                  if (_mine)
                    CircleAvatar(
                        radius: 12,
                        backgroundColor: Ui.red,
                        child: Icon(Icons.edit, size: 13, color: Colors.white)),
                ]),
              ),
              SizedBox(width: 16),
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
                    if (_mine) ...[
                      SizedBox(height: 5),
                      InkWell(
                          onTap: _editNickname,
                          child: Row(children: [
                            Flexible(
                                child: Text(
                                    _nickname.isEmpty
                                        ? 'Add movie nickname'
                                        : '@$_nickname',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: Ui.redSoft, fontSize: 13))),
                            SizedBox(width: 5),
                            Icon(Icons.edit_rounded,
                                size: 14, color: Ui.redSoft),
                          ])),
                    ],
                    if (badges)
                      ListenableBuilder(
                        listenable: ProfileData.instance,
                        builder: (_, __) => Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(children: [
                            Icon(Icons.workspace_premium_rounded,
                                size: 16, color: Colors.amber),
                            SizedBox(width: 6),
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
                      SizedBox(height: 4),
                      Text(bio,
                          style: TextStyle(color: Ui.muted, fontSize: 13)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Row(
            children: [
              _stat(Icons.forum_rounded, '$posts', 'Posts'),
              SizedBox(width: 10),
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
            SizedBox(width: 10),
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
          _tile(Icons.check_circle_outline_rounded, 'Check-ins',
              data.checkIns.length, () => _open(const CheckInsScreen())),
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

  Widget _publicStatGrid() {
    final d = _publicData;
    final sections = <(IconData, String, String)>[
      (Icons.star_rounded, 'Ratings', 'ratings'),
      (Icons.history_rounded, 'Watch history', 'history'),
      (Icons.category_rounded, 'Interests', 'interests'),
      (Icons.bookmark_rounded, 'Watchlist', 'watchlist'),
      (Icons.rate_review_rounded, 'Reviews', 'reviews'),
      (Icons.workspace_premium_rounded, 'Badges', 'badges'),
      (Icons.format_list_bulleted_rounded, 'Lists', 'lists'),
      (Icons.check_circle_outline_rounded, 'Check-ins', 'checkIns'),
      (Icons.people_alt_rounded, 'Favorite people', 'people'),
    ];
    int count(String key) {
      final value = d?[key];
      return value is List ? value.length : value is num ? value.toInt() : 0;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: GridView.count(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: .98,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (final item in sections)
            _tile(item.$1, item.$2, count(item.$3), () {
              final value = d?[item.$3];
              _openPublicDetails(item.$2, value);
            }),
        ],
      ),
    );
  }

  void _openPublicDetails(String title, dynamic value) {
    final entries = value is List ? value : const [];
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (ctx) => Scaffold(
        backgroundColor: Ui.bg,
        appBar: AppBar(title: Text(title), backgroundColor: Ui.bg),
        body: entries.isEmpty
            ? Center(child: Text('Nothing shared yet', style: TextStyle(color: Ui.muted)))
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: entries.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (_, i) {
                  final entry = entries[i];
                  if (entry is String) return ListTile(title: Text(entry));
                  if (entry is Map) {
                    final movie = entry['movie'];
                    final details = movie is Map ? movie : entry;
                    final name = details['title'] ?? details['name'] ??
                        entry['name'] ?? 'Movie';
                    final extra = entry['text'] ??
                        (entry['stars'] == null ? null : '${entry['stars']}/5 stars');
                    return ListTile(
                      title: Text('$name'),
                      subtitle: extra == null ? null : Text('$extra'),
                    );
                  }
                  return ListTile(title: Text('$entry'));
                },
              ),
      ),
    ));
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
              SizedBox(height: 8),
              Text(label.tr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w800)),
              SizedBox(height: 4),
              Text('$count',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Ui.muted)),
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
            SizedBox(width: 8),
            Text(title.tr,
                style: const TextStyle(
                    fontSize: 15.5, fontWeight: FontWeight.w900)),
          ],
        ),
      );

  Widget _content(CommunityProfile p) {
    final others = p.posts
        .where(
            (x) => x.id != p.lastTweet?.id && x.id != p.lastRecommendation?.id)
        .toList();
    return RefreshIndicator(
      color: Ui.red,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding:
            EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 48),
        children: [
          _header(p.name, p.photoUrl, p.bio,
              posts: p.postCount,
              likes: p.likeCount,
              email: null,
              badges: p.mine),
          if (p.mine) _statGrid() else _publicStatGrid(),
          if (p.mine)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: OutlinedButton.icon(
                  onPressed: _logout,
                  icon: Icon(Icons.logout_rounded),
                  label: Text('Log out'.tr)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () =>
                    Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) =>
                      WatchTogetherScreen(inviteEmail: p.mine ? null : p.email),
                )),
                icon: Icon(Icons.groups_rounded),
                label: Text('Watch Together'.tr),
                style: FilledButton.styleFrom(
                  backgroundColor: Ui.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15)),
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
            .where(
                (p) => p.name.toLowerCase().contains(_q.trim().toLowerCase()))
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
                prefixIcon: Icon(Icons.search_rounded),
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
                    : Center(child: CircularProgressIndicator()))
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
                            subtitle: Text('${p.postCount} ${'posts'.tr}',
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
