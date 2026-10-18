import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DamiPalette {
  final String name;
  final Color background;
  final Color surface;
  final Color deepSurface;
  final Color accent;
  final Color accentSoft;

  const DamiPalette({
    required this.name,
    required this.background,
    required this.surface,
    required this.deepSurface,
    required this.accent,
    required this.accentSoft,
  });
}

/// Persisted movie-app preferences shared by the UI and player.
class AppPreferences extends ChangeNotifier {
  AppPreferences._();
  static final AppPreferences instance = AppPreferences._();

  static const List<DamiPalette> palettes = [
    DamiPalette(
      name: 'Midnight Violet',
      background: Color(0xFF090711),
      surface: Color(0xFF171326),
      deepSurface: Color(0xFF100C1C),
      accent: Color(0xFF9B5CFF),
      accentSoft: Color(0xFFC5A0FF),
    ),
    DamiPalette(
      name: 'Crimson Cinema',
      background: Color(0xFF080B10),
      surface: Color(0xFF121722),
      deepSurface: Color(0xFF0D1119),
      accent: Color(0xFFE50935),
      accentSoft: Color(0xFFFF637D),
    ),
    DamiPalette(
      name: 'Ocean Blue',
      background: Color(0xFF06101B),
      surface: Color(0xFF102033),
      deepSurface: Color(0xFF0A1727),
      accent: Color(0xFF2D87FF),
      accentSoft: Color(0xFF83B8FF),
    ),
    DamiPalette(
      name: 'Emerald Night',
      background: Color(0xFF06110D),
      surface: Color(0xFF11251B),
      deepSurface: Color(0xFF0B1912),
      accent: Color(0xFF00B879),
      accentSoft: Color(0xFF68E5B2),
    ),
    DamiPalette(
      name: 'Golden Hour',
      background: Color(0xFF110D06),
      surface: Color(0xFF282012),
      deepSurface: Color(0xFF191308),
      accent: Color(0xFFE6AD24),
      accentSoft: Color(0xFFFFD978),
    ),
    DamiPalette(
      name: 'Sunset Orange',
      background: Color(0xFF140A07),
      surface: Color(0xFF2A1711),
      deepSurface: Color(0xFF1B0E09),
      accent: Color(0xFFFF6B2C),
      accentSoft: Color(0xFFFFAA7D),
    ),
    DamiPalette(
      name: 'Neon Cyan',
      background: Color(0xFF050F12),
      surface: Color(0xFF102126),
      deepSurface: Color(0xFF09171A),
      accent: Color(0xFF00C7D9),
      accentSoft: Color(0xFF7BEAF2),
    ),
    DamiPalette(
      name: 'Rose',
      background: Color(0xFF130810),
      surface: Color(0xFF281522),
      deepSurface: Color(0xFF1A0D17),
      accent: Color(0xFFFF4D96),
      accentSoft: Color(0xFFFFA0C5),
    ),
    DamiPalette(
      name: 'Pure Black',
      background: Color(0xFF000000),
      surface: Color(0xFF101010),
      deepSurface: Color(0xFF080808),
      accent: Color(0xFFF2F2F2),
      accentSoft: Color(0xFFFFFFFF),
    ),
  ];

  static const List<String> languages = [
    'English', 'Arabic', 'French', 'Spanish', 'Portuguese', 'Hindi', 'Turkish', 'Hausa', 'Yoruba'
  ];

  int _themeIndex = 1;
  String _language = 'English';
  bool _adShield = true;
  bool _lowQuality = false;
  bool _keepScreenAwake = true;
  bool _backgroundPlayback = true;
  bool _loaded = false;

  DamiPalette get palette => palettes[_themeIndex.clamp(0, palettes.length - 1).toInt()];
  int get themeIndex => _themeIndex;
  String get language => _language;
  String get languageCode => const {
    'English': 'en', 'Arabic': 'ar', 'French': 'fr', 'Spanish': 'es',
    'Portuguese': 'pt', 'Hindi': 'hi', 'Turkish': 'tr', 'Hausa': 'ha', 'Yoruba': 'yo'
  }[_language] ?? 'en';
  bool get adShield => _adShield;
  bool get lowQuality => _lowQuality;
  bool get keepScreenAwake => _keepScreenAwake;
  bool get backgroundPlayback => _backgroundPlayback;
  bool get loaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _themeIndex = (prefs.getInt('damimovies_theme_index') ?? _themeIndex)
        .clamp(0, palettes.length - 1).toInt();
    final lang = prefs.getString('damimovies_language') ?? _language;
    _language = languages.contains(lang) ? lang : 'English';
    _adShield = prefs.getBool('damimovies_ad_shield') ?? _adShield;
    _lowQuality = prefs.getBool('damimovies_low_quality') ?? _lowQuality;
    _keepScreenAwake = prefs.getBool('damimovies_keep_awake') ?? _keepScreenAwake;
    _backgroundPlayback = prefs.getBool('damimovies_background_playback') ?? _backgroundPlayback;
    _loaded = true;
    notifyListeners();
  }

  Future<void> setThemeIndex(int value) async {
    _themeIndex = value.clamp(0, palettes.length - 1).toInt();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('damimovies_theme_index', _themeIndex);
  }

  Future<void> setLanguage(String value) async {
    if (!languages.contains(value)) return;
    _language = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('damimovies_language', value);
  }

  Future<void> setAdShield(bool value) async {
    _adShield = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('damimovies_ad_shield', value);
  }

  Future<void> setLowQuality(bool value) async {
    _lowQuality = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('damimovies_low_quality', value);
  }

  Future<void> setKeepScreenAwake(bool value) async {
    _keepScreenAwake = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('damimovies_keep_awake', value);
  }

  Future<void> setBackgroundPlayback(bool value) async {
    _backgroundPlayback = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('damimovies_background_playback', value);
  }

  String translate(String english) {
    final code = languageCode;
    if (code == 'en') return english;
    return _translations[code]?[english] ?? english;
  }

  static const Map<String, Map<String, String>> _translations = {
    'ar': {
      'Movies': 'الأفلام', 'Browser': 'المتصفح', 'Downloads': 'التنزيلات', 'Library': 'المكتبة',
      'Settings': 'الإعدادات', 'Search movies...': 'ابحث عن الأفلام...', 'Trending Movies': 'الأفلام الرائجة',
      'Top 10 Today': 'أفضل 10 اليوم', 'Continue Watching': 'متابعة المشاهدة', 'Latest Trailers': 'أحدث الإعلانات',
      'Play': 'تشغيل', 'Download': 'تنزيل', 'My List': 'قائمتي', 'Refresh': 'تحديث',
      'All': 'الكل', 'Series': 'مسلسلات', 'Retry': 'إعادة المحاولة', 'Share': 'مشاركة',
      'Watch Later': 'المشاهدة لاحقاً', 'History': 'السجل', 'Theme': 'المظهر', 'Language': 'اللغة',
    },
    'fr': {
      'Movies': 'Films', 'Browser': 'Navigateur', 'Downloads': 'Téléchargements', 'Library': 'Bibliothèque',
      'Settings': 'Paramètres', 'Search movies...': 'Rechercher des films...', 'Trending Movies': 'Films tendance',
      'Top 10 Today': 'Top 10 du jour', 'Continue Watching': 'Reprendre la lecture', 'Latest Trailers': 'Bandes-annonces récentes',
      'Play': 'Lire', 'Download': 'Télécharger', 'My List': 'Ma liste', 'Refresh': 'Actualiser',
      'All': 'Tout', 'Series': 'Séries', 'Retry': 'Réessayer', 'Share': 'Partager',
      'Watch Later': 'À regarder plus tard', 'History': 'Historique', 'Theme': 'Thème', 'Language': 'Langue',
    },
    'es': {
      'Movies': 'Películas', 'Browser': 'Navegador', 'Downloads': 'Descargas', 'Library': 'Biblioteca',
      'Settings': 'Ajustes', 'Search movies...': 'Buscar películas...', 'Trending Movies': 'Películas populares',
      'Top 10 Today': 'Top 10 de hoy', 'Continue Watching': 'Continuar viendo', 'Latest Trailers': 'Últimos tráileres',
      'Play': 'Reproducir', 'Download': 'Descargar', 'My List': 'Mi lista', 'Refresh': 'Actualizar',
      'All': 'Todo', 'Series': 'Series', 'Retry': 'Reintentar', 'Share': 'Compartir',
      'Watch Later': 'Ver más tarde', 'History': 'Historial', 'Theme': 'Tema', 'Language': 'Idioma',
    },
    'pt': {
      'Movies': 'Filmes', 'Browser': 'Navegador', 'Downloads': 'Transferências', 'Library': 'Biblioteca',
      'Settings': 'Configurações', 'Search movies...': 'Pesquisar filmes...', 'Trending Movies': 'Filmes em alta',
      'Top 10 Today': 'Top 10 de hoje', 'Continue Watching': 'Continuar assistindo', 'Latest Trailers': 'Trailers recentes',
      'Play': 'Assistir', 'Download': 'Baixar', 'My List': 'Minha lista', 'Refresh': 'Atualizar',
      'All': 'Todos', 'Series': 'Séries', 'Retry': 'Tentar novamente', 'Share': 'Compartilhar',
      'Watch Later': 'Assistir depois', 'History': 'Histórico', 'Theme': 'Tema', 'Language': 'Idioma',
    },
    'hi': {
      'Movies': 'फ़िल्में', 'Browser': 'ब्राउज़र', 'Downloads': 'डाउनलोड', 'Library': 'लाइब्रेरी',
      'Settings': 'सेटिंग्स', 'Search movies...': 'फ़िल्म खोजें...', 'Trending Movies': 'लोकप्रिय फ़िल्में',
      'Top 10 Today': 'आज की टॉप 10', 'Continue Watching': 'देखना जारी रखें', 'Latest Trailers': 'नए ट्रेलर',
      'Play': 'चलाएँ', 'Download': 'डाउनलोड', 'My List': 'मेरी सूची', 'Refresh': 'रिफ़्रेश',
      'All': 'सभी', 'Series': 'सीरीज़', 'Retry': 'फिर कोशिश करें', 'Share': 'शेयर करें',
      'Watch Later': 'बाद में देखें', 'History': 'इतिहास', 'Theme': 'थीम', 'Language': 'भाषा',
    },
    'tr': {
      'Movies': 'Filmler', 'Browser': 'Tarayıcı', 'Downloads': 'İndirilenler', 'Library': 'Kitaplık',
      'Settings': 'Ayarlar', 'Search movies...': 'Film ara...', 'Trending Movies': 'Trend Filmler',
      'Top 10 Today': 'Bugünün İlk 10’u', 'Continue Watching': 'İzlemeye Devam Et', 'Latest Trailers': 'Son Fragmanlar',
      'Play': 'Oynat', 'Download': 'İndir', 'My List': 'Listem', 'Refresh': 'Yenile',
      'All': 'Tümü', 'Series': 'Diziler', 'Retry': 'Yeniden dene', 'Share': 'Paylaş',
      'Watch Later': 'Daha Sonra İzle', 'History': 'Geçmiş', 'Theme': 'Tema', 'Language': 'Dil',
    },
    'ha': {
      'Movies': 'Fina-finai', 'Browser': 'Mai bincike', 'Downloads': 'Abubuwan da aka sauke', 'Library': 'Laburare',
      'Settings': 'Saituna', 'Search movies...': 'Nemo fim...', 'Trending Movies': 'Fina-finai masu tasowa',
      'Top 10 Today': 'Manyan 10 na yau', 'Continue Watching': 'Ci gaba da kallo', 'Latest Trailers': 'Sabbin tallan fim',
      'Play': 'Kunna', 'Download': 'Sauke', 'My List': 'Jerin nawa', 'Refresh': 'Sabunta',
      'All': 'Duka', 'Series': 'Jerin shirye-shirye', 'Retry': 'Sake gwadawa', 'Share': 'Raba',
      'Watch Later': 'Kallo daga baya', 'History': 'Tarihi', 'Theme': 'Jigo', 'Language': 'Harshe',
    },
    'yo': {
      'Movies': 'Àwọn fíìmù', 'Browser': 'Ẹ̀rọ aṣàwárí', 'Downloads': 'Àwọn ìgbàsílẹ̀', 'Library': 'Ilé ìkàwé',
      'Settings': 'Ètò', 'Search movies...': 'Wá fíìmù...', 'Trending Movies': 'Àwọn fíìmù tó gbajúmọ̀',
      'Top 10 Today': 'Àwọn mẹ́wàá tó ga jù lónìí', 'Continue Watching': 'Tẹ̀ síwájú wíwo', 'Latest Trailers': 'Àwọn ìpolówó tuntun',
      'Play': 'Ṣeré', 'Download': 'Gba sílẹ̀', 'My List': 'Àkójọ mi', 'Refresh': 'Tún ṣe',
      'All': 'Gbogbo', 'Series': 'Àwọn eré tó tẹ̀lé ara wọn', 'Retry': 'Gbìyànjú lẹ́ẹ̀kansi', 'Share': 'Pín',
      'Watch Later': 'Wo nígbà míì', 'History': 'Ìtàn', 'Theme': 'Àwòrán', 'Language': 'Èdè',
    },
  };
}

extension DamiTranslation on String {
  String get tr => AppPreferences.instance.translate(this);
}
