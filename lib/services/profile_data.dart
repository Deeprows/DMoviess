import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/movie.dart';
import 'movie_library.dart';

class RatedMovie {
  final Movie movie;
  final int stars; // 1..5
  final int at;
  const RatedMovie(this.movie, this.stars, this.at);
}

class MovieReview {
  final Movie movie;
  final String text;
  final int at;
  const MovieReview(this.movie, this.text, this.at);
}

class CheckIn {
  final Movie movie;
  final int at;
  const CheckIn(this.movie, this.at);
}

class FavoritePerson {
  final int? id;
  final String name;
  final String photo;
  const FavoritePerson({this.id, required this.name, this.photo = ''});
}

class MovieList {
  final String id;
  String name;
  final List<Movie> movies;
  MovieList(this.id, this.name, this.movies);
}

class ProfileBadge {
  final String title, description;
  final int icon; // Material icon codePoint is avoided; use key instead
  final String iconKey;
  final bool earned;
  final String progress;
  const ProfileBadge(
      this.iconKey, this.title, this.description, this.earned, this.progress,
      [this.icon = 0]);
}

/// Device-local ratings, reviews, interests, lists, check-ins and favourite
/// people for the profile screen.
class ProfileData extends ChangeNotifier {
  ProfileData._();
  static final ProfileData instance = ProfileData._();
  static const _key = 'damimovies_profile_v1';

  final Map<String, RatedMovie> _ratings = {};
  final Map<String, MovieReview> _reviews = {};
  final Set<String> _interests = {};
  final List<FavoritePerson> _people = [];
  final List<MovieList> _lists = [];
  final List<CheckIn> _checkIns = [];
  bool _loaded = false;
  Future<void>? _loading;

  List<RatedMovie> get ratings =>
      _ratings.values.toList()..sort((a, b) => b.at.compareTo(a.at));
  List<MovieReview> get reviews =>
      _reviews.values.toList()..sort((a, b) => b.at.compareTo(a.at));
  List<String> get interests => _interests.toList()..sort();
  List<FavoritePerson> get people => List.unmodifiable(_people);
  List<MovieList> get lists => List.unmodifiable(_lists);
  List<CheckIn> get checkIns => List.unmodifiable(_checkIns);

  Future<void> load() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _read().whenComplete(() => _loading = null);
  }

  Future<void> _read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        Movie mv(dynamic m) =>
            Movie.fromJson(Map<String, dynamic>.from(m as Map));
        for (final e in (j['ratings'] as List? ?? [])) {
          final m = mv(e['movie']);
          _ratings[m.key] = RatedMovie(
              m, (e['stars'] as num).toInt(), (e['at'] as num).toInt());
        }
        for (final e in (j['reviews'] as List? ?? [])) {
          final m = mv(e['movie']);
          _reviews[m.key] =
              MovieReview(m, '${e['text']}', (e['at'] as num).toInt());
        }
        _interests.addAll((j['interests'] as List? ?? []).map((e) => '$e'));
        for (final e in (j['people'] as List? ?? [])) {
          _people.add(FavoritePerson(
              id: (e['id'] as num?)?.toInt(),
              name: '${e['name']}',
              photo: '${e['photo'] ?? ''}'));
        }
        for (final e in (j['lists'] as List? ?? [])) {
          _lists.add(MovieList('${e['id']}', '${e['name']}',
              [for (final m in (e['movies'] as List? ?? [])) mv(m)]));
        }
        for (final e in (j['checkIns'] as List? ?? [])) {
          _checkIns.add(CheckIn(mv(e['movie']), (e['at'] as num).toInt()));
        }
      }
    } catch (_) {
      // Corrupt data must never block the profile.
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _key,
          jsonEncode({
            'ratings': [
              for (final r in _ratings.values)
                {'movie': r.movie.toJson(), 'stars': r.stars, 'at': r.at}
            ],
            'reviews': [
              for (final r in _reviews.values)
                {'movie': r.movie.toJson(), 'text': r.text, 'at': r.at}
            ],
            'interests': _interests.toList(),
            'people': [
              for (final p in _people)
                {'id': p.id, 'name': p.name, 'photo': p.photo}
            ],
            'lists': [
              for (final l in _lists)
                {
                  'id': l.id,
                  'name': l.name,
                  'movies': l.movies.map((m) => m.toJson()).toList()
                }
            ],
            'checkIns': [
              for (final c in _checkIns) {'movie': c.movie.toJson(), 'at': c.at}
            ],
          }));
    } catch (_) {}
  }

  int _now() => DateTime.now().millisecondsSinceEpoch;

  // Ratings
  int? ratingFor(Movie m) => _ratings[m.key]?.stars;
  Future<void> rate(Movie m, int stars) {
    _ratings[m.key] = RatedMovie(m, stars.clamp(1, 5), _now());
    return _persist();
  }

  Future<void> removeRating(Movie m) {
    _ratings.remove(m.key);
    return _persist();
  }

  // Reviews
  String? reviewFor(Movie m) => _reviews[m.key]?.text;
  Future<void> saveReview(Movie m, String text) {
    final t = text.trim();
    if (t.isEmpty) {
      _reviews.remove(m.key);
    } else {
      _reviews[m.key] = MovieReview(m, t, _now());
    }
    return _persist();
  }

  Future<void> removeReview(Movie m) {
    _reviews.remove(m.key);
    return _persist();
  }

  // Interests
  bool hasInterest(String g) => _interests.contains(g);
  Future<void> toggleInterest(String g) {
    if (!_interests.remove(g)) _interests.add(g);
    return _persist();
  }

  // Favourite people
  bool isFavoritePerson(String name) =>
      _people.any((p) => p.name.toLowerCase() == name.toLowerCase());
  Future<void> toggleFavoritePerson(String name, {int? id, String photo = ''}) {
    final i =
        _people.indexWhere((p) => p.name.toLowerCase() == name.toLowerCase());
    if (i >= 0) {
      _people.removeAt(i);
    } else {
      _people.insert(0, FavoritePerson(id: id, name: name, photo: photo));
    }
    return _persist();
  }

  // Lists
  Future<MovieList> createList(String name) async {
    final l = MovieList('${_now()}', name.trim(), []);
    _lists.add(l);
    await _persist();
    return l;
  }

  Future<void> renameList(MovieList l, String name) {
    if (name.trim().isNotEmpty) l.name = name.trim();
    return _persist();
  }

  Future<void> deleteList(MovieList l) {
    _lists.removeWhere((x) => x.id == l.id);
    return _persist();
  }

  bool listHas(MovieList l, Movie m) => l.movies.any((x) => x.key == m.key);
  Future<void> toggleInList(MovieList l, Movie m) {
    final i = l.movies.indexWhere((x) => x.key == m.key);
    if (i >= 0) {
      l.movies.removeAt(i);
    } else {
      l.movies.insert(0, m);
    }
    return _persist();
  }

  // Check-ins
  Future<void> checkIn(Movie m) {
    _checkIns.insert(0, CheckIn(m, _now()));
    return _persist();
  }

  Future<void> removeCheckIn(CheckIn c) {
    _checkIns.remove(c);
    return _persist();
  }

  // Badges
  List<ProfileBadge> get badges {
    final lib = MovieLibrary.instance;
    ProfileBadge b(
            String icon, String title, String desc, int have, int need) =>
        ProfileBadge(icon, title, desc, have >= need,
            '${have > need ? need : have}/$need');
    return [
      b('star', 'First Rating', 'Rate your first title', _ratings.length, 1),
      b('stars', 'Critic', 'Rate 10 titles', _ratings.length, 10),
      b('review', 'Reviewer', 'Write your first review', _reviews.length, 1),
      b('edit', 'Storyteller', 'Write 5 reviews', _reviews.length, 5),
      b('history', 'Binge Watcher', 'Open 10 titles', lib.history.length, 10),
      b('bookmark', 'Collector', 'Save 10 titles to your watchlist',
          lib.saved.length, 10),
      b('list', 'List Maker', 'Create your first list', _lists.length, 1),
      b('check', 'Regular', 'Check in 3 times', _checkIns.length, 3),
      b('people', 'Fan', 'Add 3 favorite people', _people.length, 3),
      b('category', 'Explorer', 'Pick 5 interests', _interests.length, 5),
    ];
  }

  int get badgesEarned => badges.where((b) => b.earned).length;
}
