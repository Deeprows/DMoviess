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
  static const _ratesUrl = 'https://open.er-api.com/v6/latest/USD';

  Map<String, double> _rates = {};
  String? _selectedCountry;
  String? get selectedCountry => _selectedCountry;
  static const _kCountry = 'damimovies_pricing_country';
  static const countryNames = <String, String>{
    'NG':'Nigeria', 'GH':'Ghana', 'KE':'Kenya', 'ZA':'South Africa', 'EG':'Egypt',
    'US':'United States', 'GB':'United Kingdom', 'FR':'France', 'DE':'Germany',
    'IN':'India', 'PK':'Pakistan', 'BD':'Bangladesh', 'TR':'Türkiye',
    'SA':'Saudi Arabia', 'AE':'United Arab Emirates', 'CA':'Canada',
    'AU':'Australia', 'BR':'Brazil', 'PH':'Philippines', 'ID':'Indonesia',
    'MY':'Malaysia', 'JP':'Japan', 'CN':'China', 'MX':'Mexico',
    'TZ':'Tanzania', 'UG':'Uganda', 'RW':'Rwanda', 'ET':'Ethiopia',
    'MA':'Morocco', 'DZ':'Algeria', 'TN':'Tunisia', 'SN':'Senegal',
    'CI':'Côte d’Ivoire', 'CM':'Cameroon', 'ZM':'Zambia', 'BW':'Botswana',
    'NZ':'New Zealand', 'ES':'Spain', 'PT':'Portugal', 'IT':'Italy',
    'NL':'Netherlands', 'CH':'Switzerland', 'SE':'Sweden', 'NO':'Norway',
    'DK':'Denmark', 'PL':'Poland', 'AR':'Argentina', 'CO':'Colombia',
    'CL':'Chile', 'PE':'Peru', 'SG':'Singapore', 'TH':'Thailand',
    'VN':'Vietnam', 'KR':'South Korea', 'HK':'Hong Kong', 'TW':'Taiwan',
    'QA':'Qatar', 'KW':'Kuwait', 'OM':'Oman', 'BH':'Bahrain',
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
    if (value == null) { await prefs.remove(_kCountry); }
    else { await prefs.setString(_kCountry, value); }
  }
  String get countryLabel => countryNames[country] ?? country;
  String currencyForCountry(String c) => _countryCurrency[c] ?? 'USD';


  String get code => _countryCurrency[country] ?? 'USD';

  Future<void> load() async {
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
        final data = jsonDecode(cached);
        _rates = _parse(data['rates']);
        final t = data['t'] is int ? data['t'] as int : 0;
        fresh = DateTime.now().millisecondsSinceEpoch - t < 86400000;
        notifyListeners();
      }
      if (fresh) return;
      final response = await http.get(Uri.parse(_ratesUrl)).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return;
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      final rates = _parse(body['rates']);
      if (rates.isEmpty) return;
      _rates = rates;
      await prefs.setString(_kCache, jsonEncode({'t': DateTime.now().millisecondsSinceEpoch, 'rates': rates}));
      notifyListeners();
    } catch (error) {
      debugPrint('DamiMovies: exchange rates unavailable: $error');
    }
  }

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
    if (override != null) return PriceInfo(_format(currency, override), currency == 'USD' ? null : usdText, true);
    if (currency == 'USD') return PriceInfo(usdText, null, false);
    final rate = _rates[currency];
    if (rate == null) return PriceInfo(usdText, null, false);
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
    final grouped = intPart.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
    text = '$grouped$frac';
    final symbol = _symbols[currency];
    return symbol != null ? '$symbol$text' : '$currency $text';
  }

  static const Map<String, String> _symbols = {
    'USD': 'US\$', 'EUR': '€', 'GBP': '£', 'NGN': '₦', 'GHS': 'GH₵', 'KES': 'KSh ', 'ZAR': 'R',
    'EGP': 'E£', 'INR': '₹', 'JPY': '¥', 'CNY': 'CN¥', 'KRW': '₩', 'TRY': '₺', 'PHP': '₱',
    'CAD': 'CA\$', 'AUD': 'A\$', 'NZD': 'NZ\$', 'BRL': 'R\$', 'MXN': 'MX\$', 'RUB': '₽', 'UAH': '₴',
  };

  static const Map<String, String> _countryCurrency = {
    'US': 'USD', 'GB': 'GBP', 'NG': 'NGN', 'GH': 'GHS', 'KE': 'KES', 'ZA': 'ZAR', 'EG': 'EGP',
    'TZ': 'TZS', 'UG': 'UGX', 'RW': 'RWF', 'ET': 'ETB', 'MA': 'MAD', 'DZ': 'DZD', 'TN': 'TND',
    'SN': 'XOF', 'CI': 'XOF', 'BJ': 'XOF', 'BF': 'XOF', 'ML': 'XOF', 'NE': 'XOF', 'TG': 'XOF',
    'GW': 'XOF', 'CM': 'XAF', 'GA': 'XAF', 'CG': 'XAF', 'TD': 'XAF', 'CF': 'XAF', 'GQ': 'XAF',
    'ZM': 'ZMW', 'ZW': 'USD', 'BW': 'BWP', 'NA': 'NAD', 'MZ': 'MZN', 'AO': 'AOA', 'SL': 'SLE',
    'LR': 'LRD', 'GM': 'GMD', 'CD': 'CDF', 'SD': 'SDG', 'LY': 'LYD',
    'DE': 'EUR', 'FR': 'EUR', 'IT': 'EUR', 'ES': 'EUR', 'PT': 'EUR', 'NL': 'EUR', 'BE': 'EUR',
    'AT': 'EUR', 'IE': 'EUR', 'FI': 'EUR', 'GR': 'EUR', 'LU': 'EUR', 'SK': 'EUR', 'SI': 'EUR',
    'EE': 'EUR', 'LV': 'EUR', 'LT': 'EUR', 'MT': 'EUR', 'CY': 'EUR', 'HR': 'EUR', 'BG': 'EUR',
    'CH': 'CHF', 'SE': 'SEK', 'NO': 'NOK', 'DK': 'DKK', 'PL': 'PLN', 'CZ': 'CZK', 'HU': 'HUF',
    'RO': 'RON', 'TR': 'TRY', 'RU': 'RUB', 'UA': 'UAH',
    'CA': 'CAD', 'MX': 'MXN', 'BR': 'BRL', 'AR': 'ARS', 'CL': 'CLP', 'CO': 'COP', 'PE': 'PEN',
    'VE': 'VES', 'JM': 'JMD', 'TT': 'TTD',
    'IN': 'INR', 'PK': 'PKR', 'BD': 'BDT', 'LK': 'LKR', 'NP': 'NPR', 'CN': 'CNY', 'JP': 'JPY',
    'KR': 'KRW', 'ID': 'IDR', 'MY': 'MYR', 'SG': 'SGD', 'TH': 'THB', 'VN': 'VND', 'PH': 'PHP',
    'HK': 'HKD', 'TW': 'TWD',
    'SA': 'SAR', 'AE': 'AED', 'QA': 'QAR', 'KW': 'KWD', 'BH': 'BHD', 'OM': 'OMR', 'JO': 'JOD',
    'LB': 'LBP', 'IQ': 'IQD', 'IL': 'ILS', 'IR': 'IRR',
    'AU': 'AUD', 'NZ': 'NZD',
  };
}
