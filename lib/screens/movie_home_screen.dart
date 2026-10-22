import '../services/ad_service.dart';
import '../services/app_remote_config.dart';
import '../services/premium_service.dart';
import 'remove_ads_screen.dart';
import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../models/movie.dart';
import '../services/tmdb_service.dart';
import '../services/movie_library.dart';
import '../services/app_preferences.dart';
import '../config.dart';
import 'library_screen.dart';
import 'browser_screen.dart';
import 'downloads_screen.dart';
import 'package:share_plus/share_plus.dart';
import 'movie_detail_screen.dart';
import 'movie_player_screen.dart';
import 'trailer_player_screen.dart';
import 'settings_screen.dart';
import '../widgets/app_drawer.dart';

class MovieHomeScreen extends StatefulWidget {
  const MovieHomeScreen({super.key});
  @override
  State<MovieHomeScreen> createState() => _MovieHomeScreenState();
}

class _MovieHomeScreenState extends State<MovieHomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TmdbService _tmdb = TmdbService();
  final TextEditingController _search = TextEditingController();
  final PageController _heroController = PageController();
  Timer? _heroAutoTimer;
  Timer? _searchDebounce;
  int _heroPage = 0;
  List<Movie> _local = [], _trending = [], _top10 = [], _continueWatching = [];
  List<TmdbTrailer> _trailers = [];
  Set<String> _saved = {};
  bool _loading = true, _watchlistOnly = false;
  bool _tmdbLoading = true, _tmdbAvailable = false;
  String _tmdbError = '';
  String _query = '';
  bool _searchOpen = false;
  List<Movie> _remoteSearchResults = [];
  bool _searchLoading = false;
  String _searchError = '';
  int _searchRequestId = 0;
  String _typeFilter = 'All';
  String? _genreFilter;
  List<Movie> _genreResults = [];
  bool _genreLoading = false;
  bool _homeRequestInFlight = false;
  static const String _cachedTrendingKey = 'damimovies_tmdb_trending_cache_v2';
  static const String _cachedTopKey = 'damimovies_tmdb_top_cache_v2';

  @override
  void initState() {
    super.initState();
    MovieLibrary.instance.addListener(_syncLibrary);
    _loadHome();
    // The hero cycles through several trending titles automatically, while
    // remaining swipeable by the user.
    _heroAutoTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || !_heroController.hasClients) return;
      final count = _heroMovies.length;
      if (count < 2) return;
      final next = (_heroPage + 1) % count;
      _heroController.animateToPage(
        next,
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _heroAutoTimer?.cancel();
    _searchDebounce?.cancel();
    _searchRequestId++;
    _heroController.dispose();
    MovieLibrary.instance.removeListener(_syncLibrary);
    _search.dispose();
    super.dispose();
  }

  void _syncLibrary() {
    if (!mounted) return;
    final library = MovieLibrary.instance;
    setState(() {
      _saved = library.saved.map((m) => m.key).toSet();
      _continueWatching = library.history;
    });
  }

  Future<List<Movie>> _readMovieCache(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 3));
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) => Movie.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeMovieCache(String key, List<Movie> movies) async {
    if (movies.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 3));
      await prefs
          .setString(key, jsonEncode(movies.map((m) => m.toJson()).toList()))
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  /// Search TMDB as the user types. The debounce avoids making one request per
  /// keystroke; the explicit search icon and keyboard action can submit at once.
  void _handleSearchChanged(String value) {
    final query = value.trim();
    _searchDebounce?.cancel();
    _searchRequestId++; // Ignore any request that belongs to an older query.
    if (!mounted) return;
    setState(() {
      _query = value;
      _remoteSearchResults = [];
      _searchError = '';
      _searchLoading = query.length >= 2;
    });
    if (query.length < 2) {
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 450), () {
      _runRemoteSearch(query);
    });
  }

  Future<void> _runRemoteSearch([String? requestedQuery]) async {
    final query = (requestedQuery ?? _query).trim();
    _searchDebounce?.cancel();
    if (query.isEmpty) return;
    final requestId = ++_searchRequestId;
    if (mounted)
      setState(() {
        _searchLoading = true;
        _searchError = '';
      });
    try {
      final remote = await _tmdb.search(query).timeout(
            const Duration(seconds: 20),
            onTimeout: () => <Movie>[],
          );
      if (!mounted || requestId != _searchRequestId || query != _query.trim())
        return;
      setState(() {
        _remoteSearchResults = remote;
        _searchLoading = false;
        _searchError = remote.isEmpty ? (_tmdb.lastError ?? '') : '';
      });
    } catch (_) {
      if (!mounted || requestId != _searchRequestId || query != _query.trim())
        return;
      setState(() {
        _searchLoading = false;
        _searchError = _tmdb.lastError ??
            'Could not search TMDB. Check your internet connection and retry.';
      });
    }
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchRequestId++;
    _search.clear();
    if (!mounted) return;
    setState(() {
      _query = '';
      _remoteSearchResults = [];
      _searchLoading = false;
      _searchError = '';
    });
  }

  Future<void> _refreshLocalLibrary() async {
    try {
      await MovieLibrary.instance.load().timeout(const Duration(seconds: 5));
      await MovieLibrary.instance
          .seedFromCatalogue(_local)
          .timeout(const Duration(seconds: 4));
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 3));
      final legacyContinue = (prefs.getStringList('damimovies_continue') ?? [])
          .map((value) {
            try {
              return Movie.fromJson(
                  Map<String, dynamic>.from(jsonDecode(value) as Map));
            } catch (_) {
              return null;
            }
          })
          .whereType<Movie>()
          .toList();
      if (mounted)
        setState(() {
          _saved = MovieLibrary.instance.saved.map((m) => m.key).toSet();
          _continueWatching = MovieLibrary.instance.history.isNotEmpty
              ? MovieLibrary.instance.history
              : legacyContinue;
        });
    } catch (_) {
      // History/watchlist are optional and never block movie opening.
    }
  }

  Future<void> _loadHome() async {
    if (_homeRequestInFlight) return;
    _homeRequestInFlight = true;
    if (mounted)
      setState(() {
        _tmdbLoading = true;
        _tmdbError = '';
      });
    try {
      // Read the packaged movie catalogue first, independent of TMDB.
      try {
        final raw = await rootBundle
            .loadString('assets/data/movies.json')
            .timeout(const Duration(seconds: 5));
        final decoded = jsonDecode(raw);
        final list = decoded is List
            ? decoded
            : (decoded is Map && decoded['movies'] is List
                ? decoded['movies'] as List
                : <dynamic>[]);
        final localMovies = list
            .whereType<Map>()
            .map((e) => Movie.fromJson(Map<String, dynamic>.from(e)))
            .where((movie) => movie.name.isNotEmpty)
            .toList();
        if (mounted)
          setState(() {
            _local = localMovies;
            _loading = false;
          });
      } catch (_) {
        if (mounted) setState(() => _loading = false);
      }

      // Cached TMDB titles appear immediately on later launches/offline starts.
      final cached = await Future.wait<List<Movie>>([
        _readMovieCache(_cachedTrendingKey),
        _readMovieCache(_cachedTopKey),
      ]).timeout(const Duration(seconds: 4),
          onTimeout: () => <List<Movie>>[[], []]);
      final cachedTrending = cached[0];
      final cachedTop = cached[1];
      if (mounted && (cachedTrending.isNotEmpty || cachedTop.isNotEmpty)) {
        setState(() {
          if (_trending.isEmpty) _trending = cachedTrending;
          if (_top10.isEmpty)
            _top10 = cachedTop.isNotEmpty
                ? cachedTop.take(10).toList()
                : cachedTrending.take(10).toList();
        });
        _resetHeroCarousel();
      }

      // Hydrate local list/history out of band. Never await storage before
      // allowing a user to open a movie.
      unawaited(_refreshLocalLibrary());

      // Request only trending movies first. The previous screen started the
      // trend, top-rated, now-playing and many video requests simultaneously;
      // slow mobile networks often timed out all of them. Show the first live
      // row as soon as it arrives, then enrich the other rows afterward.
      List<Movie> trending = [];
      try {
        trending = await _tmdb
            .trending()
            .timeout(const Duration(seconds: 17), onTimeout: () => <Movie>[]);
      } catch (_) {}

      if (!mounted) return;
      if (trending.isEmpty) {
        setState(() {
          _tmdbLoading = false;
          _tmdbAvailable = false;
          _tmdbError =
              _tmdb.lastError ?? 'TMDB did not return any movies. Tap Retry.';
          if (_top10.isEmpty) _top10 = _local.take(10).toList();
        });
        return;
      }

      setState(() {
        _trending = trending;
        _top10 = trending.take(10).toList();
        _tmdbAvailable = true;
        _tmdbLoading = false;
        _tmdbError = '';
      });
      _resetHeroCarousel();
      unawaited(_writeMovieCache(_cachedTrendingKey, trending));
      unawaited(_writeMovieCache(_cachedTopKey, trending.take(10).toList()));
      unawaited(_seedCatalogueSafely([..._local, ...trending]));

      // Top-rated movies and trailer metadata are secondary loads. A failure
      // here must not hide already-visible trending results or disable taps.
      try {
        final topRated = await _tmdb
            .topRated()
            .timeout(const Duration(seconds: 16), onTimeout: () => <Movie>[]);
        if (mounted && topRated.isNotEmpty) {
          final top = topRated.take(10).toList();
          setState(() {
            _top10 = top;
            _tmdbAvailable = true;
          });
          unawaited(_writeMovieCache(_cachedTopKey, top));
        }
      } catch (_) {}

      try {
        final trailers = await _tmdb.latestTrailers().timeout(
            const Duration(seconds: 16),
            onTimeout: () => <TmdbTrailer>[]);
        if (mounted && trailers.isNotEmpty)
          setState(() => _trailers = trailers);
      } catch (_) {}
    } catch (error) {
      if (mounted)
        setState(() {
          _tmdbLoading = false;
          _tmdbAvailable = _trending.isNotEmpty || _top10.isNotEmpty;
          _tmdbError =
              _tmdb.lastError ?? 'Could not connect to TMDB. Tap Retry.';
        });
    } finally {
      _homeRequestInFlight = false;
    }
  }

  Future<void> _toggleSaved(Movie movie) async {
    // Update the icon immediately; disk persistence is best-effort background work.
    final shouldSave = !_saved.contains(movie.key);
    if (mounted)
      setState(() {
        if (shouldSave) {
          _saved.add(movie.key);
        } else {
          _saved.remove(movie.key);
        }
      });
    try {
      await MovieLibrary.instance.load().timeout(const Duration(seconds: 4));
      final alreadySaved = MovieLibrary.instance.isSaved(movie);
      if (alreadySaved != shouldSave) {
        await MovieLibrary.instance
            .toggleSaved(movie)
            .timeout(const Duration(seconds: 4));
      }
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 3));
      await prefs
          .setStringList('damimovies_watchlist', _saved.toList())
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  Future<void> _seedCatalogueSafely(Iterable<Movie> movies) async {
    try {
      await MovieLibrary.instance
          .seedFromCatalogue(movies)
          .timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  /// Card tap: the support ad (when due) shows first, then the movie opens.
  Future<void> _open(Movie movie) async {
    if (!mounted) return;
    await AdService.instance.guard(context, () => _openNow(movie));
  }

  Future<void> _openNow(Movie movie) async {
    if (!mounted) return;
    final recent = <Movie>[
      movie,
      ..._continueWatching.where((m) => m.key != movie.key)
    ].take(12).toList();
    setState(() => _continueWatching = recent);
    // Push first; shared-preference or history storage must never make a tap
    // look dead when opening a title.
    unawaited(_persistOpenedMovie(movie, recent));
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MovieDetailScreen(
        movie: movie,
        saved: _saved.contains(movie.key),
        onToggleSaved: () async {
          await _toggleSaved(movie);
        },
      ),
    ));
  }

  Future<void> _persistOpenedMovie(Movie movie, List<Movie> recent) async {
    try {
      await MovieLibrary.instance
          .recordOpened(movie)
          .timeout(const Duration(seconds: 4));
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 3));
      await prefs
          .setStringList('damimovies_continue',
              recent.map((m) => jsonEncode(m.toJson())).toList())
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  void _playNow(Movie movie) {
    if (!mounted) return;
    unawaited(AdService.instance.guard(context, () => _playNowAfterAd(movie)));
  }

  void _playNowAfterAd(Movie movie) {
    if (!mounted) return;
    final recent = <Movie>[
      movie,
      ..._continueWatching.where((m) => m.key != movie.key)
    ].take(12).toList();
    setState(() => _continueWatching = recent);
    unawaited(_persistOpenedMovie(movie, recent));
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MoviePlayerScreen(movie: movie),
    ));
  }

  List<Movie> get _baseMovies => _trending.isNotEmpty ? _trending : _local;
  List<Movie> get _heroMovies {
    final source = _baseMovies;
    final unique = <String, Movie>{};
    for (final movie in source) {
      unique.putIfAbsent(movie.key, () => movie);
    }
    // Keep hero loading light but provide several titles, not just one.
    return unique.values.take(8).toList();
  }

  void _resetHeroCarousel() {
    _heroPage = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _heroController.hasClients) {
        _heroController.jumpToPage(0);
      }
    });
  }

  List<Movie> get _searchResults {
    final query = _query.trim().toLowerCase();
    final remoteKeys = _remoteSearchResults.map((movie) => movie.key).toSet();
    final all = <String, Movie>{};
    for (final movie in [
      ..._remoteSearchResults,
      ..._trending,
      ..._top10,
      ..._local,
      ..._genreResults,
    ]) {
      all.putIfAbsent(movie.key, () => movie);
    }
    return all.values
        // TMDB relevance matches may include alternative/original titles that
        // are not visible in the display title, so don't filter remote matches
        // a second time using local substring matching.
        .where((movie) =>
            query.isEmpty ||
            remoteKeys.contains(movie.key) ||
            '${movie.title} ${movie.genre}'.toLowerCase().contains(query))
        .where((movie) =>
            _typeFilter == 'All' ||
            (_typeFilter == 'Series' ? movie.isSeries : !movie.isSeries))
        .where((movie) =>
            _genreFilter == null ||
            movie.genres.any(
                (genre) => genre.toLowerCase() == _genreFilter!.toLowerCase()))
        .where((movie) => !_watchlistOnly || _saved.contains(movie.key))
        .toList();
  }

  Future<void> _selectGenre(String? genre) async {
    setState(() {
      _genreFilter = genre;
      _genreLoading = genre != null;
    });
    if (genre == null) {
      if (mounted)
        setState(() {
          _genreResults = [];
          _genreLoading = false;
        });
      return;
    }
    try {
      final rows = await _tmdb
          .discover(genre)
          .timeout(const Duration(seconds: 10), onTimeout: () => <Movie>[]);
      if (mounted && _genreFilter == genre)
        setState(() {
          _genreResults = rows;
          _genreLoading = false;
        });
    } catch (_) {
      if (mounted) setState(() => _genreLoading = false);
    }
  }

  void _openSearch() => setState(() => _searchOpen = true);

  void _closeSearch() {
    _clearSearch();
    setState(() => _searchOpen = false);
  }

  Widget _circleIcon(IconData icon) => Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: .25),
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, size: 26),
      );

  Widget _brandHeader() => Row(children: [
        InkWell(
          customBorder: const CircleBorder(),
          onTap: () => _scaffoldKey.currentState?.openDrawer(),
          child: _circleIcon(Icons.menu_rounded),
        ),
        SizedBox(width: 12),
        Image.asset('assets/icon/home_logo.png',
            width: 44, height: 44, fit: BoxFit.contain),
        SizedBox(width: 11),
        Expanded(
            child: Text('DamiMovies'.tr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.7))),
        InkWell(
            customBorder: const CircleBorder(),
            onTap: _openSearch,
            child: _circleIcon(Icons.search_rounded)),
      ]);

  Widget _searchHeader() => Row(children: [
        InkWell(
            customBorder: const CircleBorder(),
            onTap: _closeSearch,
            child: _circleIcon(Icons.arrow_back_rounded)),
        SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: _search,
            autofocus: true,
            onChanged: _handleSearchChanged,
            onSubmitted: (value) => _runRemoteSearch(value),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search movies on DamiMovies...'.tr,
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: _clearSearch,
                      icon: Icon(Icons.close)),
              filled: true,
              fillColor: appSurface,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
      ]);

  /// Pull down at the top of the homepage to reload movie data.
  /// Preserve search text, selected filters, and the user's current view.
  Future<void> _refreshHome() async {
    await _refreshLocalLibrary();
    if (!mounted) return;

    // If startup loading is still active, wait for it to finish before
    // starting another fetch instead of silently skipping the refresh.
    while (mounted && _homeRequestInFlight) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    if (!mounted) return;
    await _loadHome();
  }

  @override
  Widget build(BuildContext context) {
    final searching = _query.trim().isNotEmpty || _watchlistOnly;
    final results = _searchResults;
    return Scaffold(
      key: _scaffoldKey,
      drawer: const AppDrawer(),
      body: SafeArea(
        child: RefreshIndicator(
          color: appRed,
          backgroundColor: appSurface,
          displacement: 65,
          onRefresh: _refreshHome,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
        SliverToBoxAdapter(
            child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: _searchOpen ? _searchHeader() : _brandHeader())),
        SliverToBoxAdapter(
            child: SizedBox(
                height: 42,
                child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 17),
                    children: [
                      for (final type in ['All', 'Movies', 'Series'])
                        Padding(
                            padding: const EdgeInsets.only(right: 7),
                            child: ChoiceChip(
                                label: Text(type.tr),
                                selected: _typeFilter ==
                                    (type == 'Movies' ? 'Movies' : type),
                                onSelected: (_) =>
                                    setState(() => _typeFilter = type),
                                selectedColor: appRed.withValues(alpha: .2),
                                side: BorderSide(
                                    color: _typeFilter == type
                                        ? appRed
                                        : Colors.white12),
                                labelStyle: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11,
                                    color: _typeFilter == type
                                        ? Colors.white
                                        : Colors.white60))),
                      SizedBox(width: 3),
                      for (final genre in [
                        'Action',
                        'Adventure',
                        'Animation',
                        'Comedy',
                        'Crime',
                        'Drama',
                        'Fantasy',
                        'Horror',
                        'Mystery',
                        'Romance',
                        'Sci-Fi',
                        'Thriller'
                      ])
                        Padding(
                            padding: const EdgeInsets.only(right: 7),
                            child: ChoiceChip(
                                label: Text(genre),
                                selected: _genreFilter == genre,
                                onSelected: (_) => _selectGenre(
                                    _genreFilter == genre ? null : genre),
                                selectedColor: appRed.withValues(alpha: .2),
                                side: BorderSide(
                                    color: _genreFilter == genre
                                        ? appRed
                                        : Colors.white12),
                                labelStyle: TextStyle(
                                    fontSize: 11,
                                    color: _genreFilter == genre
                                        ? Colors.white
                                        : Colors.white60))),
                    ]))),
        if (_genreLoading)
          SliverToBoxAdapter(
              child: LinearProgressIndicator(
                  minHeight: 2,
                  color: appRed,
                  backgroundColor: Colors.white10)),
        if (searching || _genreFilter != null || _typeFilter != 'All') ...[
          SliverToBoxAdapter(
            child: _sectionTitle(
              _watchlistOnly ? 'My Watchlist' : 'Search Results',
              _searchLoading ? 'SEARCHING TMDB…' : '${results.length} titles',
            ),
          ),
          if (_searchLoading)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    color: appRed,
                    backgroundColor: Colors.white12,
                  ),
                ),
              ),
            ),
          if (results.isEmpty && _searchLoading)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Center(
                  child: Column(
                    children: [
                      const CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('Searching TMDB for “${_query.trim()}”…',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white60)),
                    ],
                  ),
                ),
              ),
            )
          else if (results.isEmpty && _searchError.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: appSurface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.cloud_off_rounded,
                          size: 34, color: Colors.white54),
                      SizedBox(height: 10),
                      Text('TMDB search failed: $_searchError',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70)),
                      SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: () => _runRemoteSearch(_query),
                        icon: Icon(Icons.refresh_rounded),
                        label: Text('Retry search'.tr),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (results.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Center(
                  child: Text(
                    _query.trim().length < 2
                        ? 'Enter at least 2 characters to search TMDB.'
                        : 'No movies found. Try another title.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white60),
                  ),
                ),
              ),
            )
          else ...[
            if (_searchError.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                  child: Text(
                      'TMDB unavailable: $_searchError. Showing matching saved titles.',
                      style: const TextStyle(
                          color: Colors.orangeAccent, fontSize: 11)),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _poster(results[i]),
                  childCount: results.length,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 17,
                  childAspectRatio: .52,
                ),
              ),
            ),
          ],
        ] else ...[
          if (_heroMovies.isNotEmpty)
            SliverToBoxAdapter(child: _heroCarousel(_heroMovies)),
          if (_top10.isNotEmpty)
            SliverToBoxAdapter(child: _topTenRail())
          else if (_local.isNotEmpty)
            SliverToBoxAdapter(
                child: _movieRail(
                    _tmdbLoading ? 'Popular Movies' : 'Movie Picks',
                    _local.take(10).toList())),
          if (_continueWatching.isNotEmpty)
            SliverToBoxAdapter(
                child: _movieRail('Continue Watching', _continueWatching,
                    showProgress: true)),
          if (_trending.isNotEmpty)
            SliverToBoxAdapter(child: _movieRail('Trending Movies', _trending)),
          if (_trailers.isNotEmpty) SliverToBoxAdapter(child: _trailerRail()),
          if (_loading && _local.isEmpty)
            SliverToBoxAdapter(
                child: Padding(
                    padding: EdgeInsets.all(30),
                    child: Center(child: CircularProgressIndicator()))),
          if (!_tmdbLoading && !_tmdbAvailable)
            SliverToBoxAdapter(
                child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: appSurface, borderRadius: BorderRadius.circular(16)),
                child: Row(children: [
                  Icon(Icons.cloud_off_rounded, color: Colors.white60),
                  SizedBox(width: 10),
                  Expanded(
                      child: Text(
                    _tmdbError.isEmpty
                        ? 'TMDB is unavailable. Showing your saved movie catalogue.'
                        : 'TMDB unavailable: $_tmdbError Showing your saved catalogue.',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  )),
                  TextButton(onPressed: _loadHome, child: Text('Retry'.tr)),
                ]),
              ),
            )),
          if (!_loading && _local.isEmpty && !_tmdbLoading && !_tmdbAvailable)
            SliverToBoxAdapter(
                child: Padding(
              padding: const EdgeInsets.all(28),
              child: Center(
                  child: Column(children: [
                Icon(Icons.movie_filter_outlined,
                    size: 42, color: Colors.white54),
                SizedBox(height: 10),
                Text('No movies could be loaded.'.tr,
                    style: TextStyle(fontWeight: FontWeight.w700)),
                SizedBox(height: 8),
                FilledButton(onPressed: _loadHome, child: Text('Try again'.tr)),
              ])),
            )),
          const SliverToBoxAdapter(child: SizedBox(height: 26)),
        ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, [String? subtitle]) => Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 13),
      child: Row(children: [
        Expanded(
            child: Text(title.tr,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.3))),
        if (subtitle != null)
          Text(subtitle.tr,
              style: const TextStyle(color: Colors.white54, fontSize: 11))
      ]));

  Widget _heroCarousel(List<Movie> movies) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 19),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 390,
            child: PageView.builder(
              controller: _heroController,
              itemCount: movies.length,
              onPageChanged: (index) {
                if (mounted) setState(() => _heroPage = index);
              },
              itemBuilder: (context, index) =>
                  _heroSlide(movies[index], index, movies.length),
            ),
          ),
          if (movies.length > 1) ...[
            SizedBox(height: 13),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(movies.length, (index) {
                final selected = index == _heroPage;
                return GestureDetector(
                  onTap: () => _heroController.animateToPage(
                    index,
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutCubic,
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: selected ? 22 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: selected ? appRed : Colors.white30,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }

  Widget _heroSlide(Movie movie, int index, int total) {
    final backdrop =
        movie.backdrop.startsWith('http') ? movie.backdrop : movie.image;
    return GestureDetector(
      onTap: () => _open(movie),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 1),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: appSurface,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (backdrop.startsWith('http'))
              CachedNetworkImage(
                imageUrl: backdrop,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(color: appSurface),
              )
            else
              Container(color: appSurface),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x11000000),
                    Color(0x44000000),
                    Color(0xF2080B10)
                  ],
                  stops: [0, .35, 1],
                ),
              ),
            ),
            Positioned(
              top: 16,
              left: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                    color: appRed, borderRadius: BorderRadius.circular(9)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.local_fire_department_rounded,
                        size: 15, color: Colors.white),
                    SizedBox(width: 5),
                    Text('TRENDING NOW'.tr,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .8,
                            color: Colors.white)),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .55),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(
                  '${index + 1} / $total',
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Colors.white),
                ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 21,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    movie.genres.take(3).join('  •  ').toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Color(0xFFFFB8C5),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1),
                  ),
                  SizedBox(height: 9),
                  Text(
                    movie.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 31,
                        height: 1.02,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.7),
                  ),
                  SizedBox(height: 9),
                  Row(
                    children: [
                      Icon(Icons.star_rounded,
                          color: Color(0xFFFFC857), size: 18),
                      SizedBox(width: 4),
                      Text(
                          movie.rating.isEmpty
                              ? 'Trending on TMDB'
                              : '${movie.rating} / 10',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white70)),
                      SizedBox(width: 9),
                      if (movie.year.isNotEmpty)
                        Text(movie.year,
                            style: const TextStyle(
                                color: Colors.white60, fontSize: 12)),
                    ],
                  ),
                  SizedBox(height: 15),
                  Row(
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 19, vertical: 12)),
                        onPressed: () => _playNow(movie),
                        icon: Icon(Icons.play_arrow_rounded),
                        label: Text('Play'.tr,
                            style:
                                const TextStyle(fontWeight: FontWeight.w900)),
                      ),
                      SizedBox(width: 10),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white54),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12)),
                        onPressed: () => _toggleSaved(movie),
                        icon: Icon(_saved.contains(movie.key)
                            ? Icons.bookmark
                            : Icons.add),
                        label: Text(_saved.contains(movie.key)
                            ? 'Saved'
                            : 'My List'.tr),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _movieRail(String title, List<Movie> movies,
          {bool showProgress = false}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionTitle(
            title.tr, title == 'Continue Watching' ? 'Pick up again'.tr : null),
        SizedBox(
            height: showProgress ? 202 : 220,
            child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 17),
                scrollDirection: Axis.horizontal,
                itemCount: movies.length,
                separatorBuilder: (_, __) => SizedBox(width: 12),
                itemBuilder: (_, i) => SizedBox(
                    width: 128,
                    child: GestureDetector(
                        onTap: () => _open(movies[i]),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                  child: Stack(fit: StackFit.expand, children: [
                                ClipRRect(
                                    borderRadius: BorderRadius.circular(15),
                                    child: _image(movies[i].image)),
                                Positioned(
                                    right: 7,
                                    top: 7,
                                    child: _bookmarkButton(movies[i])),
                                if (showProgress &&
                                    MovieLibrary.instance
                                            .progressFor(movies[i]) >
                                        0)
                                  Positioned(
                                      left: 0,
                                      right: 0,
                                      bottom: 0,
                                      child: LinearProgressIndicator(
                                          value: MovieLibrary.instance
                                              .progressFor(movies[i]),
                                          minHeight: 4,
                                          backgroundColor: Colors.white24,
                                          color: appRed))
                              ])),
                              SizedBox(height: 8),
                              Text(movies[i].title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      height: 1.2)),
                              if (showProgress)
                                Padding(
                                    padding: EdgeInsets.only(top: 4),
                                    child: Text('Continue watching'.tr,
                                        style: TextStyle(
                                            color: Colors.white54,
                                            fontSize: 10))),
                            ]))))),
        SizedBox(height: 7)
      ]);

  Widget _topTenRail() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionTitle('Top 10 Today'),
        SizedBox(
            height: 218,
            child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                scrollDirection: Axis.horizontal,
                itemCount: _top10.length,
                separatorBuilder: (_, __) => SizedBox(width: 5),
                itemBuilder: (_, i) => SizedBox(
                    width: 142,
                    child: GestureDetector(
                        onTap: () => _open(_top10[i]),
                        child: Stack(clipBehavior: Clip.none, children: [
                          Positioned(
                              left: 28,
                              right: 0,
                              top: 2,
                              bottom: 0,
                              child: ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: _image(_top10[i].image))),
                          Positioned(
                              left: 0,
                              bottom: -7,
                              child: Text('${i + 1}',
                                  style: TextStyle(
                                      fontSize: 96,
                                      height: 1,
                                      fontWeight: FontWeight.w900,
                                      fontStyle: FontStyle.italic,
                                      foreground: Paint()
                                        ..style = PaintingStyle.stroke
                                        ..strokeWidth = 3
                                        ..color = appBg))),
                          Positioned(
                              left: 0,
                              bottom: -7,
                              child: Text('${i + 1}',
                                  style: const TextStyle(
                                      fontSize: 96,
                                      height: 1,
                                      fontWeight: FontWeight.w900,
                                      fontStyle: FontStyle.italic,
                                      color: Colors.white))),
                          Positioned(
                              top: 9,
                              right: 7,
                              child: _bookmarkButton(_top10[i])),
                        ]))))),
        SizedBox(height: 17)
      ]);

  Widget _trailerRail() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Latest Trailers'),
          SizedBox(
            height: 174,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 17),
              scrollDirection: Axis.horizontal,
              itemCount: _trailers.length,
              separatorBuilder: (_, __) => SizedBox(width: 12),
              itemBuilder: (_, i) {
                final trailer = _trailers[i];
                return SizedBox(
                  width: 246,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => TrailerPlayerScreen(
                        title: trailer.title,
                        youtubeKey: trailer.key,
                        poster: trailer.poster,
                      ),
                    )),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(15),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                _image(trailer.poster),
                                const DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.transparent,
                                        Color(0xAA000000),
                                      ],
                                    ),
                                  ),
                                ),
                                Center(
                                  child: Icon(
                                    Icons.play_circle_fill_rounded,
                                    color: Colors.white,
                                    size: 52,
                                  ),
                                ),
                                Positioned(
                                  left: 9,
                                  bottom: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: appRed,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'TRAILER',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: 7),
                        Text(
                          trailer.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SizedBox(height: 12),
        ],
      );

  Widget _poster(Movie movie) => GestureDetector(
      onTap: () => _open(movie),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: Stack(fit: StackFit.expand, children: [
          ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: _image(movie.image)),
          Positioned(top: 6, right: 6, child: _bookmarkButton(movie)),
          if (movie.rating.isNotEmpty)
            Positioned(
                left: 6,
                bottom: 6,
                child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(6)),
                    child: Text('★ ${movie.rating}',
                        style: const TextStyle(
                            fontSize: 9, fontWeight: FontWeight.bold))))
        ])),
        SizedBox(height: 7),
        Text(movie.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
        SizedBox(height: 3),
        Text(
            '${movie.year}${movie.genres.isNotEmpty ? ' • ${movie.genres.first}' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 10))
      ]));

  Widget _image(String url) => url.startsWith('http')
      ? CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(color: appSurface),
          errorWidget: (_, __, ___) => Container(
              color: appSurface,
              child: Icon(Icons.movie_outlined, color: Colors.white24)))
      : Container(
          color: appSurface,
          child: Icon(Icons.movie_outlined, color: Colors.white24));
  Widget _bookmarkButton(Movie movie) => GestureDetector(
      onTap: () => _toggleSaved(movie),
      child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .75),
              shape: BoxShape.circle),
          child: Icon(
              _saved.contains(movie.key)
                  ? Icons.bookmark
                  : Icons.bookmark_border,
              size: 16,
              color: _saved.contains(movie.key) ? appRed : Colors.white)));
}
