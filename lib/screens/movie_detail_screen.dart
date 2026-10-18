import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../main.dart';
import '../models/movie.dart';
import '../services/tmdb_service.dart';
import '../services/movie_library.dart';
import 'movie_player_screen.dart';
import 'browser_screen.dart';

class MovieDetailScreen extends StatefulWidget {
  final Movie movie;
  final bool saved;
  final Future<void> Function() onToggleSaved;
  const MovieDetailScreen({super.key, required this.movie, required this.saved, required this.onToggleSaved});
  @override State<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends State<MovieDetailScreen> with SingleTickerProviderStateMixin {
  final TmdbService _tmdb = TmdbService();
  late final TabController _tabs;
  late bool _saved;
  late Movie _movie;
  List<Movie> _similar = [];
  bool _loadingDetails = true, _loadingSimilar = true;

  @override void initState() {
    super.initState();
    _movie = widget.movie;
    _saved = widget.saved;
    _tabs = TabController(length: 2, vsync: this);
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    final results = await Future.wait<dynamic>([
      _tmdb.details(widget.movie).timeout(const Duration(seconds: 10), onTimeout: () => widget.movie),
      _tmdb.similar(widget.movie).timeout(const Duration(seconds: 10), onTimeout: () => <Movie>[]),
    ], eagerError: false).timeout(const Duration(seconds: 12), onTimeout: () => <dynamic>[widget.movie, <Movie>[]]);
    if (!mounted) return;
    setState(() {
      if (results[0] is Movie) _movie = results[0] as Movie;
      _similar = (results[1] as List<Movie>).where((m) => m.key != widget.movie.key).take(16).toList();
      _loadingDetails = false;
      _loadingSimilar = false;
    });
  }

  Future<void> _toggleSaved() async {
    await widget.onToggleSaved();
    if (!mounted) return;
    setState(() => _saved = !_saved);
    await MovieLibrary.instance.load();
  }

  void _play() => Navigator.push(context, MaterialPageRoute(builder: (_) => MoviePlayerScreen(movie: _movie)));
  void _download() {
    if (!_movie.downloadUrl.startsWith('http')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No download link is available for this title.')));
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => BrowserScreen(initialUrl: _movie.downloadUrl)));
  }

  Future<void> _share() => Share.share('${_movie.title}${_movie.year.isEmpty ? '' : ' (${_movie.year})'} on DamiMovies\n${_movie.url}');

  @override void dispose() { _tabs.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) {
    final backdrop = _movie.backdrop.startsWith('http') ? _movie.backdrop : _movie.image;
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, scrolled) => [
          SliverAppBar(
            expandedHeight: 370, pinned: true, backgroundColor: appBg,
            actions: [
              IconButton(tooltip: _saved ? 'Remove from My List' : 'Add to My List', onPressed: _toggleSaved, icon: Icon(_saved ? Icons.bookmark_rounded : Icons.bookmark_add_outlined, color: _saved ? appRed : Colors.white)),
              IconButton(tooltip: 'Share title', onPressed: _share, icon: const Icon(Icons.share_rounded)),
            ],
            flexibleSpace: FlexibleSpaceBar(background: Stack(fit: StackFit.expand, children: [
              if (backdrop.startsWith('http')) CachedNetworkImage(imageUrl: backdrop, fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(color: appSurface)),
              DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [const Color(0x33000000), const Color(0x6B080B10), appBg], stops: const [0, .42, 1]))),
              Positioned(left: 18, right: 18, bottom: 24, child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Container(width: 105, height: 154, decoration: BoxDecoration(borderRadius: BorderRadius.circular(13), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .5), blurRadius: 17, offset: const Offset(0, 7))]), child: ClipRRect(borderRadius: BorderRadius.circular(13), child: _movie.image.startsWith('http') ? CachedNetworkImage(imageUrl: _movie.image, fit: BoxFit.cover, errorWidget: (_, __, ___) => const Icon(Icons.movie_outlined)) : const Icon(Icons.movie_outlined))),
                const SizedBox(width: 14), Expanded(child: Padding(padding: const EdgeInsets.only(bottom: 2), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: appRed, borderRadius: BorderRadius.circular(6)), child: Text(_movie.isSeries ? 'SERIES' : 'MOVIE', style: const TextStyle(fontSize: 9, letterSpacing: 1, fontWeight: FontWeight.w900))),
                  const SizedBox(height: 9), Text(_movie.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 24, height: 1.08, fontWeight: FontWeight.w900, letterSpacing: -.5)),
                  const SizedBox(height: 8), Wrap(spacing: 7, runSpacing: 6, children: [if (_movie.year.isNotEmpty) _tag(_movie.year), if (_movie.rating.isNotEmpty) _tag('★ ${_movie.rating}/10'), if (_movie.runtimeText.isNotEmpty) _tag(_movie.runtimeText)]),
                ]))),
              ])),
            ])),
          ),
        ],
        body: ListView(padding: EdgeInsets.zero, children: [
          Padding(padding: const EdgeInsets.fromLTRB(18, 17, 18, 10), child: Wrap(spacing: 7, runSpacing: 7, children: _movie.genres.take(5).map(_tag).toList())),
          if (_movie.tagline.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(18, 0, 18, 9), child: Text('“${_movie.tagline}”', style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.white60))),
          Padding(padding: const EdgeInsets.fromLTRB(18, 4, 18, 18), child: Row(children: [
            Expanded(child: SizedBox(height: 51, child: FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))), onPressed: _play, icon: const Icon(Icons.play_arrow_rounded, size: 25), label: const Text('Play', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))))),
            const SizedBox(width: 10), Expanded(child: SizedBox(height: 51, child: OutlinedButton.icon(style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white24), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))), onPressed: _download, icon: const Icon(Icons.download_rounded), label: const Text('Download', style: TextStyle(fontWeight: FontWeight.w800))))),
          ])),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('OVERVIEW', style: TextStyle(fontSize: 11, color: appRed, letterSpacing: 1.4, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(_movie.overview.isNotEmpty ? _movie.overview : (_loadingDetails ? 'Loading story and movie information…' : 'No synopsis is available from TMDB for this title.'), style: const TextStyle(color: Colors.white70, height: 1.55, fontSize: 14)),
            if (_loadingDetails) Padding(padding: const EdgeInsets.only(top: 8), child: LinearProgressIndicator(minHeight: 2, color: appRed, backgroundColor: Colors.white10)),
          ])),
          const SizedBox(height: 22),
          TabBar(controller: _tabs, indicatorColor: appRed, labelColor: Colors.white, unselectedLabelColor: Colors.white54, tabs: const [Tab(text: 'More Like This'), Tab(text: 'Details')]),
          SizedBox(height: 355, child: TabBarView(controller: _tabs, children: [
            _similar.isEmpty ? Center(child: Text(_loadingSimilar ? 'Finding similar titles…' : 'No similar titles found.', style: const TextStyle(color: Colors.white54))) : GridView.builder(padding: const EdgeInsets.all(15), itemCount: _similar.length, gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 14, childAspectRatio: .48), itemBuilder: (_, i) => _similarCard(_similar[i])),
            _detailsTab(),
          ])),
          const SizedBox(height: 28),
        ]),
      ),
    );
  }

  Widget _detailsTab() {
    final date = _movie.releaseDate.isNotEmpty ? _movie.releaseDate : _movie.year;
    final metadata = <(String, String)>[
      ('Title', _movie.title),
      ('Type', _movie.isSeries ? 'TV Series' : 'Movie'),
      if (date.isNotEmpty) ('Release date', date),
      if (_movie.rating.isNotEmpty) ('TMDB rating', '${_movie.rating}/10'),
      if (_movie.runtimeText.isNotEmpty) ('Runtime', _movie.runtimeText),
      if (_movie.isSeries && _movie.seasons != null) ('Seasons', '${_movie.seasons}'),
      if (_movie.isSeries && _movie.episodes != null) ('Episodes', '${_movie.episodes}'),
      if (_movie.status.isNotEmpty) ('Status', _movie.status),
      if (_movie.language.isNotEmpty) ('Original language', _movie.language),
      if (_movie.directors.isNotEmpty) (_movie.isSeries ? 'Created by' : 'Director', _movie.directors.join(', ')),
      if (_movie.genres.isNotEmpty) ('Genres', _movie.genres.join(', ')),
    ];
    return ListView(padding: const EdgeInsets.all(18), children: [
      for (final row in metadata) Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 115, child: Text(row.$1, style: const TextStyle(color: Colors.white54, fontSize: 12))), Expanded(child: Text(row.$2, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)))])),
      if (_movie.cast.isNotEmpty) ...[
        const SizedBox(height: 12), Text('CAST', style: TextStyle(color: appRed, fontWeight: FontWeight.w900, letterSpacing: 1.2, fontSize: 11)), const SizedBox(height: 12),
        SizedBox(height: 124, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: _movie.cast.length, separatorBuilder: (_, __) => const SizedBox(width: 12), itemBuilder: (_, i) { final person = _movie.cast[i]; return SizedBox(width: 78, child: Column(children: [ClipRRect(borderRadius: BorderRadius.circular(38), child: SizedBox(width: 66, height: 66, child: person.photo.startsWith('http') ? CachedNetworkImage(imageUrl: person.photo, fit: BoxFit.cover, errorWidget: (_, __, ___) => const Icon(Icons.person)) : Container(color: appSurface, child: const Icon(Icons.person, color: Colors.white54)))), const SizedBox(height: 6), Text(person.name, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)), Text(person.character, maxLines: 1, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, color: Colors.white54))])); })),
      ],
    ]);
  }

  Widget _similarCard(Movie movie) => GestureDetector(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MovieDetailScreen(movie: movie, saved: MovieLibrary.instance.isSaved(movie), onToggleSaved: () async { await MovieLibrary.instance.toggleSaved(movie); }))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(12), child: movie.image.startsWith('http') ? CachedNetworkImage(imageUrl: movie.image, fit: BoxFit.cover, width: double.infinity, errorWidget: (_, __, ___) => Container(color: appSurface, child: const Icon(Icons.movie_outlined))) : Container(color: appSurface, child: const Icon(Icons.movie_outlined)))), const SizedBox(height: 6), Text(movie.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)), if (movie.rating.isNotEmpty) Text('★ ${movie.rating}', style: const TextStyle(color: Colors.amber, fontSize: 10))]));

  Widget _tag(String text) => Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6), decoration: BoxDecoration(color: appSurface, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white.withValues(alpha: .06))), child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700)));
}
