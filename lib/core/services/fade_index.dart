import 'dart:math' as math;
import 'dart:typed_data';

/// Índice de volumen por tiempo para fade in / fade out.
///
/// Dado el tiempo de cada fade y la duración de la pista, precalcula tablas
/// con una entrada cada [stepMs] ms. [gainAt] devuelve la ganancia (0..1)
/// que toca en una posición cualquiera, así que funciona igual con
/// reproducción normal, seek, pausa o reanudación.
///
/// - Fade in:  ganancia 0.0 exacta en la posición 0 → 1.0 en `fadeInMs`.
/// - Fade out: 1.0 en `trackMs - fadeOutMs` → 0.0 exacta en
///   `trackMs - silenceGuardMs`, y 0.0 hasta el final de la pista.
class FadeIndex {
  FadeIndex._({
    required this.fadeInMs,
    required this.fadeOutMs,
    required this.trackMs,
    required Float32List inTable,
    required Float32List outTable,
  }) : _inTable = inTable,
       _outTable = outTable;

  /// Resolución del índice: 50 ms = 20 entradas por segundo.
  static const int stepMs = 50;

  /// Margen final en silencio absoluto (el timer puede llegar tarde al
  /// último instante; con este margen el último tick siempre cae en 0).
  static const int silenceGuardMs = 120;

  /// Duraciones efectivas (ya limitadas a la mitad de la pista).
  final int fadeInMs;
  final int fadeOutMs;
  final int trackMs;

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

    return FadeIndex._(
      fadeInMs: inMs,
      fadeOutMs: outMs,
      trackMs: trackMs,
      inTable: _buildInTable(inMs),
      outTable: _buildOutTable(outMs),
    );
  }

  static Float32List _buildInTable(int inMs) {
    if (inMs <= 0) return Float32List(0);

    final n = (inMs / stepMs).ceil();
    final table = Float32List(n + 1);

    for (var i = 0; i <= n; i++) {
      final elapsed = math.min(i * stepMs, inMs);
      table[i] = _curve(elapsed / inMs);
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
      'FadeIndex(in=${fadeInMs}ms, out=${fadeOutMs}ms, pista=${trackMs}ms)\n',
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
