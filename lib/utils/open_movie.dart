import 'package:flutter/material.dart';

import '../models/movie.dart';
import '../screens/movie_detail_screen.dart';
import '../screens/movie_player_screen.dart';
import '../services/movie_library.dart';

/// Opens a movie's detail page (used by community posts).
Future<void> openMovieTitle(BuildContext context, Movie movie) async {
  final library = MovieLibrary.instance;
  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => MovieDetailScreen(
      movie: movie,
      saved: library.isSaved(movie),
      onToggleSaved: () async {
        await library.toggleSaved(movie);
      },
    ),
  ));
}

/// Opens the player straight away (used by Watch Together).
Future<void> openMoviePlayer(BuildContext context, Movie movie) async {
  try {
    await MovieLibrary.instance
        .recordOpened(movie)
        .timeout(const Duration(seconds: 3));
  } catch (_) {}
  if (!context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => MoviePlayerScreen(movie: movie),
  ));
}
