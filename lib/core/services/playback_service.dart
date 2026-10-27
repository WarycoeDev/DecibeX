import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
// just_audio ya no reproduce nada: solo se conservan sus enums para no
// romper el resto de la app (PlayerScreen y otros usan LoopMode).
import 'package:just_audio/just_audio.dart' show LoopMode, ProcessingState;

import '../models/song.dart';
import 'fade_index.dart';
import 'playback_queue.dart';
import 'settings_service.dart';
import 'statistics_service.dart';
import 'podcast_statistics_service.dart';

/// Servicio de reproducción sobre flutter_soloud (SoLoud + miniaudio).
///
/// Se eligió SoLoud porque, a diferencia de just_audio, trae reverb
/// (freeverb) y velocidad con cambio de tono integrados y funciona igual en
/// Android, iOS, Windows, macOS y Linux, sin código nativo propio.
class PlaybackService extends ChangeNotifier {
  PlaybackService._() {
    // Cambios de preamp / ReplayGain / fades / slow / reverb se aplican a la
    // pista actual al instante (sin esperar a la siguiente canción).
    SettingsService.instance.addListener(_onSettingsChanged);
  }

  static final PlaybackService instance = PlaybackService._();

  final Random _random = Random();

  SoLoud get _soloud => SoLoud.instance;

  // --- Motor / voz actual ---
  Future<void>? _engineInit;
  AudioSource? _source;
  SoundHandle? _handle;

  /// Se incrementa en cada carga; permite descartar cargas obsoletas si el
  /// usuario cambia de pista mientras otra todavía se está preparando.
  int _loadToken = 0;

  List<Song> _playingSongs = [];
  List<Song> _shuffleOrder = [];

  Song? _currentSong;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  bool _isPlaying = false;
  bool _isLoading = false;
  bool _shuffleEnabled = false;
  bool _handlingCompletion = false;

  int _currentQueueIndex = -1;
  int _shuffleCursor = -1;

  LoopMode _repeatMode = LoopMode.off;

  // --- Ticker: posición, fades, crossfade y fin de pista ---

  /// Frecuencia con la que se lee la posición y se reevalúa el volumen.
  static const Duration _tick = Duration(milliseconds: 40);

  /// Cada cuánto se notifica la posición a la UI y a las estadísticas.
  static const Duration _positionNotifyEvery = Duration(milliseconds: 150);

  Timer? _ticker;
  DateTime _lastPositionNotify = DateTime.fromMillisecondsSinceEpoch(0);

  // --- Volumen / fades ---

  /// Último volumen enviado a la voz actual (-1 = desconocido).
  double _lastAppliedVolume = -1;

  /// Índice "posición → ganancia" y la clave (fadeIn ms, fadeOut ms,
  /// duración ms) con la que se construyó.
  FadeIndex? _fadeIndex;
  (int, int, int)? _fadeIndexKey;

  // --- Slowed + Reverb ---
  double _lastSpeed = 1.0;
  bool _reverbActive = false;

  // --- Crossfade ---
  //
  // Diseño (todo guiado por la POSICIÓN de la pista saliente, no por timers
  // propios, así pausa / seek / velocidad lenta funcionan sin lógica extra):
  //
  //  1. PREPARAR: unos segundos antes de la ventana se carga la siguiente
  //     fuente (sin sonar). Así no hay retraso al arrancar la mezcla.
  //  2. ARRANCAR: al llegar a `_crossfadeStartMs` se lanza la voz entrante
  //     a volumen 0.
  //  3. MEZCLAR: en cada tick, t = (pos - inicio) / duración; la saliente
  //     baja con cos y la entrante sube con sin (potencia constante).
  //  4. TERMINAR: con t >= 1 (o si la saliente se acaba) la voz entrante SE
  //     PROMUEVE tal cual a voz principal. Nunca se vuelve a hacer play() de
  //     la misma fuente: eso era lo que duplicaba las canciones.
  //
  // PODCASTS: el crossfade NUNCA se usa con podcasts (ni como pista saliente
  // ni como entrante). Si el crossfade está activado y suena un podcast, se
  // reemplaza por un fade in + fade out con la misma duración del crossfade
  // (ver `_podcastFadeFallback`).

  /// Con cuánta antelación (antes de la ventana) se precarga la siguiente.
  static const Duration _crossfadePreloadLead = Duration(seconds: 10);

  AudioSource? _nextSource; // lista (cargada) cuando != null
  SoundHandle? _nextHandle; // sonando cuando != null
  Song? _nextSong;
  List<Song>? _pendingShuffleOrder;

  bool _crossfading = false; // voz entrante sonando (mezcla activa)
  bool _crossfadePreparing = false; // cargando la siguiente fuente
  bool _crossfadeBlocked = false; // no aplica / falló para esta pista
  int _crossfadeToken = 0; // invalida preparaciones en vuelo
  int _crossfadeStartMs = 0; // posición (ms) donde empieza la mezcla
  int _crossfadeSpanMs = 1; // duración (ms de pista) de la mezcla

  /// La pista actual entró por crossfade: su fade in ya "ocurrió" durante la
  /// mezcla y no debe volver a aplicarse.
  bool _enteredViaCrossfade = false;

  /// Archivos de más de este tamaño se leen desde disco en vez de memoria
  /// (pensado para podcasts largos).
  static const int _diskLoadThresholdBytes = 64 * 1024 * 1024;

  Song? get currentSong => _currentSong;
  Duration get position => _position;
  Duration get duration => _duration;
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;
  bool get shuffleEnabled => _shuffleEnabled;
  LoopMode get repeatMode => _repeatMode;
  List<Song> get playingSongs => List.unmodifiable(_playingSongs);

  /// Velocidad de reproducción vigente (1.0 = normal).
  double get speed => _lastSpeed;

  /// Los archivos son locales: se considera todo "bufferizado".
  Duration get bufferedPosition => _duration;

  ProcessingState get processingState {
    if (_currentSong == null) return ProcessingState.idle;
    if (_isLoading || _handlingCompletion) return ProcessingState.loading;

    if (_handle == null) {
      // Entre dos pistas (voz liberada pero seguimos "reproduciendo").
      if (_isPlaying) return ProcessingState.loading;

      // Pausa forzada por el sistema: sigue siendo reanudable.
      final ended =
          _duration > Duration.zero &&
          _position >= _duration - const Duration(seconds: 1);
      return ended ? ProcessingState.completed : ProcessingState.ready;
    }

    return ProcessingState.ready;
  }

  /// SoLoud trae reverb en todas las plataformas.
  bool get reverbSupported => true;

  int? get currentIndex => _currentQueueIndex >= 0 ? _currentQueueIndex : null;

  bool get canPlayPrevious {
    if (_isLoading || _playingSongs.isEmpty || _currentSong == null) {
      return false;
    }

    if (_position > const Duration(seconds: 3)) {
      return true;
    }

    if (_shuffleEnabled) {
      return _shuffleCursor > 0 ||
          (_repeatMode == LoopMode.all && _playingSongs.length > 1);
    }

    return _currentQueueIndex > 0 ||
        (_repeatMode == LoopMode.all && _playingSongs.length > 1);
  }

  bool get canPlayNext {
    if (_isLoading || _playingSongs.isEmpty || _currentSong == null) {
      return false;
    }

    if (_shuffleEnabled) {
      return _shuffleCursor >= 0 &&
          (_shuffleCursor < _shuffleOrder.length - 1 ||
              (_repeatMode == LoopMode.all && _playingSongs.length > 1));
    }

    return _currentQueueIndex >= 0 &&
        (_currentQueueIndex < _playingSongs.length - 1 ||
            (_repeatMode == LoopMode.all && _playingSongs.length > 1));
  }

  void _onSettingsChanged() {
    _applyPlaybackEffects();

    // Si se apagó el crossfade, se descarta lo preparado (una mezcla ya en
    // curso se deja terminar para no cortar el audio de golpe).
    if (!SettingsService.instance.crossfadeEnabled && !_crossfading) {
      _cancelCrossfade();
    }

    if (_currentSong == null || _handle == null) return;
    unawaited(_applyVolume());
  }

  bool _sameSong(Song a, Song b) {
    final pathA = a.filePath?.trim();
    final pathB = b.filePath?.trim();

    if (pathA != null &&
        pathA.isNotEmpty &&
        pathB != null &&
        pathB.isNotEmpty) {
      return pathA.replaceAll('\\', '/') == pathB.replaceAll('\\', '/');
    }

    return a.title.trim().toLowerCase() == b.title.trim().toLowerCase() &&
        a.artist.trim().toLowerCase() == b.artist.trim().toLowerCase();
  }

  int _indexOfSong(List<Song> songs, Song song) {
    return songs.indexWhere((item) => _sameSong(item, song));
  }

  void _buildShuffleOrder({Song? keepCurrentFirst}) {
    _shuffleOrder = List<Song>.from(_playingSongs);

    if (_shuffleOrder.length > 1) {
      for (var i = _shuffleOrder.length - 1; i > 0; i--) {
        final j = _random.nextInt(i + 1);
        final temp = _shuffleOrder[i];
        _shuffleOrder[i] = _shuffleOrder[j];
        _shuffleOrder[j] = temp;
      }
    }

    if (keepCurrentFirst != null) {
      final currentIndex = _indexOfSong(_shuffleOrder, keepCurrentFirst);

      if (currentIndex > 0) {
        final current = _shuffleOrder.removeAt(currentIndex);
        _shuffleOrder.insert(0, current);
      }
    }

    _shuffleCursor = _currentSong == null
        ? -1
        : _indexOfSong(_shuffleOrder, _currentSong!);
  }

  /// Nuevo orden aleatorio para cuando se completa una vuelta en
  /// "repetir cola": garantiza que la primera NO sea la que acaba de sonar.
  List<Song> _shuffleForWrap(Song? current) {
    final order = List<Song>.from(_playingSongs);

    for (var i = order.length - 1; i > 0; i--) {
      final j = _random.nextInt(i + 1);
      final temp = order[i];
      order[i] = order[j];
      order[j] = temp;
    }

    if (current != null &&
        order.length > 1 &&
        _sameSong(order.first, current)) {
      final j = 1 + _random.nextInt(order.length - 1);
      final temp = order[0];
      order[0] = order[j];
      order[j] = temp;
    }

    return order;
  }

  Future<void> toggleShuffle() => setShuffle(!_shuffleEnabled);

  Future<void> setShuffle(bool enabled) async {
    if (_shuffleEnabled == enabled) return;

    _shuffleEnabled = enabled;
    _invalidateCrossfadePlan();

    if (enabled) {
      _buildShuffleOrder(keepCurrentFirst: _currentSong);
    } else {
      _shuffleOrder = [];
      _shuffleCursor = -1;
    }

    debugPrint(
      '[PlaybackService] Aleatorio ${enabled ? "activado" : "desactivado"}',
    );

    notifyListeners();
  }

  Future<void> setRepeatMode(LoopMode mode) async {
    if (_repeatMode == mode) return;

    _repeatMode = mode;
    _invalidateCrossfadePlan();

    final label = switch (mode) {
      LoopMode.one => 'repetir canción',
      LoopMode.all => 'repetir cola',
      LoopMode.off => 'desactivado',
    };

    debugPrint('[PlaybackService] Repetición: $label');
    notifyListeners();
  }

  Future<void> cycleRepeatMode() {
    final nextMode = switch (_repeatMode) {
      LoopMode.off => LoopMode.one,
      LoopMode.one => LoopMode.all,
      LoopMode.all => LoopMode.off,
    };

    return setRepeatMode(nextMode);
  }

  Future<void> playQueue() async {
    final queue = PlaybackQueue.instance.songs;

    if (queue.isEmpty) {
      await stop();
      return;
    }

    final availableSongs = <Song>[];

    for (final song in queue) {
      final path = song.filePath;

      if (path == null || path.isEmpty || !await File(path).exists()) {
        debugPrint('[PlaybackService] Archivo no disponible: ${song.title}');
        continue;
      }

      availableSongs.add(song);
    }

    if (availableSongs.isEmpty) {
      debugPrint('[PlaybackService] No hay archivos reproducibles en la cola.');
      await stop();
      return;
    }

    _cancelCrossfade();

    _playingSongs = availableSongs;
    _currentSong = null;
    _currentQueueIndex = -1;
    _shuffleOrder = [];
    _shuffleCursor = -1;
    _position = Duration.zero;
    _duration = Duration.zero;

    if (_shuffleEnabled) {
      _buildShuffleOrder();
    }

    final firstSong = _shuffleEnabled
        ? _shuffleOrder.first
        : availableSongs.first;

    _isLoading = true;
    notifyListeners();

    try {
      await _loadAndPlaySong(firstSong);

      debugPrint(
        '[PlaybackService] Reproduciendo cola: ${availableSongs.length} canciones',
      );
    } catch (error) {
      debugPrint('[PlaybackService] No se pudo cargar la cola: $error');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ===========================================================================
  // MOTOR
  // ===========================================================================

  Future<void> _ensureEngine() {
    if (_soloud.isInitialized) return Future<void>.value();

    return _engineInit ??= _soloud.init().whenComplete(() {
      _engineInit = null;
    });
  }

  Future<void> _disposeSourceQuietly(AudioSource? source) async {
    if (source == null) return;

    try {
      // Al liberar la fuente también se detienen sus voces.
      await _soloud.disposeSource(source);
    } catch (error) {
      debugPrint('[PlaybackService] Error liberando la fuente: $error');
    }
  }

  /// Detiene y libera la voz y la fuente actuales (y cualquier voz entrante
  /// de un crossfade en curso o ya preparada).
  Future<void> _releaseVoice() async {
    // Invalida cualquier preparación de crossfade que siga en vuelo.
    _crossfadeToken++;
    _crossfadePreparing = false;
    _crossfadeBlocked = false;
    _crossfading = false;
    _pendingShuffleOrder = null;

    final nextSource = _nextSource;
    _nextSource = null;
    _nextHandle = null;
    _nextSong = null;

    final source = _source;

    _handle = null;
    _source = null;
    _lastAppliedVolume = -1;
    _syncTicker();

    await _disposeSourceQuietly(nextSource);
    await _disposeSourceQuietly(source);
  }

  Duration _livePosition() {
    final handle = _handle;
    if (handle == null) return _position;

    try {
      return _soloud.getPosition(handle);
    } catch (_) {
      return _position;
    }
  }

  bool _isValid(SoundHandle? handle) {
    if (handle == null) return false;

    try {
      return _soloud.getIsValidVoiceHandle(handle);
    } catch (_) {
      return false;
    }
  }

  /// Comprueba si la voz actual sigue siendo válida en el motor.
  ///
  /// Tras pausar en background (pérdida de audio focus, desconexión de
  /// Bluetooth, suspensión del proceso) el handle puede quedar colgado pero
  /// la voz ya no existir. En ese caso hay que recargar la pista.
  bool _isHandleAlive() => _isValid(_handle);

  // ===========================================================================
  // TICKER · posición, fades, crossfade y fin de pista
  // ===========================================================================

  /// El ticker corre solo mientras hay una voz sonando.
  void _syncTicker() {
    final needed = _handle != null && _isPlaying;

    if (needed) {
      _ticker ??= Timer.periodic(_tick, (_) => _onTick());
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _onTick() {
    final handle = _handle;

    if (handle == null || !_isPlaying || _isLoading) return;

    // La voz deja de ser válida cuando la pista termina, pero también si el
    // sistema la invalida en background.
    if (!_isValid(handle)) {
      _onVoiceEnded();
      return;
    }

    final position = _livePosition();
    _position = position;

    // Crossfade: preparar, arrancar, mezclar y terminar (todo por posición).
    _driveCrossfade(position);

    // Durante la mezcla el volumen lo gobierna _mixCrossfade.
    if (!_crossfading && _hasActiveFades(_currentSong)) {
      unawaited(_applyVolume(at: position));
    }

    final now = DateTime.now();

    if (now.difference(_lastPositionNotify) >= _positionNotifyEvery) {
      _lastPositionNotify = now;

      StatisticsService.instance.onPositionChanged(position);
      PodcastStatisticsService.instance.onPositionChanged(position);

      notifyListeners();
    }
  }

  /// La voz principal dejó de existir: fin de pista o invalidación externa.
  void _onVoiceEnded() {
    // Solo es "fin de pista" si estamos cerca del final real; si no, se
    // trata como una pausa forzada para que el usuario pueda reanudar.
    final nearEnd =
        _duration > Duration.zero &&
        _position >= _duration - const Duration(seconds: 1);

    if (!nearEnd) {
      debugPrint(
        '[PlaybackService] Voz invalidada por el sistema; se marca pausa.',
      );
      _handle = null;
      _isPlaying = false;
      _cancelCrossfade();
      _syncTicker();
      notifyListeners();
      return;
    }

    // Había una siguiente pista lista (mezcla en curso o solo precargada):
    // se promueve en lugar de recargarla, sin hueco ni duplicado.
    if (_nextSource != null && (_crossfading || _startNextVoice())) {
      unawaited(_finishCrossfade());
      return;
    }

    _handle = null;
    _syncTicker();
    unawaited(_handleTrackCompleted());
  }

  // ===========================================================================
  // SLOWED + REVERB
  //
  // - Slowed: velocidad y tono bajan juntos (efecto "cinta"): SoLoud cambia
  //   ambos con setRelativePlaySpeed. La velocidad sale de
  //   SettingsService.effectiveSpeed (1.0 → 0.65x según el slider).
  // - Reverb: filtro freeverb global de SoLoud. Se activa solo mientras el
  //   reverb está habilitado.
  // ===========================================================================

  void _applyPlaybackEffects() {
    _applySpeed();
    _applyReverb();
  }

  void _applySpeed() {
    final handle = _handle;
    if (handle == null) return;

    final speed = SettingsService.instance.effectiveSpeed;
    if ((speed - _lastSpeed).abs() < 0.0005) return;

    try {
      _soloud.setRelativePlaySpeed(handle, speed);
      _lastSpeed = speed;

      // La voz entrante del crossfade (si la hay) también cambia de velocidad.
      final nextHandle = _nextHandle;
      if (nextHandle != null && _isValid(nextHandle)) {
        _soloud.setRelativePlaySpeed(nextHandle, speed);
      }
    } catch (error) {
      debugPrint('[PlaybackService] No se pudo cambiar la velocidad: $error');
    }
  }

  void _applyReverb() {
    if (!_soloud.isInitialized) return;

    final settings = SettingsService.instance;
    final amount = settings.reverbEnabled ? settings.reverbAmount : 0.0;

    try {
      final reverb = _soloud.filters.freeverbFilter;

      if (amount <= 0.001) {
        if (_reverbActive) {
          reverb.deactivate();
          _reverbActive = false;
        }
        return;
      }

      if (!_reverbActive) {
        reverb.activate();
        _reverbActive = true;
      }

      // amount 0..1 → mezcla húmeda 10-55 % y sala mediana-grande.
      reverb.wet.value = 0.10 + amount * 0.45;
      reverb.roomSize.value = 0.60 + amount * 0.35;
      reverb.width.value = 1.0;
    } catch (error) {
      debugPrint('[PlaybackService] No se pudo aplicar el reverb: $error');
    }
  }

  // ===========================================================================
  // VOLUMEN · FADE IN / FADE OUT
  //
  // El volumen final es siempre:
  //
  //     volumen = baseVolume(ReplayGain + preamp) × FadeIndex.gainAt(posición)
  //
  // Al depender solo de la posición (no del tiempo transcurrido), el seek, la
  // pausa y la reanudación funcionan sin lógica adicional. La duración de
  // cada fade sale de SettingsService (ajustada a la velocidad actual para que
  // el fade dure lo configurado en tiempo real aunque la pista vaya lenta).
  // ===========================================================================

  /// Envía un volumen a la voz actual sin ninguna comprobación.
  Future<void> _setVolumeRaw(double volume) async {
    _lastAppliedVolume = volume;

    final handle = _handle;
    if (handle == null) return;

    try {
      _soloud.setVolume(handle, volume);
    } catch (error) {
      debugPrint('[PlaybackService] No se pudo cambiar el volumen: $error');
    }
  }

  /// Los podcasts nunca usan crossfade. Si el crossfade está activado y [song]
  /// es un podcast, se sustituye por un fade in + fade out cuya duración es la
  /// del crossfade (en lugar de las duraciones de fade in / fade out propias).
  bool _podcastFadeFallback(Song? song) {
    if (song == null || !song.isPodcast) return false;
    return SettingsService.instance.crossfadeEnabled;
  }

  /// ¿Hay algún fade que aplicar a [song] en este momento?
  bool _hasActiveFades(Song? song) {
    final settings = SettingsService.instance;

    return _podcastFadeFallback(song) ||
        settings.fadeInEnabled ||
        settings.fadeOutEnabled;
  }

  /// Devuelve el índice vigente, reconstruyéndolo si cambió la duración de
  /// algún fade (settings), la velocidad o la duración de la pista.
  FadeIndex? _currentFadeIndex() {
    final settings = SettingsService.instance;
    final speed = settings.effectiveSpeed;

    final int inMs;
    final int outMs;

    if (_podcastFadeFallback(_currentSong)) {
      // Podcast con crossfade activado: fade in y fade out con la duración
      // del crossfade.
      final ms = (settings.crossfadeDuration * 1000 * speed).round();
      inMs = ms;
      outMs = ms;
    } else {
      inMs = settings.fadeInEnabled
          ? (settings.fadeInDuration * 1000 * speed).round()
          : 0;
      outMs = settings.fadeOutEnabled
          ? (settings.fadeOutDuration * 1000 * speed).round()
          : 0;
    }

    if (inMs <= 0 && outMs <= 0) return null;

    final trackMs = _duration.inMilliseconds;
    final key = (inMs, outMs, trackMs);

    if (_fadeIndex == null || _fadeIndexKey != key) {
      _fadeIndex = FadeIndex.build(
        fadeIn: Duration(milliseconds: inMs),
        fadeOut: Duration(milliseconds: outMs),
        track: _duration,
      );
      _fadeIndexKey = key;
    }

    return _fadeIndex;
  }

  /// Volumen base derivado de ReplayGain (por pista + preamp global).
  double _baseVolume(Song song) {
    final settings = SettingsService.instance;

    if (!settings.replayGainEnabled) return 1.0;

    final trackGainDb = song.replayGainDb ?? 0.0;
    final totalGainDb = trackGainDb + settings.replayGainPreamp;

    if (totalGainDb == 0) return 1.0;

    return pow(10, totalGainDb / 20).toDouble().clamp(0.0, 4.0);
  }

  /// Calcula y aplica el volumen que toca en [at] (por defecto, la posición
  /// real de la voz). Solo llama al motor si el valor cambió.
  Future<void> _applyVolume({Duration? at, bool force = false}) async {
    final song = _currentSong;
    if (song == null || _handle == null) return;

    final position = at ?? _livePosition();

    // Durante un crossfade el volumen de ambas voces sale de la mezcla.
    if (_crossfading) {
      _mixCrossfade(position);
      return;
    }

    final fadeGain =
        _currentFadeIndex()?.gainAt(position, fadeIn: !_enteredViaCrossfade) ??
        1.0;
    final target = (_baseVolume(song) * fadeGain).clamp(0.0, 4.0).toDouble();

    if (!force) {
      // Los extremos (0 absoluto y volumen pleno) nunca se omiten por
      // tolerancia: tienen que alcanzarse exactos.
      final isEndpoint = target == 0.0 || fadeGain >= 1.0;
      final unchanged = isEndpoint
          ? target == _lastAppliedVolume
          : (target - _lastAppliedVolume).abs() < 0.001;

      if (unchanged) return;
    }

    await _setVolumeRaw(target);
  }

  // ===========================================================================
  // CROSSFADE
  // ===========================================================================

  /// Duración (en tiempo de PISTA) de la mezcla. 0 si está desactivado, la
  /// pista es muy corta o la pista actual es un podcast (los podcasts nunca
  /// hacen crossfade). Se ajusta a la velocidad para que dure lo configurado
  /// en tiempo real aunque la pista vaya lenta.
  Duration _crossfadeDuration() {
    final settings = SettingsService.instance;
    if (!settings.crossfadeEnabled) return Duration.zero;

    // Podcast: sin crossfade (se usa fade in/out, ver _podcastFadeFallback).
    if (_currentSong?.isPodcast ?? false) return Duration.zero;

    if (_duration <= const Duration(seconds: 2)) return Duration.zero;

    var ms = (settings.crossfadeDuration * 1000 * settings.effectiveSpeed)
        .round();
    // Nunca más de la mitad de la pista.
    ms = min(ms, _duration.inMilliseconds ~/ 2);
    return Duration(milliseconds: max(0, ms));
  }

  /// Quita todo lo preparado para el crossfade (y, si la mezcla estaba
  /// activa, devuelve la pista actual a su volumen normal).
  void _cancelCrossfade() {
    if (!_crossfading &&
        !_crossfadePreparing &&
        _nextSource == null &&
        !_crossfadeBlocked) {
      return;
    }

    _crossfadeToken++;
    _crossfadePreparing = false;
    _crossfadeBlocked = false;
    _pendingShuffleOrder = null;

    final wasActive = _crossfading;
    final source = _nextSource;

    _crossfading = false;
    _nextSource = null;
    _nextHandle = null;
    _nextSong = null;

    unawaited(_disposeSourceQuietly(source));

    if (wasActive && _handle != null) {
      unawaited(_applyVolume(force: true));
    }
  }

  /// Cambió la cola / aleatorio / repetición: la "siguiente" decidida puede
  /// ya no ser válida. Si la mezcla ya suena, se deja terminar.
  void _invalidateCrossfadePlan() {
    if (!_crossfading) _cancelCrossfade();
  }

  /// Paso 1: carga la siguiente fuente (sin reproducirla).
  Future<void> _prepareCrossfade() async {
    if (_crossfadePreparing ||
        _crossfading ||
        _nextSource != null ||
        _crossfadeBlocked) {
      return;
    }

    final current = _currentSong;
    if (current == null) return;

    // En "repetir canción" la mezcla es consigo misma.
    final next = _repeatMode == LoopMode.one
        ? current
        : _getNextSong(commit: false);

    // Sin siguiente (fin de cola) o podcasts (saliente o entrante):
    // transición normal, sin crossfade.
    if (next == null || current.isPodcast || next.isPodcast) {
      _crossfadeBlocked = true;
      return;
    }

    final path = next.filePath;
    if (path == null || path.isEmpty) {
      _crossfadeBlocked = true;
      return;
    }

    final token = _crossfadeToken;
    _crossfadePreparing = true; // síncrono: evita preparaciones duplicadas

    AudioSource? source;

    try {
      final exists = await File(path).exists();
      if (token != _crossfadeToken) return;

      if (!exists) {
        _crossfadeBlocked = true;
        return;
      }

      await _ensureEngine();

      final fileSize = await File(path).length();
      source = await _soloud.loadFile(
        path,
        mode: fileSize > _diskLoadThresholdBytes
            ? LoadMode.disk
            : LoadMode.memory,
      );

      // Mientras cargaba cambió la pista / la cola: se descarta.
      if (token != _crossfadeToken) {
        await _disposeSourceQuietly(source);
        return;
      }

      // La mezcla no puede durar más de la mitad de la pista entrante.
      final nextLength = _soloud.getLength(source);
      final span = min(
        _crossfadeDuration().inMilliseconds,
        nextLength.inMilliseconds ~/ 2,
      );

      if (span < 300) {
        await _disposeSourceQuietly(source);
        _crossfadeBlocked = true;
        return;
      }

      _nextSource = source;
      _nextSong = next;
      _crossfadeSpanMs = span;
      _crossfadeStartMs = _duration.inMilliseconds - span;
    } catch (error) {
      debugPrint('[PlaybackService] Error preparando crossfade: $error');
      unawaited(_disposeSourceQuietly(source));
      if (token == _crossfadeToken) _crossfadeBlocked = true;
    } finally {
      if (token == _crossfadeToken) _crossfadePreparing = false;
    }
  }

  /// Paso 2: lanza la voz entrante a volumen 0. [lateMs] es cuánto se pasó
  /// ya del inicio de la ventana (si la precarga tardó), para mantener
  /// ambas pistas alineadas con la mezcla.
  bool _startNextVoice({int lateMs = 0}) {
    final source = _nextSource;
    if (source == null) return false;
    if (_crossfading) return true;

    try {
      final handle = _soloud.play(source, volume: 0.0, paused: true);

      final speed = SettingsService.instance.effectiveSpeed;
      if ((speed - 1.0).abs() > 0.0005) {
        _soloud.setRelativePlaySpeed(handle, speed);
      }

      final offsetMs = min(lateMs, _crossfadeSpanMs);
      if (offsetMs > 150) {
        try {
          _soloud.seek(handle, Duration(milliseconds: offsetMs));
        } catch (_) {}
      }

      _soloud.setPause(handle, false);

      _nextHandle = handle;
      _crossfading = true;
      return true;
    } catch (error) {
      debugPrint(
        '[PlaybackService] No se pudo iniciar la voz entrante: $error',
      );
      return false;
    }
  }

  /// Orquesta las fases del crossfade en cada tick.
  void _driveCrossfade(Duration position) {
    if (_currentSong == null || _handlingCompletion) return;

    if (!_crossfading) {
      // Con un podcast sonando esto devuelve 0: nunca hay crossfade.
      final cf = _crossfadeDuration();
      if (cf <= Duration.zero || _crossfadeBlocked) return;

      // Fase 1: precargar con antelación.
      if (_nextSource == null) {
        final preloadAt = _duration - cf - _crossfadePreloadLead;

        if (!_crossfadePreparing && position >= preloadAt) {
          unawaited(_prepareCrossfade());
        }
        return;
      }

      // Fase 2: arrancar al entrar en la ventana.
      if (position.inMilliseconds < _crossfadeStartMs) return;

      if (!_startNextVoice(
        lateMs: position.inMilliseconds - _crossfadeStartMs,
      )) {
        _cancelCrossfade();
        _crossfadeBlocked = true;
        return;
      }
    }

    // Fase 3: mezclar. Fase 4: terminar.
    final t = _mixCrossfade(position);
    if (t >= 1.0) unawaited(_finishCrossfade());
  }

  /// Aplica los volúmenes de ambas voces según el progreso (0..1) de la
  /// mezcla, que sale de la posición de la pista saliente. Curva de potencia
  /// constante (cos/sin): sin "hueco" de volumen a mitad de la mezcla.
  double _mixCrossfade(Duration position) {
    final span = max(1, _crossfadeSpanMs);
    final t = ((position.inMilliseconds - _crossfadeStartMs) / span)
        .clamp(0.0, 1.0)
        .toDouble();

    final song = _currentSong;
    final next = _nextSong;
    if (song == null || next == null) return t;

    final angle = t * pi / 2;

    // La saliente conserva su fade in (si aún lo tiene) pero NO su fade out:
    // el crossfade ya es su fade out.
    final fadeGain =
        _currentFadeIndex()?.gainAt(
          position,
          fadeIn: !_enteredViaCrossfade,
          fadeOut: false,
        ) ??
        1.0;

    final outVolume = (_baseVolume(song) * fadeGain * cos(angle))
        .clamp(0.0, 4.0)
        .toDouble();
    final inVolume = (_baseVolume(next) * sin(angle))
        .clamp(0.0, 4.0)
        .toDouble();

    try {
      final outHandle = _handle;
      if (outHandle != null && _isValid(outHandle)) {
        _soloud.setVolume(outHandle, outVolume);
      }

      final inHandle = _nextHandle;
      if (inHandle != null && _isValid(inHandle)) {
        _soloud.setVolume(inHandle, inVolume);
      }
    } catch (error) {
      debugPrint('[PlaybackService] No se pudo mezclar el crossfade: $error');
    }

    _lastAppliedVolume = outVolume;
    return t;
  }

  /// Paso 4: la voz entrante pasa a ser la principal, TAL CUAL (misma voz,
  /// misma posición). El intercambio de estado es síncrono (antes del primer
  /// await) para que ningún tick vea un estado a medias.
  Future<void> _finishCrossfade() async {
    if (!_crossfading) return;

    final nextSource = _nextSource;
    final nextHandle = _nextHandle;
    final nextSong = _nextSong;

    if (nextSource == null || nextHandle == null || nextSong == null) {
      _cancelCrossfade();
      return;
    }

    final oldSource = _source;
    final pendingShuffle = _pendingShuffleOrder;

    // --- Intercambio síncrono ---
    _crossfadeToken++;
    _crossfading = false;
    _crossfadePreparing = false;
    _crossfadeBlocked = false;
    _pendingShuffleOrder = null;
    _nextSource = null;
    _nextHandle = null;
    _nextSong = null;

    _source = nextSource;
    _handle = nextHandle;
    _currentSong = nextSong;
    _enteredViaCrossfade = true;

    _duration = _soloud.getLength(nextSource);
    _position = _livePosition();
    _currentQueueIndex = _indexOfSong(_playingSongs, nextSong);

    if (_shuffleEnabled) {
      if (pendingShuffle != null) _shuffleOrder = pendingShuffle;
      _shuffleCursor = _indexOfSong(_shuffleOrder, nextSong);
    }

    StatisticsService.instance.onSongChanged(nextSong);
    PodcastStatisticsService.instance.onSongChanged(nextSong);
    PodcastStatisticsService.instance.onDurationChanged(_duration);

    // La voz promovida ya iba a la velocidad vigente (_lastSpeed se mantiene).
    _lastAppliedVolume = -1;
    _applyPlaybackEffects();
    unawaited(_applyVolume(force: true));

    _isPlaying = true;
    _lastPositionNotify = DateTime.fromMillisecondsSinceEpoch(0);
    _syncTicker();
    notifyListeners();

    // Recién ahora (ya sin riesgo de carreras) se libera la pista saliente.
    await _disposeSourceQuietly(oldSource);
  }

  // ===========================================================================
  // REPRODUCCIÓN
  // ===========================================================================

  Future<void> _loadAndPlaySong(Song song, {Duration? startAt}) async {
    final path = song.filePath;

    if (path == null || path.isEmpty || !await File(path).exists()) {
      debugPrint('[PlaybackService] Archivo no disponible: ${song.title}');
      return;
    }

    final token = ++_loadToken;

    // Se libera la pista anterior (y cualquier crossfade pendiente).
    await _releaseVoice();

    _position = Duration.zero;
    _duration = Duration.zero;
    _currentSong = song;
    _enteredViaCrossfade = false;
    _currentQueueIndex = _indexOfSong(_playingSongs, song);

    StatisticsService.instance.onSongChanged(song);
    PodcastStatisticsService.instance.onSongChanged(song);

    if (_shuffleEnabled) {
      _shuffleCursor = _indexOfSong(_shuffleOrder, song);

      if (_shuffleCursor < 0) {
        _buildShuffleOrder(keepCurrentFirst: song);
        _shuffleCursor = _indexOfSong(_shuffleOrder, song);
      }
    }

    notifyListeners();

    // Posición inicial: la pedida explícitamente (p. ej. al recargar tras
    // una invalidación en background) o, en podcasts, la guardada.
    final initialPosition =
        startAt ??
        (song.isPodcast
            ? PodcastStatisticsService.instance.resumePositionFor(song)
            : Duration.zero);

    try {
      await _ensureEngine();

      final fileSize = await File(path).length();
      final source = await _soloud.loadFile(
        path,
        mode: fileSize > _diskLoadThresholdBytes
            ? LoadMode.disk
            : LoadMode.memory,
      );

      // Mientras cargaba, el usuario eligió otra pista: se descarta esta.
      if (token != _loadToken) {
        await _disposeSourceQuietly(source);
        return;
      }

      _source = source;
      _duration = _soloud.getLength(source);
      PodcastStatisticsService.instance.onDurationChanged(_duration);

      // La voz nace en pausa y a volumen 0: seek, velocidad y volumen se
      // dejan listos ANTES de que suene el primer sample (sin "tramitos" a
      // volumen pleno ni saltos de velocidad).
      final handle = _soloud.play(source, volume: 0.0, paused: true);

      _handle = handle;
      _lastSpeed = 1.0; // una voz nueva siempre arranca a velocidad normal
      _lastAppliedVolume = 0.0;

      if (initialPosition > Duration.zero) {
        try {
          _soloud.seek(handle, initialPosition);
          _position = initialPosition;
        } catch (error) {
          debugPrint('[PlaybackService] No se pudo reanudar: $error');
        }
      }

      _applyPlaybackEffects();
      await _applyVolume(at: initialPosition, force: true);

      _soloud.setPause(handle, false);
      _isPlaying = true;
      _lastPositionNotify = DateTime.fromMillisecondsSinceEpoch(0);
      _syncTicker();
      notifyListeners();
    } catch (error) {
      _isPlaying = false;
      _syncTicker();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> appendToPlaybackQueue(Song song) async {
    if (_playingSongs.any((item) => _sameSong(item, song))) {
      return;
    }

    final path = song.filePath;

    if (path == null || path.isEmpty || !await File(path).exists()) {
      debugPrint('[PlaybackService] Archivo no disponible: ${song.title}');
      return;
    }

    if (_playingSongs.isEmpty) {
      await playQueue();
      return;
    }

    _invalidateCrossfadePlan();
    _playingSongs.add(song);

    if (_shuffleEnabled) {
      if (_shuffleOrder.isEmpty) {
        _shuffleOrder = [_currentSong, song].whereType<Song>().toList();
      } else {
        final insertAt = _shuffleCursor < 0
            ? _shuffleOrder.length
            : _shuffleCursor +
                  1 +
                  _random.nextInt(_shuffleOrder.length - _shuffleCursor);

        _shuffleOrder.insert(insertAt.clamp(0, _shuffleOrder.length), song);
      }

      _shuffleCursor = _currentSong == null
          ? -1
          : _indexOfSong(_shuffleOrder, _currentSong!);
    }

    debugPrint('[PlaybackService] Añadida al final de la cola: ${song.title}');

    notifyListeners();
  }

  Future<void> reorderPlaybackQueue(int oldIndex, int newIndex) async {
    final queue = PlaybackQueue.instance;
    final queueSongs = queue.songs;

    if (oldIndex < 0 ||
        oldIndex >= queueSongs.length ||
        newIndex < 0 ||
        newIndex > queueSongs.length) {
      return;
    }

    if (newIndex > oldIndex) {
      newIndex--;
    }

    if (oldIndex == newIndex) return;

    if (!queue.move(oldIndex, newIndex)) return;

    _invalidateCrossfadePlan();

    final reorderedSongs = queue.songs;

    _playingSongs = reorderedSongs
        .where(
          (song) =>
              _playingSongs.any((playingSong) => _sameSong(playingSong, song)),
        )
        .toList();

    _currentQueueIndex = _currentSong == null
        ? -1
        : _indexOfSong(_playingSongs, _currentSong!);

    if (_shuffleEnabled) {
      _shuffleOrder.removeWhere(
        (song) => !_playingSongs.any((item) => _sameSong(item, song)),
      );

      for (final song in _playingSongs) {
        if (!_shuffleOrder.any((item) => _sameSong(item, song))) {
          _shuffleOrder.add(song);
        }
      }

      _shuffleCursor = _currentSong == null
          ? -1
          : _indexOfSong(_shuffleOrder, _currentSong!);
    }

    debugPrint('[PlaybackService] Cola reordenada');
    notifyListeners();
  }

  Future<void> removeFromPlaybackQueue(Song song) async {
    final current = _currentSong;

    if (current != null && _sameSong(current, song)) {
      debugPrint(
        '[PlaybackService] No se puede eliminar la canción actual: ${song.title}',
      );
      return;
    }

    // La que está entrando por crossfade ya está sonando: tampoco.
    final incoming = _nextSong;
    if (_crossfading && incoming != null && _sameSong(incoming, song)) {
      return;
    }

    final queue = PlaybackQueue.instance;

    if (!queue.contains(song)) return;

    _invalidateCrossfadePlan();
    queue.remove(song);

    _playingSongs.removeWhere((item) => _sameSong(item, song));
    _shuffleOrder.removeWhere((item) => _sameSong(item, song));

    _currentQueueIndex = current == null
        ? -1
        : _indexOfSong(_playingSongs, current);

    _shuffleCursor = current == null
        ? -1
        : _indexOfSong(_shuffleOrder, current);

    debugPrint('[PlaybackService] Eliminada de la cola: ${song.title}');

    notifyListeners();
  }

  Future<void> pause() async {
    final handle = _handle;

    if (handle != null && _isHandleAlive()) {
      _position = _livePosition();
      _soloud.setPause(handle, true);
    }

    // Pausar también la voz entrante si estamos en crossfade.
    final nextHandle = _nextHandle;
    if (nextHandle != null && _isValid(nextHandle)) {
      try {
        _soloud.setPause(nextHandle, true);
      } catch (_) {}
    }

    _isPlaying = false;
    _syncTicker();
    notifyListeners();

    await PodcastStatisticsService.instance.flush();
  }

  /// Punto desde el que recargar la pista actual si su voz murió (para no
  /// volver al segundo 0 tras una invalidación en background).
  Duration? _resumePointForReload() {
    final song = _currentSong;
    if (song == null) return null;

    if (_position <= const Duration(seconds: 1)) return null;

    if (_duration > Duration.zero &&
        _position >= _duration - const Duration(seconds: 1)) {
      return null;
    }

    return _position;
  }

  Future<void> resume() async {
    if (_playingSongs.isEmpty) return;

    if (_currentSong == null) {
      await playQueue();
      return;
    }

    var handle = _handle;

    // Mezcla en curso cuya pista saliente ya terminó: se promueve la entrante.
    if (handle != null && !_isHandleAlive() && _crossfading) {
      await _finishCrossfade();
      handle = _handle;
    }

    // Sin voz, o voz invalidada por el sistema (background, pérdida de audio
    // focus, Bluetooth desconectado): se vuelve a cargar, retomando desde la
    // posición donde estaba, en vez de intentar reanudar una voz muerta.
    if (handle == null || !_isHandleAlive()) {
      debugPrint(
        '[PlaybackService] Voz no válida al reanudar; recargando pista.',
      );
      await _loadAndPlaySong(_currentSong!, startAt: _resumePointForReload());
      return;
    }

    // Volumen que toca en la posición actual (si se pausó a mitad de un
    // fade o de un crossfade, continúa desde ahí) antes de que vuelva a sonar.
    await _applyVolume(force: true);

    try {
      _soloud.setPause(handle, false);
    } catch (error) {
      debugPrint(
        '[PlaybackService] Fallo al reanudar la voz; recargando: $error',
      );
      await _loadAndPlaySong(_currentSong!, startAt: _resumePointForReload());
      return;
    }

    // Reanudar también la voz entrante si estamos en crossfade.
    final nextHandle = _nextHandle;
    if (nextHandle != null && _isValid(nextHandle)) {
      try {
        _soloud.setPause(nextHandle, false);
      } catch (_) {}
    }

    _isPlaying = true;
    _syncTicker();
    notifyListeners();
  }

  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await pause();
    } else {
      await resume();
    }
  }

  Future<void> playSongFromQueue(Song song) async {
    if (_isLoading) return;

    final index = _indexOfSong(_playingSongs, song);

    if (index < 0) {
      debugPrint('[PlaybackService] La canción no está cargada: ${song.title}');
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      if (_shuffleEnabled &&
          !_shuffleOrder.any((item) => _sameSong(item, song))) {
        _buildShuffleOrder(keepCurrentFirst: song);
      }

      await _loadAndPlaySong(song);
    } catch (error) {
      debugPrint('[PlaybackService] Error al seleccionar canción: $error');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> playNext() async {
    if (_isLoading || _playingSongs.isEmpty || _currentSong == null) {
      return;
    }

    final nextSong = _getNextSong();

    if (nextSong == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      await _loadAndPlaySong(nextSong);
    } catch (error) {
      debugPrint('[PlaybackService] Error al reproducir siguiente: $error');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> playPrevious() async {
    if (_isLoading || _playingSongs.isEmpty || _currentSong == null) {
      return;
    }

    if (_position > const Duration(seconds: 3)) {
      await seek(Duration.zero);
      return;
    }

    final previousSong = _getPreviousSong();

    if (previousSong == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      await _loadAndPlaySong(previousSong);
    } catch (error) {
      debugPrint('[PlaybackService] Error al reproducir anterior: $error');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Siguiente canción según cola / aleatorio / repetición.
  ///
  /// Con [commit] = false no modifica el estado: es solo una "mirada" (la usa
  /// el crossfade). Si la vuelta aleatoria se completa, el nuevo orden se
  /// guarda en [_pendingShuffleOrder] y se aplica al promover la pista.
  Song? _getNextSong({bool commit = true}) {
    if (_shuffleEnabled) {
      if (_shuffleCursor < 0) return null;

      if (_shuffleCursor < _shuffleOrder.length - 1) {
        return _shuffleOrder[_shuffleCursor + 1];
      }

      if (_repeatMode == LoopMode.all && _shuffleOrder.length > 1) {
        final current = _currentSong;
        final order = _shuffleForWrap(current);

        if (commit) {
          _shuffleOrder = order;
          _pendingShuffleOrder = null;
          _shuffleCursor = current == null ? -1 : _indexOfSong(order, current);
        } else {
          _pendingShuffleOrder = order;
        }

        return order.first;
      }

      return null;
    }

    if (_currentQueueIndex < 0) return null;

    if (_currentQueueIndex < _playingSongs.length - 1) {
      return _playingSongs[_currentQueueIndex + 1];
    }

    if (_repeatMode == LoopMode.all && _playingSongs.length > 1) {
      return _playingSongs.first;
    }

    return null;
  }

  Song? _getPreviousSong() {
    if (_shuffleEnabled) {
      if (_shuffleCursor > 0) {
        return _shuffleOrder[_shuffleCursor - 1];
      }

      if (_repeatMode == LoopMode.all && _shuffleOrder.length > 1) {
        return _shuffleOrder.last;
      }

      return null;
    }

    if (_currentQueueIndex > 0) {
      return _playingSongs[_currentQueueIndex - 1];
    }

    if (_repeatMode == LoopMode.all && _playingSongs.length > 1) {
      return _playingSongs.last;
    }

    return null;
  }

  Future<void> _handleTrackCompleted() async {
    if (_handlingCompletion || _isLoading || _currentSong == null) {
      return;
    }

    _handlingCompletion = true;

    try {
      PodcastStatisticsService.instance.onTrackCompleted();

      // Libera la fuente de la pista que terminó.
      await _releaseVoice();

      if (_repeatMode == LoopMode.one) {
        await _loadAndPlaySong(_currentSong!);
        return;
      }

      final nextSong = _getNextSong();

      if (nextSong != null) {
        await _loadAndPlaySong(nextSong);
      } else {
        _isPlaying = false;
        _position = _duration;
        _syncTicker();
        notifyListeners();
      }
    } catch (error) {
      debugPrint('[PlaybackService] Error al avanzar la reproducción: $error');
    } finally {
      _handlingCompletion = false;
    }
  }

  Future<void> seek(Duration position) async {
    final handle = _handle;
    if (handle == null || !_isHandleAlive()) return;

    var target = position;

    if (target < Duration.zero) target = Duration.zero;
    if (_duration > Duration.zero && target > _duration) target = _duration;

    try {
      _soloud.seek(handle, target);
    } catch (error) {
      debugPrint('[PlaybackService] No se pudo hacer seek: $error');
      return;
    }

    _position = target;

    // Volver al inicio de una pista que entró por crossfade: su fade in
    // vuelve a aplicar como en cualquier otra pista.
    if (target < const Duration(seconds: 1)) _enteredViaCrossfade = false;

    // Mezcla activa: si se salta antes de la ventana se cancela; si se salta
    // dentro de ella, la entrante se realinea con el nuevo progreso.
    if (_crossfading) {
      final offsetMs = target.inMilliseconds - _crossfadeStartMs;

      if (offsetMs < 0) {
        _cancelCrossfade();
      } else {
        final nextHandle = _nextHandle;
        if (nextHandle != null && _isValid(nextHandle)) {
          try {
            _soloud.seek(
              nextHandle,
              Duration(milliseconds: min(offsetMs, _crossfadeSpanMs)),
            );
          } catch (_) {}
        }
      }
    }

    StatisticsService.instance.onSeek(target);
    PodcastStatisticsService.instance.onSeek(target);

    // Volumen que toca en la posición de destino: al saltar dentro de un
    // fade, suena en su nivel correcto; al saltar fuera, vuelve al pleno.
    await _applyVolume(at: target);

    notifyListeners();
  }

  Future<void> stop() async {
    _loadToken++; // invalida cualquier carga en curso

    _ticker?.cancel();
    _ticker = null;
    _fadeIndex = null;
    _fadeIndexKey = null;

    await _releaseVoice(); // también limpia el crossfade

    _playingSongs = [];
    _shuffleOrder = [];
    _currentSong = null;
    _currentQueueIndex = -1;
    _shuffleCursor = -1;
    _position = Duration.zero;
    _duration = Duration.zero;
    _isPlaying = false;
    _isLoading = false;
    _handlingCompletion = false;
    _enteredViaCrossfade = false;
    _lastSpeed = 1.0;

    StatisticsService.instance.onSongChanged(null);
    PodcastStatisticsService.instance.onSongChanged(null);
    await PodcastStatisticsService.instance.flush();

    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    SettingsService.instance.removeListener(_onSettingsChanged);
    unawaited(_releaseVoice());
    unawaited(PodcastStatisticsService.instance.flush());
    super.dispose();
  }
}
