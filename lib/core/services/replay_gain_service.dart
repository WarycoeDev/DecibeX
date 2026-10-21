import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';

import '../models/song.dart';
import 'library_scanner.dart';

/// Calcula la ganancia ReplayGain 2.0 por archivo usando FFmpeg (EBU R128).
///
/// Optimizaciones clave:
/// - Sin ffprobe síncrono: si la duración no está en el Song, se analiza
///   solo el fragmento estándar (10s skip + 20s muestra).
/// - 4 workers en paralelo (ebur128 es single-thread, hay cores de sobra).
/// - Salida a /dev/null en vez de stdout (evita buffer en memoria).
/// - Cache negativo de pistas fallidas para no reintentarlas en el próximo run.
/// - Parseo tolerante: si no hay "Summary:", usa el último "I:" del log.
class ReplayGainService extends ChangeNotifier {
  ReplayGainService._();

  static final ReplayGainService instance = ReplayGainService._();

  // --- Configuración de análisis ---

  /// Target ReplayGain 2.0 (EBU R128, −18 LUFS).
  static const double _targetLufs = -18.0;

  static const double _minGainDb = -12.0;
  static const double _maxGainDb = 12.0;

  /// Segundos a saltar al inicio (evita fades-in / silencios).
  static const double _skipStart = 10.0;

  /// Segundos a saltar al final (evita fades-out / silencios).
  static const double _skipEnd = 10.0;

  /// Duración del fragmento a analizar. 20s basta para estimar LUFS
  /// integrado con error < 0.7 dB en la mayoría de música.
  static const double _sampleDuration = 20.0;

  /// Cuántas pistas analizar en paralelo. ebur128 es single-thread;
  /// 4 satura bien móviles modernos sin ahogar la UI.
  static const int _maxParallel = 4;

  static const int _saveBatchSize = 25;

  // --- Estado expuesto ---

  bool isRunning = false;
  int processed = 0;
  int total = 0;
  String? lastError;

  /// Último tiempo medido por pista (ms), útil para diagnóstico.
  int lastTrackMs = 0;

  /// Pistas que fallaron en esta sesión (o persistidas externamente).
  /// Se saltan en runs posteriores hasta que el usuario haga clearAll().
  final Set<String> _failed = {};

  Future<void> analyzeLibrary({bool force = false}) async {
    if (isRunning) return;

    final scanner = LibraryScanner.instance;

    final targets = scanner.musicSongs
        .where((s) => force || s.replayGainDb == null)
        .where((s) => s.filePath != null)
        .where((s) => !_failed.contains(s.filePath))
        .toList();

    if (targets.isEmpty) {
      processed = 0;
      total = 0;
      notifyListeners();
      return;
    }

    isRunning = true;
    processed = 0;
    total = targets.length;
    lastError = null;
    notifyListeners();

    var sinceLastSave = 0;
    var index = 0;

    Future<void> worker() async {
      while (isRunning && index < targets.length) {
        final song = targets[index++];
        final path = song.filePath!;
        final sw = Stopwatch()..start();

        try {
          if (!await File(path).exists()) {
            processed++;
            notifyListeners();
            continue;
          }

          final totalSeconds = _resolveDurationSeconds(song);
          final gain = await _measureGain(path, totalSeconds);
          await scanner.setReplayGain(song, gain);

          sinceLastSave++;
          if (sinceLastSave >= _saveBatchSize) {
            await scanner.saveIndexNow();
            sinceLastSave = 0;
          }
        } catch (e) {
          _failed.add(path);
          debugPrint('[ReplayGain] Falló "${song.title}": $e');
        } finally {
          lastTrackMs = sw.elapsedMilliseconds;
        }

        processed++;
        notifyListeners();
      }
    }

    try {
      final workers = targets.length < _maxParallel
          ? targets.length
          : _maxParallel;

      await Future.wait(List.generate(workers, (_) => worker()));
      await scanner.saveIndexNow();
    } catch (e) {
      lastError = e.toString();
      debugPrint('[ReplayGain] Error general: $e');
    } finally {
      isRunning = false;
      notifyListeners();
    }
  }

  void cancel() {
    if (!isRunning) return;
    isRunning = false;
    notifyListeners();
  }

  Future<void> clearAll() async {
    if (isRunning) return;

    final scanner = LibraryScanner.instance;
    final targets = scanner.musicSongs
        .where((s) => s.replayGainDb != null)
        .toList();

    for (final song in targets) {
      await scanner.setReplayGain(song, null);
    }

    await scanner.saveIndexNow();
    _failed.clear();
    processed = 0;
    total = 0;
    notifyListeners();
  }

  /// Devuelve la duración total en segundos SOLO si ya está en el Song.
  /// Si no, retorna 0 y `_sampleWindow` usará el fragmento estándar.
  /// No invoca ffprobe: el coste (~100-300ms + proceso nativo) no compensa
  /// para canciones cortas, y el window ya maneja el caso desconocido.
  double _resolveDurationSeconds(Song song) {
    final parsed = _parseDuration(song.duration);
    if (parsed != null && parsed > 0) return parsed;
    return 0;
  }

  double? _parseDuration(String duration) {
    final parts = duration.split(':');
    try {
      if (parts.length == 2) {
        final m = int.parse(parts[0]);
        final s = int.parse(parts[1]);
        return (m * 60 + s).toDouble();
      }
      if (parts.length == 3) {
        final h = int.parse(parts[0]);
        final m = int.parse(parts[1]);
        final s = int.parse(parts[2]);
        return (h * 3600 + m * 60 + s).toDouble();
      }
    } catch (_) {}
    return null;
  }

  /// Construye los argumentos FFmpeg para analizar solo un fragmento.
  ({double seek, double length}) _sampleWindow(double totalSeconds) {
    if (totalSeconds <= 0) {
      return (seek: _skipStart, length: _sampleDuration);
    }

    final safeEnd = totalSeconds - _skipEnd;

    // Canción muy corta: analiza desde el inicio sin skip final.
    if (safeEnd <= _skipStart + 2) {
      return (seek: 0, length: totalSeconds.clamp(1.0, _sampleDuration));
    }

    final available = safeEnd - _skipStart;

    if (available <= _sampleDuration) {
      return (seek: _skipStart, length: available);
    }

    return (seek: _skipStart, length: _sampleDuration);
  }

  Future<double> _measureGain(String path, double totalSeconds) async {
    final window = _sampleWindow(totalSeconds);
    final safePath = path.replaceAll('\\', '/').replaceAll("'", r"'\''");

    // -ss antes de -i: seek rápido (no decodifica lo anterior).
    // -t después de -i: limita la duración procesada.
    // ebur128 con peak=true mide LUFS integrado + true peak del fragmento.
    // -f null /dev/null: evita que FFmpegKit acumule output en memoria.
    final command =
        "-hide_banner -nostats "
        "-ss ${window.seek.toStringAsFixed(2)} "
        "-t ${window.length.toStringAsFixed(2)} "
        "-i '$safePath' "
        "-af ebur128=peak=true "
        "-f null /dev/null";

    final session = await FFmpegKit.execute(command);
    final output = await session.getOutput() ?? '';
    final code = await session.getReturnCode();

    if (!ReturnCode.isSuccess(code)) {
      throw Exception('FFmpeg falló con código $code');
    }

    final lufs = _extractLufs(output);
    if (lufs == null) {
      throw Exception('Sin LUFS en la salida de ebur128');
    }

    final peakMatches = RegExp(
      r'Peak:\s*(-?\d+(?:\.\d+)?)\s*dBFS',
    ).allMatches(output).toList();
    final peakDb = peakMatches.isEmpty
        ? 0.0
        : double.parse(peakMatches.last.group(1)!);

    var gain = _targetLufs - lufs;

    // Prevención de clipping: si pico + gain > 0 dBFS, atenuar.
    final projectedPeak = peakDb + gain;
    if (projectedPeak > 0) {
      gain -= projectedPeak;
    }

    return gain.clamp(_minGainDb, _maxGainDb).toDouble();
  }

  /// Extrae el LUFS integrado. Prefiere el bloque `Summary:` si existe,
  /// pero cae al último `I:` del log completo (ebur128 no siempre imprime
  /// Summary en fragmentos muy cortos o silenciosos).
  double? _extractLufs(String output) {
    final summaryIdx = output.lastIndexOf('Summary:');
    final scope = summaryIdx >= 0 ? output.substring(summaryIdx) : output;

    final matches = RegExp(
      r'I:\s*(-?\d+(?:\.\d+)?)\s*LUFS',
    ).allMatches(scope).toList();

    if (matches.isEmpty) return null;
    return double.parse(matches.last.group(1)!);
  }
}
