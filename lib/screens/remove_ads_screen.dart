import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import '../services/app_remote_config.dart';
import '../services/currency_service.dart';
import '../services/premium_service.dart';

class RemoveAdsScreen extends StatefulWidget {
  const RemoveAdsScreen({super.key});

  @override
  State<RemoveAdsScreen> createState() => _RemoveAdsScreenState();
}

class _RemoveAdsScreenState extends State<RemoveAdsScreen> {
  final _token = TextEditingController();
  int _plan = 0;
  bool _busy = false;
  String? _message;
  bool _messageOk = false;

  @override
  void initState() {
    super.initState();
    CurrencyService.instance.load();
  }

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    if (_busy) return;
    if (_token.text.trim().isEmpty) {
      setState(() { _message = 'Paste your token first.'; _messageOk = false; });
      return;
    }
    setState(() { _busy = true; _message = null; });
    final result = await PremiumService.instance.redeem(_token.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = result.message;
      _messageOk = result.ok;
      if (result.ok) _token.clear();
    });
  }

  Future<void> _buyOnWhatsApp(RemoveAdsConfig config, RemovePlan plan) async {
    final price = CurrencyService.instance.priceFor(plan, config);
    final text = 'Hi, I want to remove ads on DamiMovies.\n'
        'Plan: ${plan.days} days (${price.text})\n'
        'My Device ID: ${PremiumService.instance.installId}';
    final uri = Uri.parse('https://wa.me/${config.whatsapp}?text=${Uri.encodeComponent(text)}');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      setState(() { _message = 'Could not open WhatsApp.'; _messageOk = false; });
    }
  }

  String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge([PremiumService.instance, CurrencyService.instance, RemoteConfig.instance]),
        builder: (context, _) {
          final config = RemoteConfig.instance.removeAds;
          final premium = PremiumService.instance;
          final plans = config.plans;
          if (_plan >= plans.length) _plan = 0;
          return Scaffold(
            appBar: AppBar(title: const Text('Remove ads')),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
              children: [
                if (premium.active) _activeCard(premium),
                if (premium.active) const SizedBox(height: 18),
                const Text('Choose a plan', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                for (var i = 0; i < plans.length; i++) _planTile(i, plans[i], config),
                const SizedBox(height: 14),
                if (config.whatsapp.isNotEmpty)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1FAF5A),
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: () => _buyOnWhatsApp(config, plans[_plan]),
                    icon: const Icon(Icons.chat_rounded),
                    label: const Text('Buy token on WhatsApp', style: TextStyle(fontWeight: FontWeight.w800)),
                  )
                else
                  const Text('Contact support to buy a token.', style: TextStyle(color: Colors.white60)),
                const SizedBox(height: 12),
                _deviceId(premium),
                const SizedBox(height: 26),
                const Text('Already have a token?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                TextField(
                  controller: _token,
                  minLines: 2,
                  maxLines: 4,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(hintText: 'Paste your token here'),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: appRed, minimumSize: const Size.fromHeight(52)),
                  onPressed: _busy ? null : _redeem,
                  child: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                      : const Text('Remove ads now', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Row(children: [
                    Icon(_messageOk ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                        color: _messageOk ? const Color(0xFF1FAF5A) : appAccentSoft, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_message!, style: TextStyle(color: _messageOk ? const Color(0xFF1FAF5A) : appAccentSoft))),
                  ]),
                ],
                const SizedBox(height: 22),
                const Text(
                  'A token only works on the phone whose Device ID it was made for, and adds days on top of any time you already have.',
                  style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.45),
                ),
              ],
            ),
          );
        },
      );

  Widget _activeCard(PremiumService premium) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: appRed.withValues(alpha: .16),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: appRed.withValues(alpha: .4)),
        ),
        child: Row(children: [
          Icon(Icons.verified_rounded, color: appRed, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Ads removed', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 3),
              Text('Until ${_date(premium.until!)} · ${premium.daysLeft} days left',
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ]),
          ),
        ]),
      );

  Widget _planTile(int index, RemovePlan plan, RemoveAdsConfig config) {
    final price = CurrencyService.instance.priceFor(plan, config);
    final selected = index == _plan;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _plan = index),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: appSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? appRed : Colors.white12, width: selected ? 2 : 1),
          ),
          child: Row(children: [
            Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: selected ? appRed : Colors.white38),
            const SizedBox(width: 12),
            Expanded(
              child: Text('${plan.days} days', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(price.text, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              if (price.usdText != null && !price.exact)
                Text('≈ ${price.usdText}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _deviceId(PremiumService premium) => Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
        decoration: BoxDecoration(color: appSurface, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          const Text('Device ID', style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(width: 12),
          Expanded(
            child: SelectableText(premium.installId,
                style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: .8)),
          ),
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy_rounded, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: premium.installId));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Device ID copied')));
            },
          ),
        ]),
      );
}
