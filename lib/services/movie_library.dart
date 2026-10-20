import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/movie.dart';

/// Device-local Watch Later and Watch History for DamiMovies.
class MovieLibrary extends ChangeNotifier {
  MovieLibrary._();
  static final MovieLibrary instance = MovieLibrary._();
  static const _savedKey = 'damimovies_saved_movies';
  static const _historyKey = 'damimovies_history_movies';
  static const _progressKey = 'damimovies_playback_progress';
  final List<Movie> _saved = [];
  final List<Movie> _history = [];
  final Map<String, double> _progress = {};
  bool _loaded = false;
  Future<void>? _loading;
  List<Movie> get saved => List.unmodifiable(_saved);
  List<Movie> get history => List.unmodifiable(_history);
  bool get loaded => _loaded;
  bool isSaved(Movie movie) => _saved.any((m) => m.key == movie.key);
  double progressFor(Movie movie) => _progress[movie.key] ?? 0;
  bool get hasResumeItems => _history.any((m) => progressFor(m) > 0.01);

  Future<void> load() {
    if (_loaded) return Future<void>.value();
    final pending = _loading;
    if (pending != null) return pending;
    _loading = _read().whenComplete(() {
      _loading = null;
    });
    return _loading!;
  }

  Future<void> _read() async {
    try {
      // Preferences are convenience storage, never a reason to block playback.
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 4));
      List<Movie> decode(String key) {
        try {
          final raw = prefs.getString(key);
          if (raw == null) return [];
          final value = jsonDecode(raw);
          if (value is! List) return [];
          return value
              .whereType<Map>()
              .map((e) => Movie.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        } catch (_) {
          return [];
        }
      }

      _saved
        ..clear()
        ..addAll(decode(_savedKey));
      _history
        ..clear()
        ..addAll(decode(_historyKey));
      _progress.clear();
      try {
        final rawProgress = prefs.getString(_progressKey);
        if (rawProgress != null) {
          final value = jsonDecode(rawProgress);
          if (value is Map) {
            for (final entry in value.entries) {
              final n = entry.value;
              if (n is num && n >= 0 && n <= 1) {
                _progress[entry.key.toString()] = n.toDouble();
              }
            }
          }
        }
      } catch (_) {}
    } catch (_) {
      // A blank local library is valid. A storage/plugin failure must not
      // wedge load() forever, because movie taps also record history.
      _saved.clear();
      _history.clear();
      _progress.clear();
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance()
        .timeout(const Duration(seconds: 4));
    await prefs
        .setString(
            _savedKey, jsonEncode(_saved.map((m) => m.toJson()).toList()))
        .timeout(const Duration(seconds: 3));
    await prefs
        .setString(
            _historyKey, jsonEncode(_history.map((m) => m.toJson()).toList()))
        .timeout(const Duration(seconds: 3));
    await prefs
        .setString(_progressKey, jsonEncode(_progress))
        .timeout(const Duration(seconds: 3));
    // Keep compatibility with the first DamiMovies build's watchlist key list.
    await prefs
        .setStringList(
            'damimovies_watchlist', _saved.map((m) => m.key).toList())
        .timeout(const Duration(seconds: 3));
  }

  Future<bool> toggleSaved(Movie movie) async {
    await load();
    final index = _saved.indexWhere((m) => m.key == movie.key);
    final result = index < 0;
    if (result) {
      _saved.insert(0, movie);
    } else {
      _saved.removeAt(index);
    }
    notifyListeners();
    await _save();
    return result;
  }

  Future<void> recordOpened(Movie movie) async {
    await load();
    _history.removeWhere((m) => m.key == movie.key);
    _history.insert(0, movie);
    if (_history.length > 100) _history.removeRange(100, _history.length);
    notifyListeners();
    await _save();
  }

  /// Records a video's latest playback position as a fraction from 0 to 1.
  /// Near-complete videos are removed from Continue Watching.
  Future<void> setProgress(
      Movie movie, double position, double duration) async {
    await load();
    if (duration <= 0 || position < 0) return;
    final fraction = (position / duration).clamp(0.0, 1.0).toDouble();
    if (fraction >= .97) {
      _progress.remove(movie.key);
    } else if (fraction >= .005) {
      _progress[movie.key] = fraction;
    }
    _history.removeWhere((m) => m.key == movie.key);
    _history.insert(0, movie);
    if (_history.length > 100) _history.removeRange(100, _history.length);
    notifyListeners();
    await _save();
  }

  /// Allows a resume prompt on built-in HTML5 streams where duration and
  /// currentTime are accessible to the app. Embed pages may not expose them.
  Future<double> resumeFraction(Movie movie) async {
    await load();
    return _progress[movie.key] ?? 0;
  }

  Future<void> removeSaved(Movie movie) async {
    await load();
    _saved.removeWhere((m) => m.key == movie.key);
    notifyListeners();
    await _save();
  }

  Future<void> removeHistory(Movie movie) async {
    await load();
    _history.removeWhere((m) => m.key == movie.key);
    _progress.remove(movie.key);
    notifyListeners();
    await _save();
  }

  Future<void> clearHistory() async {
    await load();
    _history.clear();
    _progress.clear();
    notifyListeners();
    await _save();
  }

  /// Migrate old builds, which stored only a list of saved identifiers.
  Future<void> seedFromCatalogue(Iterable<Movie> catalogue) async {
    await load();
    final prefs = await SharedPreferences.getInstance();
    final oldKeys = (prefs.getStringList('damimovies_watchlist') ?? []).toSet();
    if (oldKeys.isEmpty) return;
    var changed = false;
    for (final movie in catalogue) {
      if ((oldKeys.contains(movie.key) ||
              oldKeys.contains(movie.url) ||
              oldKeys.contains(movie.name)) &&
          !_saved.any((m) => m.key == movie.key)) {
        _saved.add(movie);
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
      await _save();
    }
  }
}
