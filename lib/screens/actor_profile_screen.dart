import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../models/movie.dart';
import '../services/ad_service.dart';
import '../services/movie_library.dart';
import '../services/profile_data.dart';
import '../services/tmdb_service.dart';
import 'movie_detail_screen.dart';
import 'tv_show_detail_screen.dart';

/// Opens from any cast member on a movie or series details page.
/// Older saved cast items without a person ID are resolved by exact name.
class ActorProfileScreen extends StatefulWidget {
  final MovieCastMember person;

  const ActorProfileScreen({super.key, required this.person});

  @override
  State<ActorProfileScreen> createState() => _ActorProfileScreenState();
}

class _ActorProfileScreenState extends State<ActorProfileScreen> {
  final TmdbService _movies = TmdbService();
  TmdbActorDetails? _actor;
  bool _loading = true;
  bool _showFullBio = false;

  @override
  void initState() {
    super.initState();
    unawaited(ProfileData.instance.load());
    unawaited(_load());
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    TmdbActorDetails? actor;
    try {
      var id = widget.person.id;
      if (id == null || id <= 0) {
        final matches = await _movies
            .searchPeople(widget.person.name)
            .timeout(const Duration(seconds: 16), onTimeout: () => []);
        final wanted = widget.person.name.trim().toLowerCase();
        for (final person in matches) {
          if (person.id > 0 && person.name.trim().toLowerCase() == wanted) {
            id = person.id;
            break;
          }
        }
      }
      if (id != null && id > 0) {
        actor = await _movies.actorDetails(id).timeout(
              const Duration(seconds: 20),
              onTimeout: () => null,
            );
      }
    } catch (_) {
      // Present a friendly retry state instead of exposing network details.
    }
    if (!mounted) return;
    setState(() {
      _actor = actor;
      _loading = false;
    });
  }

  Future<void> _toggleFavorite() async {
    final actor = _actor;
    final name = actor?.name.isNotEmpty == true
        ? actor!.name
        : widget.person.name;
    final photo = actor?.photo.isNotEmpty == true
        ? actor!.photo
        : widget.person.photo;
    final wasFavorite = ProfileData.instance.isFavoritePerson(name);
    await ProfileData.instance.toggleFavoritePerson(name, photo: photo);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(wasFavorite
            ? '$name removed from favorites'
            : '$name added to favorites'),
      ));
  }

  void _openMovie(Movie movie) {
    unawaited(AdService.instance.guard(context, () {
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => movie.isSeries
            ? TvShowDetailScreen(show: movie)
            : MovieDetailScreen(
                movie: movie,
                saved: MovieLibrary.instance.isSaved(movie),
                onToggleSaved: () async {
                  await MovieLibrary.instance.toggleSaved(movie);
                },
              ),
      ));
    }));
  }

  Widget _portrait(String url, {double? width, double? height}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: width,
        height: height,
        child: url.startsWith('http')
            ? CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, __) => _photoFallback(),
                errorWidget: (_, __, ___) => _photoFallback(),
              )
            : _photoFallback(),
      ),
    );
  }

  Widget _photoFallback() => Container(
        color: appSurface,
        alignment: Alignment.center,
        child: const Icon(
          Icons.person_rounded,
          size: 60,
          color: Colors.white38,
        ),
      );

  Widget _fact(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.white54)),
          const SizedBox(height: 3),
          Text(value,
              style: const TextStyle(
                  fontSize: 13, color: Colors.white, height: 1.3)),
        ],
      ),
    );
  }

  Widget _movieTile(Movie movie) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openMovie(movie),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox.expand(
                child: movie.image.startsWith('http')
                    ? CachedNetworkImage(
                        imageUrl: movie.image,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          color: appSurface,
                          child: const Icon(Icons.movie_outlined,
                              color: Colors.white38),
                        ),
                      )
                    : Container(
                        color: appSurface,
                        child: const Icon(Icons.movie_outlined,
                            color: Colors.white38),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(movie.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12, height: 1.2, fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(
            [if (movie.year.isNotEmpty) movie.year, if (movie.isSeries) 'TV']
                .join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: Colors.white54),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final actor = _actor;
    final name = actor?.name.isNotEmpty == true
        ? actor!.name
        : widget.person.name;
    final photo = actor?.photo.isNotEmpty == true
        ? actor!.photo
        : widget.person.photo;

    return Scaffold(
      backgroundColor: appBg,
      appBar: AppBar(
        title: const Text('Actor profile'),
        backgroundColor: appBg,
        actions: [
          ListenableBuilder(
            listenable: ProfileData.instance,
            builder: (context, _) {
              final favorite = ProfileData.instance.isFavoritePerson(name);
              return IconButton(
                tooltip: favorite ? 'Remove from favorites' : 'Add to favorites',
                onPressed: _toggleFavorite,
                icon: Icon(
                  favorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: favorite ? appRed : Colors.white,
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          color: appRed,
          backgroundColor: appSurface,
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _portrait(photo, width: 126, height: 178),
                  const SizedBox(width: 17),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 23,
                                height: 1.12)),
                        if (widget.person.character.isNotEmpty) ...[
                          const SizedBox(height: 7),
                          Text('As ${widget.person.character}',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.white70)),
                        ],
                        if (actor != null) ...[
                          _fact('Known for', actor.knownFor),
                          _fact('Born', actor.birthday),
                          _fact('Place of birth', actor.placeOfBirth),
                          _fact('Died', actor.deathday),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (_loading) ...[
                const SizedBox(height: 30),
                Center(child: CircularProgressIndicator(color: appRed)),
                const SizedBox(height: 12),
                const Center(
                  child: Text('Loading actor details…',
                      style: TextStyle(color: Colors.white70)),
                ),
              ] else if (actor == null) ...[
                const SizedBox(height: 32),
                const Text(
                  'More information about this actor is unavailable right now.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 14),
                Center(
                  child: OutlinedButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try again'),
                  ),
                ),
              ] else ...[
                if (actor.biography.trim().isNotEmpty) ...[
                  const SizedBox(height: 30),
                  const Text('Biography',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  Text(
                    actor.biography.trim(),
                    maxLines: _showFullBio ? null : 7,
                    overflow: _showFullBio ? null : TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 14, height: 1.55),
                  ),
                  if (actor.biography.length > 450)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => setState(
                            () => _showFullBio = !_showFullBio),
                        child: Text(_showFullBio ? 'Read less' : 'Read more',
                            style: TextStyle(color: appRed)),
                      ),
                    ),
                ],
                if (actor.alsoKnownAs.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _fact('Also known as', actor.alsoKnownAs.join(', ')),
                ],
                const SizedBox(height: 28),
                Row(
                  children: [
                    const Expanded(
                      child: Text('Movies & series',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w900)),
                    ),
                    Text('${actor.filmography.length} titles',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white54)),
                  ],
                ),
                const SizedBox(height: 15),
                if (actor.filmography.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text('No titles to show right now.',
                        style: TextStyle(color: Colors.white60)),
                  )
                else
                  LayoutBuilder(
                    builder: (context, constraints) => GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      shrinkWrap: true,
                      itemCount: actor.filmography.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: constraints.maxWidth >= 500 ? 4 : 3,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 16,
                        childAspectRatio: 0.49,
                      ),
                      itemBuilder: (_, index) =>
                          _movieTile(actor.filmography[index]),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
