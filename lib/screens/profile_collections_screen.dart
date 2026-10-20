import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/movie.dart';
import '../services/movie_library.dart';
import '../services/profile_data.dart';
import '../services/tmdb_service.dart';
import '../theme/app_theme.dart';
import '../utils/l10n.dart';
import 'movie_detail_screen.dart';

// ---------------------------------------------------------------------------
// Shared helpers (also used by the movie detail screen)
// ---------------------------------------------------------------------------

void openMovie(BuildContext context, Movie movie) {
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => MovieDetailScreen(
      movie: movie,
      saved: MovieLibrary.instance.isSaved(movie),
      onToggleSaved: () async {
        await MovieLibrary.instance.toggleSaved(movie);
      },
    ),
  ));
}

void _toast(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

String _date(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}  ${two(d.hour)}:${two(d.minute)}';
}

Future<String?> _askText(BuildContext context, String title,
    {String initial = '',
    String hint = '',
    int lines = 1,
    bool allowEmpty = false}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Ui.card,
      title: Text(title.tr),
      content: TextField(
        controller: c,
        autofocus: true,
        minLines: lines,
        maxLines: lines == 1 ? 1 : lines + 3,
        maxLength: lines == 1 ? 60 : 600,
        decoration: InputDecoration(hintText: hint.tr),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: Text('Cancel'.tr)),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Ui.red),
          onPressed: () {
            final t = c.text.trim();
            if (t.isEmpty && !allowEmpty) return;
            Navigator.pop(ctx, t);
          },
          child: Text('Save'.tr),
        ),
      ],
    ),
  );
}

Future<void> showRatingSheet(BuildContext context, Movie movie) async {
  final data = ProfileData.instance;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Ui.card,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
      final current = data.ratingFor(movie) ?? 0;
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(movie.title,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
          SizedBox(height: 6),
          Text('Tap a star to rate'.tr, style: TextStyle(color: Ui.muted)),
          SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                iconSize: 40,
                onPressed: () async {
                  await data.rate(movie, i);
                  setSheet(() {});
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                icon: Icon(
                    i <= current
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    color: i <= current ? Colors.amber : Ui.dim),
              ),
          ]),
          if (current > 0)
            TextButton(
              onPressed: () async {
                await data.removeRating(movie);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text('Remove rating'.tr),
            ),
        ]),
      );
    }),
  );
}

Future<void> showReviewDialog(BuildContext context, Movie movie) async {
  final data = ProfileData.instance;
  final existing = data.reviewFor(movie);
  final text = await _askText(context, 'Review: ${movie.title}',
      initial: existing ?? '',
      hint: 'What did you think?',
      lines: 4,
      allowEmpty: existing != null);
  if (text == null) return;
  await data.saveReview(movie, text);
  if (context.mounted) {
    _toast(context, text.isEmpty ? 'Review removed'.tr : 'Review saved'.tr);
  }
}

Future<void> checkInMovie(BuildContext context, Movie movie) async {
  await ProfileData.instance.checkIn(movie);
  if (context.mounted) _toast(context, 'Checked in to ${movie.title}');
}

Future<void> showAddToListSheet(BuildContext context, Movie movie) async {
  final data = ProfileData.instance;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Ui.card,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => ListenableBuilder(
      listenable: data,
      builder: (ctx, _) => SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .7),
          child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text('Add to list'.tr,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w900)),
                ),
                ListTile(
                  leading:
                      Icon(Icons.add_circle_outline_rounded, color: Ui.redSoft),
                  title: Text('New list'.tr),
                  onTap: () async {
                    final name =
                        await _askText(ctx, 'New list', hint: 'List name');
                    if (name == null) return;
                    final l = await data.createList(name);
                    await data.toggleInList(l, movie);
                  },
                ),
                for (final l in data.lists)
                  CheckboxListTile(
                    activeColor: Ui.red,
                    value: data.listHas(l, movie),
                    title: Text(l.name),
                    subtitle: Text('${l.movies.length} ${'titles'.tr}'),
                    onChanged: (_) => data.toggleInList(l, movie),
                  ),
              ]),
        ),
      ),
    ),
  );
}

Future<Movie?> pickMovie(BuildContext context) => Navigator.of(context)
    .push<Movie>(MaterialPageRoute(builder: (_) => const MoviePickerScreen()));

Widget _poster(String url, {double w = 52, double h = 76}) => ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: SizedBox(
        width: w,
        height: h,
        child: url.startsWith('http')
            ? CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(color: Ui.cardDeep))
            : Container(
                color: Ui.cardDeep,
                child: Icon(Icons.movie_rounded, color: Ui.dim)),
      ),
    );

Widget _stars(int n, {double size = 16}) =>
    Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 1; i <= 5; i++)
        Icon(i <= n ? Icons.star_rounded : Icons.star_border_rounded,
            size: size, color: i <= n ? Colors.amber : Ui.dim),
    ]);

class _Empty extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Empty(this.icon, this.text);
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 54, color: Colors.white24),
            SizedBox(height: 12),
            Text(text.tr,
                textAlign: TextAlign.center, style: TextStyle(color: Ui.muted)),
          ]),
        ),
      );
}

class _Page extends StatelessWidget {
  final String title;
  final WidgetBuilder body;
  final String? fabLabel;
  final IconData fabIcon;
  final VoidCallback? onFab;
  final List<Widget>? actions;
  const _Page(
      {required this.title,
      required this.body,
      this.fabLabel,
      this.fabIcon = Icons.add_rounded,
      this.onFab,
      this.actions});

  @override
  Widget build(BuildContext context) {
    ProfileData.instance.load();
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(
        backgroundColor: Ui.bg,
        title:
            Text(title.tr, style: const TextStyle(fontWeight: FontWeight.w900)),
        actions: actions,
      ),
      body: ListenableBuilder(
          listenable: ProfileData.instance, builder: (ctx, __) => body(ctx)),
      floatingActionButton: fabLabel == null
          ? null
          : FloatingActionButton.extended(
              backgroundColor: Ui.red,
              foregroundColor: Ui.palette.onAccent,
              onPressed: onFab,
              icon: Icon(fabIcon),
              label: Text(fabLabel!.tr),
            ),
    );
  }
}

Widget _row(BuildContext context,
    {required Movie movie,
    Widget? subtitle,
    Widget? trailing,
    VoidCallback? onTap}) {
  return Container(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
    decoration: BoxDecoration(
      color: Ui.card,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Ui.glassLine),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap ?? () => openMovie(context, movie),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          _poster(movie.image),
          SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(movie.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15)),
              if (movie.year.isNotEmpty)
                Text(movie.year,
                    style: TextStyle(color: Ui.muted, fontSize: 12)),
              if (subtitle != null) ...[SizedBox(height: 6), subtitle],
            ]),
          ),
          if (trailing != null) trailing,
        ]),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Movie picker (search TMDB)
// ---------------------------------------------------------------------------

class MoviePickerScreen extends StatefulWidget {
  const MoviePickerScreen({super.key});
  @override
  State<MoviePickerScreen> createState() => _MoviePickerScreenState();
}

class _MoviePickerScreenState extends State<MoviePickerScreen> {
  final _tmdb = TmdbService();
  Timer? _debounce;
  List<Movie> _results = [];
  bool _loading = false;
  String _last = '';

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () => _search(q));
  }

  Future<void> _search(String q) async {
    final query = q.trim();
    if (query.isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() {
      _loading = true;
      _last = query;
    });
    List<Movie> r = [];
    try {
      r = await _tmdb.search(query);
    } catch (_) {}
    if (!mounted || _last != query) return;
    setState(() {
      _results = r;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(
        backgroundColor: Ui.bg,
        title: Text('Pick a movie'.tr,
            style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            autofocus: true,
            onChanged: _onChanged,
            onSubmitted: _search,
            decoration: InputDecoration(
              hintText: 'Search movies and series'.tr,
              prefixIcon: Icon(Icons.search_rounded),
              filled: true,
              fillColor: Colors.white.withValues(alpha: .06),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: _results.isEmpty
              ? _Empty(Icons.search_rounded,
                  _last.isEmpty ? 'Type a title to search.' : 'No results.')
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: _results.length,
                  itemBuilder: (ctx, i) => _row(ctx,
                      movie: _results[i],
                      onTap: () => Navigator.pop(ctx, _results[i])),
                ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Ratings
// ---------------------------------------------------------------------------

class RatingsScreen extends StatelessWidget {
  const RatingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final data = ProfileData.instance;
    return _Page(
      title: 'Ratings',
      fabLabel: 'Rate a movie',
      fabIcon: Icons.star_rounded,
      onFab: () async {
        final m = await pickMovie(context);
        if (m != null && context.mounted) await showRatingSheet(context, m);
      },
      body: (context) {
        final list = data.ratings;
        if (list.isEmpty) {
          return const _Empty(Icons.star_border_rounded,
              'No ratings yet. Rate a title to see it here.');
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
          itemCount: list.length,
          itemBuilder: (ctx, i) {
            final r = list[i];
            return _row(ctx,
                movie: r.movie,
                subtitle: _stars(r.stars),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                      tooltip: 'Change rating'.tr,
                      onPressed: () => showRatingSheet(ctx, r.movie),
                      icon:
                          Icon(Icons.edit_rounded, color: Ui.muted, size: 20)),
                  IconButton(
                      tooltip: 'Remove'.tr,
                      onPressed: () => data.removeRating(r.movie),
                      icon: Icon(Icons.delete_outline_rounded,
                          color: Ui.muted, size: 20)),
                ]));
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Reviews
// ---------------------------------------------------------------------------

class ReviewsScreen extends StatelessWidget {
  const ReviewsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final data = ProfileData.instance;
    return _Page(
      title: 'Reviews',
      fabLabel: 'Write a review',
      fabIcon: Icons.rate_review_rounded,
      onFab: () async {
        final m = await pickMovie(context);
        if (m != null && context.mounted) await showReviewDialog(context, m);
      },
      body: (context) {
        final list = data.reviews;
        if (list.isEmpty) {
          return const _Empty(Icons.rate_review_outlined,
              'No reviews yet. Write one to see it here.');
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
          itemCount: list.length,
          itemBuilder: (ctx, i) {
            final r = list[i];
            return _row(ctx,
                movie: r.movie,
                subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.text,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white70,
                              height: 1.35,
                              fontSize: 13)),
                      SizedBox(height: 4),
                      Text(_date(r.at),
                          style: TextStyle(color: Ui.dim, fontSize: 11)),
                    ]),
                trailing: Column(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                      tooltip: 'Edit'.tr,
                      onPressed: () => showReviewDialog(ctx, r.movie),
                      icon:
                          Icon(Icons.edit_rounded, color: Ui.muted, size: 20)),
                  IconButton(
                      tooltip: 'Remove'.tr,
                      onPressed: () => data.removeReview(r.movie),
                      icon: Icon(Icons.delete_outline_rounded,
                          color: Ui.muted, size: 20)),
                ]));
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Interests
// ---------------------------------------------------------------------------

class InterestsScreen extends StatelessWidget {
  const InterestsScreen({super.key});
  static const genres = [
    'Action',
    'Adventure',
    'Animation',
    'Comedy',
    'Crime',
    'Documentary',
    'Drama',
    'Family',
    'Fantasy',
    'History',
    'Horror',
    'Music',
    'Mystery',
    'Romance',
    'Sci-Fi',
    'Thriller',
    'War',
    'Western',
  ];

  @override
  Widget build(BuildContext context) {
    final data = ProfileData.instance;
    return _Page(
      title: 'Interests',
      body: (context) {
        return ListView(padding: const EdgeInsets.all(18), children: [
          Text('Pick the genres you love.'.tr,
              style: TextStyle(color: Ui.muted)),
          SizedBox(height: 16),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final g in genres)
              FilterChip(
                label: Text(g.tr),
                selected: data.hasInterest(g),
                showCheckmark: false,
                selectedColor: Ui.red,
                labelStyle: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: data.hasInterest(g)
                        ? Ui.palette.onAccent
                        : Colors.white),
                backgroundColor: Ui.card,
                side: BorderSide(color: Ui.glassLine),
                onSelected: (_) => data.toggleInterest(g),
              ),
          ]),
        ]);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Lists
// ---------------------------------------------------------------------------

class ListsScreen extends StatelessWidget {
  const ListsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final data = ProfileData.instance;
    return _Page(
      title: 'Lists',
      fabLabel: 'New list',
      onFab: () async {
        final name = await _askText(context, 'New list', hint: 'List name');
        if (name != null) await data.createList(name);
      },
      body: (context) {
        final lists = data.lists;
        if (lists.isEmpty) {
          return const _Empty(Icons.format_list_bulleted_rounded,
              'No lists yet. Create one to organise your movies.');
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          itemCount: lists.length,
          itemBuilder: (ctx, i) {
            final l = lists[i];
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Ui.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Ui.glassLine),
              ),
              child: ListTile(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
                leading:
                    Icon(Icons.format_list_bulleted_rounded, color: Ui.redSoft),
                title: Text(l.name,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('${l.movies.length} ${'titles'.tr}',
                    style: TextStyle(color: Ui.muted)),
                onTap: () => Navigator.of(ctx).push(MaterialPageRoute<void>(
                    builder: (_) => ListDetailScreen(list: l))),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'rename') {
                      final n =
                          await _askText(ctx, 'Rename list', initial: l.name);
                      if (n != null) await data.renameList(l, n);
                    } else if (v == 'delete') {
                      final ok = await showDialog<bool>(
                        context: ctx,
                        builder: (d) => AlertDialog(
                          backgroundColor: Ui.card,
                          title: Text('Delete list?'.tr),
                          content: Text(l.name),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(d, false),
                                child: Text('Cancel'.tr)),
                            FilledButton(
                                style: FilledButton.styleFrom(
                                    backgroundColor: Ui.red),
                                onPressed: () => Navigator.pop(d, true),
                                child: Text('Delete'.tr)),
                          ],
                        ),
                      );
                      if (ok == true) await data.deleteList(l);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'rename', child: Text('Rename'.tr)),
                    PopupMenuItem(value: 'delete', child: Text('Delete'.tr)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class ListDetailScreen extends StatelessWidget {
  final MovieList list;
  const ListDetailScreen({super.key, required this.list});
  @override
  Widget build(BuildContext context) {
    final data = ProfileData.instance;
    return ListenableBuilder(
      listenable: data,
      builder: (context, _) => _Page(
        title: list.name,
        fabLabel: 'Add movie',
        onFab: () async {
          final m = await pickMovie(context);
          if (m != null && !data.listHas(list, m))
            await data.toggleInList(list, m);
        },
        body: (_) => list.movies.isEmpty
            ? const _Empty(Icons.movie_creation_outlined,
                'This list is empty. Add a movie.')
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
                itemCount: list.movies.length,
                itemBuilder: (ctx, i) => _row(ctx,
                    movie: list.movies[i],
                    trailing: IconButton(
                        tooltip: 'Remove'.tr,
                        onPressed: () =>
                            data.toggleInList(list, list.movies[i]),
                        icon: Icon(Icons.close_rounded, color: Ui.muted))),
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Check-ins
// ---------------------------------------------------------------------------

class CheckInsScreen extends StatelessWidget {
  const CheckInsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final data = ProfileData.instance;
    return _Page(
      title: 'Check-ins',
      fabLabel: 'Check in',
      fabIcon: Icons.check_circle_outline_rounded,
      onFab: () async {
        final m = await pickMovie(context);
        if (m != null && context.mounted) await checkInMovie(context, m);
      },
      body: (context) {
        final list = data.checkIns;
        if (list.isEmpty) {
          return const _Empty(Icons.check_circle_outline_rounded,
              'No check-ins yet. Check in when you watch something.');
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
          itemCount: list.length,
          itemBuilder: (ctx, i) {
            final c = list[i];
            return _row(ctx,
                movie: c.movie,
                subtitle: Text(_date(c.at),
                    style: TextStyle(color: Ui.muted, fontSize: 12)),
                trailing: IconButton(
                    tooltip: 'Remove'.tr,
                    onPressed: () => data.removeCheckIn(c),
                    icon: Icon(Icons.delete_outline_rounded,
                        color: Ui.muted, size: 20)));
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Favorite people
// ---------------------------------------------------------------------------

Widget _avatar(String photo, String name, double radius) => CircleAvatar(
      radius: radius,
      backgroundColor: Ui.cardDeep,
      backgroundImage:
          photo.startsWith('http') ? CachedNetworkImageProvider(photo) : null,
      child: photo.startsWith('http')
          ? null
          : Text(name.isEmpty ? '?' : name[0].toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w900)),
    );

class FavoritePeopleScreen extends StatelessWidget {
  const FavoritePeopleScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final data = ProfileData.instance;
    return _Page(
      title: 'Favorite people',
      fabLabel: 'Add person',
      fabIcon: Icons.person_add_alt_1_rounded,
      onFab: () async {
        final p = await Navigator.of(context).push<TmdbPerson>(
            MaterialPageRoute(builder: (_) => const PersonPickerScreen()));
        if (p != null && !data.isFavoritePerson(p.name)) {
          await data.toggleFavoritePerson(p.name, id: p.id, photo: p.photo);
        }
      },
      body: (context) {
        final list = data.people;
        if (list.isEmpty) {
          return const _Empty(Icons.people_outline_rounded,
              'No favorite people yet. Add actors and directors you love.');
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          itemCount: list.length,
          itemBuilder: (ctx, i) {
            final p = list[i];
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Ui.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Ui.glassLine),
              ),
              child: ListTile(
                leading: _avatar(p.photo, p.name, 26),
                title: Text(p.name,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                trailing: IconButton(
                    tooltip: 'Remove'.tr,
                    onPressed: () => data.toggleFavoritePerson(p.name),
                    icon: Icon(Icons.favorite_rounded, color: Ui.red)),
              ),
            );
          },
        );
      },
    );
  }
}

class PersonPickerScreen extends StatefulWidget {
  const PersonPickerScreen({super.key});
  @override
  State<PersonPickerScreen> createState() => _PersonPickerScreenState();
}

class _PersonPickerScreenState extends State<PersonPickerScreen> {
  final _tmdb = TmdbService();
  Timer? _debounce;
  List<TmdbPerson> _results = [];
  bool _loading = false;
  String _last = '';

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () => _search(q));
  }

  Future<void> _search(String q) async {
    final query = q.trim();
    if (query.isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() {
      _loading = true;
      _last = query;
    });
    List<TmdbPerson> r = [];
    try {
      r = await _tmdb.searchPeople(query);
    } catch (_) {}
    if (!mounted || _last != query) return;
    setState(() {
      _results = r;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(
        backgroundColor: Ui.bg,
        title: Text('Find a person'.tr,
            style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            autofocus: true,
            onChanged: _onChanged,
            onSubmitted: _search,
            decoration: InputDecoration(
              hintText: 'Search actors and directors'.tr,
              prefixIcon: Icon(Icons.search_rounded),
              filled: true,
              fillColor: Colors.white.withValues(alpha: .06),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: _results.isEmpty
              ? _Empty(Icons.search_rounded,
                  _last.isEmpty ? 'Type a name to search.' : 'No results.')
              : ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (ctx, i) {
                    final p = _results[i];
                    return ListTile(
                      leading: _avatar(p.photo, p.name, 24),
                      title: Text(p.name,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: p.known.isEmpty
                          ? null
                          : Text(p.known, style: TextStyle(color: Ui.muted)),
                      onTap: () => Navigator.pop(ctx, p),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Badges
// ---------------------------------------------------------------------------

IconData _badgeIcon(String key) {
  switch (key) {
    case 'star':
      return Icons.star_rounded;
    case 'stars':
      return Icons.auto_awesome_rounded;
    case 'review':
      return Icons.rate_review_rounded;
    case 'edit':
      return Icons.edit_note_rounded;
    case 'history':
      return Icons.history_rounded;
    case 'bookmark':
      return Icons.bookmarks_rounded;
    case 'list':
      return Icons.format_list_bulleted_rounded;
    case 'check':
      return Icons.check_circle_rounded;
    case 'people':
      return Icons.people_alt_rounded;
    default:
      return Icons.category_rounded;
  }
}

class BadgesScreen extends StatelessWidget {
  const BadgesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final lib = MovieLibrary.instance..load();
    return ListenableBuilder(
      listenable: lib,
      builder: (context, _) => _Page(
        title: 'Badges',
        body: (context) {
          final badges = ProfileData.instance.badges;
          final earned = badges.where((b) => b.earned).length;
          return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
                  child: Text('$earned / ${badges.length} ${'earned'.tr}',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w900)),
                ),
                for (final b in badges)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Ui.card,
                      borderRadius: BorderRadius.circular(18),
                      border:
                          Border.all(color: b.earned ? Ui.red : Ui.glassLine),
                    ),
                    child: Row(children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: b.earned ? Ui.red : Ui.cardDeep,
                        child: Icon(_badgeIcon(b.iconKey),
                            color: b.earned ? Ui.palette.onAccent : Ui.dim),
                      ),
                      SizedBox(width: 14),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(b.title.tr,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15)),
                              SizedBox(height: 2),
                              Text(b.description.tr,
                                  style: TextStyle(
                                      color: Ui.muted, fontSize: 12.5)),
                            ]),
                      ),
                      b.earned
                          ? Icon(Icons.check_circle_rounded, color: Ui.red)
                          : Text(b.progress, style: TextStyle(color: Ui.muted)),
                    ]),
                  ),
              ]);
        },
      ),
    );
  }
}
