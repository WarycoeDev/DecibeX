import 'package:flutter/material.dart';

/// Language preference stored by DecibeX.
enum AppLanguage { system, spanish, english }

class AppLocalizations {
  AppLocalizations(this.locale) : _strings = _catalog[_languageFor(locale)]!;

  final Locale locale;
  final Map<String, String> _strings;
  static const supportedLocales = [Locale('es'), Locale('en')];

  static Locale resolve(AppLanguage preference, Locale systemLocale) {
    if (preference == AppLanguage.english) return const Locale('en');
    if (preference == AppLanguage.spanish) return const Locale('es');
    return systemLocale.languageCode.toLowerCase().startsWith('es')
        ? const Locale('es')
        : const Locale('en');
  }

  static AppLanguage languageFrom(String? value) =>
      AppLanguage.values.firstWhere(
        (item) => item.name == value,
        orElse: () => AppLanguage.system,
      );

  static String _languageFor(Locale locale) =>
      locale.languageCode.toLowerCase().startsWith('es') ? 'es' : 'en';

  String get(String key, [Map<String, Object?> values = const {}]) {
    var value = _strings[key] ?? _catalog['en']![key] ?? key;
    for (final entry in values.entries) {
      value = value.replaceAll('{${entry.key}}', '${entry.value}');
    }
    return value;
  }

  String get appName => 'DecibeX';
  String get home => get('home');
  String get library => get('library');
  String get search => get('search');
  String get settings => get('settings');
  String get mainMenu => get('mainMenu');
  String get close => get('close');
  String get cancel => get('cancel');
  String get accept => get('accept');
  String get delete => get('delete');
  String get create => get('create');
  String get save => get('save');
  String get language => get('language');
  String get systemLanguage => get('systemLanguage');
  String get spanish => get('spanish');
  String get english => get('english');
  String get appearance => get('appearance');
  String get appearanceSubtitle => get('appearanceSubtitle');
  String get darkTheme => get('darkTheme');
  String get darkThemeOn => get('darkThemeOn');
  String get darkThemeOff => get('darkThemeOff');
  String get accentColor => get('accentColor');
  String get accentColorSubtitle => get('accentColorSubtitle');
  String get audio => get('audio');
  String get audioSubtitle => get('audioSubtitle');
  String get music => get('music');
  String get podcasts => get('podcasts');
  String get playlists => get('playlists');
  String get favorites => get('favorites');
  String get artists => get('artists');
  String get albums => get('albums');
  String get songs => get('songs');
  String get all => get('all');
  String get noResults => get('noResults');
  String get noSongs => get('noSongs');
  String get noArtists => get('noArtists');
  String get noAlbums => get('noAlbums');
  String get noPodcasts => get('noPodcasts');
  String get queueEmpty => get('queueEmpty');
  String get play => get('play');
  String get pause => get('pause');
  String get previous => get('previous');
  String get next => get('next');
  String get moreOptions => get('moreOptions');
  String get configuration => get('configuration');
  String get personalization => get('personalization');
  String get listeningDescription => get('listeningDescription');
  String get resetSettings => get('resetSettings');
  String get localConfiguration => get('localConfiguration');
  String get overwriteQueue => get('overwriteQueue');
  String get addAllToQueue => get('addAllToQueue');
  String get playAll => get('playAll');
  String get mostPlayed => get('mostPlayed');
  String get mostPlayedSubtitle => get('mostPlayedSubtitle');
  String get yourFavorites => get('yourFavorites');
  String get yourFavoritesSubtitle => get('yourFavoritesSubtitle');
  String get configureLibrary => get('configureLibrary');
  String get configureLibrarySubtitle => get('configureLibrarySubtitle');
  String get noSongsYet => get('noSongsYet');
  String get scanLibrarySubtitle => get('scanLibrarySubtitle');
  String get noPlayedSongs => get('noPlayedSongs');
  String get markFavoritesSubtitle => get('markFavoritesSubtitle');
  String get searchYoutubeHint => get('searchYoutubeHint');
  String get searchYoutube => get('searchYoutube');
  String get clear => get('clear');
  String get download => get('download');
  String get chooseFolder => get('chooseFolder');
  String get selectLocation => get('selectLocation');
  String get downloadFolder => get('downloadFolder');
  String get downloadFormat => get('downloadFormat');
  String get compressedCompatible => get('compressedCompatible');
  String get losslessAudio => get('losslessAudio');
  String get uncompressedAudio => get('uncompressedAudio');
  String get typePlaylistName => get('typePlaylistName');
  String get playlistName => get('playlistName');
  String get addSelected => get('addSelected');
  String get addSongs => get('addSongs');
  String get rename => get('rename');
  String get export => get('export');
  String get importPlaylist => get('importPlaylist');
  String get newPlaylist => get('newPlaylist');
  String get noPlaylists => get('noPlaylists');
  String get emptyPlaylist => get('emptyPlaylist');
  String get favoritesQueue => get('favoritesQueue');
  String get playbackQueue => get('playbackQueue');
  String get shuffle => get('shuffle');
  String get repeatOff => get('repeatOff');
  String get repeatSong => get('repeatSong');
  String get repeatQueue => get('repeatQueue');
  String get back => get('back');

  // ── HomeScreen ──
  String get yourMusicalSpace => get('yourMusicalSpace');
  String get yourMusicYourWay => get('yourMusicYourWay');
  String get everythingYouLove => get('everythingYouLove');
  String get noFavoritesYet => get('noFavoritesYet');
  String get playSongToAppear => get('playSongToAppear');

  // ── LibraryScreen: header ──
  String get yourCollection => get('yourCollection');
  String get yourLibrary => get('yourLibrary');
  String get libraryDescription => get('libraryDescription');
  String get scanPending => get('scanPending');
  String get scanNow => get('scanNow');
  String lastScanAt(Object date) => get('lastScanAt', {'date': date});

  // ── LibraryScreen: section titles ──
  String get unknown => get('unknown');
  String get allSongs => get('allSongs');
  String get yourPodcasts => get('yourPodcasts');
  String get yourPlaylists => get('yourPlaylists');
  String get yourArtists => get('yourArtists');
  String get yourAlbums => get('yourAlbums');
  String get playlist => get('playlist');

  // ── LibraryScreen: section subtitles ──
  String nSongsFromArtist(int n) => get('nSongsFromArtist', {'count': n});
  String nSongsFromAlbum(int n) => get('nSongsFromAlbum', {'count': n});
  String nEpisodesFromPodcast(int n) =>
      get('nEpisodesFromPodcast', {'count': n});
  String nSongsInCollection(int n) => get('nSongsInCollection', {'count': n});
  String nPodcastsInCollection(int n) =>
      get('nPodcastsInCollection', {'count': n});
  String nPlaylistsInCollection(int n) =>
      get('nPlaylistsInCollection', {'count': n});
  String nSongsAvailable(int n) => get('nSongsAvailable', {'count': n});
  String nFavoriteItems(int n) => get('nFavoriteItems', {'count': n});
  String nArtistsInCollection(int n) =>
      get('nArtistsInCollection', {'count': n});
  String nAlbumsInCollection(int n) => get('nAlbumsInCollection', {'count': n});
  String nSongs(int n) => get('nSongs', {'count': n});

  // ── LibraryScreen: acciones ──
  String get finishReordering => get('finishReordering');
  String get reorderFavorites => get('reorderFavorites');
  String get resume => get('resume');
  String get addToQueue => get('addToQueue');
  String get addPlaylist => get('addPlaylist');
  String get listView => get('listView');
  String get gridView => get('gridView');

  // ── LibraryScreen: playlist ──
  String get createPlaylist => get('createPlaylist');
  String get newPlaylistSubtitle => get('newPlaylistSubtitle');
  String get renamePlaylist => get('renamePlaylist');
  String renamePlaylistSubtitle(Object name) =>
      get('renamePlaylistSubtitle', {'name': name});
  String get exportPlaylist => get('exportPlaylist');
  String get deletePlaylist => get('deletePlaylist');
  String get songSingular => get('songSingular');
  String get songsPlural => get('songsPlural');
  String get deletePlaylistWarning => get('deletePlaylistWarning');
  String addSongsToPlaylist(Object name) =>
      get('addSongsToPlaylist', {'name': name});
  String get noSongsAvailableInLibrary => get('noSongsAvailableInLibrary');
  String get playlistOptions => get('playlistOptions');
  String missingSongsInPlaylist(int count) =>
      get('missingSongsInPlaylist', {'count': count});

  // ── LibraryScreen: empty states ──
  String get noPlaylistsYet => get('noPlaylistsYet');
  String get noPlaylistsMessage => get('noPlaylistsMessage');
  String get playlistNotAvailable => get('playlistNotAvailable');
  String get playlistNotAvailableMessage => get('playlistNotAvailableMessage');
  String get emptyPlaylistMessage => get('emptyPlaylistMessage');
  String get emptyPlaylistAddSongsHint => get('emptyPlaylistAddSongsHint');
  String get noPodcastsYet => get('noPodcastsYet');
  String get noPodcastsMessage => get('noPodcastsMessage');
  String get noPodcastEpisodes => get('noPodcastEpisodes');
  String get noPodcastEpisodesMessage => get('noPodcastEpisodesMessage');
  String get markFavoritesOrEpisodes => get('markFavoritesOrEpisodes');
  String get noSongsFromArtist => get('noSongsFromArtist');
  String get noSongsFromAlbum => get('noSongsFromAlbum');
  String get libraryEmpty => get('libraryEmpty');
  String get songsWillAppearHere => get('songsWillAppearHere');
  String get libraryEmptyMessage => get('libraryEmptyMessage');

  // ── SearchScreen ──
  String get searchScreen => get('searchScreen');
  String get searchYoutubeMode => get('searchYoutubeMode');
  String get findYourMusic => get('findYourMusic');
  String get exploreAndDownload => get('exploreAndDownload');
  String get searchTitle => get('searchTitle');
  String get searchYoutubeDescription => get('searchYoutubeDescription');
  String get searchLibraryDescription => get('searchLibraryDescription');
  String get searchLibraryHint => get('searchLibraryHint');
  String get filterAll => get('filterAll');
  String get filterSongs => get('filterSongs');
  String get filterArtists => get('filterArtists');
  String get filterAlbums => get('filterAlbums');
  String get filterPodcasts => get('filterPodcasts');
  String get filterYoutube => get('filterYoutube');
  String get searchNoResultsTitle => get('searchNoResultsTitle');
  String get searchTryOtherWords => get('searchTryOtherWords');
  String get searchOnYoutubeTitle => get('searchOnYoutubeTitle');
  String get searchOnYoutubeMessage => get('searchOnYoutubeMessage');
  String get searchStartTypingTitle => get('searchStartTypingTitle');
  String get searchStartTypingMessage => get('searchStartTypingMessage');
  String get searchNoSongsTitle => get('searchNoSongsTitle');
  String searchNoSongsMessage(Object query) =>
      get('searchNoSongsMessage', {'query': query});
  String get searchNoArtistsTitle => get('searchNoArtistsTitle');
  String searchNoArtistsMessage(Object query) =>
      get('searchNoArtistsMessage', {'query': query});
  String get searchNoAlbumsTitle => get('searchNoAlbumsTitle');
  String searchNoAlbumsMessage(Object query) =>
      get('searchNoAlbumsMessage', {'query': query});
  String get searchNoPodcastsTitle => get('searchNoPodcastsTitle');
  String searchNoPodcastsMessage(Object query) =>
      get('searchNoPodcastsMessage', {'query': query});
  String searchNoResultsMessage(Object query) =>
      get('searchNoResultsMessage', {'query': query});
  String get searchYoutubeError => get('searchYoutubeError');
  String searchYoutubeErrorDetail(Object error) =>
      get('searchYoutubeErrorDetail', {'error': error});
  String get searchYoutubeNoMoreResults => get('searchYoutubeNoMoreResults');
  String searchYoutubeLoadMoreError(Object error) =>
      get('searchYoutubeLoadMoreError', {'error': error});
  String get searchLoadMore => get('searchLoadMore');
  String get searchLoadingMore => get('searchLoadingMore');
  String get openDetailOf => get('openDetailOf');
  String openDetailOfTitle(Object title) =>
      get('openDetailOfTitle', {'title': title});

  // ── YouTube download dialogs ──
  String get ytDownloadTitle => get('ytDownloadTitle');
  String get ytDownloadDirectory => get('ytDownloadDirectory');
  String get ytFileName => get('ytFileName');
  String get ytFileNameHint => get('ytFileNameHint');
  String get ytChooseValidFileName => get('ytChooseValidFileName');
  String get ytChooseFolderFirst => get('ytChooseFolderFirst');
  String get ytPreparingDownloader => get('ytPreparingDownloader');
  String get ytPreparingDownloaderSubtitle =>
      get('ytPreparingDownloaderSubtitle');
  String get ytDownloading => get('ytDownloading');
  String get ytDownloadingStatus => get('ytDownloadingStatus');
  String get ytDownloadCompleted => get('ytDownloadCompleted');
  String get ytDownloadFailed => get('ytDownloadFailed');
  String get ytDownloadFailedSubtitle => get('ytDownloadFailedSubtitle');
  String get ytUnexpectedError => get('ytUnexpectedError');
  String get ytFileSavedSuccessfully => get('ytFileSavedSuccessfully');
  String get ytDoNotClose => get('ytDoNotClose');
  String get ytAndroidOnly => get('ytAndroidOnly');
  String get ytInitializeFailed => get('ytInitializeFailed');
  String get ytDownloadAudioStatus => get('ytDownloadAudioStatus');
  String get ytDownloadFinishedNoFile => get('ytDownloadFinishedNoFile');
  String get ytDownloadErrorMessage => get('ytDownloadErrorMessage');
  String get ytDownloadClose => get('ytDownloadClose');
  String get ytDownloadDone => get('ytDownloadDone');

  // ── SettingsScreen ──
  String get settingsAppearanceTitle => get('settingsAppearanceTitle');
  String get settingsAppearanceSubtitle => get('settingsAppearanceSubtitle');
  String get settingsAudioTitle => get('settingsAudioTitle');
  String get settingsAudioSubtitle => get('settingsAudioSubtitle');
  String get settingsLibraryTitle => get('settingsLibraryTitle');
  String get settingsLibrarySubtitle => get('settingsLibrarySubtitle');
  String get settingsAboutTitle => get('settingsAboutTitle');
  String get settingsAboutSubtitle => get('settingsAboutSubtitle');
  String get settingsSaveError => get('settingsSaveError');
  String get settingsResetTitle => get('settingsResetTitle');
  String get settingsResetMessage => get('settingsResetMessage');
  String get settingsResetConfirm => get('settingsResetConfirm');
  String get settingsResetButton => get('settingsResetButton');
  String get accentViolet => get('accentViolet');
  String get accentBlue => get('accentBlue');
  String get accentCyan => get('accentCyan');
  String get accentGreen => get('accentGreen');
  String get accentOrange => get('accentOrange');
  String get accentPink => get('accentPink');
  String get accentRed => get('accentRed');
  String get accentCustom => get('accentCustom');
  String get replayGainTitle => get('replayGainTitle');
  String get replayGainSubtitle => get('replayGainSubtitle');
  String get replayGainPreampTitle => get('replayGainPreampTitle');
  String get replayGainPreampSubtitle => get('replayGainPreampSubtitle');
  String get replayGainAnalyzerTitle => get('replayGainAnalyzerTitle');
  String get replayGainAnalyzerSubtitle => get('replayGainAnalyzerSubtitle');
  String get replayGainAnalyzeButton => get('replayGainAnalyzeButton');
  String get replayGainReanalyzeTooltip => get('replayGainReanalyzeTooltip');
  String get replayGainClearTooltip => get('replayGainClearTooltip');
  String get replayGainCalculating => get('replayGainCalculating');
  String get replayGainNoPending => get('replayGainNoPending');
  String get replayGainCompleted => get('replayGainCompleted');
  String get replayGainAnalyzingProgress => get('replayGainAnalyzingProgress');
  String get replayGainNoPendingSubtitle => get('replayGainNoPendingSubtitle');
  String get replayGainCompletedSubtitle => get('replayGainCompletedSubtitle');
  String get replayGainNormalizationPerTrack =>
      get('replayGainNormalizationPerTrack');
  String get replayGainNoPendingInfo => get('replayGainNoPendingInfo');
  String get replayGainGainsSaved => get('replayGainGainsSaved');
  String get replayGainProgressTitle => get('replayGainProgressTitle');
  String get replayGainReady => get('replayGainReady');
  String get replayGainCompletedShort => get('replayGainCompletedShort');
  String get replayGainTracksFormat => get('replayGainTracksFormat');
  String get replayGainTracksProcessed => get('replayGainTracksProcessed');
  String get replayGainInProgress => get('replayGainInProgress');
  String get replayGainStop => get('replayGainStop');
  String get replayGainReanalyzeTitle => get('replayGainReanalyzeTitle');
  String get replayGainReanalyzeSubtitle => get('replayGainReanalyzeSubtitle');
  String get replayGainReanalyzeWarning => get('replayGainReanalyzeWarning');
  String get replayGainReanalyzeInfo => get('replayGainReanalyzeInfo');
  String get replayGainReanalyzeButton => get('replayGainReanalyzeButton');
  String get replayGainClearTitle => get('replayGainClearTitle');
  String get replayGainClearSubtitle => get('replayGainClearSubtitle');
  String get replayGainClearWarning => get('replayGainClearWarning');
  String get replayGainClearInfo => get('replayGainClearInfo');
  String get replayGainClearButton => get('replayGainClearButton');
  String get fadeInTitle => get('fadeInTitle');
  String get fadeInSubtitle => get('fadeInSubtitle');
  String get fadeInDurationTitle => get('fadeInDurationTitle');
  String get fadeInDurationSubtitle => get('fadeInDurationSubtitle');
  String get fadeOutTitle => get('fadeOutTitle');
  String get fadeOutSubtitle => get('fadeOutSubtitle');
  String get fadeOutDurationTitle => get('fadeOutDurationTitle');
  String get fadeOutDurationSubtitle => get('fadeOutDurationSubtitle');
  String get includeSubdirectoriesTitle => get('includeSubdirectoriesTitle');
  String get includeSubdirectoriesSubtitle =>
      get('includeSubdirectoriesSubtitle');
  String get musicDirectoriesTitle => get('musicDirectoriesTitle');
  String get musicDirectoriesSubtitle => get('musicDirectoriesSubtitle');
  String get podcastDirectoriesTitle => get('podcastDirectoriesTitle');
  String get podcastDirectoriesSubtitle => get('podcastDirectoriesSubtitle');
  String get addMusicDirectoryTooltip => get('addMusicDirectoryTooltip');
  String get addPodcastDirectoryTooltip => get('addPodcastDirectoryTooltip');
  String get removeDirectoryTooltip => get('removeDirectoryTooltip');
  String get selectMusicDirectoryDialog => get('selectMusicDirectoryDialog');
  String get selectPodcastDirectoryDialog =>
      get('selectPodcastDirectoryDialog');
  String get directoryAlreadyAddedMusic => get('directoryAlreadyAddedMusic');
  String get directoryAlreadyAddedPodcast =>
      get('directoryAlreadyAddedPodcast');
  String directoryPickErrorMusic(Object error) =>
      get('directoryPickErrorMusic', {'error': error});
  String directoryPickErrorPodcast(Object error) =>
      get('directoryPickErrorPodcast', {'error': error});
  String get noMusicDirectories => get('noMusicDirectories');
  String get noPodcastDirectories => get('noPodcastDirectories');
  String get noMusicDirectoriesHint => get('noMusicDirectoriesHint');
  String get noPodcastDirectoriesHint => get('noPodcastDirectoriesHint');
  String get aboutAppName => get('aboutAppName');
  String get aboutAppTagline => get('aboutAppTagline');
  String get aboutVersion => get('aboutVersion');
  String get aboutDescription => get('aboutDescription');
  String get aboutLicenses => get('aboutLicenses');
  String get aboutLicensesSubtitle => get('aboutLicensesSubtitle');
  String get aboutMadeWithFlutter => get('aboutMadeWithFlutter');
  String get aboutCopyright => get('aboutCopyright');

  String get removeFromQueue => get('removeFromQueue');
  String get removeFromFavorites => get('removeFromFavorites');
  String get addToFavorites => get('addToFavorites');
  String get playlistsSection => get('playlistsSection');
  String nSelected(int count) => get('nSelected', {'count': count});

  String get playback => get('playback');
  String get playbackOptions => get('playbackOptions');
  String get repeatSection => get('repeatSection');
  String get nowPlaying => get('nowPlaying');
  String get minimizePlayer => get('minimizePlayer');
  String get closePlayerAndStop => get('closePlayerAndStop');
  String get dragToReorder => get('dragToReorder');
  String get tapSongToPlay => get('tapSongToPlay');
  String get nothingPlaying => get('nothingPlaying');
  String get selectSongToStart => get('selectSongToStart');
  String get unknownArtist => get('unknownArtist');
  String get unknownAlbum => get('unknownAlbum');
  String libraryInitError(Object error) =>
      get('libraryInitError', {'error': error});
  String get configFileNotFound => get('configFileNotFound');
  String configUpdateError(Object error) =>
      get('configUpdateError', {'error': error});
  String get scanPartialWarning => get('scanPartialWarning');
  String scanError(Object error) => get('scanError', {'error': error});
  String favoriteSaveError(Object error) =>
      get('favoriteSaveError', {'error': error});
  String get audioNotificationChannelName =>
      get('audioNotificationChannelName');
  String get audioNotificationChannelDescription =>
      get('audioNotificationChannelDescription');
  String get effects => get('effects');
  String get slowedEffect => get('slowedEffect');
  String get reverbEffect => get('reverbEffect');
  String get reverbAndroidOnly => get('reverbAndroidOnly');

  static const Map<String, Map<String, String>> _catalog = {
    'es': {
      'audioNotificationChannelName': 'Reproducción de audio',
      'audioNotificationChannelDescription':
          'Controles de reproducción de DecibeX',
      'home': 'Inicio',
      'library': 'Biblioteca',
      'search': 'Buscar',
      'settings': 'Configuración',
      'mainMenu': 'MENÚ PRINCIPAL',
      'close': 'Cerrar',
      'cancel': 'Cancelar',
      'accept': 'Aceptar',
      'delete': 'Borrar',
      'create': 'Crear',
      'save': 'Guardar',
      'language': 'Idioma',
      'systemLanguage': 'Idioma del sistema',
      'spanish': 'Español',
      'english': 'Inglés',
      'appearance': 'Apariencia',
      'appearanceSubtitle': 'Personaliza el aspecto de DecibeX.',
      'darkTheme': 'Tema oscuro',
      'darkThemeOn': 'La interfaz está configurada en oscuro.',
      'darkThemeOff': 'La interfaz está configurada en claro.',
      'accentColor': 'Color de acento',
      'accentColorSubtitle': 'Selecciona el color principal de la interfaz.',
      'audio': 'Audio',
      'audioSubtitle': 'Preferencias de reproducción y sonido.',
      'music': 'Música',
      'podcasts': 'Podcasts',
      'playlists': 'Playlists',
      'favorites': 'Favoritos',
      'artists': 'Artistas',
      'albums': 'Álbumes',
      'songs': 'Canciones',
      'all': 'Todo',
      'noResults': 'Sin resultados',
      'noSongs': 'Sin canciones',
      'noArtists': 'Sin artistas',
      'noAlbums': 'Sin álbumes',
      'noPodcasts': 'Sin podcasts',
      'queueEmpty': 'La cola está vacía',
      'play': 'Reproducir',
      'pause': 'Pausar',
      'previous': 'Anterior',
      'next': 'Siguiente',
      'moreOptions': 'Más opciones',
      'configuration': 'Configuración',
      'personalization': 'PERSONALIZACIÓN',
      'listeningDescription': 'Ajusta tu experiencia de escucha a tu manera.',
      'resetSettings': 'Restablecer configuración',
      'localConfiguration': 'DecibeX · Configuración local',
      'overwriteQueue': 'Sobrescribir cola',
      'addAllToQueue': 'Agregar todos a la cola',
      'playAll': 'Reproducir todo',
      'mostPlayed': 'Más escuchadas',
      'mostPlayedSubtitle': 'Las canciones que más suenan',
      'yourFavorites': 'Tus favoritos',
      'yourFavoritesSubtitle': 'Tu colección personal',
      'configureLibrary': 'Configura tu biblioteca',
      'configureLibrarySubtitle':
          'Agrega una carpeta en Configuración > Biblioteca para empezar.',
      'noSongsYet': 'Aún no hay canciones',
      'scanLibrarySubtitle':
          'Escanea tu biblioteca para empezar a escuchar música.',
      'noPlayedSongs': 'Aún no hay canciones escuchadas',
      'markFavoritesSubtitle':
          'Marca canciones como favoritas para verlas aquí.',
      'searchYoutubeHint': 'Buscar en YouTube...',
      'searchYoutube': 'Buscar',
      'clear': 'Borrar',
      'download': 'Descargar',
      'chooseFolder': 'Elegir carpeta',
      'selectLocation': 'Seleccionar ubicación',
      'downloadFolder': 'Elegir carpeta de descarga',
      'downloadFormat': 'Formato de descarga',
      'compressedCompatible': 'Comprimido y compatible',
      'losslessAudio': 'Audio sin pérdida',
      'uncompressedAudio': 'Audio sin comprimir',
      'typePlaylistName': 'Escribe un nombre',
      'playlistName': 'Nombre de la playlist',
      'addSelected': 'Añadir seleccionadas',
      'addSongs': 'Añadir canciones',
      'rename': 'Renombrar',
      'export': 'Exportar',
      'importPlaylist': 'Importar playlist',
      'newPlaylist': 'Nueva playlist',
      'noPlaylists': 'Todavía no hay playlists',
      'emptyPlaylist': 'Esta playlist está vacía',
      'favoritesQueue': 'Favoritos',
      'playbackQueue': 'Cola',
      'shuffle': 'Reproducción aleatoria',
      'repeatOff': 'No repetir',
      'repeatSong': 'Repetir canción',
      'repeatQueue': 'Repetir cola',
      'back': 'Volver',
      // HomeScreen
      'yourMusicalSpace': 'TU ESPACIO MUSICAL',
      'yourMusicYourWay': 'Tu música, a tu manera.',
      'everythingYouLove': 'Todo lo que te gusta escuchar, en un solo lugar.',
      'noFavoritesYet': 'Todavía no tienes favoritos',
      'playSongToAppear':
          'Reproduce una canción al menos 5 segundos para que aparezca aquí.',
      // LibraryScreen
      'yourCollection': 'TU COLECCIÓN',
      'yourLibrary': 'Tu biblioteca',
      'libraryDescription':
          'Toda tu música y tus podcasts, organizados en un solo lugar.',
      'scanPending': 'Escaneo pendiente',
      'lastScanAt': 'Último escaneo: {date}',
      'scanNow': 'Escanear ahora',
      'unknown': 'Desconocido',
      'allSongs': 'Todas las canciones',
      'yourPodcasts': 'Tus podcasts',
      'yourPlaylists': 'Tus playlists',
      'yourArtists': 'Tus artistas',
      'yourAlbums': 'Tus álbumes',
      'playlist': 'Playlist',
      'nSongsFromArtist': '{count} canciones de este artista',
      'nSongsFromAlbum': '{count} canciones de este álbum',
      'nEpisodesFromPodcast': '{count} episodios de este podcast',
      'nSongsInCollection': '{count} canciones en tu colección',
      'nPodcastsInCollection': '{count} podcasts en tu colección',
      'nPlaylistsInCollection': '{count} playlists en tu colección',
      'nSongsAvailable': '{count} canciones disponibles',
      'nFavoriteItems': '{count} elementos favoritos',
      'nArtistsInCollection': '{count} artistas en tu colección',
      'nAlbumsInCollection': '{count} álbumes en tu colección',
      'nSongs': '{count} canciones',
      'finishReordering': 'Terminar de ordenar',
      'reorderFavorites': 'Reordenar favoritos',
      'resume': 'Reanudar',
      'addToQueue': 'Agregar a la cola',
      'addPlaylist': 'Añadir playlist',
      'listView': 'Vista de lista',
      'gridView': 'Vista de cuadrícula',
      'createPlaylist': 'Crear playlist',
      'newPlaylistSubtitle':
          'Ponle un nombre para empezar a organizar tu música.',
      'renamePlaylist': 'Renombrar playlist',
      'renamePlaylistSubtitle': 'Elige un nuevo nombre para "{name}".',
      'exportPlaylist': 'Exportar playlist',
      'deletePlaylist': 'Eliminar playlist',
      'songSingular': 'canción',
      'songsPlural': 'canciones',
      'deletePlaylistWarning':
          'Los archivos de música no se eliminarán, solo la playlist. Esta acción no se puede deshacer.',
      'addSongsToPlaylist': 'Añadir canciones a {name}',
      'noSongsAvailableInLibrary':
          'No hay canciones disponibles en la biblioteca.',
      'playlistOptions': 'Opciones de playlist',
      'missingSongsInPlaylist':
          '{count} canciones no disponibles en la biblioteca. Sus rutas se conservarán en la playlist.',
      'noPlaylistsYet': 'Todavía no hay playlists',
      'noPlaylistsMessage':
          'Crea o importa una playlist para organizar tus canciones.',
      'playlistNotAvailable': 'Playlist no disponible',
      'playlistNotAvailableMessage': 'La playlist pudo haber sido eliminada.',
      'emptyPlaylistMessage': 'Esta playlist está vacía',
      'emptyPlaylistAddSongsHint':
          'Añade canciones con el botón de añadir canciones de arriba.',
      'noPodcastsYet': 'Todavía no hay podcasts',
      'noPodcastsMessage':
          'Agrega directorios en Configuración > Biblioteca > Podcasts y escanea tus archivos.',
      'noPodcastEpisodes': 'No hay episodios de este podcast',
      'noPodcastEpisodesMessage':
          'Los episodios aparecerán aquí cuando estén disponibles en tu biblioteca.',
      'markFavoritesOrEpisodes':
          'Marca canciones o episodios como favoritos para verlos aquí.',
      'noSongsFromArtist': 'No hay canciones de este artista',
      'noSongsFromAlbum': 'No hay canciones de este álbum',
      'libraryEmpty': 'Tu biblioteca está vacía',
      'songsWillAppearHere':
          'Las canciones aparecerán aquí cuando estén disponibles en tu biblioteca.',
      'libraryEmptyMessage':
          'Agrega directorios en Configuración > Biblioteca y escanea tus archivos.',
      // SearchScreen
      'searchScreen': 'Pantalla de búsqueda',
      'searchYoutubeMode': 'BUSCAR EN YOUTUBE',
      'findYourMusic': 'ENCUENTRA TU MÚSICA',
      'exploreAndDownload': 'Explora y descarga',
      'searchTitle': 'Buscar',
      'searchYoutubeDescription':
          'Busca videos o audio de YouTube y elige el formato de descarga.',
      'searchLibraryDescription':
          'Explora toda tu colección por canción, artista, álbum o podcast.',
      'searchLibraryHint': 'Canciones, artistas, álbumes o podcasts',
      'filterAll': 'Todo',
      'filterSongs': 'Canciones',
      'filterArtists': 'Artistas',
      'filterAlbums': 'Álbumes',
      'filterPodcasts': 'Podcasts',
      'filterYoutube': 'YouTube',
      'searchNoResultsTitle': 'Sin resultados',
      'searchTryOtherWords': 'Prueba con otras palabras.',
      'searchOnYoutubeTitle': 'Buscar en YouTube',
      'searchOnYoutubeMessage':
          'Escribe algo y pulsa Enter para buscar videos o audio en YouTube.',
      'searchStartTypingTitle': 'Empieza a escribir',
      'searchStartTypingMessage':
          'Busca por título, artista, álbum o podcast en toda tu biblioteca.',
      'searchNoSongsTitle': 'Sin canciones',
      'searchNoSongsMessage': 'Ninguna canción coincide con "{query}".',
      'searchNoArtistsTitle': 'Sin artistas',
      'searchNoArtistsMessage': 'Ningún artista coincide con "{query}".',
      'searchNoAlbumsTitle': 'Sin álbumes',
      'searchNoAlbumsMessage': 'Ningún álbum coincide con "{query}".',
      'searchNoPodcastsTitle': 'Sin podcasts',
      'searchNoPodcastsMessage': 'Ningún podcast coincide con "{query}".',
      'searchNoResultsMessage':
          'No encontramos nada que coincida con "{query}".',
      'searchYoutubeError': 'Error al buscar en YouTube',
      'searchYoutubeErrorDetail': 'Error al buscar en YouTube: {error}',
      'searchYoutubeNoMoreResults': 'No hay más resultados.',
      'searchYoutubeLoadMoreError': 'Error al cargar más: {error}',
      'searchLoadMore': 'Buscar más resultados',
      'searchLoadingMore': 'Cargando…',
      'openDetailOf': 'Abrir detalle',
      'openDetailOfTitle': 'Abrir detalle de "{title}"',
      // YouTube download dialogs
      'ytDownloadTitle': 'Descargar',
      'ytDownloadDirectory': 'Directorio de guardado',
      'ytFileName': 'Nombre del archivo',
      'ytFileNameHint': 'Nombre sin extensión',
      'ytChooseValidFileName': 'Escribe un nombre de archivo válido.',
      'ytChooseFolderFirst': 'Elige una carpeta de descarga.',
      'ytPreparingDownloader': 'Preparando descargador',
      'ytPreparingDownloaderSubtitle': 'Esto puede tardar la primera vez',
      'ytDownloading': 'Descargando…',
      'ytDownloadingStatus': 'Descargando audio…',
      'ytDownloadCompleted': 'Descarga completada',
      'ytDownloadFailed': 'No se pudo descargar',
      'ytDownloadFailedSubtitle': 'Ocurrió un error inesperado',
      'ytUnexpectedError': 'Ocurrió un error inesperado.',
      'ytFileSavedSuccessfully': 'Archivo guardado correctamente',
      'ytDoNotClose': 'No cierres esta ventana mientras se descarga.',
      'ytAndroidOnly':
          'La descarga con Extractor solo está habilitada en Android.',
      'ytInitializeFailed':
          'No se pudo inicializar Extractor. Verifica tu conexión a internet.',
      'ytDownloadAudioStatus': 'Descargando audio…',
      'ytDownloadFinishedNoFile':
          'La descarga terminó pero no se encontró el archivo generado.',
      'ytDownloadErrorMessage': 'No se pudo descargar el audio.',
      'ytDownloadClose': 'Cerrar',
      'ytDownloadDone': 'Cerrar',
      // SettingsScreen
      'settingsAppearanceTitle': 'Apariencia',
      'settingsAppearanceSubtitle': 'Personaliza el aspecto de DecibeX.',
      'settingsAudioTitle': 'Audio',
      'settingsAudioSubtitle': 'Preferencias de reproducción y sonido.',
      'settingsLibraryTitle': 'Biblioteca',
      'settingsLibrarySubtitle': 'Configura las carpetas de música y podcasts.',
      'settingsAboutTitle': 'Acerca de DecibeX',
      'settingsAboutSubtitle': 'Información y estado de la configuración.',
      'settingsSaveError': 'No se pudieron guardar los ajustes.',
      'settingsResetTitle': 'Restablecer configuración',
      'settingsResetMessage':
          'Se restaurarán los valores predeterminados de DecibeX. Los directorios de música y podcasts también se eliminarán de sus listas.',
      'settingsResetConfirm': 'Restablecer',
      'settingsResetButton': 'Restablecer',
      'accentViolet': 'Violeta',
      'accentBlue': 'Azul',
      'accentCyan': 'Cian',
      'accentGreen': 'Verde',
      'accentOrange': 'Naranja',
      'accentPink': 'Rosa',
      'accentRed': 'Rojo',
      'accentCustom': 'Personalizado',
      'replayGainTitle': 'ReplayGain',
      'replayGainSubtitle': 'Normalización del volumen entre canciones.',
      'replayGainPreampTitle': 'ReplayGain preamp',
      'replayGainPreampSubtitle': 'Se suma a la ganancia de cada pista.',
      'replayGainAnalyzerTitle': 'Calcular ReplayGain por archivo',
      'replayGainAnalyzerSubtitle':
          'Analiza cada pista y guarda su ganancia en la biblioteca.',
      'replayGainAnalyzeButton': 'Analizar pendientes',
      'replayGainReanalyzeTooltip': 'Reanalizar toda la biblioteca',
      'replayGainClearTooltip': 'Borrar ganancias calculadas',
      'replayGainCalculating': 'Calculando ReplayGain',
      'replayGainNoPending': 'No hay pistas nuevas',
      'replayGainCompleted': 'ReplayGain completado',
      'replayGainAnalyzingProgress': 'Analizando {processed} de {total}…',
      'replayGainNoPendingSubtitle': 'Todas las pistas ya tienen su ganancia.',
      'replayGainCompletedSubtitle': 'Análisis finalizado.',
      'replayGainNormalizationPerTrack': 'Normalización de volumen por pista',
      'replayGainNoPendingInfo': 'No se ha analizado ninguna pista nueva.',
      'replayGainGainsSaved': 'Ganancias guardadas en la biblioteca',
      'replayGainProgressTitle': 'Progreso del análisis',
      'replayGainReady': 'Listo',
      'replayGainCompletedShort': 'Completado',
      'replayGainTracksFormat': '{processed} / {total} pistas',
      'replayGainTracksProcessed': '{total} pistas procesadas',
      'replayGainInProgress': 'En progreso…',
      'replayGainStop': 'Detener',
      'replayGainReanalyzeTitle': 'Reanalizar biblioteca',
      'replayGainReanalyzeSubtitle': 'Se recalcularán todas las ganancias.',
      'replayGainReanalyzeWarning':
          'Puede tardar bastante según el tamaño de tu biblioteca.',
      'replayGainReanalyzeInfo':
          'Las ganancias actuales se sobrescribirán con los nuevos valores calculados.',
      'replayGainReanalyzeButton': 'Reanalizar',
      'replayGainClearTitle': 'Borrar ganancias',
      'replayGainClearSubtitle':
          'Se eliminarán todas las ganancias calculadas.',
      'replayGainClearWarning':
          'Las pistas volverán a sonar sin normalización.',
      'replayGainClearInfo':
          'Esta acción no se puede deshacer. Deberás analizar de nuevo cada pista para recuperar la normalización.',
      'replayGainClearButton': 'Borrar',
      'fadeInTitle': 'Fade in',
      'fadeInSubtitle': 'Aumenta gradualmente el volumen al iniciar.',
      'fadeInDurationTitle': 'Duración del fade in',
      'fadeInDurationSubtitle': 'Tiempo de entrada gradual.',
      'fadeOutTitle': 'Fade out',
      'fadeOutSubtitle': 'Reduce gradualmente el volumen al finalizar.',
      'fadeOutDurationTitle': 'Duración del fade out',
      'fadeOutDurationSubtitle': 'Tiempo de salida gradual.',
      'includeSubdirectoriesTitle': 'Incluir subdirectorios',
      'includeSubdirectoriesSubtitle':
          'Buscar música también dentro de las subcarpetas.',
      'musicDirectoriesTitle': 'Directorios de música',
      'musicDirectoriesSubtitle':
          'Carpetas que se incluirán al escanear la biblioteca musical.',
      'podcastDirectoriesTitle': 'Directorios de podcasts',
      'podcastDirectoriesSubtitle':
          'Carpetas independientes para almacenar y localizar podcasts.',
      'addMusicDirectoryTooltip': 'Agregar directorio de música',
      'addPodcastDirectoryTooltip': 'Agregar directorio de podcasts',
      'removeDirectoryTooltip': 'Eliminar directorio',
      'selectMusicDirectoryDialog': 'Seleccionar directorio de música',
      'selectPodcastDirectoryDialog': 'Seleccionar directorio de podcasts',
      'directoryAlreadyAddedMusic':
          'Este directorio de música ya está agregado.',
      'directoryAlreadyAddedPodcast':
          'Este directorio de podcasts ya está agregado.',
      'directoryPickErrorMusic':
          'No se pudo seleccionar el directorio de música: {error}',
      'directoryPickErrorPodcast':
          'No se pudo seleccionar el directorio de podcasts: {error}',
      'noMusicDirectories': 'No hay directorios de música',
      'noPodcastDirectories': 'No hay directorios de podcasts',
      'noMusicDirectoriesHint':
          'Agrega una carpeta para configurar tu biblioteca musical.',
      'noPodcastDirectoriesHint':
          'Agrega una carpeta para configurar tus podcasts.',
      'aboutAppName': 'DecibeX',
      'aboutAppTagline': 'Reproductor de música y podcasts',
      'aboutVersion': 'Versión 1.0.0',
      'aboutDescription':
          'DecibeX es un reproductor local enfocado en la calidad de audio, con soporte para ReplayGain, fades de volumen y organización de tu biblioteca musical y de podcasts.',
      'aboutLicenses': 'Licencias de terceros',
      'aboutLicensesSubtitle': 'Paquetes y recursos utilizados',
      'aboutMadeWithFlutter': 'Hecho con Flutter',
      'aboutCopyright': '© {year} DecibeX. Todos los derechos reservados.',
      'removeFromQueue': 'Quitar de la cola',
      'removeFromFavorites': 'Quitar de favoritos',
      'addToFavorites': 'Agregar a favoritos',
      'playlistsSection': 'Listas de reproducción',
      'nSelected': '{count} seleccionadas',
      'playback': 'Reproducción',
      'playbackOptions': 'Opciones de reproducción',
      'repeatSection': 'REPETICIÓN',
      'nowPlaying': 'REPRODUCIENDO',
      'minimizePlayer': 'Minimizar reproductor',
      'closePlayerAndStop': 'Cerrar reproductor y detener música',
      'dragToReorder': 'Arrastra el icono para cambiar el orden',
      'tapSongToPlay': 'Pulsa una canción para reproducirla',
      'nothingPlaying': 'No hay música reproduciéndose',
      'selectSongToStart':
          'Selecciona una canción de tu biblioteca para comenzar.',
      'unknownArtist': 'Artista desconocido',
      'unknownAlbum': 'Álbum desconocido',
      'libraryInitError': 'No se pudo inicializar la biblioteca: {error}',
      'configFileNotFound':
          'No se encontró el archivo de configuración. Se conservará la configuración anterior.',
      'configUpdateError': 'No se pudo actualizar la configuración: {error}',
      'scanPartialWarning':
          'El escaneo terminó parcialmente. Se conservaron los archivos que no pudieron verificarse.',
      'scanError': 'Error durante el escaneo: {error}',
      'favoriteSaveError': 'No se pudo guardar el favorito: {error}',
      'effects': 'Efectos',
      'slowedEffect': 'Slowed (más lento)',
      'reverbEffect': 'Reverb',
      'reverbAndroidOnly': 'Solo disponible en Android',
    },
    'en': {
      'audioNotificationChannelName': 'Audio playback',
      'effects': 'Effects',
      'slowedEffect': 'Slowed',
      'reverbEffect': 'Reverb',
      'reverbAndroidOnly': 'Only available on Android',
      'audioNotificationChannelDescription': 'DecibeX playback controls',
      'home': 'Home',
      'library': 'Library',
      'search': 'Search',
      'settings': 'Settings',
      'mainMenu': 'MAIN MENU',
      'close': 'Close',
      'cancel': 'Cancel',
      'accept': 'OK',
      'delete': 'Delete',
      'create': 'Create',
      'save': 'Save',
      'language': 'Language',
      'systemLanguage': 'System language',
      'spanish': 'Spanish',
      'english': 'English',
      'appearance': 'Appearance',
      'appearanceSubtitle': 'Customize the look of DecibeX.',
      'darkTheme': 'Dark theme',
      'darkThemeOn': 'The interface is set to dark.',
      'darkThemeOff': 'The interface is set to light.',
      'accentColor': 'Accent color',
      'accentColorSubtitle': 'Select the main interface color.',
      'audio': 'Audio',
      'audioSubtitle': 'Playback and sound preferences.',
      'music': 'Music',
      'podcasts': 'Podcasts',
      'playlists': 'Playlists',
      'favorites': 'Favorites',
      'artists': 'Artists',
      'albums': 'Albums',
      'songs': 'Songs',
      'all': 'All',
      'noResults': 'No results',
      'noSongs': 'No songs',
      'noArtists': 'No artists',
      'noAlbums': 'No albums',
      'noPodcasts': 'No podcasts',
      'queueEmpty': 'The queue is empty',
      'play': 'Play',
      'pause': 'Pause',
      'previous': 'Previous',
      'next': 'Next',
      'moreOptions': 'More options',
      'configuration': 'Settings',
      'personalization': 'CUSTOMIZATION',
      'listeningDescription': 'Adjust your listening experience your way.',
      'resetSettings': 'Reset settings',
      'localConfiguration': 'DecibeX · Local configuration',
      'overwriteQueue': 'Overwrite queue',
      'addAllToQueue': 'Add all to queue',
      'playAll': 'Play all',
      'mostPlayed': 'Most played',
      'mostPlayedSubtitle': 'The songs you play most',
      'yourFavorites': 'Your favorites',
      'yourFavoritesSubtitle': 'Your personal collection',
      'configureLibrary': 'Set up your library',
      'configureLibrarySubtitle':
          'Add a folder in Settings > Library to get started.',
      'noSongsYet': 'No songs yet',
      'scanLibrarySubtitle': 'Scan your library to start listening.',
      'noPlayedSongs': 'No songs played yet',
      'markFavoritesSubtitle': 'Mark songs as favorites to see them here.',
      'searchYoutubeHint': 'Search YouTube...',
      'searchYoutube': 'Search',
      'clear': 'Clear',
      'download': 'Download',
      'chooseFolder': 'Choose folder',
      'selectLocation': 'Select location',
      'downloadFolder': 'Choose download folder',
      'downloadFormat': 'Download format',
      'compressedCompatible': 'Compressed and compatible',
      'losslessAudio': 'Lossless audio',
      'uncompressedAudio': 'Uncompressed audio',
      'typePlaylistName': 'Enter a name',
      'playlistName': 'Playlist name',
      'addSelected': 'Add selected',
      'addSongs': 'Add songs',
      'rename': 'Rename',
      'export': 'Export',
      'importPlaylist': 'Import playlist',
      'newPlaylist': 'New playlist',
      'noPlaylists': 'No playlists yet',
      'emptyPlaylist': 'This playlist is empty',
      'favoritesQueue': 'Favorites',
      'playbackQueue': 'Queue',
      'shuffle': 'Shuffle',
      'repeatOff': 'Do not repeat',
      'repeatSong': 'Repeat song',
      'repeatQueue': 'Repeat queue',
      'back': 'Back',
      // HomeScreen
      'yourMusicalSpace': 'YOUR MUSICAL SPACE',
      'yourMusicYourWay': 'Your music, your way.',
      'everythingYouLove': 'Everything you love to listen to, in one place.',
      'noFavoritesYet': 'You have no favorites yet',
      'playSongToAppear':
          'Play a song for at least 5 seconds for it to show up here.',
      // LibraryScreen
      'yourCollection': 'YOUR COLLECTION',
      'yourLibrary': 'Your library',
      'libraryDescription':
          'All your music and podcasts, organized in one place.',
      'scanPending': 'Scan pending',
      'lastScanAt': 'Last scan: {date}',
      'scanNow': 'Scan now',
      'unknown': 'Unknown',
      'allSongs': 'All songs',
      'yourPodcasts': 'Your podcasts',
      'yourPlaylists': 'Your playlists',
      'yourArtists': 'Your artists',
      'yourAlbums': 'Your albums',
      'playlist': 'Playlist',
      'nSongsFromArtist': '{count} songs from this artist',
      'nSongsFromAlbum': '{count} songs from this album',
      'nEpisodesFromPodcast': '{count} episodes from this podcast',
      'nSongsInCollection': '{count} songs in your collection',
      'nPodcastsInCollection': '{count} podcasts in your collection',
      'nPlaylistsInCollection': '{count} playlists in your collection',
      'nSongsAvailable': '{count} songs available',
      'nFavoriteItems': '{count} favorite items',
      'nArtistsInCollection': '{count} artists in your collection',
      'nAlbumsInCollection': '{count} albums in your collection',
      'nSongs': '{count} songs',
      'finishReordering': 'Finish reordering',
      'reorderFavorites': 'Reorder favorites',
      'resume': 'Resume',
      'addToQueue': 'Add to queue',
      'addPlaylist': 'Add playlist',
      'listView': 'List view',
      'gridView': 'Grid view',
      'createPlaylist': 'Create playlist',
      'newPlaylistSubtitle': 'Give it a name to start organizing your music.',
      'renamePlaylist': 'Rename playlist',
      'renamePlaylistSubtitle': 'Choose a new name for "{name}".',
      'exportPlaylist': 'Export playlist',
      'deletePlaylist': 'Delete playlist',
      'songSingular': 'song',
      'songsPlural': 'songs',
      'deletePlaylistWarning':
          'Music files will not be deleted, only the playlist. This action cannot be undone.',
      'addSongsToPlaylist': 'Add songs to {name}',
      'noSongsAvailableInLibrary': 'No songs available in the library.',
      'playlistOptions': 'Playlist options',
      'missingSongsInPlaylist':
          '{count} songs unavailable in the library. Their paths will be kept in the playlist.',
      'noPlaylistsYet': 'No playlists yet',
      'noPlaylistsMessage':
          'Create or import a playlist to organize your songs.',
      'playlistNotAvailable': 'Playlist not available',
      'playlistNotAvailableMessage': 'The playlist may have been deleted.',
      'emptyPlaylistMessage': 'This playlist is empty',
      'emptyPlaylistAddSongsHint': 'Add songs with the add songs button above.',
      'noPodcastsYet': 'No podcasts yet',
      'noPodcastsMessage':
          'Add folders in Settings > Library > Podcasts and scan your files.',
      'noPodcastEpisodes': 'No episodes in this podcast',
      'noPodcastEpisodesMessage':
          'Episodes will appear here when they are available in your library.',
      'markFavoritesOrEpisodes':
          'Mark songs or episodes as favorites to see them here.',
      'noSongsFromArtist': 'No songs from this artist',
      'noSongsFromAlbum': 'No songs from this album',
      'libraryEmpty': 'Your library is empty',
      'songsWillAppearHere':
          'Songs will appear here when they are available in your library.',
      'libraryEmptyMessage':
          'Add folders in Settings > Library and scan your files.',
      // SearchScreen
      'searchScreen': 'Search screen',
      'searchYoutubeMode': 'SEARCH ON YOUTUBE',
      'findYourMusic': 'FIND YOUR MUSIC',
      'exploreAndDownload': 'Explore and download',
      'searchTitle': 'Search',
      'searchYoutubeDescription':
          'Search YouTube videos or audio and choose the download format.',
      'searchLibraryDescription':
          'Explore your entire collection by song, artist, album or podcast.',
      'searchLibraryHint': 'Songs, artists, albums or podcasts',
      'filterAll': 'All',
      'filterSongs': 'Songs',
      'filterArtists': 'Artists',
      'filterAlbums': 'Albums',
      'filterPodcasts': 'Podcasts',
      'filterYoutube': 'YouTube',
      'searchNoResultsTitle': 'No results',
      'searchTryOtherWords': 'Try different words.',
      'searchOnYoutubeTitle': 'Search on YouTube',
      'searchOnYoutubeMessage':
          'Type something and press Enter to search videos or audio on YouTube.',
      'searchStartTypingTitle': 'Start typing',
      'searchStartTypingMessage':
          'Search by title, artist, album or podcast across your entire library.',
      'searchNoSongsTitle': 'No songs',
      'searchNoSongsMessage': 'No songs match "{query}".',
      'searchNoArtistsTitle': 'No artists',
      'searchNoArtistsMessage': 'No artists match "{query}".',
      'searchNoAlbumsTitle': 'No albums',
      'searchNoAlbumsMessage': 'No albums match "{query}".',
      'searchNoPodcastsTitle': 'No podcasts',
      'searchNoPodcastsMessage': 'No podcasts match "{query}".',
      'searchNoResultsMessage': 'We found nothing matching "{query}".',
      'searchYoutubeError': 'Error searching YouTube',
      'searchYoutubeErrorDetail': 'Error searching YouTube: {error}',
      'searchYoutubeNoMoreResults': 'No more results.',
      'searchYoutubeLoadMoreError': 'Error loading more: {error}',
      'searchLoadMore': 'Load more results',
      'searchLoadingMore': 'Loading…',
      'openDetailOf': 'Open detail',
      'openDetailOfTitle': 'Open detail of "{title}"',
      // YouTube download dialogs
      'ytDownloadTitle': 'Download',
      'ytDownloadDirectory': 'Save directory',
      'ytFileName': 'File name',
      'ytFileNameHint': 'Name without extension',
      'ytChooseValidFileName': 'Enter a valid file name.',
      'ytChooseFolderFirst': 'Choose a download folder.',
      'ytPreparingDownloader': 'Preparing downloader',
      'ytPreparingDownloaderSubtitle': 'This may take a while the first time',
      'ytDownloading': 'Downloading…',
      'ytDownloadingStatus': 'Downloading audio…',
      'ytDownloadCompleted': 'Download completed',
      'ytDownloadFailed': 'Download failed',
      'ytDownloadFailedSubtitle': 'An unexpected error occurred',
      'ytUnexpectedError': 'An unexpected error occurred.',
      'ytFileSavedSuccessfully': 'File saved successfully',
      'ytDoNotClose': 'Do not close this window while downloading.',
      'ytAndroidOnly': 'Download with Extractor is only available on Android.',
      'ytInitializeFailed':
          'Could not initialize Extractor. Check your internet connection.',
      'ytDownloadAudioStatus': 'Downloading audio…',
      'ytDownloadFinishedNoFile':
          'The download finished but the generated file was not found.',
      'ytDownloadErrorMessage': 'Could not download the audio.',
      'ytDownloadClose': 'Close',
      'ytDownloadDone': 'Close',
      // SettingsScreen
      'settingsAppearanceTitle': 'Appearance',
      'settingsAppearanceSubtitle': 'Customize the look of DecibeX.',
      'settingsAudioTitle': 'Audio',
      'settingsAudioSubtitle': 'Playback and sound preferences.',
      'settingsLibraryTitle': 'Library',
      'settingsLibrarySubtitle': 'Configure your music and podcast folders.',
      'settingsAboutTitle': 'About DecibeX',
      'settingsAboutSubtitle': 'Information and configuration status.',
      'settingsSaveError': 'Could not save settings.',
      'settingsResetTitle': 'Reset settings',
      'settingsResetMessage':
          'DecibeX defaults will be restored. Music and podcast directories will also be removed from their lists.',
      'settingsResetConfirm': 'Reset',
      'settingsResetButton': 'Reset',
      'accentViolet': 'Violet',
      'accentBlue': 'Blue',
      'accentCyan': 'Cyan',
      'accentGreen': 'Green',
      'accentOrange': 'Orange',
      'accentPink': 'Pink',
      'accentRed': 'Red',
      'accentCustom': 'Custom',
      'replayGainTitle': 'ReplayGain',
      'replayGainSubtitle': 'Volume normalization between songs.',
      'replayGainPreampTitle': 'ReplayGain preamp',
      'replayGainPreampSubtitle': 'Added to each track gain.',
      'replayGainAnalyzerTitle': 'Calculate ReplayGain per file',
      'replayGainAnalyzerSubtitle':
          'Analyze each track and save its gain in the library.',
      'replayGainAnalyzeButton': 'Analyze pending',
      'replayGainReanalyzeTooltip': 'Reanalyze entire library',
      'replayGainClearTooltip': 'Clear calculated gains',
      'replayGainCalculating': 'Calculating ReplayGain',
      'replayGainNoPending': 'No new tracks',
      'replayGainCompleted': 'ReplayGain completed',
      'replayGainAnalyzingProgress': 'Analyzing {processed} of {total}…',
      'replayGainNoPendingSubtitle': 'All tracks already have their gain.',
      'replayGainCompletedSubtitle': 'Analysis finished.',
      'replayGainNormalizationPerTrack': 'Per-track volume normalization',
      'replayGainNoPendingInfo': 'No new tracks were analyzed.',
      'replayGainGainsSaved': 'Gains saved to the library',
      'replayGainProgressTitle': 'Analysis progress',
      'replayGainReady': 'Ready',
      'replayGainCompletedShort': 'Completed',
      'replayGainTracksFormat': '{processed} / {total} tracks',
      'replayGainTracksProcessed': '{total} tracks processed',
      'replayGainInProgress': 'In progress…',
      'replayGainStop': 'Stop',
      'replayGainReanalyzeTitle': 'Reanalyze library',
      'replayGainReanalyzeSubtitle': 'All gains will be recalculated.',
      'replayGainReanalyzeWarning':
          'This may take a while depending on your library size.',
      'replayGainReanalyzeInfo':
          'Current gains will be overwritten with the newly calculated values.',
      'replayGainReanalyzeButton': 'Reanalyze',
      'replayGainClearTitle': 'Clear gains',
      'replayGainClearSubtitle': 'All calculated gains will be deleted.',
      'replayGainClearWarning': 'Tracks will play without normalization again.',
      'replayGainClearInfo':
          'This action cannot be undone. You will need to analyze each track again to restore normalization.',
      'replayGainClearButton': 'Delete',
      'fadeInTitle': 'Fade in',
      'fadeInSubtitle': 'Gradually increases volume on start.',
      'fadeInDurationTitle': 'Fade in duration',
      'fadeInDurationSubtitle': 'Gradual entry time.',
      'fadeOutTitle': 'Fade out',
      'fadeOutSubtitle': 'Gradually reduces volume on finish.',
      'fadeOutDurationTitle': 'Fade out duration',
      'fadeOutDurationSubtitle': 'Gradual exit time.',
      'includeSubdirectoriesTitle': 'Include subdirectories',
      'includeSubdirectoriesSubtitle':
          'Also search for music inside subfolders.',
      'musicDirectoriesTitle': 'Music directories',
      'musicDirectoriesSubtitle':
          'Folders included when scanning the music library.',
      'podcastDirectoriesTitle': 'Podcast directories',
      'podcastDirectoriesSubtitle':
          'Independent folders to store and locate podcasts.',
      'addMusicDirectoryTooltip': 'Add music directory',
      'addPodcastDirectoryTooltip': 'Add podcast directory',
      'removeDirectoryTooltip': 'Remove directory',
      'selectMusicDirectoryDialog': 'Select music directory',
      'selectPodcastDirectoryDialog': 'Select podcast directory',
      'directoryAlreadyAddedMusic': 'This music directory is already added.',
      'directoryAlreadyAddedPodcast':
          'This podcast directory is already added.',
      'directoryPickErrorMusic':
          'Could not select the music directory: {error}',
      'directoryPickErrorPodcast':
          'Could not select the podcast directory: {error}',
      'noMusicDirectories': 'No music directories',
      'noPodcastDirectories': 'No podcast directories',
      'noMusicDirectoriesHint': 'Add a folder to configure your music library.',
      'noPodcastDirectoriesHint': 'Add a folder to configure your podcasts.',
      'aboutAppName': 'DecibeX',
      'aboutAppTagline': 'Music and podcast player',
      'aboutVersion': 'Version 1.0.0',
      'aboutDescription':
          'DecibeX is a local player focused on audio quality, with support for ReplayGain, volume fades and organization of your music and podcast library.',
      'aboutLicenses': 'Third-party licenses',
      'aboutLicensesSubtitle': 'Packages and resources used',
      'aboutMadeWithFlutter': 'Made with Flutter',
      'aboutCopyright': '© {year} DecibeX. All rights reserved.',
      'removeFromQueue': 'Remove from queue',
      'removeFromFavorites': 'Remove from favorites',
      'addToFavorites': 'Add to favorites',
      'playlistsSection': 'Playlists',
      'nSelected': '{count} selected',
      'playback': 'Playback',
      'playbackOptions': 'Playback options',
      'repeatSection': 'REPEAT',
      'nowPlaying': 'NOW PLAYING',
      'minimizePlayer': 'Minimize player',
      'closePlayerAndStop': 'Close player and stop music',
      'dragToReorder': 'Drag the icon to reorder',
      'tapSongToPlay': 'Tap a song to play it',
      'nothingPlaying': 'Nothing is playing',
      'selectSongToStart': 'Select a song from your library to start.',
      'unknownArtist': 'Unknown artist',
      'unknownAlbum': 'Unknown album',
      'libraryInitError': 'Could not initialize the library: {error}',
      'configFileNotFound':
          'Configuration file not found. Previous configuration will be kept.',
      'configUpdateError': 'Could not update configuration: {error}',
      'scanPartialWarning':
          'Scan finished partially. Files that could not be verified were kept.',
      'scanError': 'Error during scan: {error}',
      'favoriteSaveError': 'Could not save favorite: {error}',
    },
  };
}

extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ??
      AppLocalizations(Localizations.localeOf(this));
}

class AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();
  @override
  bool isSupported(Locale locale) => ['es', 'en'].contains(locale.languageCode);
  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);
  @override
  bool shouldReload(AppLocalizationsDelegate old) => false;
}
