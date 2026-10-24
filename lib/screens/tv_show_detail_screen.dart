import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../main.dart';
import '../models/movie.dart';
import '../models/tv_show.dart';
import '../services/movie_library.dart';
import '../services/profile_data.dart';
import '../services/download_upgrade_service.dart';
import '../services/download_urls_config.dart';
import 'in_app_download_screen.dart';
import 'community_composer.dart';
import 'profile_collections_screen.dart';
import 'watch_together_screen.dart';
import '../services/tmdb_service.dart';
import 'actor_profile_screen.dart';
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
  TvEpisode? _selectedEpisode;

  Movie get _show => _info?.show ?? widget.show;
  int get _id => widget.show.tmdbId ?? -1;

  @override
  void initState() {
    super.initState();
    MovieLibrary.instance.load().then((_) { if (mounted) setState(() {}); });
    ProfileData.instance.load();
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
    setState(() { _episodeLoading = false; _episodes = episodes; _selectedEpisode = episodes.isEmpty ? null : episodes.first; });
  }

  Future<void> _toggleSaved() async {
    try { await MovieLibrary.instance.toggleSaved(_show); } catch (_) {}
    if (mounted) setState(() {});
  }

  /// Keep season and episode in the URL so the JSON-based provider selection
  /// can generate /tv/{id}/{season}/{episode}. Do not use the TMDB episode id
  /// in place of the *series* id: embed providers generally expect series id.
  Movie _episodeMovie(TvEpisode episode) {
    final id = _show.tmdbId;
    if (id == null) return _show;
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
    return entry;
  }

  void _watch(TvEpisode episode) {
    final entry = _episodeMovie(episode);
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => MoviePlayerScreen(movie: entry),
    ));
  }

  // Prefer an explicitly configured episode download link when present.
  // Otherwise use the global JSON provider with the SERIES TMDB ID.
  Future<String?> _episodeDownloadUrl(TvEpisode episode) async {
    final template = _show.downloadUrl.trim();
    if (template.contains('{season}') && template.contains('{episode}') &&
        template.contains('{id}')) {
      final link = template
          .replaceAll('{id}', '$_id')
          .replaceAll('{season}', '${episode.seasonNumber}')
          .replaceAll('{episode}', '${episode.number}');
      final uri = Uri.tryParse(link);
      if (uri != null &&
          (uri.scheme == 'https' || uri.scheme == 'http') &&
          uri.host.isNotEmpty) return link;
    }
    final config = await DownloadUrlsConfig.load();
    return config.urlFor(
      tmdbId: _id,
      season: episode.seasonNumber,
      episode: episode.number,
    );
  }

  Future<void> _downloadEpisode() async {
    final episode = _selectedEpisode;
    if (episode == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Choose a season and episode first.'),
      ));
      return;
    }
    final url = await _episodeDownloadUrl(episode);
    if (!mounted) return;
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('A download page is not available for this episode.'),
      ));
      return;
    }
    await DownloadUpgradeService.onDownloadTap(
      context,
      continueDownload: () async {
        if (!mounted) return;
        await Navigator.of(context).push<void>(MaterialPageRoute<void>(
          builder: (_) => InAppDownloadScreen(
            movieTitle: _episodeMovie(episode).title,
            downloadUrl: url,
          ),
        ));
      },
    );
  }

  Widget _engagementActions() {
    final data = ProfileData.instance;
    return ListenableBuilder(
      listenable: data,
      builder: (context, _) {
        final rating = data.ratingFor(_show);
        final reviewed = data.reviewFor(_show) != null;
        Widget action(IconData icon, String label, VoidCallback onTap, {bool active = false}) =>
            Expanded(child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 13),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, color: active ? appRed : Colors.white70, size: 23),
                  const SizedBox(height: 5),
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                      color: active ? appRed : Colors.white70)),
                ]),
              ),
            ));
        return Container(
          decoration: BoxDecoration(
            color: appSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: .07)),
          ),
          child: Row(children: [
            action(rating == null ? Icons.star_border_rounded : Icons.star_rounded,
              rating == null ? 'Rate' : 'Rated $rating★',
              () => showRatingSheet(context, _show), active: rating != null),
            action(reviewed ? Icons.rate_review_rounded : Icons.rate_review_outlined,
              reviewed ? 'Reviewed' : 'Review',
              () => showReviewDialog(context, _show), active: reviewed),
            action(Icons.check_circle_outline_rounded, 'Check in',
              () => checkInMovie(context, _show)),
            action(Icons.playlist_add_rounded, 'Add to list',
              () => showAddToListSheet(context, _show)),
          ]),
        );
      },
    );
  }

  ButtonStyle _softOutline() => OutlinedButton.styleFrom(
    minimumSize: const Size(0, 50),
    backgroundColor: Colors.white.withValues(alpha: .05),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    side: BorderSide(color: Colors.white.withValues(alpha: .2)),
  );

  Widget _sectionHead(String title, {String? note}) => Row(children: [
    Container(
      width: 4, height: 20,
      margin: const EdgeInsets.only(right: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [appAccentSoft, appRed]),
        borderRadius: BorderRadius.circular(99),
      ),
    ),
    Expanded(child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -.5))),
    if (note != null) Text(note, style: const TextStyle(fontSize: 11.5, color: Colors.white54)),
  ]);

  Widget _socialActions() => Row(children: [
    Expanded(child: OutlinedButton.icon(
      style: _softOutline(),
      onPressed: () => showCommunityComposer(context, movie: _show),
      icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
      label: const Text('Tweet', style: TextStyle(fontWeight: FontWeight.w800)),
    )),
    const SizedBox(width: 10),
    Expanded(child: OutlinedButton.icon(
      style: _softOutline(),
      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => WatchTogetherScreen(movie: _selectedEpisode == null
          ? _show : _episodeMovie(_selectedEpisode!)),
      )),
      icon: const Icon(Icons.theaters_rounded, size: 18),
      label: const Text('Watch Together', maxLines: 1,
        overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800)),
    )),
  ]);

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
              SizedBox(height: 350, width: double.infinity,
                child: _art(backdrop)),
              Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0, .3, .68, 1],
                  colors: [const Color(0x66000000), const Color(0x00000000), appBg.withValues(alpha: .75), appBg]),
              ))),
              Positioned(top: 12, left: 14, child: _topButton(Icons.arrow_back_rounded, () => Navigator.pop(context))),
              Positioned(top: 12, right: 14, child: _topButton(saved ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded, _toggleSaved)),
              Positioned(left: 18, right: 18, bottom: 13, child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [appRed, appAccentSoft]),
                      borderRadius: BorderRadius.circular(99),
                      boxShadow: [BoxShadow(color: appRed.withValues(alpha: .4), blurRadius: 12, offset: const Offset(0, 4))],
                    ),
                    child: Text('TV series', style: TextStyle(color: appRed.computeLuminance() > .5 ? Colors.black : Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(height: 9),
                  Text(show.title, maxLines: 3, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 31, fontWeight: FontWeight.w900, height: 1.05, letterSpacing: -1,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 16)])),
                  const SizedBox(height: 10),
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
                      .map((g) => Chip(label: Text(g, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        visualDensity: VisualDensity.compact,
                        shape: const StadiumBorder(),
                        backgroundColor: appSurface, side: BorderSide(color: Colors.white.withValues(alpha: .1)))).toList()),
                const SizedBox(height: 13),
                if (show.overview.isNotEmpty) Text(show.overview,
                    style: const TextStyle(fontSize: 13.5, color: Colors.white70, height: 1.6)),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(child: FilledButton.icon(
                    onPressed: _episodes.isNotEmpty ? () => _watch(_episodes.first) : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: appRed, foregroundColor: appRed.computeLuminance() > .5 ? Colors.black : Colors.white,
                      minimumSize: const Size(0, 54),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Watch episode', style: TextStyle(fontWeight: FontWeight.w800)),
                  )),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: _trailer,
                    icon: const Icon(Icons.play_circle_outline_rounded),
                    label: const Text('Trailer'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 54),
                      backgroundColor: Colors.white.withValues(alpha: .05),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      side: BorderSide(color: Colors.white.withValues(alpha: .25)),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                SizedBox(width: double.infinity, child: OutlinedButton.icon(
                  onPressed: _downloadEpisode,
                  icon: const Icon(Icons.download_rounded),
                  label: Text(_selectedEpisode == null ? 'Download episode' :
                    'Download S${_selectedEpisode!.seasonNumber}E${_selectedEpisode!.number}'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 50),
                    backgroundColor: Colors.white.withValues(alpha: .05),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                )),
                const SizedBox(height: 13),
                _socialActions(),
                const SizedBox(height: 13),
                _engagementActions(),
                if (show.cast.isNotEmpty) ...[
                  const SizedBox(height: 26),
                  _sectionHead('Top cast', note: '${show.cast.length} actors'),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 176,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: show.cast.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (_, i) => _castTile(show.cast[i]),
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                _sectionHead('Seasons and episodes'),
                const SizedBox(height: 4),
                const Padding(
                  padding: EdgeInsets.only(left: 14),
                  child: Text('Choose a season, then an episode', style: TextStyle(color: Colors.white60, fontSize: 12)),
                ),
                const SizedBox(height: 14),
                if (_loading) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
                else if (_error.isNotEmpty) _message(_error, onRetry: _loadDetails)
                else if (seasons.isEmpty) _message('No episode listings are available yet.')
                else ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(color: appSurface, borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withValues(alpha: .1))),
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
                const Text('TV information and episode listings.',
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

  Widget _castTile(MovieCastMember person) => SizedBox(
    width: 96,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ActorProfileScreen(person: person),
        )),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              width: 96,
              height: 112,
              child: person.photo.startsWith('http')
                ? CachedNetworkImage(
                    imageUrl: person.photo,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => _actorFallback(),
                    errorWidget: (_, __, ___) => _actorFallback(),
                  )
                : _actorFallback(),
            ),
          ),
          const SizedBox(height: 7),
          Text(person.name, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          if (person.character.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(person.character, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: Colors.white60, height: 1.2)),
          ],
        ]),
      ),
    ),
  );

  Widget _actorFallback() => Container(
    color: appSurface,
    alignment: Alignment.center,
    child: const Icon(Icons.person_rounded, size: 38, color: Colors.white38),
  );

  Widget _topButton(IconData icon, VoidCallback onTap) => Container(
    width: 44, height: 44,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.black.withValues(alpha: .4),
      border: Border.all(color: Colors.white.withValues(alpha: .2)),
    ),
    child: IconButton(onPressed: onTap, icon: Icon(icon, color: Colors.white, size: 22)),
  );

  Widget _tag(IconData icon, String text, {Color color = Colors.white70}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .4),
      border: Border.all(color: Colors.white.withValues(alpha: .15)),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [Icon(icon, color: color, size: 15), const SizedBox(width: 5),
        Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700))],
    ),
  );

  Widget _episodeTile(TvEpisode episode) {
    final selected = _selectedEpisode?.number == episode.number &&
        _selectedEpisode?.seasonNumber == episode.seasonNumber;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: selected ? appRed.withValues(alpha: .1) : appSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: selected ? appRed.withValues(alpha: .7) : Colors.white.withValues(alpha: .07)),
        ),
        child: InkWell(
          onTap: () { setState(() => _selectedEpisode = episode); _watch(episode); },
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ClipRRect(borderRadius: BorderRadius.circular(16), child: SizedBox(
                width: 112, height: 88,
                child: Stack(fit: StackFit.expand, children: [
                  _art(episode.still.isEmpty ? _show.backdrop : episode.still),
                  Center(child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .5),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white54, width: 1.2),
                    ),
                    child: const Icon(Icons.play_arrow_rounded, size: 22, color: Colors.white),
                  )),
                ]),
              )),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Episode ${episode.number}', style: TextStyle(color: appAccentSoft, fontWeight: FontWeight.w800, fontSize: 11.5)),
                const SizedBox(height: 3),
                Text(episode.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, height: 1.2)),
                const SizedBox(height: 4),
                Text([
                  if (episode.runtime != null && episode.runtime! > 0) '${episode.runtime} min',
                  if (episode.airDate.isNotEmpty) episode.airDate,
                ].join(' • '), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 10.5)),
                if (episode.overview.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(episode.overview, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 10.5, height: 1.3)),
                ],
              ])),
              IconButton(
                tooltip: 'Select episode for download or Watch Together',
                onPressed: () => setState(() => _selectedEpisode = episode),
                icon: Icon(selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                  color: selected ? appRed : Colors.white38),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _message(String text, {VoidCallback? onRetry}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 26),
    child: Column(children: [
      Container(
        width: 56, height: 56,
        decoration: BoxDecoration(shape: BoxShape.circle, color: appRed.withValues(alpha: .14)),
        child: Icon(Icons.info_outline_rounded, color: appAccentSoft, size: 26),
      ),
      const SizedBox(height: 10),
      Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
      if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Try again')),
    ]),
  );
}
