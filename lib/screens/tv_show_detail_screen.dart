import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../main.dart';
import '../models/movie.dart';
import '../models/tv_show.dart';
import '../services/movie_library.dart';
import '../services/tmdb_service.dart';
import 'movie_player_screen.dart';
import 'trailer_player_screen.dart';

class TvShowDetailScreen extends StatefulWidget {
  const TvShowDetailScreen({super.key, required this.show});
  final Movie show;

  @override
  State<TvShowDetailScreen> createState() => _TvShowDetailScreenState();
}

class _TvShowDetailScreenState extends State<TvShowDetailScreen> {
  final _tmdb = TmdbService();
  TvSeriesInfo? _info;
  List<TvEpisode> _episodes = [];
  int? _season;
  int _request = 0;
  bool _loading = true;
  bool _episodeLoading = false;
  String _error = '';

  Movie get _show => _info?.show ?? widget.show;
  int get _id => widget.show.tmdbId ?? -1;

  @override
  void initState() {
    super.initState();
    MovieLibrary.instance.load().then((_) { if (mounted) setState(() {}); });
    _loadDetails();
  }

  @override
  void dispose() {
    _request++;
    super.dispose();
  }

  Future<void> _loadDetails() async {
    if (mounted) setState(() { _loading = true; _error = ''; });
    TvSeriesInfo? info;
    try { info = await _tmdb.tvSeries(_id); } catch (_) {}
    if (!mounted) return;
    if (info == null) {
      setState(() { _loading = false; _error = 'Series details are unavailable. Please try again.'; });
      return;
    }
    final options = info.seasons;
    final preferred = options.where((s) => s.number > 0).toList();
    final chosen = preferred.isNotEmpty
        ? preferred.first.number
        : (options.isNotEmpty ? options.first.number : null);
    setState(() { _info = info; _season = chosen; _loading = false; });
    if (chosen != null) await _loadEpisodes(chosen);
  }

  Future<void> _loadEpisodes(int season) async {
    final request = ++_request;
    setState(() { _season = season; _episodeLoading = true; _episodes = []; });
    List<TvEpisode> episodes = [];
    try { episodes = await _tmdb.tvSeasonEpisodes(_id, season); } catch (_) {}
    if (!mounted || request != _request) return;
    setState(() { _episodeLoading = false; _episodes = episodes; });
  }

  Future<void> _toggleSaved() async {
    try { await MovieLibrary.instance.toggleSaved(_show); } catch (_) {}
    if (mounted) setState(() {});
  }

  /// Keep season and episode in the URL so the JSON-based provider selection
  /// can generate /tv/{id}/{season}/{episode}. Do not use the TMDB episode id
  /// in place of the *series* id: embed providers generally expect series id.
  void _watch(TvEpisode episode) {
    final id = _show.tmdbId;
    if (id == null) return;
    final season = episode.seasonNumber;
    final ep = episode.number;
    final route = '${AppConfig.embedBase}/tv/$id/$season/$ep';
    final entry = Movie(
      name: '${_show.title} · S${season.toString().padLeft(2, '0')}E${ep.toString().padLeft(2, '0')} · ${episode.name}',
      url: route,
      downloadUrl: '',
      rating: _show.rating,
      genre: _show.genre,
      image: episode.still.isNotEmpty ? episode.still : _show.image,
      date: episode.airDate,
      backdrop: _show.backdrop,
      mediaType: 'tv',
      overview: episode.overview,
      releaseDate: episode.airDate,
    );
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => MoviePlayerScreen(movie: entry),
    ));
  }

  Future<void> _trailer() async {
    final trailer = await _tmdb.trailerFor(_show);
    if (!mounted) return;
    if (trailer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No trailer is available for this show.')),
      );
      return;
    }
    Navigator.push(context, MaterialPageRoute<void>(
      builder: (_) => TrailerPlayerScreen(
        title: trailer.title, youtubeKey: trailer.key, poster: trailer.poster,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final show = _show;
    final backdrop = show.backdrop.isNotEmpty ? show.backdrop : show.image;
    final saved = MovieLibrary.instance.isSaved(show);
    final seasons = _info?.seasons ?? <TvSeason>[];
    return Scaffold(
      backgroundColor: appBg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadDetails,
          color: appRed,
          child: CustomScrollView(slivers: [
            SliverToBoxAdapter(child: Stack(children: [
              SizedBox(height: 310, width: double.infinity,
                child: _art(backdrop)),
              Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0, .48, 1],
                  colors: [Colors.black54, Colors.transparent, appBg]),
              ))),
              Positioned(top: 12, left: 14, child: _topButton(Icons.arrow_back_rounded, () => Navigator.pop(context))),
              Positioned(top: 12, right: 14, child: _topButton(saved ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded, _toggleSaved)),
              Positioned(left: 18, right: 18, bottom: 13, child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('DAMI SERIES', style: TextStyle(color: appRed, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2)),
                  const SizedBox(height: 5),
                  Text(show.title, maxLines: 3, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 29, fontWeight: FontWeight.w900, height: 1.09)),
                  const SizedBox(height: 9),
                  Wrap(spacing: 12, runSpacing: 6, children: [
                    if (show.rating.isNotEmpty) _tag(Icons.star_rounded, '${show.rating}/10', color: const Color(0xFFFFCE56)),
                    if (show.year.isNotEmpty) _tag(Icons.calendar_today_outlined, show.year),
                    if (show.seasons != null) _tag(Icons.video_library_outlined, '${show.seasons} seasons'),
                  ]),
                ],
              )),
            ])),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 38),
              sliver: SliverList(delegate: SliverChildListDelegate([
                if (show.genres.isNotEmpty)
                  Wrap(spacing: 7, runSpacing: 8, children: show.genres.take(4)
                      .map((g) => Chip(label: Text(g, style: const TextStyle(fontSize: 11)),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: appSurface, side: BorderSide(color: Colors.white.withValues(alpha: .12)))).toList()),
                const SizedBox(height: 13),
                if (show.overview.isNotEmpty) Text(show.overview,
                    style: const TextStyle(fontSize: 13, color: Colors.white70, height: 1.55)),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(child: FilledButton.icon(
                    onPressed: _episodes.isNotEmpty ? () => _watch(_episodes.first) : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: appRed, foregroundColor: Colors.white,
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13))),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Watch episode', style: TextStyle(fontWeight: FontWeight.w800)),
                  )),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: _trailer,
                    icon: const Icon(Icons.play_circle_outline_rounded),
                    label: const Text('Trailer'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      side: BorderSide(color: Colors.white.withValues(alpha: .25)),
                    ),
                  ),
                ]),
                const SizedBox(height: 28),
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Seasons & Episodes', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text('Choose a season, then an episode', style: TextStyle(color: Colors.white60, fontSize: 11)),
                  ])),
                ]),
                const SizedBox(height: 14),
                if (_loading) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
                else if (_error.isNotEmpty) _message(_error, onRetry: _loadDetails)
                else if (seasons.isEmpty) _message('No episode listings are available yet.')
                else ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(color: appSurface, borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: Colors.white12)),
                    child: DropdownButtonHideUnderline(child: DropdownButton<int>(
                      value: _season,
                      isExpanded: true,
                      dropdownColor: appSurface,
                      icon: Icon(Icons.keyboard_arrow_down_rounded, color: appRed),
                      items: seasons.map((s) => DropdownMenuItem<int>(
                        value: s.number,
                        child: Text(s.number == 0 ? 'Specials' : '${s.name} · ${s.episodeCount} episodes',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      )).toList(),
                      onChanged: (selected) { if (selected != null && selected != _season) _loadEpisodes(selected); },
                    )),
                  ),
                  const SizedBox(height: 14),
                  if (_episodeLoading) const Padding(padding: EdgeInsets.all(42), child: Center(child: CircularProgressIndicator()))
                  else if (_episodes.isEmpty)
                    _message('No episodes found for this season.',
                        onRetry: _season == null ? null : () => _loadEpisodes(_season!))
                  else
                    ..._episodes.map(_episodeTile),
                ],
                const SizedBox(height: 20),
                const Text('TV information and episode listings from TMDB. Playback availability depends on your configured sources.',
                  style: TextStyle(color: Colors.white38, fontSize: 10, height: 1.4),
                  textAlign: TextAlign.center),
              ])),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _art(String url) => url.isEmpty
      ? Container(color: appSurface, child: const Icon(Icons.live_tv_outlined, color: Colors.white30))
      : CachedNetworkImage(imageUrl: url, fit: BoxFit.cover,
          placeholder: (_, __) => Container(color: appSurface),
          errorWidget: (_, __, ___) => Container(color: appSurface, child: const Icon(Icons.broken_image_outlined)));

  Widget _topButton(IconData icon, VoidCallback onTap) => Material(
    color: Colors.black54, borderRadius: BorderRadius.circular(20),
    child: IconButton(onPressed: onTap, icon: Icon(icon, color: Colors.white)),
  );

  Widget _tag(IconData icon, String text, {Color color = Colors.white70}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [Icon(icon, color: color, size: 15), const SizedBox(width: 4),
      Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700))],
  );

  Widget _episodeTile(TvEpisode episode) => Padding(
    padding: const EdgeInsets.only(bottom: 11),
    child: Material(
      color: appSurface, borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => _watch(episode),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(borderRadius: BorderRadius.circular(9), child: SizedBox(
              width: 108, height: 84,
              child: Stack(fit: StackFit.expand, children: [
                _art(episode.still.isEmpty ? _show.backdrop : episode.still),
                Center(child: Container(
                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                  padding: const EdgeInsets.all(5),
                  child: const Icon(Icons.play_arrow_rounded, size: 25, color: Colors.white),
                )),
              ]),
            )),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('EPISODE ${episode.number}', style: TextStyle(color: appRed, fontWeight: FontWeight.w900, fontSize: 10)),
              const SizedBox(height: 4),
              Text(episode.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text([
                if (episode.runtime != null && episode.runtime! > 0) '${episode.runtime} min',
                if (episode.airDate.isNotEmpty) episode.airDate,
              ].join(' • '), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 10)),
              if (episode.overview.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(episode.overview, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 10, height: 1.25)),
              ],
            ])),
          ]),
        ),
      ),
    ),
  );

  Widget _message(String text, {VoidCallback? onRetry}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 26),
    child: Column(children: [
      Icon(Icons.info_outline_rounded, color: appRed, size: 28),
      const SizedBox(height: 8),
      Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
      if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Try again')),
    ]),
  );
}
