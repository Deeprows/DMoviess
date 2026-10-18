import 'package:flutter_test/flutter_test.dart';
import 'package:damimovies/models/movie.dart';

void main() {
  test('movie data retains playback sources and display metadata', () {
    final movie = Movie.fromJson({
      'name': 'Sample Film (2026)',
      'url': 'https://example.com/embed/movie/12',
      'altUrl': 'https://backup.example.com/movie/12',
      'thirdUrl': 'https://third.example.com/movie/12',
      'downloadUrl': 'https://example.com/download/12',
      'rating': '8.1/10 ⭐',
      'genre': 'Drama,Thriller',
      'tmdbId': 12,
      'type': 'movie',
      'overview': 'A sample story.',
    });

    expect(movie.title, 'Sample Film');
    expect(movie.year, '2026');
    expect(movie.altUrl, 'https://backup.example.com/movie/12');
    expect(movie.thirdUrl, 'https://third.example.com/movie/12');
    expect(movie.toJson()['overview'], 'A sample story.');
  });
  test('legacy IMDb catalogue entry normalizes its poster and derives backup source', () {
    final movie = Movie.fromJson({
      'name': 'Primetime (2026)',
      'url': 'https://vsembed.ru/embed/movie/tt34206385',
      'downloadUrl': 'https://web.nxsha.app/dl/movie/tt34206385',
      'rating': '68/100 TMDB ⭐',
      'image': 'https://www.themoviedb.org/t/p/w1280/poster-file.jpg',
    });

    expect(movie.url, 'https://vsembed.su/embed/movie/tt34206385');
    expect(movie.altUrl, 'https://web.nxsha.app/embed/movie/tt34206385');
    expect(movie.rating, '6.8');
    expect(movie.image, 'https://image.tmdb.org/t/p/w500/poster-file.jpg');

    // Detail metadata may add a numeric TMDB ID later, but fallback URLs must
    // still use the working IMDb identifier from the configured source.
    final enriched = Movie.fromJson({
      'name': 'Primetime (2026)',
      'tmdbId': 123,
      'url': 'https://vsembed.su/embed/movie/tt34206385',
    });
    expect(enriched.altUrl, 'https://web.nxsha.app/embed/movie/tt34206385');
  });

}
