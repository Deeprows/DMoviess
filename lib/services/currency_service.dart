import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_remote_config.dart';

class PriceInfo {
  final String text; // what to show, e.g. NGN 1,500
  final String? usdText; // US$1.50 when the main text is another currency
  final bool exact; // true when set by you in localPrices
  const PriceInfo(this.text, this.usdText, this.exact);
}

/// Shows prices in the phone's currency. USD prices are converted with a free
/// public exchange-rate feed (cached for a day); prices you set per currency in
/// app_config.json "localPrices" always win. With no rate, USD is shown.
class CurrencyService extends ChangeNotifier {
  CurrencyService._();
  static final CurrencyService instance = CurrencyService._();

  static const _kCache = 'damimovies_fx_cache';
  // Several independent feeds. Frankfurter only covers ~30 ECB currencies (no
  // GHS/NGN/KES...), so the others must come first for African currencies.
  static const _ratesUrls = <String>[
    'https://open.er-api.com/v6/latest/USD',
    'https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.json',
    'https://latest.currency-api.pages.dev/v1/currencies/usd.json',
    'https://api.frankfurter.dev/v1/latest?base=USD',
  ];

  Map<String, double> _rates = {};
  bool _loadingRates = false;
  bool get loadingRates => _loadingRates;
  bool hasPrice(RemovePlan plan, RemoveAdsConfig config) =>
      code == 'USD' || config.localPrices[code]?['${plan.days}'] != null || _rates[code] != null;

  String? _selectedCountry;
  String? get selectedCountry => _selectedCountry;
  static const _kCountry = 'damimovies_pricing_country';
  static const countryNames = <String, String>{
    'NG': 'Nigeria',
    'GH': 'Ghana',
    'KE': 'Kenya',
    'ZA': 'South Africa',
    'EG': 'Egypt',
    'US': 'United States',
    'GB': 'United Kingdom',
    'FR': 'France',
    'DE': 'Germany',
    'IN': 'India',
    'PK': 'Pakistan',
    'BD': 'Bangladesh',
    'TR': 'Türkiye',
    'SA': 'Saudi Arabia',
    'AE': 'United Arab Emirates',
    'CA': 'Canada',
    'AU': 'Australia',
    'BR': 'Brazil',
    'PH': 'Philippines',
    'ID': 'Indonesia',
    'MY': 'Malaysia',
    'JP': 'Japan',
    'CN': 'China',
    'MX': 'Mexico',
    'TZ': 'Tanzania',
    'UG': 'Uganda',
    'RW': 'Rwanda',
    'ET': 'Ethiopia',
    'MA': 'Morocco',
    'DZ': 'Algeria',
    'TN': 'Tunisia',
    'SN': 'Senegal',
    'CI': 'Côte d’Ivoire',
    'CM': 'Cameroon',
    'ZM': 'Zambia',
    'BW': 'Botswana',
    'NZ': 'New Zealand',
    'ES': 'Spain',
    'PT': 'Portugal',
    'IT': 'Italy',
    'NL': 'Netherlands',
    'CH': 'Switzerland',
    'SE': 'Sweden',
    'NO': 'Norway',
    'DK': 'Denmark',
    'PL': 'Poland',
    'AR': 'Argentina',
    'CO': 'Colombia',
    'CL': 'Chile',
    'PE': 'Peru',
    'SG': 'Singapore',
    'TH': 'Thailand',
    'VN': 'Vietnam',
    'KR': 'South Korea',
    'HK': 'Hong Kong',
    'TW': 'Taiwan',
    'QA': 'Qatar',
    'KW': 'Kuwait',
    'OM': 'Oman',
    'BH': 'Bahrain',
  };
  String get detectedCountry {
    for (final locale in ui.PlatformDispatcher.instance.locales) {
      final c = locale.countryCode?.toUpperCase();
      if (c != null && _countryCurrency.containsKey(c)) return c;
    }
    return 'US';
  }

  String get country => _selectedCountry ?? detectedCountry;
  Future<void> setCountry(String? value) async {
    if (value != null && !_countryCurrency.containsKey(value)) return;
    _selectedCountry = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(_kCountry);
    } else {
      await prefs.setString(_kCountry, value);
    }
    if (!_hasRate(code)) unawaited(load());
  }

  String get countryLabel => countryNames[country] ?? country;
  String currencyForCountry(String c) => _countryCurrency[c] ?? 'USD';

  String get code => _countryCurrency[country] ?? 'USD';

  Future<void> load() async {
    if (_loadingRates) return;
    _loadingRates = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedCountry = prefs.getString(_kCountry);
      if (storedCountry != null && _countryCurrency.containsKey(storedCountry)) {
        _selectedCountry = storedCountry;
        notifyListeners();
      }
      final cached = prefs.getString(_kCache);
      var fresh = false;
      if (cached != null) {
        try {
          final data = jsonDecode(cached);
          _rates = {..._rates, ..._parse(data['rates'])};
          final t = data['t'] is int ? data['t'] as int : 0;
          // Only "fresh" if it is recent AND has the rate for the selected
          // currency (a partial cache used to hide GHS for a whole day).
          fresh = _rates.isNotEmpty &&
              _hasRate(code) &&
              DateTime.now().millisecondsSinceEpoch - t < 86400000;
          notifyListeners();
        } catch (_) {}
      }
      if (!fresh) {
        for (final url in _ratesUrls) {
          try {
            final response = await http
                .get(Uri.parse(url))
                .timeout(const Duration(seconds: 8));
            if (response.statusCode != 200) continue;
            final body = jsonDecode(utf8.decode(response.bodyBytes));
            var rates = <String, double>{};
            if (body is Map) {
              rates = _parse(body['rates']);
              if (rates.isEmpty && body['usd'] is Map) {
                rates = _parse((body['usd'] as Map)
                    .map((k, v) => MapEntry('$k'.toUpperCase(), v)));
              }
            }
            if (rates.isEmpty) continue;
            _rates = {..._rates, ...rates, 'USD': 1.0};
            await prefs.setString(_kCache, jsonEncode({
              't': DateTime.now().millisecondsSinceEpoch,
              'rates': _rates,
            }));
            notifyListeners();
            if (_hasRate(code)) break; // otherwise try the next feed
          } catch (error) {
            debugPrint('DamiMovies: currency feed unavailable: $error');
          }
        }
      }
    } finally {
      _loadingRates = false;
      notifyListeners();
    }
  }

  bool _hasRate(String c) => c == 'USD' || _rates[c] != null;

  Map<String, double> _parse(Object? raw) {
    final out = <String, double>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v is num && v > 0) out['$k'] = v.toDouble();
      });
    }
    return out;
  }

  PriceInfo priceFor(RemovePlan plan, RemoveAdsConfig config) {
    final currency = code;
    final usdText = _format('USD', plan.usd);
    final override = config.localPrices[currency]?['${plan.days}'];
    if (override != null)
      return PriceInfo(_format(currency, override),
          currency == 'USD' ? null : usdText, true);
    if (currency == 'USD') return PriceInfo(usdText, null, false);
    final rate = _rates[currency];
    if (rate == null) return PriceInfo(_loadingRates ? 'Loading…' : 'Rate unavailable', null, false);
    return PriceInfo(_format(currency, _nice(plan.usd * rate)), usdText, false);
  }

  double _nice(double v) {
    if (v >= 10000) return (v / 100).round() * 100.0;
    if (v >= 1000) return (v / 50).round() * 50.0;
    if (v >= 100) return (v / 5).round() * 5.0;
    if (v >= 10) return v.roundToDouble();
    return (v * 100).round() / 100;
  }

  String _format(String currency, double amount) {
    final whole = amount == amount.roundToDouble();
    var text = amount.toStringAsFixed(whole ? 0 : 2);
    final dot = text.indexOf('.');
    final intPart = dot == -1 ? text : text.substring(0, dot);
    final frac = dot == -1 ? '' : text.substring(dot);
    final grouped =
        intPart.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
    text = '$grouped$frac';
    final symbol = _symbols[currency];
    return symbol != null ? '$symbol$text' : '$currency $text';
  }

  static const Map<String, String> _symbols = {
    'USD': 'US\$',
    'EUR': '€',
    'GBP': '£',
    'NGN': '₦',
    'GHS': 'GH₵',
    'KES': 'KSh ',
    'ZAR': 'R',
    'EGP': 'E£',
    'INR': '₹',
    'JPY': '¥',
    'CNY': 'CN¥',
    'KRW': '₩',
    'TRY': '₺',
    'PHP': '₱',
    'CAD': 'CA\$',
    'AUD': 'A\$',
    'NZD': 'NZ\$',
    'BRL': 'R\$',
    'MXN': 'MX\$',
    'RUB': '₽',
    'UAH': '₴',
  };

  static const Map<String, String> _countryCurrency = {
    'US': 'USD',
    'GB': 'GBP',
    'NG': 'NGN',
    'GH': 'GHS',
    'KE': 'KES',
    'ZA': 'ZAR',
    'EG': 'EGP',
    'TZ': 'TZS',
    'UG': 'UGX',
    'RW': 'RWF',
    'ET': 'ETB',
    'MA': 'MAD',
    'DZ': 'DZD',
    'TN': 'TND',
    'SN': 'XOF',
    'CI': 'XOF',
    'BJ': 'XOF',
    'BF': 'XOF',
    'ML': 'XOF',
    'NE': 'XOF',
    'TG': 'XOF',
    'GW': 'XOF',
    'CM': 'XAF',
    'GA': 'XAF',
    'CG': 'XAF',
    'TD': 'XAF',
    'CF': 'XAF',
    'GQ': 'XAF',
    'ZM': 'ZMW',
    'ZW': 'USD',
    'BW': 'BWP',
    'NA': 'NAD',
    'MZ': 'MZN',
    'AO': 'AOA',
    'SL': 'SLE',
    'LR': 'LRD',
    'GM': 'GMD',
    'CD': 'CDF',
    'SD': 'SDG',
    'LY': 'LYD',
    'DE': 'EUR',
    'FR': 'EUR',
    'IT': 'EUR',
    'ES': 'EUR',
    'PT': 'EUR',
    'NL': 'EUR',
    'BE': 'EUR',
    'AT': 'EUR',
    'IE': 'EUR',
    'FI': 'EUR',
    'GR': 'EUR',
    'LU': 'EUR',
    'SK': 'EUR',
    'SI': 'EUR',
    'EE': 'EUR',
    'LV': 'EUR',
    'LT': 'EUR',
    'MT': 'EUR',
    'CY': 'EUR',
    'HR': 'EUR',
    'BG': 'EUR',
    'CH': 'CHF',
    'SE': 'SEK',
    'NO': 'NOK',
    'DK': 'DKK',
    'PL': 'PLN',
    'CZ': 'CZK',
    'HU': 'HUF',
    'RO': 'RON',
    'TR': 'TRY',
    'RU': 'RUB',
    'UA': 'UAH',
    'CA': 'CAD',
    'MX': 'MXN',
    'BR': 'BRL',
    'AR': 'ARS',
    'CL': 'CLP',
    'CO': 'COP',
    'PE': 'PEN',
    'VE': 'VES',
    'JM': 'JMD',
    'TT': 'TTD',
    'IN': 'INR',
    'PK': 'PKR',
    'BD': 'BDT',
    'LK': 'LKR',
    'NP': 'NPR',
    'CN': 'CNY',
    'JP': 'JPY',
    'KR': 'KRW',
    'ID': 'IDR',
    'MY': 'MYR',
    'SG': 'SGD',
    'TH': 'THB',
    'VN': 'VND',
    'PH': 'PHP',
    'HK': 'HKD',
    'TW': 'TWD',
    'SA': 'SAR',
    'AE': 'AED',
    'QA': 'QAR',
    'KW': 'KWD',
    'BH': 'BHD',
    'OM': 'OMR',
    'JO': 'JOD',
    'LB': 'LBP',
    'IQ': 'IQD',
    'IL': 'ILS',
    'IR': 'IRR',
    'AU': 'AUD',
    'NZ': 'NZD',
  };
}
