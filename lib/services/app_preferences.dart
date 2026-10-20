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
class AppPreferences extends ChangeNotifier with WidgetsBindingObserver {
  AppPreferences._() { WidgetsBinding.instance.addObserver(this); }

  @override
  void didChangeLocales(List<Locale>? locales) {
    if (_language == systemLanguage) notifyListeners();
  }
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

  static const String systemLanguage = 'System Default (Automatic)';
  static const List<String> languages = [
    systemLanguage,
    'English', 'Arabic', 'French', 'Spanish', 'Portuguese', 'Hindi', 'Turkish', 'Hausa', 'Yoruba'
  ];

  int _themeIndex = 1;
  String _language = systemLanguage;
  bool _adShield = true;
  bool _lowQuality = false;
  bool _keepScreenAwake = true;
  bool _backgroundPlayback = true;
  bool _loaded = false;

  DamiPalette get palette => palettes[_themeIndex.clamp(0, palettes.length - 1).toInt()];
  int get themeIndex => _themeIndex;
  String get language => _language;
  String get languageCode => _language == systemLanguage
      ? _deviceLanguageCode
      : (const {
    'English': 'en', 'Arabic': 'ar', 'French': 'fr', 'Spanish': 'es',
    'Portuguese': 'pt', 'Hindi': 'hi', 'Turkish': 'tr', 'Hausa': 'ha', 'Yoruba': 'yo'
  }[_language] ?? 'en');

  String get _deviceLanguageCode {
    const supported = {'en', 'ar', 'fr', 'es', 'pt', 'hi', 'tr', 'ha', 'yo'};
    final locales = WidgetsBinding.instance.platformDispatcher.locales;
    for (final locale in locales) {
      if (supported.contains(locale.languageCode.toLowerCase())) {
        return locale.languageCode.toLowerCase();
      }
    }
    return 'en';
  }
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
    _language = languages.contains(lang) ? lang : systemLanguage;
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
    return _translations[code]?[english] ?? _extraTranslations[code]?[english] ?? english;
  }

  static const Map<String, Map<String, String>> _extraTranslations = {
    'ar': {
      'My profile': 'ملفي الشخصي',
      'Log out': 'تسجيل الخروج',
      'Watch Together': 'المشاهدة معًا',
      'Ratings': 'التقييمات',
      'Watch history': 'سجل المشاهدة',
      'Interests': 'الاهتمامات',
      'Watchlist': 'قائمة المشاهدة',
      'Reviews': 'المراجعات',
      'Badges': 'الشارات',
      'Lists': 'القوائم',
      'Check-ins': 'تسجيلات المشاهدة',
      'Favorite people': 'الأشخاص المفضلون',
      'Posts': 'المنشورات',
      'Likes received': 'الإعجابات المستلمة',
      'Edit profile': 'تعديل الملف الشخصي',
      'Change photo': 'تغيير الصورة',
      'Save': 'حفظ',
      'Cancel': 'إلغاء',
      'Home': 'الرئيسية',
      'Community': 'المجتمع',
      'Profile': 'الملف الشخصي',
      'Search': 'البحث',
      'Notifications': 'الإشعارات',
      'About': 'حول',
      'Check for updates': 'التحقق من التحديثات',
    },
    'fr': {
      'My profile': 'Mon profil',
      'Log out': 'Déconnexion',
      'Watch Together': 'Regarder ensemble',
      'Ratings': 'Notes',
      'Watch history': 'Historique de visionnage',
      'Interests': 'Centres d’intérêt',
      'Watchlist': 'Liste à regarder',
      'Reviews': 'Avis',
      'Badges': 'Badges',
      'Lists': 'Listes',
      'Check-ins': 'Enregistrements',
      'Favorite people': 'Personnes favorites',
      'Posts': 'Publications',
      'Likes received': 'J’aime reçus',
      'Edit profile': 'Modifier le profil',
      'Change photo': 'Changer la photo',
      'Save': 'Enregistrer',
      'Cancel': 'Annuler',
      'Home': 'Accueil',
      'Community': 'Communauté',
      'Profile': 'Profil',
      'Search': 'Recherche',
      'Notifications': 'Notifications',
      'About': 'À propos',
      'Check for updates': 'Vérifier les mises à jour',
    },
    'es': {
      'My profile': 'Mi perfil',
      'Log out': 'Cerrar sesión',
      'Watch Together': 'Ver juntos',
      'Ratings': 'Calificaciones',
      'Watch history': 'Historial de reproducción',
      'Interests': 'Intereses',
      'Watchlist': 'Lista de seguimiento',
      'Reviews': 'Reseñas',
      'Badges': 'Insignias',
      'Lists': 'Listas',
      'Check-ins': 'Registros',
      'Favorite people': 'Personas favoritas',
      'Posts': 'Publicaciones',
      'Likes received': 'Me gusta recibidos',
      'Edit profile': 'Editar perfil',
      'Change photo': 'Cambiar foto',
      'Save': 'Guardar',
      'Cancel': 'Cancelar',
      'Home': 'Inicio',
      'Community': 'Comunidad',
      'Profile': 'Perfil',
      'Search': 'Buscar',
      'Notifications': 'Notificaciones',
      'About': 'Acerca de',
      'Check for updates': 'Buscar actualizaciones',
    },
    'pt': {
      'My profile': 'Meu perfil',
      'Log out': 'Sair',
      'Watch Together': 'Assistir juntos',
      'Ratings': 'Avaliações',
      'Watch history': 'Histórico de visualização',
      'Interests': 'Interesses',
      'Watchlist': 'Lista para assistir',
      'Reviews': 'Críticas',
      'Badges': 'Emblemas',
      'Lists': 'Listas',
      'Check-ins': 'Check-ins',
      'Favorite people': 'Pessoas favoritas',
      'Posts': 'Publicações',
      'Likes received': 'Curtidas recebidas',
      'Edit profile': 'Editar perfil',
      'Change photo': 'Alterar foto',
      'Save': 'Salvar',
      'Cancel': 'Cancelar',
      'Home': 'Início',
      'Community': 'Comunidade',
      'Profile': 'Perfil',
      'Search': 'Pesquisar',
      'Notifications': 'Notificações',
      'About': 'Sobre',
      'Check for updates': 'Verificar atualizações',
    },
    'hi': {
      'My profile': 'मेरी प्रोफ़ाइल',
      'Log out': 'लॉग आउट',
      'Watch Together': 'साथ में देखें',
      'Ratings': 'रेटिंग',
      'Watch history': 'देखने का इतिहास',
      'Interests': 'रुचियाँ',
      'Watchlist': 'वॉचलिस्ट',
      'Reviews': 'समीक्षाएँ',
      'Badges': 'बैज',
      'Lists': 'सूचियाँ',
      'Check-ins': 'चेक-इन',
      'Favorite people': 'पसंदीदा लोग',
      'Posts': 'पोस्ट',
      'Likes received': 'प्राप्त लाइक',
      'Edit profile': 'प्रोफ़ाइल संपादित करें',
      'Change photo': 'फ़ोटो बदलें',
      'Save': 'सहेजें',
      'Cancel': 'रद्द करें',
      'Home': 'होम',
      'Community': 'समुदाय',
      'Profile': 'प्रोफ़ाइल',
      'Search': 'खोज',
      'Notifications': 'सूचनाएँ',
      'About': 'परिचय',
      'Check for updates': 'अपडेट जाँचें',
    },
    'tr': {
      'My profile': 'Profilim',
      'Log out': 'Çıkış yap',
      'Watch Together': 'Birlikte izle',
      'Ratings': 'Puanlar',
      'Watch history': 'İzleme geçmişi',
      'Interests': 'İlgi alanları',
      'Watchlist': 'İzleme listesi',
      'Reviews': 'Yorumlar',
      'Badges': 'Rozetler',
      'Lists': 'Listeler',
      'Check-ins': 'Girişler',
      'Favorite people': 'Favori kişiler',
      'Posts': 'Gönderiler',
      'Likes received': 'Alınan beğeniler',
      'Edit profile': 'Profili düzenle',
      'Change photo': 'Fotoğrafı değiştir',
      'Save': 'Kaydet',
      'Cancel': 'İptal',
      'Home': 'Ana sayfa',
      'Community': 'Topluluk',
      'Profile': 'Profil',
      'Search': 'Ara',
      'Notifications': 'Bildirimler',
      'About': 'Hakkında',
      'Check for updates': 'Güncellemeleri kontrol et',
    },
    'ha': {
      'My profile': 'Bayanan martaba',
      'Log out': 'Fita',
      'Watch Together': 'Kalla tare',
      'Ratings': 'Ƙimantawa',
      'Watch history': 'Tarihin kallo',
      'Interests': 'Abubuwan sha’awa',
      'Watchlist': 'Jerin kallo',
      'Reviews': 'Sharhi',
      'Badges': 'Lambobin yabo',
      'Lists': 'Jerin abubuwa',
      'Check-ins': 'Rajista',
      'Favorite people': 'Mutanen da aka fi so',
      'Posts': 'Saƙonni',
      'Likes received': 'So da aka samu',
      'Edit profile': 'Gyara bayanai',
      'Change photo': 'Canza hoto',
      'Save': 'Ajiye',
      'Cancel': 'Soke',
      'Home': 'Gida',
      'Community': 'Al’umma',
      'Profile': 'Bayanan martaba',
      'Search': 'Bincika',
      'Notifications': 'Sanarwa',
      'About': 'Game da',
      'Check for updates': 'Duba sabuntawa',
    },
    'yo': {
      'My profile': 'Profaili mi',
      'Log out': 'Jáde',
      'Watch Together': 'Wo papọ̀',
      'Ratings': 'Ìdájọ́',
      'Watch history': 'Ìtàn wíwo',
      'Interests': 'Àwọn ìfẹ́',
      'Watchlist': 'Àkójọ wíwo',
      'Reviews': 'Àwọn àtúnyẹ̀wò',
      'Badges': 'Àwọn àmì-ẹ̀yẹ',
      'Lists': 'Àwọn àkójọ',
      'Check-ins': 'Àwọn ìforúkọsílẹ̀',
      'Favorite people': 'Àwọn ènìyàn ayanfẹ́',
      'Posts': 'Àwọn ìfìwéránṣẹ́',
      'Likes received': 'Àwọn ìfẹ́ tí a gba',
      'Edit profile': 'Ṣàtúnṣe profaili',
      'Change photo': 'Yí fọ́tò padà',
      'Save': 'Fipamọ́',
      'Cancel': 'Fagilé',
      'Home': 'Ilé',
      'Community': 'Àwùjọ',
      'Profile': 'Profaili',
      'Search': 'Wá',
      'Notifications': 'Ìfitónilétí',
      'About': 'Nípa',
      'Check for updates': 'Ṣàyẹ̀wò ìmúdójúìwọ̀n',
    },
  };

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
