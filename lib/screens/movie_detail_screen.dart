import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../main.dart';
import '../models/movie.dart';
import '../services/ad_service.dart';
import '../services/app_analytics.dart';
import '../services/app_preferences.dart';
import '../services/download_upgrade_service.dart';
import '../services/tmdb_service.dart';
import '../services/movie_library.dart';
import 'external_download_screen.dart';
import '../services/profile_data.dart';
import 'community_composer.dart';
import 'profile_collections_screen.dart';
import 'actor_profile_screen.dart';
import 'movie_player_screen.dart';
import 'watch_together_screen.dart';
import 'trailer_player_screen.dart';

class MovieDetailScreen extends StatefulWidget {
  final Movie movie;
  final bool saved;
  final Future<void> Function() onToggleSaved;
  const MovieDetailScreen(
      {super.key,
      required this.movie,
      required this.saved,
      required this.onToggleSaved});
  @override
  State<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends State<MovieDetailScreen>
    with SingleTickerProviderStateMixin {
  final TmdbService _tmdb = TmdbService();
  late final TabController _tabs;
  late bool _saved;
  late Movie _movie;
  List<Movie> _similar = [];
  TmdbTrailer? _trailer;
  bool _loadingDetails = true, _loadingSimilar = true, _loadingTrailer = true;
  bool _openingPlayer = false;

  @override
  void initState() {
    super.initState();
    _movie = widget.movie;
    AppAnalytics.instance.movieDetailsViewed(widget.movie);
    _saved = widget.saved;
    _tabs = TabController(length: 2, vsync: this);
    ProfileData.instance.load();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    final results = await Future.wait<dynamic>([
      _tmdb
          .details(widget.movie)
          .timeout(const Duration(seconds: 10), onTimeout: () => widget.movie),
      _tmdb
          .similar(widget.movie)
          .timeout(const Duration(seconds: 10), onTimeout: () => <Movie>[]),
    ], eagerError: false)
        .timeout(const Duration(seconds: 12),
            onTimeout: () => <dynamic>[widget.movie, <Movie>[]]);
    if (!mounted) return;
    setState(() {
      if (results[0] is Movie) _movie = results[0] as Movie;
      _similar = (results[1] as List<Movie>)
          .where((m) => m.key != widget.movie.key)
          .take(16)
          .toList();
      _loadingDetails = false;
      _loadingSimilar = false;
    });
    // Resolve the title to its TMDB ID first, then retrieve the video key.
    // This avoids duplicate /find requests for catalogue entries using IMDb IDs.
    unawaited(_loadTrailer(_movie));
  }

  Future<void> _loadTrailer(Movie movie) async {
    if (mounted) setState(() => _loadingTrailer = true);
    TmdbTrailer? found;
    try {
      found = await _tmdb
          .trailerFor(movie)
          .timeout(const Duration(seconds: 13), onTimeout: () => null);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _trailer = found;
      _loadingTrailer = false;
    });
  }

  void _watchTrailer() {
    final trailer = _trailer;
    if (trailer == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TrailerPlayerScreen(
        title: trailer.title,
        youtubeKey: trailer.key,
        poster: trailer.poster,
      ),
    ));
  }

  Future<void> _toggleSaved() async {
    await widget.onToggleSaved();
    if (!mounted) return;
    setState(() => _saved = !_saved);
    await MovieLibrary.instance.load();
  }

  Future<void> _download() async {
    final url = _movie.downloadUrl.trim();
    if (!url.startsWith('http')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('No download link is available for this title.'.tr)),
      );
      return;
    }

    await DownloadUpgradeService.onDownloadTap(
      context,
      continueDownload: () async {
        if (!mounted) return;
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => ExternalDownloadScreen(
              movieTitle: _movie.title,
              downloadUrl: url,
            ),
          ),
        );
      },
    );
  }

  Future<void> _play() async {
    // Push the player FIRST. Its WebView begins loading while the support-ad
    // route is on top, so Skip Ad reveals the existing player immediately.
    if (_openingPlayer || !mounted) return;
    _openingPlayer = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => _PlayerBehindPlayAd(movie: _movie),
        ),
      );
    } finally {
      _openingPlayer = false;
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backdrop =
        _movie.backdrop.startsWith('http') ? _movie.backdrop : _movie.image;
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, scrolled) => [
          SliverAppBar(
            expandedHeight: 370,
            pinned: true,
            backgroundColor: appBg,
            actions: [
              IconButton(
                  tooltip: _saved ? 'Remove from My List' : 'Add to My List',
                  onPressed: _toggleSaved,
                  icon: Icon(
                      _saved
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_add_outlined,
                      color: _saved ? appRed : Colors.white)),
            ],
            flexibleSpace: FlexibleSpaceBar(
                background: Stack(fit: StackFit.expand, children: [
              if (backdrop.startsWith('http'))
                CachedNetworkImage(
                    imageUrl: backdrop,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(color: appSurface)),
              DecoratedBox(
                  decoration: BoxDecoration(
                      gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                    const Color(0x33000000),
                    const Color(0x6B080B10),
                    appBg
                  ],
                          stops: [
                    0,
                    .42,
                    1
                  ]))),
              Positioned(
                  left: 18,
                  right: 18,
                  bottom: 24,
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                            width: 105,
                            height: 154,
                            decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(13),
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.black.withValues(alpha: .5),
                                      blurRadius: 17,
                                      offset: const Offset(0, 7))
                                ]),
                            child: ClipRRect(
                                borderRadius: BorderRadius.circular(13),
                                child: _movie.image.startsWith('http')
                                    ? CachedNetworkImage(
                                        imageUrl: _movie.image,
                                        fit: BoxFit.cover,
                                        errorWidget: (_, __, ___) =>
                                            Icon(Icons.movie_outlined))
                                    : Icon(Icons.movie_outlined))),
                        SizedBox(width: 14),
                        Expanded(
                            child: Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                              color: appRed,
                                              borderRadius:
                                                  BorderRadius.circular(6)),
                                          child: Text(
                                              _movie.isSeries
                                                  ? 'SERIES'
                                                  : 'MOVIE',
                                              style: const TextStyle(
                                                  fontSize: 9,
                                                  letterSpacing: 1,
                                                  fontWeight:
                                                      FontWeight.w900))),
                                      SizedBox(height: 9),
                                      Text(_movie.title,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 24,
                                              height: 1.08,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: -.5)),
                                      SizedBox(height: 8),
                                      Wrap(
                                          spacing: 7,
                                          runSpacing: 6,
                                          children: [
                                            if (_movie.year.isNotEmpty)
                                              _tag(_movie.year),
                                            if (_movie.rating.isNotEmpty)
                                              _tag('★ ${_movie.rating}/10'),
                                            if (_movie.runtimeText.isNotEmpty)
                                              _tag(_movie.runtimeText)
                                          ]),
                                    ]))),
                      ])),
            ])),
          ),
        ],
        body: ListView(padding: EdgeInsets.zero, children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(18, 17, 18, 10),
              child: Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: _movie.genres.take(5).map(_tag).toList())),
          if (_movie.tagline.isNotEmpty)
            Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 9),
                child: Text('“${_movie.tagline}”',
                    style: const TextStyle(
                        fontStyle: FontStyle.italic, color: Colors.white60))),
          Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
              child: Row(children: [
                Expanded(
                    child: SizedBox(
                        height: 51,
                        child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14))),
                            onPressed: _play,
                            icon: Icon(Icons.play_arrow_rounded, size: 25),
                            label: Text('Play'.tr,
                                style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15))))),
                SizedBox(width: 10),
                Expanded(
                    child: SizedBox(
                        height: 51,
                        child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white24),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14))),
                            onPressed: _download,
                            icon: Icon(Icons.download_rounded),
                            label: Text('Download'.tr,
                                style:
                                    TextStyle(fontWeight: FontWeight.w800))))),
              ])),
          Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Row(children: [
                Expanded(
                    child: SizedBox(
                        height: 46,
                        child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white24),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14))),
                            onPressed: () =>
                                showCommunityComposer(context, movie: _movie),
                            icon: Icon(Icons.chat_bubble_outline_rounded,
                                size: 20),
                            label: Text('Tweet'.tr,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800))))),
                SizedBox(width: 10),
                Expanded(
                    child: SizedBox(
                        height: 46,
                        child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white24),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14))),
                            onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        WatchTogetherScreen(movie: _movie))),
                            icon: Icon(Icons.theaters_rounded, size: 20),
                            label: Text('Watch Together'.tr,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800))))),
              ])),
          _profileActions(),
          _trailerSection(),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('OVERVIEW'.tr,
                        style: TextStyle(
                            fontSize: 11,
                            color: appRed,
                            letterSpacing: 1.4,
                            fontWeight: FontWeight.w900)),
                    SizedBox(height: 8),
                    Text(
                        _movie.overview.isNotEmpty
                            ? _movie.overview
                            : (_loadingDetails
                                ? 'Loading story and movie information…'
                                : 'No synopsis is available for this title.'),
                        style: const TextStyle(
                            color: Colors.white70, height: 1.55, fontSize: 14)),
                    if (_loadingDetails)
                      Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: LinearProgressIndicator(
                              minHeight: 2,
                              color: appRed,
                              backgroundColor: Colors.white10)),
                  ])),
          SizedBox(height: 22),
          TabBar(
              controller: _tabs,
              indicatorColor: appRed,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              tabs: [Tab(text: 'More Like This'), Tab(text: 'Details')]),
          SizedBox(
              height: 355,
              child: TabBarView(controller: _tabs, children: [
                _similar.isEmpty
                    ? Center(
                        child: Text(
                            _loadingSimilar
                                ? 'Finding similar titles…'
                                : 'No similar titles found.',
                            style: const TextStyle(color: Colors.white54)))
                    : GridView.builder(
                        padding: const EdgeInsets.all(15),
                        itemCount: _similar.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 14,
                                childAspectRatio: .48),
                        itemBuilder: (_, i) => _similarCard(_similar[i])),
                _detailsTab(),
              ])),
          SizedBox(height: 28),
        ]),
      ),
    );
  }

  void _openActor(MovieCastMember person) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ActorProfileScreen(person: person),
    ));
  }

  Future<void> _toggleFavoritePerson(MovieCastMember person) async {
    final was = ProfileData.instance.isFavoritePerson(person.name);
    await ProfileData.instance
        .toggleFavoritePerson(person.name, photo: person.photo);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(was
              ? '${person.name} removed from favorites'
              : '${person.name} added to favorites')));
  }

  Widget _profileActions() {
    final data = ProfileData.instance;
    return ListenableBuilder(
      listenable: data,
      builder: (context, _) {
        final stars = data.ratingFor(_movie);
        final reviewed = data.reviewFor(_movie) != null;
        Widget action(IconData icon, String label, VoidCallback onTap,
                {bool active = false}) =>
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon,
                        color: active ? appRed : Colors.white70, size: 24),
                    SizedBox(height: 4),
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: active ? appRed : Colors.white70)),
                  ]),
                ),
              ),
            );
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
          child: Container(
            decoration: BoxDecoration(
                color: appSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: .06))),
            child: Row(children: [
              action(
                  stars == null
                      ? Icons.star_border_rounded
                      : Icons.star_rounded,
                  stars == null ? 'Rate' : 'Rated $stars★',
                  () => showRatingSheet(context, _movie),
                  active: stars != null),
              action(
                  reviewed
                      ? Icons.rate_review_rounded
                      : Icons.rate_review_outlined,
                  reviewed ? 'Reviewed' : 'Review',
                  () => showReviewDialog(context, _movie),
                  active: reviewed),
              action(Icons.check_circle_outline_rounded, 'Check in',
                  () => checkInMovie(context, _movie)),
              action(Icons.playlist_add_rounded, 'Add to list',
                  () => showAddToListSheet(context, _movie)),
            ]),
          ),
        );
      },
    );
  }

  Widget _trailerSection() {
    final trailer = _trailer;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('TRAILER'.tr,
                  style: TextStyle(
                      color: appRed,
                      fontSize: 11,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w900)),
              const Spacer(),
              if (_loadingTrailer)
                Text('SEARCHING TMDB…'.tr,
                    style: TextStyle(
                        color: Colors.white38, fontSize: 9, letterSpacing: .8)),
              if (!_loadingTrailer && trailer != null)
                Text('PLAY IN APP'.tr,
                    style: TextStyle(
                        color: Colors.white54, fontSize: 9, letterSpacing: .8)),
            ],
          ),
          SizedBox(height: 10),
          if (_loadingTrailer)
            Container(
              height: 158,
              decoration: BoxDecoration(
                  color: appSurface, borderRadius: BorderRadius.circular(14)),
              child: Center(
                  child: SizedBox(
                      width: 23,
                      height: 23,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: appRed))),
            )
          else if (trailer != null)
            Material(
              color: appSurface,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _watchTrailer,
                child: SizedBox(
                  height: 158,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (trailer.poster.startsWith('http'))
                        CachedNetworkImage(
                          imageUrl: trailer.poster,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              Container(color: appSurface),
                        )
                      else
                        Container(color: appSurface),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x22000000), Color(0xCC000000)],
                          ),
                        ),
                      ),
                      Center(
                        child: Icon(Icons.play_circle_fill_rounded,
                            color: Colors.white, size: 62),
                      ),
                      Positioned(
                        left: 13,
                        right: 13,
                        bottom: 12,
                        child: Row(
                          children: [
                            Icon(Icons.ondemand_video_rounded,
                                color: Colors.white, size: 17),
                            SizedBox(width: 7),
                            Expanded(
                                child: Text('Watch ${_movie.title} trailer',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12))),
                            Icon(Icons.open_in_new_rounded,
                                color: Colors.white70, size: 16),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                  color: appSurface,
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: .05))),
              child: Row(
                children: [
                  Icon(Icons.movie_filter_outlined,
                      color: Colors.white54, size: 30),
                  SizedBox(width: 12),
                  Expanded(
                      child: Text(
                          'No YouTube trailer is listed on TMDB for this title yet.'
                              .tr,
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              height: 1.35))),
                  TextButton(
                      onPressed: () => _loadTrailer(_movie),
                      child: Text('Retry'.tr)),
                ],
              ),
            ),
          SizedBox(height: 2),
        ],
      ),
    );
  }

  Widget _detailsTab() {
    final date =
        _movie.releaseDate.isNotEmpty ? _movie.releaseDate : _movie.year;
    final metadata = <(String, String)>[
      ('Title', _movie.title),
      ('Type', _movie.isSeries ? 'TV Series' : 'Movie'),
      if (date.isNotEmpty) ('Release date', date),
      if (_movie.rating.isNotEmpty) ('Rating', '${_movie.rating}/10'),
      if (_movie.runtimeText.isNotEmpty) ('Runtime', _movie.runtimeText),
      if (_movie.isSeries && _movie.seasons != null)
        ('Seasons', '${_movie.seasons}'),
      if (_movie.isSeries && _movie.episodes != null)
        ('Episodes', '${_movie.episodes}'),
      if (_movie.status.isNotEmpty) ('Status', _movie.status),
      if (_movie.language.isNotEmpty) ('Original language', _movie.language),
      if (_movie.directors.isNotEmpty)
        (
          _movie.isSeries ? 'Created by' : 'Director',
          _movie.directors.join(', ')
        ),
      if (_movie.genres.isNotEmpty) ('Genres', _movie.genres.join(', ')),
    ];
    return ListView(padding: const EdgeInsets.all(18), children: [
      for (final row in metadata)
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                  width: 115,
                  child: Text(row.$1,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12))),
              Expanded(
                  child: Text(row.$2,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)))
            ])),
      if (_movie.cast.isNotEmpty) ...[
        SizedBox(height: 12),
        Text('CAST'.tr,
            style: TextStyle(
                color: appRed,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                fontSize: 11)),
        SizedBox(height: 6),
        Text('Tap an actor to view their profile · Hold to add to favorites',
            style: const TextStyle(color: Colors.white54, fontSize: 10)),
        SizedBox(height: 12),
        SizedBox(
            height: 124,
            child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _movie.cast.length,
                separatorBuilder: (_, __) => SizedBox(width: 12),
                itemBuilder: (_, i) {
                  final person = _movie.cast[i];
                  return GestureDetector(
                      onTap: () => _openActor(person),
                      onLongPress: () => _toggleFavoritePerson(person),
                      child: SizedBox(
                          width: 78,
                          child: Column(children: [
                            ClipRRect(
                                borderRadius: BorderRadius.circular(38),
                                child: SizedBox(
                                    width: 66,
                                    height: 66,
                                    child: person.photo.startsWith('http')
                                        ? CachedNetworkImage(
                                            imageUrl: person.photo,
                                            fit: BoxFit.cover,
                                            errorWidget: (_, __, ___) =>
                                                Icon(Icons.person))
                                        : Container(
                                            color: appSurface,
                                            child: Icon(Icons.person,
                                                color: Colors.white54)))),
                            SizedBox(height: 6),
                            Text(
                                ProfileData.instance
                                        .isFavoritePerson(person.name)
                                    ? '♥ ${person.name}'
                                    : person.name,
                                maxLines: 2,
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: ProfileData.instance
                                            .isFavoritePerson(person.name)
                                        ? appRed
                                        : null)),
                            Text(person.character,
                                maxLines: 1,
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 9, color: Colors.white54))
                          ])));
                })),
      ],
    ]);
  }

  Widget _similarCard(Movie movie) => GestureDetector(
      onTap: () => AdService.instance.guard(context, () {
            if (!mounted) return;
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => MovieDetailScreen(
                        movie: movie,
                        saved: MovieLibrary.instance.isSaved(movie),
                        onToggleSaved: () async {
                          await MovieLibrary.instance.toggleSaved(movie);
                        })));
          }),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: movie.image.startsWith('http')
                    ? CachedNetworkImage(
                        imageUrl: movie.image,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        errorWidget: (_, __, ___) => Container(
                            color: appSurface,
                            child: Icon(Icons.movie_outlined)))
                    : Container(
                        color: appSurface, child: Icon(Icons.movie_outlined)))),
        SizedBox(height: 6),
        Text(movie.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
        if (movie.rating.isNotEmpty)
          Text('★ ${movie.rating}',
              style: const TextStyle(color: Colors.amber, fontSize: 10))
      ]));

  Widget _tag(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
          color: appSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: .06))),
      child: Text(text,
          style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w700)));
}

/// Keeps the real movie player mounted beneath the usual support-ad route.
/// Unlike the old "ad -> Navigator.push(player)" sequence, this allows the
/// player WebView to resolve its URL and load while the user watches the ad.
/// The black interaction shield stops touches leaking into the player before
/// the ad has been skipped; it is removed only after guardPlay completes.
class _PlayerBehindPlayAd extends StatefulWidget {
  const _PlayerBehindPlayAd({required this.movie});

  final Movie movie;

  @override
  State<_PlayerBehindPlayAd> createState() => _PlayerBehindPlayAdState();
}

class _PlayerBehindPlayAdState extends State<_PlayerBehindPlayAd> {
  bool _adCompleted = false;

  @override
  void initState() {
    super.initState();
    // Wait one frame so MoviePlayerScreen can mount/start loading before
    // opening the ad route above it. The shield prevents a visible flash.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_presentAd());
    });
  }

  Future<void> _presentAd() async {
    try {
      // Reuses exactly the same ad loading, countdown, Skip Ad, and Continue
      // on failure logic as the existing Download button. Premium bypasses it.
      await AdService.instance.guardPlay(context, () async {});
    } catch (error) {
      debugPrint('DamiMovies: unable to show Play ad: $error');
    } finally {
      if (mounted) setState(() => _adCompleted = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Built even while covered: do not rebuild it when the ad ends.
        MoviePlayerScreen(movie: widget.movie),
        if (!_adCompleted)
          const Positioned.fill(
            child: AbsorbPointer(
              absorbing: true,
              child: ColoredBox(color: Colors.black),
            ),
          ),
      ],
    );
  }
}
