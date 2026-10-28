import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class SupportDamiMoviesScreen extends StatefulWidget {
  const SupportDamiMoviesScreen({super.key});

  @override
  State<SupportDamiMoviesScreen> createState() => _SupportDamiMoviesScreenState();
}

class _SupportDamiMoviesScreenState extends State<SupportDamiMoviesScreen> {
  Map<String, dynamic>? config;
  String? error;
  int? amount;
  bool custom = false;
  final customController = TextEditingController();
  static const accent = Color(0xffec0640);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    Map<String, dynamic>? data;

    // Load the latest support details from the repository so JSON changes can
    // appear without rebuilding the APK. The bundled asset remains a fallback
    // for offline use or if GitHub is temporarily unavailable.
    try {
      final uri = Uri.parse(
        'https://raw.githubusercontent.com/Deeprows/DMoviess/main/assets/data/support_damimovies.json?t=${DateTime.now().millisecondsSinceEpoch}',
      );
      final response = await http.get(uri, headers: const {
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
      }).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map<String, dynamic>) data = decoded;
      }
    } catch (_) {
      // Continue to the bundled copy below.
    }

    if (data == null) {
      try {
        final text = await rootBundle.loadString('assets/data/support_damimovies.json');
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) data = decoded;
      } catch (_) {
        // Show the friendly error state below.
      }
    }

    if (!mounted) return;
    if (data == null) {
      setState(() => error = 'Unable to load support details. Check your connection and try again.');
      return;
    }

    final amounts = (data['amounts'] as List? ?? [])
        .whereType<num>()
        .map((n) => n.toInt())
        .where((n) => n > 0)
        .toList();
    setState(() {
      config = data;
      amount = amounts.isEmpty ? null : amounts.first;
      error = null;
    });
  }

  @override
  void dispose() {
    customController.dispose();
    super.dispose();
  }

  String _str(dynamic value) => value?.toString() ?? '';

  void _copy(String value, String label) {
    if (value.trim().isEmpty) return;
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label copied')));
  }

  Widget _walletCard(Map<String, dynamic> wallet) {
    final provider = _str(wallet['provider']);
    final name = _str(wallet['accountName']);
    final number = _str(wallet['accountNumber']);
    final network = _str(wallet['network']);
    return Card(
      color: const Color(0xff191d29),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xff323643))),
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Icon(Icons.account_balance_wallet_outlined, color: accent), const SizedBox(width: 10), Expanded(child: Text(_str(wallet['label']), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)))]),
          const SizedBox(height: 12),
          if (provider.isNotEmpty) _detail('Provider', provider),
          if (network.isNotEmpty) _detail('Network', network),
          if (name.isNotEmpty) _detail('Account name', name),
          if (number.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Account / wallet address', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(child: SelectableText(number, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
              IconButton(tooltip: 'Copy account details', onPressed: () => _copy(number, 'Account details'), icon: const Icon(Icons.copy_rounded, color: accent)),
            ]),
          ],
          if (_str(wallet['instructions']).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_str(wallet['instructions']), style: const TextStyle(color: Colors.white70))),
        ]),
      ),
    );
  }

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 115, child: Text(label, style: const TextStyle(color: Colors.white60))),
      Expanded(child: SelectableText(value, style: const TextStyle(fontWeight: FontWeight.w600))),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final data = config;
    return Scaffold(
      backgroundColor: const Color(0xff080b12),
      appBar: AppBar(title: const Text('Support DamiMovies'), backgroundColor: const Color(0xff080b12)),
      body: data == null
          ? Center(child: error == null ? const CircularProgressIndicator(color: accent) : Text(error!))
          : ListView(padding: const EdgeInsets.fromLTRB(18, 14, 18, 40), children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xff490c25), Color(0xff171927)]), borderRadius: BorderRadius.circular(24)),
                child: Column(children: [
                  const CircleAvatar(radius: 32, backgroundColor: accent, child: Icon(Icons.favorite_rounded, color: Colors.white, size: 35)),
                  const SizedBox(height: 14),
                  Text(_str(data['headline']), textAlign: TextAlign.center, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 12),
                  Text(_str(data['message']), textAlign: TextAlign.center, style: const TextStyle(height: 1.5, color: Colors.white70)),
                ]),
              ),
              const SizedBox(height: 26),
              const Text('Choose your support amount', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: custom ? 'custom' : amount?.toString(),
                isExpanded: true,
                dropdownColor: const Color(0xff202330),
                decoration: InputDecoration(prefixIcon: const Icon(Icons.volunteer_activism_outlined, color: accent), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)), labelText: 'Amount to support'),
                items: [
                  for (final n in (data['amounts'] as List? ?? []).whereType<num>())
                    DropdownMenuItem(value: n.toInt().toString(), child: Text('${_str(data['currencySymbol'])}${n.toInt()} (${_str(data['currency'])})')),
                  if (data['allowCustomAmount'] == true) const DropdownMenuItem(value: 'custom', child: Text('Other amount (enter your own)')),
                ],
                onChanged: (v) => setState(() { custom = v == 'custom'; if (!custom) amount = int.tryParse(v ?? ''); }),
              ),
              if (custom) Padding(
                padding: const EdgeInsets.only(top: 12),
                child: TextField(controller: customController, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Enter amount (${_str(data['currency'])})', border: const OutlineInputBorder())),
              ),
              const SizedBox(height: 12),
              Text('Your selected support: ${_str(data['currencySymbol'])}${custom ? (customController.text.isEmpty ? 'Enter amount' : customController.text) : (amount?.toString() ?? '—')}', style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 26),
              const Text('Send your contribution', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Use one of the payment options below. Tap the copy icon to copy the account or wallet address.', style: TextStyle(color: Colors.white70, height: 1.4)),
              const SizedBox(height: 16),
              for (final wallet in (data['wallets'] as List? ?? []))
                if (wallet is Map<String, dynamic>) _walletCard(wallet),
              const SizedBox(height: 16),
              Text(_str(data['thankYou']), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xffff698c))),
              const SizedBox(height: 14),
              Text(_str(data['disclaimer']), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.5)),
            ]),
    );
  }
}
