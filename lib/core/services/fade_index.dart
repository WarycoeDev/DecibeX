import 'dart:math' as math;
import 'dart:typed_data';

/// Índice de volumen por tiempo para fade in / fade out.
///
/// Dado el tiempo de cada fade y la duración de la pista, precalcula tablas
/// con una entrada cada [stepMs] ms. [gainAt] devuelve la ganancia (0..1)
/// que toca en una posición cualquiera, así que funciona igual con
/// reproducción normal, seek, pausa o reanudación.
///
/// - Fade in:  ganancia 0.0 exacta en la posición 0, se mantiene en 0.0
///   durante [startSilenceGuardMs] para absorber el jitter entre `play()`
///   y el primer buffer audible, y llega a 1.0 en `fadeInMs`.
/// - Fade out: 1.0 en `trackMs - fadeOutMs` → 0.0 exacta en
///   `trackMs - silenceGuardMs`, y 0.0 hasta el final de la pista.
class FadeIndex {
  FadeIndex._({
    required this.fadeInMs,
    required this.fadeOutMs,
    required this.trackMs,
    required int startGuardMs,
    required Float32List inTable,
    required Float32List outTable,
  }) : _startGuardMs = startGuardMs,
       _inTable = inTable,
       _outTable = outTable;

  /// Resolución del índice: 50 ms = 20 entradas por segundo.
  static const int stepMs = 50;

  /// Margen final en silencio absoluto (el timer puede llegar tarde al
  /// último instante; con este margen el último tick siempre cae en 0).
  static const int silenceGuardMs = 120;

  /// Margen inicial en silencio absoluto. Absorbe el desfase entre el
  /// momento en que se llama a `play()` y el primer buffer que llega
  /// realmente al dispositivo de audio (típicamente 100-300 ms en
  /// Android/iOS). Sin esto se escucha un "tramito" a volumen pleno.
  static const int startSilenceGuardMs = 220;

  /// Duraciones efectivas (ya limitadas a la mitad de la pista).
  final int fadeInMs;
  final int fadeOutMs;
  final int trackMs;

  /// Guard inicial efectivo aplicado a esta pista (recortado si el fade
  /// in es muy corto).
  final int _startGuardMs;

  /// `_inTable[i]` = ganancia a `i * stepMs` ms desde el inicio.
  final Float32List _inTable;

  /// `_outTable[i]` = ganancia cuando faltan `i * stepMs` ms para el final.
  final Float32List _outTable;

  factory FadeIndex.build({
    required Duration fadeIn,
    required Duration fadeOut,
    required Duration track,
  }) {
    final trackMs = track.inMilliseconds;

    var inMs = math.max(0, fadeIn.inMilliseconds);
    // Sin duración conocida no se puede anclar el fade out al final.
    var outMs = trackMs > 0 ? math.max(0, fadeOut.inMilliseconds) : 0;

    if (trackMs > 0) {
      final half = trackMs ~/ 2;
      inMs = math.min(inMs, half);
      outMs = math.min(outMs, half);
    }

    // El guard inicial nunca puede consumir todo el fade in: si el fade in
    // es más corto que el guard, el guard se recorta a 1/4 del fade in.
    final startGuard = inMs > 0 ? math.min(startSilenceGuardMs, inMs ~/ 4) : 0;

    return FadeIndex._(
      fadeInMs: inMs,
      fadeOutMs: outMs,
      trackMs: trackMs,
      startGuardMs: startGuard,
      inTable: _buildInTable(inMs, startGuard),
      outTable: _buildOutTable(outMs),
    );
  }

  static Float32List _buildInTable(int inMs, int startGuard) {
    if (inMs <= 0) return Float32List(0);

    final n = (inMs / stepMs).ceil();
    final table = Float32List(n + 1);

    // El fade in "útil" empieza después del guard inicial.
    final span = inMs - startGuard;

    for (var i = 0; i <= n; i++) {
      final elapsed = math.min(i * stepMs, inMs);
      if (elapsed <= startGuard) {
        table[i] = 0.0;
      } else if (span <= 0) {
        table[i] = 1.0;
      } else {
        table[i] = _curve((elapsed - startGuard) / span);
      }
    }

    table[0] = 0.0; // silencio absoluto en el primer instante
    return table;
  }

  static Float32List _buildOutTable(int outMs) {
    if (outMs <= 0) return Float32List(0);

    final guard = math.min(silenceGuardMs, outMs ~/ 4);
    final span = outMs - guard; // > 0 porque guard <= outMs / 4
    final n = (outMs / stepMs).ceil();
    final table = Float32List(n + 1);

    for (var i = 0; i <= n; i++) {
      final remaining = math.min(i * stepMs, outMs);
      table[i] = _curve((remaining - guard) / span);
    }

    table[0] = 0.0; // silencio absoluto en el último instante
    return table;
  }

  /// Curva suave (smoothstep): arranque y llegada sin saltos.
  static double _curve(double t) {
    final x = t.clamp(0.0, 1.0).toDouble();
    return x * x * (3 - 2 * x);
  }

  static double _lookup(Float32List table, double ms) {
    if (ms <= 0) return table.first;

    final pos = ms / stepMs;
    final i = pos.floor();

    if (i >= table.length - 1) return table.last;

    final frac = pos - i;
    return table[i] + (table[i + 1] - table[i]) * frac;
  }

  bool get hasFades => _inTable.isNotEmpty || _outTable.isNotEmpty;

  /// Ganancia (0..1) que toca en [position].
  double gainAt(Duration position) {
    final posMs = position.inMicroseconds / 1000.0;
    var gain = 1.0;

    if (_inTable.isNotEmpty && posMs < fadeInMs) {
      gain *= _lookup(_inTable, posMs);
    }

    if (_outTable.isNotEmpty && trackMs > 0) {
      final remaining = trackMs - posMs;
      if (remaining < fadeOutMs) {
        gain *= _lookup(_outTable, math.max(0.0, remaining));
      }
    }

    return gain.clamp(0.0, 1.0).toDouble();
  }

  /// Tabla legible "segundo → ganancia" para depurar.
  String debugDescribe() {
    final b = StringBuffer(
      'FadeIndex(in=${fadeInMs}ms, out=${fadeOutMs}ms, pista=${trackMs}ms, '
      'startGuard=${_startGuardMs}ms)\n',
    );

    if (_inTable.isNotEmpty) {
      for (var ms = 0; ms <= fadeInMs; ms += 1000) {
        final g = gainAt(Duration(milliseconds: ms)).toStringAsFixed(3);
        b.writeln('  in  ${(ms / 1000).toStringAsFixed(1)} s → $g');
      }
    }

    if (_outTable.isNotEmpty) {
      for (var ms = trackMs - fadeOutMs; ms <= trackMs; ms += 1000) {
        final g = gainAt(Duration(milliseconds: ms)).toStringAsFixed(3);
        b.writeln('  out ${(ms / 1000).toStringAsFixed(1)} s → $g');
      }
      b.writeln('  out ${(trackMs / 1000).toStringAsFixed(1)} s → 0.000');
    }

    return b.toString();
  }
}
