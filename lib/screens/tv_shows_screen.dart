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
  String _genre = 'All';

  static const _categories = [
    'All', 'Drama', 'Comedy', 'Crime', 'Action & Adventure',
    'Animation', 'Documentary', 'Sci-Fi & Fantasy',
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
    List<Movie> trending = [], popular = [];
    await Future.wait([
      () async { try { trending = await _tmdb.tvTrending(); } catch (_) {} }(),
      () async { try { popular = await _tmdb.tvPopular(); } catch (_) {} }(),
    ]);
    if (!mounted) return;
    setState(() {
      _trending = trending;
      _popular = popular;
      _page = 1;
      _hasMore = popular.isNotEmpty;
      _featuredPage = 0;
      _loading = false;
      _error = trending.isEmpty && popular.isEmpty
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
    if (_genre == 'All') return input;
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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: appRed.withValues(alpha: .16), borderRadius: BorderRadius.circular(13)),
                    child: Icon(Icons.live_tv_rounded, color: appRed, size: 23),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('TV SHOWS', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: .7)),
                    Text('Binge-worthy stories, all in one place', style: TextStyle(fontSize: 11, color: Colors.white60)),
                  ])),
                  IconButton(tooltip: 'Refresh TV shows', onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
                ]),
                const SizedBox(height: 22),
                TextField(
                  controller: _search,
                  onChanged: _searchChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search TV shows, series...',
                    prefixIcon: Icon(Icons.search_rounded, color: appRed),
                    suffixIcon: _query.isNotEmpty ? IconButton(
                      tooltip: 'Clear search',
                      onPressed: () { _search.clear(); _searchChanged(''); FocusScope.of(context).unfocus(); },
                      icon: const Icon(Icons.close_rounded),
                    ) : null,
                    filled: true,
                    fillColor: appSurface,
                    contentPadding: const EdgeInsets.symmetric(vertical: 15),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
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
                    SizedBox(height: 245, child: PageView.builder(
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
                        decoration: BoxDecoration(color: i == _featuredPage ? appRed : Colors.white30, borderRadius: BorderRadius.circular(8)),
                      ),
                    )),
                    const SizedBox(height: 28),
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
                        selectedColor: appRed.withValues(alpha: .35),
                        backgroundColor: appSurface,
                        side: BorderSide(color: _genre == category ? appRed : Colors.white10),
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
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: BorderSide(color: appRed.withValues(alpha: .6))),
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

  Widget _heading(String title, String eyebrow, IconData icon) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(eyebrow, style: TextStyle(color: appRed, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
      const SizedBox(height: 5),
      Row(children: [Icon(icon, color: appRed, size: 21), const SizedBox(width: 8),
        Expanded(child: Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)))],),
    ],
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
    borderRadius: BorderRadius.circular(22),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Stack(fit: StackFit.expand, children: [
        _art(show.backdrop.isNotEmpty ? show.backdrop : show.image),
        const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Colors.black26, Colors.transparent, Colors.black87, Colors.black]))),
        Positioned(top: 15, left: 15, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(color: appRed, borderRadius: BorderRadius.circular(9)),
          child: Text('TRENDING  #$rank', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
        )),
        Positioned(bottom: 18, left: 16, right: 16, child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(show.title, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
            const SizedBox(height: 5),
            Row(children: [
              const Icon(Icons.star_rounded, size: 15, color: Color(0xFFFFCC58)),
              const SizedBox(width: 3),
              Text(show.rating.isEmpty ? 'New' : show.rating, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              if (show.year.isNotEmpty) ...[const SizedBox(width: 12), Text(show.year, style: const TextStyle(color: Colors.white70, fontSize: 12))],
              const Spacer(),
              Icon(Icons.arrow_circle_right_rounded, color: appRed, size: 29),
            ]),
          ],
        )),
      ]),
    ),
  );

  Widget _posterCard(Movie show) => InkWell(
    onTap: () => _open(show),
    borderRadius: BorderRadius.circular(12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Stack(fit: StackFit.expand, children: [
        ClipRRect(borderRadius: BorderRadius.circular(12), child: _art(show.image)),
        if (show.rating.isNotEmpty)
          Positioned(top: 6, right: 6, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
            decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(7)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.star_rounded, color: Color(0xFFFFCC58), size: 12),
              const SizedBox(width: 2),
              Text(show.rating, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
            ]),
          )),
      ])),
      const SizedBox(height: 6),
      Text(show.title, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      Text(show.year.isEmpty ? 'TV Series' : show.year,
          maxLines: 1, style: const TextStyle(fontSize: 10, color: Colors.white54)),
    ]),
  );

  Widget _empty(String message, {VoidCallback? retry}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 45, horizontal: 18),
    child: Column(children: [
      Icon(Icons.live_tv_outlined, color: appRed, size: 43),
      const SizedBox(height: 12),
      Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
      if (retry != null) ...[
        const SizedBox(height: 14),
        FilledButton(onPressed: retry, child: const Text('Try again')),
      ],
    ]),
  );
}
