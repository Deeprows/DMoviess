import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/movie.dart';
import '../config.dart';

/// TMDB API service. Override the built-in key at build time with
/// --dart-define=TMDB_API_KEY=YOUR_KEY.
class TmdbService {
  static const String _providedApiKey = String.fromEnvironment('TMDB_API_KEY', defaultValue: '');
  static const String _fallbackApiKey = 'b83de997ce0ca0406c12cab7f256e43a';
  String get _apiKey => _providedApiKey.trim().isNotEmpty ? _providedApiKey.trim() : _fallbackApiKey;
  static const String _imageBase = 'https://image.tmdb.org/t/p/';
  bool get enabled => _apiKey.isNotEmpty;
  String? _lastError;
  String? get lastError => _lastError;
  final Map<String, ({int id, String type})> _resolvedReferences = {};

  Future<Map<String, dynamic>?> _get(String path, [Map<String, String> params = const {}]) async {
    if (!enabled) {
      _lastError = 'TMDB API key is missing.';
      return null;
    }
    try {
      final uri = Uri.https('api.themoviedb.org', '/3$path', {
        'api_key': _apiKey,
        'language': 'en-US',
        ...params,
      });
      final response = await http.get(uri, headers: const {'accept': 'application/json'})
          .timeout(const Duration(seconds: 9));
      if (response.statusCode != 200) {
        _lastError = response.statusCode == 401
            ? 'TMDB rejected the API key (HTTP 401).'
            : 'TMDB request failed (HTTP ${response.statusCode}).';
        return null;
      }
      final value = jsonDecode(utf8.decode(response.bodyBytes));
      if (value is Map<String, dynamic>) {
        _lastError = null;
        return value;
      }
      _lastError = 'TMDB returned an unexpected response.';
      return null;
    } catch (error) {
      _lastError = error.toString().contains('TimeoutException')
          ? 'TMDB timed out. Check the internet connection and retry.'
          : 'Could not reach TMDB. Check internet access and the API key.';
      return null;
    }
  }

  Movie? _movie(dynamic raw, {String type = 'movie'}) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! int) return null;
    final mediaType = (raw['media_type'] ?? type).toString();
    if (mediaType != 'movie' && mediaType != 'tv') return null;
    final isTv = mediaType == 'tv';
    final title = (raw[isTv ? 'name' : 'title'] ?? raw['title'] ?? raw['name'] ?? '').toString().trim();
    if (title.isEmpty) return null;
    final date = (raw[isTv ? 'first_air_date' : 'release_date'] ?? '').toString();
    final year = date.length >= 4 ? date.substring(0, 4) : '';
    final genres = <String>[];
    if (raw['genres'] is List) {
      for (final g in raw['genres'] as List) {
        if (g is Map && g['name'] != null) genres.add(g['name'].toString());
      }
    } else {
      genres.addAll(_genreNames(raw['genre_ids']));
    }
    final vote = raw['vote_average'];
    final poster = (raw['poster_path'] ?? '').toString();
    final backdrop = (raw['backdrop_path'] ?? '').toString();
    final imageUrl = poster.isEmpty ? '' : '${_imageBase}w500$poster';
    return Movie(
      name: year.isEmpty ? title : '$title ($year)',
      url: '${AppConfig.embedBase}/${isTv ? 'tv' : 'movie'}/$id',
      downloadUrl: '${AppConfig.downloadBase}/${isTv ? 'tv' : 'movie'}/$id',
      rating: vote is num && vote > 0 ? vote.toStringAsFixed(1) : '',
      genre: genres.join(','),
      image: imageUrl,
      date: '',
      backdrop: backdrop.isEmpty ? '' : '${_imageBase}w1280$backdrop',
      tmdbId: id,
      mediaType: mediaType,
      overview: (raw['overview'] ?? '').toString(),
      tagline: (raw['tagline'] ?? '').toString(),
      status: (raw['status'] ?? '').toString(),
      language: (raw['original_language'] ?? '').toString().toUpperCase(),
      releaseDate: date,
      runtime: raw['runtime'] is num ? (raw['runtime'] as num).toInt() : null,
      seasons: raw['number_of_seasons'] is num ? (raw['number_of_seasons'] as num).toInt() : null,
      episodes: raw['number_of_episodes'] is num ? (raw['number_of_episodes'] as num).toInt() : null,
    );
  }

  static const Map<int, String> _genres = {
    28:'Action',12:'Adventure',16:'Animation',35:'Comedy',80:'Crime',99:'Documentary',18:'Drama',
    10751:'Family',14:'Fantasy',36:'History',27:'Horror',10402:'Music',9648:'Mystery',10749:'Romance',
    878:'Sci-Fi',53:'Thriller',10752:'War',37:'Western',10759:'Action & Adventure',10765:'Sci-Fi & Fantasy',
    10762:'Kids',10763:'News',10764:'Reality',10766:'Soap',10767:'Talk',10768:'War & Politics'
  };
  List<String> _genreNames(dynamic raw) => raw is List
      ? raw.whereType<num>().map((n) => _genres[n]).whereType<String>().toList()
      : <String>[];

  Future<List<Movie>> _list(String path, [Map<String, String> params = const {}, String type = 'movie']) async {
    final data = await _get(path, params);
    final results = data?['results'];
    if (results is! List) return [];
    return results.map((e) => _movie(e, type: type)).whereType<Movie>().toList();
  }

  /// TMDB's current-day trending catalogue includes both films and series.
  Future<List<Movie>> trending() => _list('/trending/all/day');

  /// Combine popular-rated films and shows, then rank by TMDB's rating order.
  Future<List<Movie>> topRated() async {
    final results = await Future.wait([
      _list('/movie/top_rated', {'page': '1'}),
      _list('/tv/top_rated', {'page': '1'}, 'tv'),
    ], eagerError: false).timeout(const Duration(seconds: 11), onTimeout: () => <List<Movie>>[[], []]);
    final all = [...results[0], ...results[1]];
    all.sort((a, b) => (double.tryParse(b.rating) ?? 0).compareTo(double.tryParse(a.rating) ?? 0));
    return all;
  }

  Future<List<Movie>> continueDiscover() => _list('/movie/now_playing', {'page':'1'});

  Future<({int id, String type})?> _resolveReference(Movie movie) async {
    final directId = movie.tmdbId ?? int.tryParse(
      RegExp(r'/(?:embed/)?(?:movie|tv)/(\d+)', caseSensitive: false)
          .firstMatch(movie.url)?.group(1) ?? '',
    );
    if (directId != null) return (id: directId, type: movie.isSeries ? 'tv' : 'movie');
    final cached = _resolvedReferences[movie.key];
    if (cached != null) return cached;

    // Older catalogue entries use IMDb IDs (tt1234567) in their embed URL.
    // Resolve them through TMDB's /find endpoint to retrieve cast/details.
    final imdbId = RegExp(
      r'/(?:embed/)?(?:movie|tv)/(tt\d+)',
      caseSensitive: false,
    ).firstMatch(movie.url)?.group(1);
    if (imdbId == null) return null;
    final data = await _get('/find/$imdbId', {'external_source': 'imdb_id'});
    if (data == null) return null;
    final desired = movie.isSeries ? 'tv_results' : 'movie_results';
    final alternate = movie.isSeries ? 'movie_results' : 'tv_results';
    for (final key in [desired, alternate]) {
      final rows = data[key];
      if (rows is! List) continue;
      for (final row in rows.whereType<Map>()) {
        final id = (row['id'] as num?)?.toInt();
        if (id == null) continue;
        final type = key == 'tv_results' ? 'tv' : 'movie';
        final reference = (id: id, type: type);
        _resolvedReferences[movie.key] = reference;
        return reference;
      }
    }
    return null;
  }

  Future<Movie?> details(Movie movie) async {
    final reference = await _resolveReference(movie);
    if (reference == null) return movie;
    final id = reference.id;
    final type = reference.type;
    final data = await _get('/$type/$id', {'append_to_response': 'credits,external_ids'});
    if (data == null) return movie;
    final enriched = _movie(data, type: type);
    if (enriched == null) return movie;
    final credits = data['credits'];
    final cast = <MovieCastMember>[];
    final directors = <String>[];
    if (credits is Map) {
      final rawCast = credits['cast'];
      if (rawCast is List) {
        for (final item in rawCast.whereType<Map>().take(16)) {
          final name = (item['name'] ?? '').toString();
          if (name.isEmpty) continue;
          final photo = (item['profile_path'] ?? '').toString();
          cast.add(MovieCastMember(name: name, character: (item['character'] ?? '').toString(), photo: photo.isEmpty ? '' : '${_imageBase}w185$photo'));
        }
      }
      final rawCrew = credits['crew'];
      if (rawCrew is List && !movie.isSeries) {
        for (final item in rawCrew.whereType<Map>()) {
          if (item['job'] == 'Director' && item['name'] != null) directors.add(item['name'].toString());
        }
      }
    }
    if (movie.isSeries && data['created_by'] is List) {
      for (final item in (data['created_by'] as List).whereType<Map>()) {
        if (item['name'] != null) directors.add(item['name'].toString());
      }
    }
    // TMDB catalog IDs are numeric, while the embed/download providers used
    // by the local catalogue commonly expect IMDb IDs (tt...). Resolve the
    // provider ID for generated URLs only; never overwrite a custom URL.
    final externalIds = data['external_ids'];
    final imdbId = (data['imdb_id'] ?? (externalIds is Map ? externalIds['imdb_id'] : null) ?? '').toString().trim();
    final validImdbId = RegExp(r'^tt\d+$').hasMatch(imdbId) ? imdbId : '';
    final generatedUrl = '${AppConfig.embedBase}/$type/$id';
    final generatedDownloadUrl = '${AppConfig.downloadBase}/$type/$id';
    final resolvedProviderUrl = validImdbId.isNotEmpty ? '${AppConfig.embedBase}/$type/$validImdbId' : generatedUrl;
    final resolvedDownloadUrl = validImdbId.isNotEmpty ? '${AppConfig.downloadBase}/$type/$validImdbId' : generatedDownloadUrl;
    return enriched.copyWith(
      name: movie.name,
      url: movie.url == generatedUrl && validImdbId.isNotEmpty ? resolvedProviderUrl : movie.url,
      downloadUrl: movie.downloadUrl == generatedDownloadUrl && validImdbId.isNotEmpty ? resolvedDownloadUrl : movie.downloadUrl,
      image: movie.image.isNotEmpty ? movie.image : enriched.image,
      backdrop: movie.backdrop.isNotEmpty ? movie.backdrop : enriched.backdrop,
      backupUrl: movie.backupUrl,
      thirdUrl: movie.thirdUrl,
      referer: movie.referer,
      userAgent: movie.userAgent,
      altReferer: movie.altReferer,
      altUserAgent: movie.altUserAgent,
      thirdReferer: movie.thirdReferer,
      thirdUserAgent: movie.thirdUserAgent,
      cast: cast,
      directors: directors.toSet().toList(),
    );
  }

  Future<List<Movie>> similar(Movie movie) async {
    final reference = await _resolveReference(movie);
    if (reference == null) return [];
    return _list('/${reference.type}/${reference.id}/similar', {'page': '1'}, reference.type);
  }

  Future<List<TmdbTrailer>> latestTrailers() async {
    final candidates = await _list('/movie/now_playing', {'page': '1'});
    final limited = candidates.take(8).toList();
    final results = await Future.wait<TmdbTrailer?>(limited.map((movie) async {
      final id = movie.tmdbId;
      if (id == null) return null;
      final data = await _get('/movie/$id/videos');
      final videos = data?['results'];
      if (videos is! List) return null;
      final matches = videos.whereType<Map>().where((video) =>
        (video['site'] ?? '').toString().toLowerCase() == 'youtube' &&
        (video['type'] ?? '').toString().toLowerCase() == 'trailer' &&
        (video['key'] ?? '').toString().isNotEmpty).toList();
      if (matches.isEmpty) return null;
      matches.sort((a,b) => (b['published_at'] ?? '').toString().compareTo((a['published_at'] ?? '').toString()));
      final video = matches.first;
      return TmdbTrailer(title: movie.title, poster: movie.backdrop.isEmpty ? movie.image : movie.backdrop,
        key: video['key'].toString(), publishedAt: (video['published_at'] ?? '').toString());
    }), eagerError: false).timeout(const Duration(seconds: 12), onTimeout: () => <TmdbTrailer?>[]);
    return results.whereType<TmdbTrailer>().toList();
  }

  static const Map<String, List<String?>> _discoverGenres = {
    'Action': ['28', '10759'], 'Adventure': ['12', '10759'], 'Animation': ['16', '16'],
    'Comedy': ['35', '35'], 'Crime': ['80', '80'], 'Documentary': ['99', '99'],
    'Drama': ['18', '18'], 'Fantasy': ['14', '10765'], 'Horror': ['27', null],
    'Mystery': ['9648', '9648'], 'Romance': ['10749', null], 'Sci-Fi': ['878', '10765'],
    'Thriller': ['53', null], 'War': ['10752', '10768'], 'Western': ['37', '37'],
  };

  Future<List<Movie>> discover(String genre) async {
    final ids = _discoverGenres[genre];
    if (ids == null) return [];
    final requests = <Future<List<Movie>>>[];
    if (ids[0] != null) requests.add(_list('/discover/movie', {'with_genres': ids[0]!, 'sort_by': 'popularity.desc', 'include_adult': 'false'}));
    if (ids[1] != null) requests.add(_list('/discover/tv', {'with_genres': ids[1]!, 'sort_by': 'popularity.desc', 'include_adult': 'false'}, 'tv'));
    final lists = await Future.wait(requests, eagerError: false).timeout(const Duration(seconds: 10), onTimeout: () => <List<Movie>>[]);
    final out = <Movie>[];
    final maxLength = lists.fold<int>(0, (max, list) => list.length > max ? list.length : max);
    for (var index = 0; index < maxLength; index++) {
      for (final list in lists) { if (index < list.length) out.add(list[index]); }
    }
    return out;
  }

  Future<List<Movie>> search(String query) async {
    if (query.trim().isEmpty) return [];
    return _list('/search/multi', {'query': query.trim(), 'include_adult': 'false'});
  }
}

class TmdbTrailer {
  final String title, poster, key, publishedAt;
  const TmdbTrailer({required this.title, required this.poster, required this.key, required this.publishedAt});
  String get youtubeUrl => 'https://www.youtube.com/watch?v=$key';
}
