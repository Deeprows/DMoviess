import '../config.dart';

class MovieCastMember {
  final int? id;
  final String name;
  final String character;
  final String photo;

  const MovieCastMember(
      {this.id, required this.name, required this.character, this.photo = ''});

  factory MovieCastMember.fromJson(Map<String, dynamic> json) =>
      MovieCastMember(
        id: json['id'] is num
            ? (json['id'] as num).toInt()
            : int.tryParse('${json['id'] ?? ''}'),
        name: (json['name'] ?? '').toString(),
        character: (json['character'] ?? '').toString(),
        photo: (json['photo'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'name': name,
        'character': character,
        'photo': photo,
      };
}

/// Movie or series model. The original catalogue fields remain compatible with
/// assets/data/movies.json; the extra fields are filled from TMDB details.
class Movie {
  final String name, url, downloadUrl, rating, genre, image, date, backdrop;
  final String backupUrl,
      thirdUrl,
      referer,
      userAgent,
      altReferer,
      altUserAgent,
      thirdReferer,
      thirdUserAgent;
  final int? tmdbId;
  final String mediaType;
  final String overview, tagline, status, language, releaseDate;
  final int? runtime, seasons, episodes;
  final List<String> directors;
  final List<MovieCastMember> cast;

  const Movie({
    required this.name,
    required this.url,
    required this.downloadUrl,
    required this.rating,
    required this.genre,
    required this.image,
    required this.date,
    this.backdrop = '',
    this.backupUrl = '',
    this.thirdUrl = '',
    this.referer = '',
    this.userAgent = '',
    this.altReferer = '',
    this.altUserAgent = '',
    this.thirdReferer = '',
    this.thirdUserAgent = '',
    this.tmdbId,
    this.mediaType = 'movie',
    this.overview = '',
    this.tagline = '',
    this.status = '',
    this.language = '',
    this.releaseDate = '',
    this.runtime,
    this.seasons,
    this.episodes,
    this.directors = const [],
    this.cast = const [],
  });

  factory Movie.fromJson(Map<String, dynamic> j) {
    final id = int.tryParse(
        '${j['tmdbId'] ?? j['tmdb_id'] ?? j['tmdb'] ?? j['id'] ?? ''}');
    final typeRaw =
        (j['type'] ?? j['mediaType'] ?? 'movie').toString().toLowerCase();
    final type = (typeRaw == 'tv' ||
            typeRaw == 'series' ||
            typeRaw == 'show' ||
            (j['url'] ?? '').toString().contains('/tv/'))
        ? 'tv'
        : 'movie';
    return Movie(
      name: (j['name'] ?? j['title'] ?? 'Untitled').toString(),
      url: _normaliseSourceUrl(
          (j['url'] ?? (id == null ? '' : '${AppConfig.embedBase}/$type/$id'))
              .toString()),
      downloadUrl: (j['downloadUrl'] ??
              (id == null ? '' : '${AppConfig.downloadBase}/$type/$id'))
          .toString(),
      rating: _normaliseRating((j['rating'] ?? '').toString()),
      genre: (j['genre'] ??
              (j['genres'] is List ? (j['genres'] as List).join(',') : ''))
          .toString(),
      image: normalizeImage((j['image'] ?? '').toString()),
      date: (j['date'] ?? '').toString(),
      backdrop: (j['backdrop'] ?? '').toString(),
      backupUrl: (j['altUrl'] ??
              j['alt_url'] ??
              j['backupUrl'] ??
              j['backup_url'] ??
              '')
          .toString(),
      thirdUrl:
          (j['thirdUrl'] ?? j['third_url'] ?? j['player3'] ?? '').toString(),
      referer: (j['referer'] ?? '').toString(),
      userAgent: (j['userAgent'] ?? j['user_agent'] ?? '').toString(),
      altReferer: (j['altReferer'] ?? j['alt_referer'] ?? '').toString(),
      altUserAgent: (j['altUserAgent'] ?? j['alt_user_agent'] ?? '').toString(),
      thirdReferer: (j['thirdReferer'] ?? j['third_referer'] ?? '').toString(),
      thirdUserAgent:
          (j['thirdUserAgent'] ?? j['third_user_agent'] ?? '').toString(),
      tmdbId: id,
      mediaType: type,
      overview: (j['overview'] ?? j['summary'] ?? '').toString(),
      tagline: (j['tagline'] ?? '').toString(),
      status: (j['status'] ?? '').toString(),
      language: (j['language'] ?? '').toString(),
      releaseDate: (j['releaseDate'] ?? j['release_date'] ?? '').toString(),
      runtime: j['runtime'] is num
          ? (j['runtime'] as num).toInt()
          : int.tryParse('${j['runtime'] ?? ''}'),
      seasons: j['seasons'] is num
          ? (j['seasons'] as num).toInt()
          : int.tryParse('${j['seasons'] ?? ''}'),
      episodes: j['episodes'] is num
          ? (j['episodes'] as num).toInt()
          : int.tryParse('${j['episodes'] ?? ''}'),
      directors: (j['directors'] is List)
          ? (j['directors'] as List).map((e) => e.toString()).toList()
          : [],
      cast: (j['cast'] is List)
          ? (j['cast'] as List)
              .whereType<Map>()
              .map(
                  (e) => MovieCastMember.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : [],
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'url': url,
        'downloadUrl': downloadUrl,
        'rating': rating,
        'genre': genre,
        'image': image,
        'date': date,
        'backdrop': backdrop,
        'altUrl': backupUrl,
        'thirdUrl': thirdUrl,
        'referer': referer,
        'userAgent': userAgent,
        'altReferer': altReferer,
        'altUserAgent': altUserAgent,
        'thirdReferer': thirdReferer,
        'thirdUserAgent': thirdUserAgent,
        if (tmdbId != null) 'tmdbId': tmdbId,
        'type': mediaType,
        'overview': overview,
        'tagline': tagline,
        'status': status,
        'language': language,
        'releaseDate': releaseDate,
        if (runtime != null) 'runtime': runtime,
        if (seasons != null) 'seasons': seasons,
        if (episodes != null) 'episodes': episodes,
        'directors': directors,
        'cast': cast.map((e) => e.toJson()).toList(),
      };

  String get title => name.replaceFirst(RegExp(r'\s*\(\d{4}\)\s*$'), '').trim();
  String get year =>
      RegExp(r'(?:19|20)\d{2}')
          .firstMatch(releaseDate.isNotEmpty ? releaseDate : name)
          ?.group(0) ??
      '';
  List<String> get genres => genre
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toSet()
      .toList();
  String get key =>
      tmdbId != null ? '$mediaType:$tmdbId' : (url.isNotEmpty ? url : name);
  bool get isSeries => mediaType == 'tv' || url.contains('/tv/');
  String get altUrl {
    if (backupUrl.trim().isNotEmpty) return backupUrl.trim();
    // Prefer a provider/IMDb ID already present in the source URL. Detail
    // enrichment adds the numeric TMDB ID to Movie, but must not replace a
    // working IMDb-based fallback URL with that unrelated numeric ID.
    final sourceId =
        RegExp(r'/(?:embed/)?(?:movie|tv)/(tt\d+|\d+)', caseSensitive: false)
            .firstMatch(url)
            ?.group(1);
    final id = sourceId?.startsWith('tt') == true
        ? sourceId
        : tmdbId?.toString() ?? sourceId;
    if (id == null) return '';
    return isSeries
        ? '${AppConfig.altEmbedBase}/tv/$id/1/1'
        : '${AppConfig.altEmbedBase}/movie/$id';
  }

  String get runtimeText {
    final r = runtime;
    if (r == null || r <= 0) return '';
    final h = r ~/ 60, m = r % 60;
    if (h == 0) return '${m}m';
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  static String _normaliseRating(String raw) {
    final input = raw.trim();
    final ten = RegExp(r'(\d+(?:\.\d+)?)\s*/\s*10(?!\d)').firstMatch(input);
    if (ten != null) {
      final value = double.tryParse(ten.group(1)!);
      if (value != null) return value.toStringAsFixed(1);
    }
    final hundred = RegExp(r'(\d+(?:\.\d+)?)\s*/\s*100').firstMatch(input);
    if (hundred != null) {
      final value = double.tryParse(hundred.group(1)!);
      if (value != null) return (value / 10).toStringAsFixed(1);
    }
    return input.replaceAll('⭐', '').trim();
  }

  static String normalizeImage(String raw) {
    final match = RegExp(
      r'^https?://(?:www\.|media\.)?themoviedb\.org/t/p/[^/]+/(.+)$',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (match != null)
      return 'https://image.tmdb.org/t/p/w500/${match.group(1)}';
    return raw.trim();
  }

  static String _normaliseSourceUrl(String raw) {
    final input = raw.trim();
    final match = RegExp(r'^https?://([^/]+)/embed/(movie|tv)/(.*)$',
            caseSensitive: false)
        .firstMatch(input);
    if (match == null) return input;
    final host = match.group(1)!.toLowerCase();
    if (!AppConfig.replaceHosts.contains(host)) return input;
    return '${AppConfig.embedBase}/${match.group(2)!.toLowerCase()}/${match.group(3)}';
  }

  Movie copyWith({
    String? name,
    String? url,
    String? downloadUrl,
    String? rating,
    String? genre,
    String? image,
    String? date,
    String? backdrop,
    String? backupUrl,
    String? thirdUrl,
    String? referer,
    String? userAgent,
    String? altReferer,
    String? altUserAgent,
    String? thirdReferer,
    String? thirdUserAgent,
    int? tmdbId,
    String? mediaType,
    String? overview,
    String? tagline,
    String? status,
    String? language,
    String? releaseDate,
    int? runtime,
    int? seasons,
    int? episodes,
    List<String>? directors,
    List<MovieCastMember>? cast,
  }) =>
      Movie(
        name: name ?? this.name,
        url: url ?? this.url,
        downloadUrl: downloadUrl ?? this.downloadUrl,
        rating: rating ?? this.rating,
        genre: genre ?? this.genre,
        image: image ?? this.image,
        date: date ?? this.date,
        backdrop: backdrop ?? this.backdrop,
        backupUrl: backupUrl ?? this.backupUrl,
        thirdUrl: thirdUrl ?? this.thirdUrl,
        referer: referer ?? this.referer,
        userAgent: userAgent ?? this.userAgent,
        altReferer: altReferer ?? this.altReferer,
        altUserAgent: altUserAgent ?? this.altUserAgent,
        thirdReferer: thirdReferer ?? this.thirdReferer,
        thirdUserAgent: thirdUserAgent ?? this.thirdUserAgent,
        tmdbId: tmdbId ?? this.tmdbId,
        mediaType: mediaType ?? this.mediaType,
        overview: overview ?? this.overview,
        tagline: tagline ?? this.tagline,
        status: status ?? this.status,
        language: language ?? this.language,
        releaseDate: releaseDate ?? this.releaseDate,
        runtime: runtime ?? this.runtime,
        seasons: seasons ?? this.seasons,
        episodes: episodes ?? this.episodes,
        directors: directors ?? this.directors,
        cast: cast ?? this.cast,
      );
}
