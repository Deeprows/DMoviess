import '../services/auth_service.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config.dart';
import '../main.dart';
import '../services/app_preferences.dart';
import 'browser_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _notice(BuildContext context) async {
    var title = 'DamiMovies Notice';
    var body = 'Discover movies and series from TMDB, save titles to your library, and continue watching where supported by the player source. Playback and downloads depend on the third-party source used by each title.';
    if (AppConfig.noticeUrl.trim().isNotEmpty) {
      try {
        final response = await http.get(Uri.parse(AppConfig.noticeUrl)).timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) {
          final parsed = jsonDecode(response.body);
          if (parsed is Map) {
            title = (parsed['title'] ?? title).toString();
            body = (parsed['message'] ?? parsed['body'] ?? parsed['text'] ?? body).toString();
          }
        }
      } catch (_) {}
    }
    if (!context.mounted) return;
    await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: Text(body, style: const TextStyle(height: 1.5))),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close'))],
    ));
  }

  Future<void> _checkUpdate(BuildContext context) async {
    final link = AppConfig.updateUrl.trim();
    if (link.isEmpty) {
      if (!context.mounted) return;
      await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
        title: const Text('Update checker'),
        content: const Text('No update at the moment. Please check again later.'),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('OK'))],
      ));
      return;
    }
    try {
      final response = await http.get(Uri.parse(link)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        dynamic data;
        try { data = jsonDecode(response.body); } catch (_) {}
        if (data is Map) {
          final version = (data['version'] ?? 'New version').toString();
          final apk = (data['apkUrl'] ?? data['url'] ?? '').toString();
          final notes = (data['notes'] ?? 'A newer version may be available.').toString();
          if (!context.mounted) return;
          await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
            title: Text('DamiMovies update · $version'),
            content: Text(notes),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Later')),
              if (apk.startsWith('http')) FilledButton(onPressed: () { Navigator.pop(dialogContext); launchUrl(Uri.parse(apk), mode: LaunchMode.externalApplication); }, child: const Text('Get update')),
            ],
          ));
          return;
        }
      }
      await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not check updates. Check your connection and try again.')));
    }
  }

  Future<void> _about(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('DamiMovies'),
        content: const Text(
          'DamiMovies is just a movie hub for movie lovers. No video or movie is hosted here. All content is the copyright of its respective owners.',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _support(BuildContext context) async {
    final link = AppConfig.supportUrl.trim();
    if (link.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No support link is configured for this build.')));
      return;
    }
    await Navigator.push(context, MaterialPageRoute(builder: (_) => BrowserScreen(initialUrl: link)));
  }

  @override
  Widget build(BuildContext context) {
    final prefs = AppPreferences.instance;
    return AnimatedBuilder(
      animation: prefs,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: Text('Settings'.tr)),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(colors: [prefs.palette.accent.withValues(alpha: .28), prefs.palette.surface]),
                border: Border.all(color: prefs.palette.accent.withValues(alpha: .25)),
              ),
              child: Row(children: [
                Container(width: 52, height: 52, decoration: BoxDecoration(color: prefs.palette.accent, borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.movie_filter_rounded, size: 30, color: Colors.white)),
                const SizedBox(width: 13),
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('DamiMovies', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                  SizedBox(height: 3), Text('Personalise your movie experience', style: TextStyle(color: Colors.white60, fontSize: 12)),
                ])),
                const Text('v${AppConfig.appVersion}', style: TextStyle(color: Colors.white54, fontSize: 11)),
              ]),
            ),
            const SizedBox(height: 24),
            _heading('Theme'),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: AppPreferences.palettes.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 1.22, crossAxisSpacing: 9, mainAxisSpacing: 9),
              itemBuilder: (context, index) {
                final palette = AppPreferences.palettes[index];
                final selected = prefs.themeIndex == index;
                return InkWell(
                  borderRadius: BorderRadius.circular(15),
                  onTap: () => prefs.setThemeIndex(index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: palette.background, borderRadius: BorderRadius.circular(15), border: Border.all(color: selected ? palette.accent : Colors.white12, width: selected ? 2 : 1)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Container(width: 18, height: 18, decoration: BoxDecoration(color: palette.accent, shape: BoxShape.circle)),
                        const SizedBox(width: 5),
                        Expanded(child: Container(height: 6, decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(4)))),
                        if (selected) Icon(Icons.check_circle_rounded, size: 16, color: palette.accent),
                      ]),
                      const Spacer(),
                      Text(palette.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 10.5)),
                      const SizedBox(height: 4),
                      Container(height: 4, width: 42, decoration: BoxDecoration(color: palette.accent, borderRadius: BorderRadius.circular(5))),
                    ]),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            _heading('Language'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: prefs.language,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.translate_rounded), border: OutlineInputBorder()),
              items: [for (final language in AppPreferences.languages) DropdownMenuItem(value: language, child: Text(language))],
              onChanged: (value) { if (value != null) prefs.setLanguage(value); },
            ),
            const SizedBox(height: 22),
            _heading('Player & browsing'),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: prefs.adShield,
              onChanged: prefs.setAdShield,
              title: const Text('Block pop-ups and ad redirects'),
              subtitle: const Text('Best-effort blocking in the video player and browser.'),
              secondary: const Icon(Icons.shield_outlined),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: prefs.lowQuality,
              onChanged: prefs.setLowQuality,
              title: const Text('Prefer low quality on direct streams'),
              subtitle: const Text('Uses the lowest HLS level when the stream supports it.'),
              secondary: const Icon(Icons.high_quality_outlined),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: prefs.keepScreenAwake,
              onChanged: prefs.setKeepScreenAwake,
              title: const Text('Keep screen awake while playing'),
              subtitle: const Text('Avoids screen timeout when watching a movie.'),
              secondary: const Icon(Icons.brightness_5_outlined),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: prefs.backgroundPlayback,
              onChanged: prefs.setBackgroundPlayback,
              title: const Text('Background playback controls'),
              subtitle: const Text('Shows Android media controls while the player is open.'),
              secondary: const Icon(Icons.headphones_rounded),
            ),
            const SizedBox(height: 20),
            _heading('App'),
            _actionTile(Icons.campaign_outlined, 'Notice', 'Read the current DamiMovies notice', () => _notice(context)),
            _actionTile(Icons.system_update_alt_rounded, 'Check for updates', 'Check a configured update source', () => _checkUpdate(context)),
            _actionTile(Icons.favorite_border_rounded, 'Support DamiMovies', 'Open the configured support page', () => _support(context)),
            if (AuthService.instance.user != null) _accountTile(context),
            _actionTile(Icons.share_rounded, 'Share DamiMovies', 'Share the app link', () => Share.share('Discover movies with DamiMovies.\n${AppConfig.appUrl}')),
            _actionTile(Icons.info_outline_rounded, 'About', 'Movie hub for movie lovers', () => _about(context)),
          ],
        ),
      ),
    );
  }

  Widget _accountTile(BuildContext context) {
    final user = AuthService.instance.user!;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 2),
      leading: Icon(Icons.account_circle_rounded, color: appRed),
      title: Text(user.name.isNotEmpty ? user.name : 'Signed in', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
      subtitle: Text(user.email, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      trailing: TextButton(
        onPressed: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Sign out?'),
              content: const Text('You will need to sign in with Gmail again to keep watching.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out')),
              ],
            ),
          );
          if (ok != true) return;
          await AuthService.instance.signOut();
          if (context.mounted) Navigator.of(context).popUntil((route) => route.isFirst);
        },
        child: const Text('Sign out'),
      ),
    );
  }

  Widget _heading(String text) => Padding(padding: const EdgeInsets.only(left: 2), child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)));

  Widget _actionTile(IconData icon, String title, String subtitle, VoidCallback onTap) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 2),
    leading: Icon(icon, color: appRed),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
    subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 11)),
    trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white38),
    onTap: onTap,
  );
}
