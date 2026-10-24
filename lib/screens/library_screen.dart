import '../utils/l10n.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../main.dart';
import '../models/movie.dart';
import '../services/ad_service.dart';
import '../services/movie_library.dart';
import 'movie_detail_screen.dart';
import 'downloads_screen.dart';
import '../services/download_manager.dart';

class LibraryScreen extends StatefulWidget {
  final int initialTab;
  const LibraryScreen({super.key, this.initialTab = 0});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  @override
  void initState() {
    super.initState();
    _tabs = TabController(
        length: 3, vsync: this, initialIndex: widget.initialTab.clamp(0, 2));
    MovieLibrary.instance.load();
    // Native download tasks are persistent and continue independently of this tab.
    DownloadManager.instance.init();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = MovieLibrary.instance;
    return Scaffold(
      appBar: AppBar(
          title: Text('My Library'.tr,
              style: TextStyle(fontWeight: FontWeight.w900)),
          actions: [
            IconButton(
                tooltip: 'Clear watch history',
                onPressed: () async {
                  final yes = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                              title: Text('Clear watch history?'.tr),
                              content: Text(
                                  'This will remove recently opened titles from your device.'
                                      .tr),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: Text('Cancel'.tr)),
                                FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: Text('Clear'.tr))
                              ]));
                  if (yes == true) await library.clearHistory();
                },
                icon: Icon(Icons.delete_sweep_outlined)),
          ],
          bottom: TabBar(controller: _tabs, indicatorColor: appRed, tabs: [
            Tab(icon: Icon(Icons.bookmark_border), text: 'Watch Later'),
            Tab(icon: Icon(Icons.history_rounded), text: 'History'),
            Tab(icon: Icon(Icons.download_rounded), text: 'Downloads'),
          ])),
      body: ListenableBuilder(
          listenable: library,
          builder: (context, _) => TabBarView(controller: _tabs, children: [
                _movieList(library.saved,
                    emptyIcon: Icons.bookmark_add_outlined,
                    emptyText: 'Your saved movies and series will appear here.',
                    remove: (m) => library.removeSaved(m)),
                _movieList(library.history,
                    emptyIcon: Icons.history_rounded,
                    emptyText: 'Titles you open will appear here.',
                    remove: (m) => library.removeHistory(m)),
                const DownloadsScreen(embedded: true),
              ])),
    );
  }

  Widget _movieList(List<Movie> movies,
      {required IconData emptyIcon,
      required String emptyText,
      required Future<void> Function(Movie) remove}) {
    if (movies.isEmpty)
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(emptyIcon, size: 54, color: Colors.white24),
                SizedBox(height: 12),
                Text(emptyText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white60))
              ])));
    return ListView.separated(
        padding: const EdgeInsets.all(14),
        itemCount: movies.length,
        separatorBuilder: (_, __) => SizedBox(height: 10),
        itemBuilder: (context, i) {
          final movie = movies[i];
          return Container(
              height: 118,
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                  color: appSurface, borderRadius: BorderRadius.circular(15)),
              child: Row(children: [
                ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: SizedBox(
                        width: 70,
                        height: 100,
                        child: movie.image.startsWith('http')
                            ? CachedNetworkImage(
                                imageUrl: movie.image,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) =>
                                    Icon(Icons.movie_outlined))
                            : Icon(Icons.movie_outlined))),
                SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () => _open(movie),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          movie.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text([
                          if (movie.year.isNotEmpty) movie.year,
                          if (movie.rating.isNotEmpty) '★ ${movie.rating}',
                          movie.isSeries ? 'Series' : 'Movie',
                        ].join(' • ')),
                        SizedBox(height: 5),
                        Text(
                          movie.genres.take(2).join(' • '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                    tooltip: 'Remove',
                    onPressed: () => remove(movie),
                    icon: Icon(Icons.delete_outline_rounded,
                        color: Colors.white54)),
              ]));
        });
  }

  Future<void> _open(Movie movie) async {
    await AdService.instance.guard(context, () => _openNow(movie));
  }

  Future<void> _openNow(Movie movie) async {
    if (!mounted) return;
    final library = MovieLibrary.instance;
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => MovieDetailScreen(
                movie: movie,
                saved: library.isSaved(movie),
                onToggleSaved: () async {
                  await library.toggleSaved(movie);
                })));
  }
}
