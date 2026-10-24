import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../models/movie.dart';
import '../services/tmdb_service.dart';
import 'tv_show_detail_screen.dart';

/// Dedicated TV tab. Only TV endpoints are requested: nothing is added to
/// the Movies home catalogue.
class TvShowsScreen extends StatefulWidget {
  const TvShowsScreen({super.key});

  @override
  State<TvShowsScreen> createState() => _TvShowsScreenState();
}

class _TvShowsScreenState extends State<TvShowsScreen> {
  final _tmdb = TmdbService();
  final _search = TextEditingController();
  final _featured = PageController(viewportFraction: .92);
  Timer? _debounce;
  List<Movie> _trending = [];
  List<Movie> _popular = [];
  List<Movie> _airing = [];
  List<Movie> _onAir = [];
  List<Movie> _kDrama = [];
  List<Movie> _anime = [];
  List<Movie> _reality = [];
  List<Movie> _results = [];
  bool _loading = true;
  bool _searching = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  int _featuredPage = 0;
  int _request = 0;
  String _query = '';
  String _error = '';
  String _genre = 'All Series';

  static const _categories = [
    'All Series', 'Drama', 'Comedy', 'Crime', 'Animation',
    'Documentary', 'Sci-Fi & Fantasy', 'Reality', 'Kids',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _request++;
    _debounce?.cancel();
    _featured.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = ''; });
    // The requests are independent: one failing should not hide the other.
    List<Movie> trending = [], popular = [], airing = [], onAir = [], kDrama = [], anime = [], reality = [];
    await Future.wait([
      () async { try { trending = await _tmdb.tvTrending(); } catch (_) {} }(),
      () async { try { popular = await _tmdb.tvPopular(); } catch (_) {} }(),
      () async { try { airing = await _tmdb.tvAiringToday(); } catch (_) {} }(),
      () async { try { onAir = await _tmdb.tvOnAir(); } catch (_) {} }(),
      () async { try { kDrama = await _tmdb.tvDiscover(genreId: '18', language: 'ko'); } catch (_) {} }(),
      () async { try { anime = await _tmdb.tvDiscover(genreId: '16', language: 'ja'); } catch (_) {} }(),
      () async { try { reality = await _tmdb.tvDiscover(genreId: '10764'); } catch (_) {} }(),
    ]);
    if (!mounted) return;
    setState(() {
      _trending = trending;
      _popular = popular;
      _airing = airing;
      _onAir = onAir;
      _kDrama = kDrama;
      _anime = anime;
      _reality = reality;
      _page = 1;
      _hasMore = popular.isNotEmpty;
      _featuredPage = 0;
      _loading = false;
      _error = trending.isEmpty && popular.isEmpty && airing.isEmpty && onAir.isEmpty
          ? 'Could not load TV shows. Check your connection and try again.' : '';
    });
  }

  void _searchChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    final serial = ++_request;
    setState(() {
      _query = query;
      _results = [];
      _searching = query.length >= 2;
    });
    if (query.length < 2) return;
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      List<Movie> matches = [];
      try { matches = await _tmdb.tvSearch(query); } catch (_) {}
      if (!mounted || serial != _request) return;
      setState(() { _results = matches; _searching = false; });
    });
  }

  Future<void> _more() async {
    if (_loadingMore || !_hasMore || _loading || _query.length >= 2) return;
    setState(() => _loadingMore = true);
    List<Movie> items = [];
    try { items = await _tmdb.tvPopular(page: _page + 1); } catch (_) {}
    if (!mounted) return;
    setState(() {
      if (items.isNotEmpty) {
        final oldIds = _popular.map((m) => m.tmdbId).toSet();
        _popular = [..._popular, ...items.where((m) => !oldIds.contains(m.tmdbId))];
        _page++;
      } else {
        _hasMore = false;
      }
      _loadingMore = false;
    });
  }

  void _open(Movie show) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => TvShowDetailScreen(show: show)),
      );

  List<Movie> _filter(List<Movie> input) {
    if (_genre == 'All Series') return input;
    return input.where((show) => show.genres.contains(_genre)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final querying = _query.length >= 2;
    final filtered = _filter(querying ? _results : _popular);
    return Scaffold(
      backgroundColor: appBg,
      body: SafeArea(
        child: RefreshIndicator(
          color: appRed,
          onRefresh: _load,
          child: LayoutBuilder(builder: (context, constraints) {
            final columns = constraints.maxWidth >= 700 ? 5 : constraints.maxWidth >= 490 ? 4 : 3;
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
              children: [
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    ShaderMask(
                      blendMode: BlendMode.srcIn,
                      shaderCallback: (rect) => LinearGradient(colors: [Colors.white, appAccentSoft]).createShader(rect),
                      child: const Text('TV Shows', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -.9)),
                    ),
                    const SizedBox(height: 2),
                    const Text('Binge-worthy stories, all in one place', style: TextStyle(fontSize: 12.5, color: Colors.white60)),
                  ])),
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _load,
                    child: Container(
                      width: 46, height: 46,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle, color: appSurface,
                        border: Border.all(color: Colors.white.withValues(alpha: .08)),
                      ),
                      child: const Icon(Icons.refresh_rounded, size: 22),
                    ),
                  ),
                ]),
                const SizedBox(height: 22),
                TextField(
                  controller: _search,
                  onChanged: _searchChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search TV shows, series...',
                    prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54),
                    suffixIcon: _query.isNotEmpty ? IconButton(
                      tooltip: 'Clear search',
                      onPressed: () { _search.clear(); _searchChanged(''); FocusScope.of(context).unfocus(); },
                      icon: const Icon(Icons.close_rounded),
                    ) : null,
                    filled: true,
                    fillColor: appSurface,
                    contentPadding: const EdgeInsets.symmetric(vertical: 15),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: .08))),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide(color: appRed.withValues(alpha: .8), width: 1.4)),
                  ),
                ),
                const SizedBox(height: 20),
                if (_loading && !querying)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 105), child: Center(child: CircularProgressIndicator()))
                else if (_error.isNotEmpty && !querying)
                  _empty(_error, retry: _load)
                else ...[
                  if (!querying && _trending.isNotEmpty) ...[
                    _heading('Trending this week', 'HOT RIGHT NOW', Icons.local_fire_department_rounded),
                    const SizedBox(height: 13),
                    SizedBox(height: 270, child: PageView.builder(
                      controller: _featured,
                      itemCount: _trending.take(8).length,
                      onPageChanged: (index) => setState(() => _featuredPage = index),
                      itemBuilder: (_, index) {
                        final show = _trending[index];
                        return Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: _featureCard(show, index + 1),
                        );
                      },
                    )),
                    const SizedBox(height: 10),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(_trending.take(8).length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        height: 5, width: i == _featuredPage ? 22 : 5,
                        decoration: BoxDecoration(
                          color: i == _featuredPage ? appRed : Colors.white24,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: i == _featuredPage ? [BoxShadow(color: appRed.withValues(alpha: .6), blurRadius: 8)] : null,
                        ),
                      ),
                    )),
                    const SizedBox(height: 28),
                  ],
                  if (!querying) ...[
                    _seriesRail('New Episodes', 'AIRING TODAY', Icons.new_releases_rounded, _airing),
                    _seriesRail('Currently Airing', 'FOLLOW THE STORY', Icons.live_tv_rounded, _onAir),
                    _seriesRail('Korean Dramas', 'K-DRAMA COLLECTION', Icons.favorite_rounded, _kDrama),
                    _seriesRail('Anime Series', 'ANIMATED STORIES', Icons.auto_awesome_rounded, _anime),
                    _seriesRail('Reality TV', 'UNSCRIPTED SERIES', Icons.theater_comedy_rounded, _reality),
                  ],
                  _heading(querying ? 'Search results' : 'Popular TV shows',
                      querying ? '${_results.length} SERIES FOUND' : 'DISCOVER YOUR NEXT SHOW',
                      querying ? Icons.search_rounded : Icons.auto_awesome_rounded),
                  const SizedBox(height: 14),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: _categories.map((category) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(category), selected: _genre == category,
                        showCheckmark: false,
                        shape: const StadiumBorder(),
                        selectedColor: appRed.withValues(alpha: .22),
                        backgroundColor: Colors.white.withValues(alpha: .06),
                        labelStyle: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w800,
                            color: _genre == category ? Colors.white : Colors.white60),
                        side: BorderSide(color: _genre == category ? appRed : Colors.white12),
                        onSelected: (_) => setState(() => _genre = category),
                      ),
                    )).toList()),
                  ),
                  const SizedBox(height: 16),
                  if (_searching) const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
                  else if (filtered.isEmpty)
                    _empty(querying ? 'No TV shows found. Try another title or genre.' : 'No shows match this genre yet.')
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filtered.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns, crossAxisSpacing: 11, mainAxisSpacing: 15,
                        childAspectRatio: .53,
                      ),
                      itemBuilder: (_, index) => _posterCard(filtered[index]),
                    ),
                  if (!querying && _hasMore && _popular.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Center(child: OutlinedButton.icon(
                      onPressed: _loadingMore ? null : _more,
                      icon: _loadingMore
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.expand_more_rounded),
                      label: Text(_loadingMore ? 'Loading TV shows...' : 'Load more shows'),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.white, shape: const StadiumBorder(), minimumSize: const Size(0, 46), backgroundColor: Colors.white.withValues(alpha: .05), side: BorderSide(color: appRed.withValues(alpha: .6))),
                    )),
                  ],
                ],
                const SizedBox(height: 18),
                const Text('TV show details and episodes powered by TMDB', textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, fontSize: 10)),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _seriesRail(String label, String eyebrow, IconData icon, List<Movie> shows) {
    if (shows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _heading(label, eyebrow, icon),
        const SizedBox(height: 13),
        SizedBox(height: 228, child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: shows.length > 16 ? 16 : shows.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, index) => SizedBox(width: 124, child: _posterCard(shows[index])),
        )),
      ]),
    );
  }

  Widget _heading(String title, String eyebrow, IconData icon) => Row(children: [
    Container(
      width: 4, height: 20,
      margin: const EdgeInsets.only(right: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [appAccentSoft, appRed]),
        borderRadius: BorderRadius.circular(99),
      ),
    ),
    Expanded(child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -.5))),
    if (icon == Icons.search_rounded)
      Text(eyebrow.toLowerCase().replaceFirstMapped(RegExp(r'^.'), (m) => m[0]!.toUpperCase()),
          style: const TextStyle(color: Colors.white54, fontSize: 11.5)),
  ]);

  Widget _frame({required double radius, required Widget child}) => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .35), blurRadius: 12, offset: const Offset(0, 6))],
    ),
    foregroundDecoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Colors.white.withValues(alpha: .08)),
    ),
    child: ClipRRect(borderRadius: BorderRadius.circular(radius), child: child),
  );

  Widget _art(String url, {BoxFit fit = BoxFit.cover}) {
    if (url.isEmpty) return Container(color: appSurface,
        child: const Center(child: Icon(Icons.tv_rounded, size: 35, color: Colors.white24)));
    return CachedNetworkImage(
      imageUrl: url, fit: fit,
      placeholder: (_, __) => Container(color: appSurface,
          child: const Center(child: Icon(Icons.tv_rounded, color: Colors.white24))),
      errorWidget: (_, __, ___) => Container(color: appSurface,
          child: const Center(child: Icon(Icons.broken_image_outlined, color: Colors.white30))),
    );
  }

  Widget _featureCard(Movie show, int rank) => InkWell(
    onTap: () => _open(show),
    borderRadius: BorderRadius.circular(28),
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [BoxShadow(color: appRed.withValues(alpha: .22), blurRadius: 26, offset: const Offset(0, 10))],
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(fit: StackFit.expand, children: [
          _art(show.backdrop.isNotEmpty ? show.backdrop : show.image),
          DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [const Color(0x22000000), const Color(0x00000000), appBg.withValues(alpha: .6), appBg.withValues(alpha: .96)],
              stops: const [0, .3, .62, 1]))),
          Positioned(top: 14, left: 14, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [appRed, appAccentSoft]),
              borderRadius: BorderRadius.circular(99),
              boxShadow: [BoxShadow(color: appRed.withValues(alpha: .45), blurRadius: 14, offset: const Offset(0, 4))],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.local_fire_department_rounded, size: 15, color: appRed.computeLuminance() > .5 ? Colors.black : Colors.white),
              const SizedBox(width: 5),
              Text('Trending #$rank', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: appRed.computeLuminance() > .5 ? Colors.black : Colors.white)),
            ]),
          )),
          Positioned(bottom: 18, left: 18, right: 18, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(show.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 26, height: 1.04, fontWeight: FontWeight.w900, letterSpacing: -.9,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 16)])),
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.star_rounded, size: 17, color: Color(0xFFFFCC58)),
                const SizedBox(width: 4),
                Text(show.rating.isEmpty ? 'New' : show.rating, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                if (show.year.isNotEmpty) ...[const SizedBox(width: 12), Text(show.year, style: const TextStyle(color: Colors.white70, fontSize: 12.5))],
                const Spacer(),
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 26),
                ),
              ]),
            ],
          )),
        ]),
      ),
    ),
  );

  Widget _posterCard(Movie show) => InkWell(
    onTap: () => _open(show),
    borderRadius: BorderRadius.circular(18),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Stack(fit: StackFit.expand, children: [
        _frame(radius: 18, child: _art(show.image)),
        if (show.rating.isNotEmpty)
          Positioned(left: 6, bottom: 6, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .6),
              border: Border.all(color: Colors.white24),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.star_rounded, color: Color(0xFFFFCC58), size: 12),
              const SizedBox(width: 2),
              Text(show.rating, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
            ]),
          )),
      ])),
      const SizedBox(height: 8),
      Text(show.title, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
      const SizedBox(height: 1),
      Text(show.year.isEmpty ? 'TV Series' : show.year,
          maxLines: 1, style: const TextStyle(fontSize: 10.5, color: Colors.white54)),
    ]),
  );

  Widget _empty(String message, {VoidCallback? retry}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 45, horizontal: 18),
    child: Column(children: [
      Container(
        width: 72, height: 72,
        decoration: BoxDecoration(shape: BoxShape.circle, color: appRed.withValues(alpha: .14)),
        child: Icon(Icons.live_tv_outlined, color: appAccentSoft, size: 34),
      ),
      const SizedBox(height: 12),
      Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
      if (retry != null) ...[
        const SizedBox(height: 14),
        FilledButton(onPressed: retry, child: const Text('Try again')),
      ],
    ]),
  );
}
