import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../main.dart';
import '../models/movie.dart';
import '../services/ad_service.dart';
import '../services/movie_library.dart';
import 'movie_detail_screen.dart';

class LibraryScreen extends StatefulWidget {
  final int initialTab;
  const LibraryScreen({super.key, this.initialTab = 0});
  @override State<LibraryScreen> createState() => _LibraryScreenState();
}
class _LibraryScreenState extends State<LibraryScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  @override void initState() { super.initState(); _tabs = TabController(length: 2, vsync: this, initialIndex: widget.initialTab.clamp(0, 1)); MovieLibrary.instance.load(); }
  @override void dispose() { _tabs.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) {
    final library = MovieLibrary.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('My Library', style: TextStyle(fontWeight: FontWeight.w900)), actions: [
        IconButton(tooltip: 'Clear watch history', onPressed: () async {
          final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Clear watch history?'), content: const Text('This will remove recently opened titles from your device.'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear'))]));
          if (yes == true) await library.clearHistory();
        }, icon: const Icon(Icons.delete_sweep_outlined)),
      ], bottom: TabBar(controller: _tabs, indicatorColor: appRed, tabs: const [Tab(icon: Icon(Icons.bookmark_border), text: 'Watch Later'), Tab(icon: Icon(Icons.history_rounded), text: 'History')])),
      body: ListenableBuilder(listenable: library, builder: (context, _) => TabBarView(controller: _tabs, children: [
        _movieList(library.saved, emptyIcon: Icons.bookmark_add_outlined, emptyText: 'Your saved movies and series will appear here.', remove: (m) => library.removeSaved(m)),
        _movieList(library.history, emptyIcon: Icons.history_rounded, emptyText: 'Titles you open will appear here.', remove: (m) => library.removeHistory(m)),
      ])),
    );
  }

  Widget _movieList(List<Movie> movies, {required IconData emptyIcon, required String emptyText, required Future<void> Function(Movie) remove}) {
    if (movies.isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(emptyIcon, size: 54, color: Colors.white24), const SizedBox(height: 12), Text(emptyText, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60))])));
    return ListView.separated(padding: const EdgeInsets.all(14), itemCount: movies.length, separatorBuilder: (_, __) => const SizedBox(height: 10), itemBuilder: (context, i) {
      final movie = movies[i];
      return Container(height: 118, padding: const EdgeInsets.all(9), decoration: BoxDecoration(color: appSurface, borderRadius: BorderRadius.circular(15)), child: Row(children: [
        ClipRRect(borderRadius: BorderRadius.circular(9), child: SizedBox(width: 70, height: 100, child: movie.image.startsWith('http') ? CachedNetworkImage(imageUrl: movie.image, fit: BoxFit.cover, errorWidget: (_, __, ___) => const Icon(Icons.movie_outlined)) : const Icon(Icons.movie_outlined))),
        const SizedBox(width: 12),
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
                const SizedBox(height: 5),
                Text([
                  if (movie.year.isNotEmpty) movie.year,
                  if (movie.rating.isNotEmpty) '★ ${movie.rating}',
                  movie.isSeries ? 'Series' : 'Movie',
                ].join(' • ')),
                const SizedBox(height: 5),
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
        IconButton(tooltip: 'Remove', onPressed: () => remove(movie), icon: const Icon(Icons.delete_outline_rounded, color: Colors.white54)),
      ]));
    });
  }

  Future<void> _open(Movie movie) async {
    await AdService.instance.guard(context, () => _openNow(movie));
  }

  Future<void> _openNow(Movie movie) async {
    if (!mounted) return;
    final library = MovieLibrary.instance;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => MovieDetailScreen(movie: movie, saved: library.isSaved(movie), onToggleSaved: () async { await library.toggleSaved(movie); })));
  }
}
