import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';

import '../models/song.dart';
import 'library_scanner.dart';

/// Calcula la ganancia ReplayGain 2.0 por archivo usando FFmpeg (EBU R128).
///
/// Para acelerar el análisis SOLO procesa un fragmento representativo de
/// cada canción (por defecto: 10 s de skip, 30 s de muestra, 10 s de skip
/// final). Esto reduce el tiempo por pista de ~30 s a ~2-4 s sin pérdida
/// perceptible de precisión (< 0.5 dB de error típico).
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

  /// Duración del fragmento a analizar. 30 s es suficiente para estimar
  /// LUFS integrado con error < 0.5 dB en la mayoría de música.
  static const double _sampleDuration = 30.0;

  /// Cuántas pistas analizar en paralelo. FFmpeg es intensivo en CPU;
  /// 2 satura la mayoría de móviles sin ahogar la UI.
  static const int _maxParallel = 2;

  static const int _saveBatchSize = 25;

  // --- Estado expuesto ---

  bool isRunning = false;
  int processed = 0;
  int total = 0;
  String? lastError;

  /// Último tiempo medido por pista (ms), útil para diagnóstico.
  int lastTrackMs = 0;

  Future<void> analyzeLibrary({bool force = false}) async {
    if (isRunning) return;

    final scanner = LibraryScanner.instance;

    final targets = scanner.musicSongs
        .where((s) => force || s.replayGainDb == null)
        .where((s) => s.filePath != null)
        .toList();

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

          // Necesitamos la duración total para calcular el skip final.
          final totalSeconds = await _resolveDurationSeconds(song, path);

          final gain = await _measureGain(path, totalSeconds);
          await scanner.setReplayGain(song, gain);

          sinceLastSave++;
          if (sinceLastSave >= _saveBatchSize) {
            await scanner.saveIndexNow();
            sinceLastSave = 0;
          }
        } catch (e) {
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
    processed = 0;
    total = 0;
    notifyListeners();
  }

  /// Devuelve la duración total en segundos. Primero intenta parsear el
  /// `duration` del Song (formato `m:ss` o `h:mm:ss`). Si es `0:00` o
  /// inválido, hace un ffprobe rápido (~100 ms).
  Future<double> _resolveDurationSeconds(Song song, String path) async {
    final parsed = _parseDuration(song.duration);
    if (parsed != null && parsed > 0) return parsed;

    try {
      final session = await FFprobeKit.getMediaInformation(path);
      final info = session.getMediaInformation();
      final durationStr = info?.getDuration();
      if (durationStr != null) {
        final seconds = double.tryParse(durationStr);
        if (seconds != null && seconds > 0) return seconds;
      }
    } catch (e) {
      debugPrint('[ReplayGain] ffprobe falló para $path: $e');
    }

    return 0; // desconocida → se analizará sin skip final
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
  ///
  /// - Sin duración conocida: analiza solo `_sampleDuration` desde `_skipStart`.
  /// - Con duración conocida: analiza `_sampleDuration` desde `_skipStart`,
  ///   pero si la canción es muy corta, ajusta para no analizar el final.
  ({double seek, double length}) _sampleWindow(double totalSeconds) {
    if (totalSeconds <= 0) {
      // Desconocida: confía en que hay al menos skipStart + sample.
      return (seek: _skipStart, length: _sampleDuration);
    }

    final safeEnd = totalSeconds - _skipEnd;

    // Canción muy corta: analiza desde el inicio sin skip final.
    if (safeEnd <= _skipStart + 2) {
      return (seek: 0, length: totalSeconds.clamp(1.0, _sampleDuration));
    }

    final available = safeEnd - _skipStart;

    if (available <= _sampleDuration) {
      // Canción corta pero válida: analiza todo el tramo útil.
      return (seek: _skipStart, length: available);
    }

    // Canción normal: fragmento de _sampleDuration.
    return (seek: _skipStart, length: _sampleDuration);
  }

  Future<double> _measureGain(String path, double totalSeconds) async {
    final window = _sampleWindow(totalSeconds);
    final safePath = path.replaceAll('\\', '/').replaceAll("'", r"'\''");

    // -ss antes de -i: seek rápido (no decodifica lo anterior).
    // -t después de -i: limita la duración procesada.
    // ebur128 con peak=true mide LUFS integrado + true peak del fragmento.
    final command =
        "-hide_banner -nostats "
        "-ss ${window.seek.toStringAsFixed(2)} "
        "-t ${window.length.toStringAsFixed(2)} "
        "-i '$safePath' "
        "-af ebur128=peak=true -f null -";

    final session = await FFmpegKit.execute(command);
    final output = await session.getOutput() ?? '';
    final code = await session.getReturnCode();

    if (!ReturnCode.isSuccess(code)) {
      throw Exception('FFmpeg falló con código $code');
    }

    final summaryIdx = output.lastIndexOf('Summary:');
    if (summaryIdx < 0) {
      throw Exception('Salida de ebur128 sin Summary');
    }
    final summary = output.substring(summaryIdx);

    final integratedMatch = RegExp(
      r'I:\s*(-?\d+(?:\.\d+)?)\s*LUFS',
    ).firstMatch(summary);
    final peakMatch = RegExp(
      r'Peak:\s*(-?\d+(?:\.\d+)?)\s*dBFS',
    ).firstMatch(summary);

    if (integratedMatch == null) {
      throw Exception('Sin LUFS integrado');
    }

    final lufs = double.parse(integratedMatch.group(1)!);
    final peakDb = peakMatch != null ? double.parse(peakMatch.group(1)!) : 0.0;

    var gain = _targetLufs - lufs;

    // Prevención de clipping: si pico + gain > 0 dBFS, atenuar.
    final projectedPeak = peakDb + gain;
    if (projectedPeak > 0) {
      gain -= projectedPeak;
    }

    return gain.clamp(_minGainDb, _maxGainDb).toDouble();
  }
}
