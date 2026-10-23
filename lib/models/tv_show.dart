import 'movie.dart';

/// TV metadata parsed from TMDB. The API does not supply video streams.
class TvSeriesInfo {
  const TvSeriesInfo({required this.show, required this.seasons});
  final Movie show;
  final List<TvSeason> seasons;
}

class TvSeason {
  const TvSeason({
    required this.number,
    required this.name,
    required this.episodeCount,
    this.poster = '',
    this.overview = '',
    this.airDate = '',
  });

  final int number;
  final String name;
  final int episodeCount;
  final String poster;
  final String overview;
  final String airDate;

  factory TvSeason.fromTmdb(Map<String, dynamic> data) {
    final p = (data['poster_path'] ?? '').toString();
    return TvSeason(
      number: (data['season_number'] as num?)?.toInt() ?? 0,
      name: (data['name'] ?? 'Season').toString(),
      episodeCount: (data['episode_count'] as num?)?.toInt() ?? 0,
      poster: p.isEmpty ? '' : 'https://image.tmdb.org/t/p/w500$p',
      overview: (data['overview'] ?? '').toString(),
      airDate: (data['air_date'] ?? '').toString(),
    );
  }
}

class TvEpisode {
  const TvEpisode({
    required this.number,
    required this.seasonNumber,
    required this.name,
    this.overview = '',
    this.still = '',
    this.airDate = '',
    this.runtime,
    this.rating,
  });

  final int number;
  final int seasonNumber;
  final String name;
  final String overview;
  final String still;
  final String airDate;
  final int? runtime;
  final double? rating;

  factory TvEpisode.fromTmdb(Map<String, dynamic> data) {
    final p = (data['still_path'] ?? '').toString();
    return TvEpisode(
      number: (data['episode_number'] as num?)?.toInt() ?? 0,
      seasonNumber: (data['season_number'] as num?)?.toInt() ?? 0,
      name: (data['name'] ?? 'Episode').toString(),
      overview: (data['overview'] ?? '').toString(),
      still: p.isEmpty ? '' : 'https://image.tmdb.org/t/p/w500$p',
      airDate: (data['air_date'] ?? '').toString(),
      runtime: (data['runtime'] as num?)?.toInt(),
      rating: (data['vote_average'] as num?)?.toDouble(),
    );
  }
}
