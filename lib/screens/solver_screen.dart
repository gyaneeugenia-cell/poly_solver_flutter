import 'package:file_selector/file_selector.dart' as fs;
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';

import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../state/session.dart';
import '../api/api_client.dart';
import 'login_screen.dart';

// ✅ THIS LINE ONLY for web CSV download support
import '../utils/web_download_stub.dart'
    if (dart.library.html) '../utils/web_download.dart';



class _HistoryItem {
  _HistoryItem({
    required this.timestamp,
    required this.userName,
    required this.equation,
    required this.realRootsText,
    required this.complexRootsText,
  });

  final DateTime timestamp;
  final String userName;
  final String equation;
  final String realRootsText;
  final String complexRootsText;
}

class SolverScreen extends StatefulWidget {
  const SolverScreen({
    super.key,
    required this.session,
    required this.onLogout,
    this.userName,
  });

  final Session session;
  final VoidCallback onLogout;

  /// Optional, so this file compiles even if you do not pass it yet.
  /// If you want CSV to include the username, pass it from login_screen.dart.
  final String? userName;

  @override
  State<SolverScreen> createState() => _SolverScreenState();
}

class _SolverScreenState extends State<SolverScreen> {
  @override
  void initState() {
    super.initState();
    _loadHistoryFromServer();
  }

  final _degreeCtrl = TextEditingController(text: '2');
  final _coeffsCtrl = TextEditingController(text: '1, 0, -1');
  final ScrollController _mobileScrollCtrl = ScrollController();

  bool _loading = false;
  String? _error;
  

  bool _hasSolved = false;
  bool _hasPlotted = false;
  bool _showGraph = true;

  String _equation = '';
  List<double> _coeffs = [];

  String _realRootsText = '';
  String _complexRootsText = '';

  final List<_HistoryItem> _history = [];

  double _baseXMin = -10;
  double _baseXMax = 10;

  double _viewXMin = -10;
  double _viewXMax = 10;
  double _viewYMin = -10;
  double _viewYMax = 10;

  List<FlSpot> _curve = [];
  List<double> _realRoots = [];

  final GlobalKey _graphKey = GlobalKey();

  List<double> _parseCoeffs(String text) {
    return text.split(',').map((e) => double.parse(e.trim())).toList();
  }

  double _evalPoly(List<double> c, double x) {
    double y = 0;
    for (int i = 0; i < c.length; i++) {
      y += c[i] * pow(x, c.length - i - 1);
    }
    return y;
  }

  double _cauchyBound(List<double> coeffs) {
    if (coeffs.isEmpty) return 10;
    final a0 = coeffs.first.abs();
    if (a0 < 1e-12) return 10;
    double maxRatio = 0;
    for (int i = 1; i < coeffs.length; i++) {
      maxRatio = max(maxRatio, coeffs[i].abs() / a0);
    }
    final r = 1.0 + maxRatio;
    if (!r.isFinite || r <= 0) return 10;
    return min(1000.0, max(5.0, r));
  }

String _caretToSuperscript(String eq) {
  return eq.replaceAllMapped(
    RegExp(r'\^(-?\d+)'),
    (m) => _toSuperscriptInt(int.parse(m.group(1)!)),
  );
}


  String _toSuperscriptInt(int n) {
    const map = {
      '0': '⁰',
      '1': '¹',
      '2': '²',
      '3': '³',
      '4': '⁴',
      '5': '⁵',
      '6': '⁶',
      '7': '⁷',
      '8': '⁸',
      '9': '⁹',
      '-': '⁻',
    };
    final s = n.toString();
    return s.split('').map((ch) => map[ch] ?? ch).join();
  }


  String _formatEquationUnicode(List<double> coeffs) {
    final n = coeffs.length - 1;
    final parts = <String>[];

    for (int i = 0; i < coeffs.length; i++) {
      final a = coeffs[i];
      final p = n - i;
      if (a.abs() < 1e-12) continue;

      final sign = a >= 0 ? '+' : '-';
      final absA = a.abs();

      String term;
      if (p == 0) {
        term = absA.toString();
      } else if (p == 1) {
        if ((absA - 1).abs() < 1e-12) {
          term = 'x';
        } else {
          term = '${absA}x';
        }
      } else {
        final sup = _toSuperscriptInt(p);
        if ((absA - 1).abs() < 1e-12) {
          term = 'x$sup';
        } else {
          term = '${absA}x$sup';
        }
      }

      if (parts.isEmpty) {
        parts.add(a >= 0 ? term : '- $term');
      } else {
        parts.add(' $sign $term');
      }
    }

    final body = parts.isEmpty ? '0' : parts.join();
    return 'f(x) = $body';
  }



  void _computeCurveAndFitY() {
    if (_coeffs.isEmpty) return;

    const samples = 700;
    final xMin = _viewXMin;
    final xMax = _viewXMax;

    final pts = <FlSpot>[];
    double minY = double.infinity;
    double maxY = -double.infinity;

    for (int i = 0; i <= samples; i++) {
      final x = xMin + (xMax - xMin) * i / samples;
      final y = _evalPoly(_coeffs, x);
      if (y.isFinite) {
        minY = min(minY, y);
        maxY = max(maxY, y);
      }
      pts.add(FlSpot(x, y));
    }

    if (!minY.isFinite || !maxY.isFinite) {
      minY = -10;
      maxY = 10;
    }

    final span = (maxY - minY).abs();
    final pad = span == 0 ? 1.0 : span * 0.12;

    final interval = _niceInterval(span);

    _viewYMin = _snap(minY - pad, interval, false);
    _viewYMax = _snap(maxY + pad, interval, true);


    if (_viewYMin > 0) _viewYMin = 0 - pad;
    if (_viewYMax < 0) _viewYMax = 0 + pad;

    _curve = pts;
  }

  double _niceInterval(double span) {
    if (!span.isFinite || span <= 0) return 1;
    final targetTicks = 8.0;
    final raw = span / targetTicks;
    final pow10 = pow(10, (log(raw) / ln10).floor()).toDouble();
    final scaled = raw / pow10;

    double nice;
    if (scaled <= 1) nice = 1;
    else if (scaled <= 2) nice = 2;
    else if (scaled <= 5) nice = 5;
    else nice = 10;

    return nice * pow10;
  }
  double _snap(double value, double step, bool up) {
  if (step <= 0) return value;
  return up
      ? (value / step).ceil() * step
      : (value / step).floor() * step;
  }

  String _fmtAxis(double v) {
    final a = v.abs();
    if (a >= 1000) return v.toStringAsFixed(0);
    if (a >= 100) return v.toStringAsFixed(0);
    if (a >= 10) return v.toStringAsFixed(1);
    if (a >= 1) return v.toStringAsFixed(2);
    return v.toStringAsFixed(3);
  }

  Future<void> _solvePressed() async {
    setState(() {
      _loading = true;
      _error = null;

      _hasSolved = false;
      _hasPlotted = false;

      _equation = '';
      _realRootsText = '';
      _complexRootsText = '';

      _realRoots = [];
      _curve = [];
    });

    try {
      final degree = int.parse(_degreeCtrl.text.trim());
      final coeffs = _parseCoeffs(_coeffsCtrl.text);

      if (coeffs.length != degree + 1) {
        throw Exception(
          'Coefficient count mismatch. Degree $degree requires ${degree + 1} coefficients.',
        );

      }

      final bound = _cauchyBound(coeffs);
      final xMin = -bound;
      final xMax = bound;

      final result = await widget.session.api.solve(
        degree: degree,
        coeffs: coeffs,
        xMin: xMin,
        xMax: xMax,
      );

      final roots = result.roots;

      final realRoots = <double>[];
      final complexRoots = <String>[];

      for (final r in roots) {
        if (r.im.abs() < 1e-8) {
          realRoots.add(r.re);
        } else {
          final sign = r.im >= 0 ? '+' : '-';
          complexRoots.add('x = ${r.re} $sign ${r.im.abs()}i');
        }
      }

      realRoots.sort();

      final realText = realRoots.isEmpty
          ? 'None'
          : realRoots.map((x) => 'x = $x').join('\n');

      final complexText = complexRoots.isEmpty ? 'None' : complexRoots.join('\n');

      final eqDisplay = _formatEquationUnicode(coeffs);
      
      setState(() {
        _coeffs = coeffs;
        _equation = eqDisplay;

        _realRoots = realRoots;

        _realRootsText = realText;
        _complexRootsText = complexText;

        _baseXMin = xMin;
        _baseXMax = xMax;

        _viewXMin = _baseXMin;
        _viewXMax = _baseXMax;

        _viewYMin = -10;
        _viewYMax = 10;

        _hasSolved = true;


      });
      await _loadHistoryFromServer();

// Save to server safely and refresh full history.

} catch (e) {
  setState(() {
    _error = e.toString().replaceAll('Exception: ', '');
  });

  if (!mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(_error ?? 'Failed to solve polynomial')),
  );
}
 finally {
      setState(() {
        _loading = false;
      });
    }
  }

  void _plotPressed() {
    if (!_hasSolved) return;
    setState(() {
      _viewXMin = _baseXMin;
      _viewXMax = _baseXMax;
      _computeCurveAndFitY();
      _hasPlotted = true;
    });
  }

  void _zoom(bool zoomIn) {
    if (!_hasSolved || !_hasPlotted) return;

    final cx = (_viewXMin + _viewXMax) / 2;
    final cy = (_viewYMin + _viewYMax) / 2;

    final xSpan = (_viewXMax - _viewXMin).abs();
    final ySpan = (_viewYMax - _viewYMin).abs();

    final factor = zoomIn ? 0.75 : 1.25;

    final newXSpan = max(0.001, xSpan * factor);
    final newYSpan = max(0.001, ySpan * factor);

    setState(() {
      _viewXMin = cx - newXSpan / 2;
      _viewXMax = cx + newXSpan / 2;
      _viewYMin = cy - newYSpan / 2;
      _viewYMax = cy + newYSpan / 2;
      _computeCurveAndFitY();
    });
  }

  void _fitView() {
    if (!_hasSolved || !_hasPlotted) return;
    setState(() {
      _viewXMin = _baseXMin;
      _viewXMax = _baseXMax;
      _computeCurveAndFitY();
    });
  }

  void _refresh() {
    setState(() {
      _error = null;

      _hasSolved = false;
      _hasPlotted = false;

      _equation = '';
      _realRootsText = '';
      _complexRootsText = '';

      _curve = [];
      _realRoots = [];

      _showGraph = true;

      _viewXMin = _baseXMin;
      _viewXMax = _baseXMax;
      _viewYMin = -10;
      _viewYMax = 10;
    });
  }

  Future<Uint8List?> _captureGraphPngBytes() async {
    try {
      final boundary =
          _graphKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;

      final image = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Uint8List? _pngToJpeg(Uint8List pngBytes) {
    try {
      final decoded = img.decodePng(pngBytes);
      if (decoded == null) return null;
      final jpg = img.encodeJpg(decoded, quality: 90);
      return Uint8List.fromList(jpg);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _pickSavePath({
    required String suggestedName,
    required List<String> extensions,
    required String label,
  }) async {
    final loc = await fs.getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: [
        fs.XTypeGroup(
          label: label,
          extensions: extensions,
        ),
      ],
    );
    if (loc == null) return null;

    var path = loc.path;
    final lower = path.toLowerCase();

    bool endsWithAny = false;
    for (final ext in extensions) {
      if (lower.endsWith('.$ext')) {
        endsWithAny = true;
        break;
      }
    }

    if (!endsWithAny && extensions.isNotEmpty) {
      path = '$path.${extensions.first}';
    }
    return path;
  }

  Future<void> _exportGraphJpeg() async {
    if (!_hasSolved || !_hasPlotted || !_showGraph) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plot the graph first')),
      );
      return;
    }

    final pngBytes = await _captureGraphPngBytes();
    if (pngBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Graph export failed')),
      );
      return;
    }

    final jpegBytes = _pngToJpeg(pngBytes);
    if (jpegBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Graph export failed')),
      );
      return;
    }

    final path = await _pickSavePath(
      suggestedName: 'polynomial_graph.jpg',
      extensions: const ['jpg', 'jpeg'],
      label: 'JPEG',
    );
    if (path == null) return;

    await File(path).writeAsBytes(jpegBytes);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Graph exported as JPEG')),
    );
  }

Future<void> _exportHistoryCsv() async {
  if (_history.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No history to export')),
    );
    return;
  }

  final sb = StringBuffer();
  sb.writeln(
    'username,timestamp,equation,real_roots,complex_roots',
  );

  for (final h in _history) {
    sb.writeln(
      '${_csvEscape(h.userName)},'
      '${_csvEscape(_formatTimestamp(h.timestamp))},'
      '${_csvEscape(h.equation)},'
      '${_csvEscape(h.realRootsText)},'
      '${_csvEscape(h.complexRootsText)}',
    );
  }

  final csvBytes = utf8.encode('\uFEFF${sb.toString()}');

  // -----------------------------
  // WEB DOWNLOAD
  // -----------------------------
if (kIsWeb) {
  downloadCsvWeb(
    Uint8List.fromList(csvBytes),
    'polynomial_history.csv',
  );
  return;
}


  // -----------------------------
  // DESKTOP (Windows / macOS / Linux)
  // -----------------------------
  final loc = await fs.getSaveLocation(
    suggestedName: 'polynomial_history.csv',
    acceptedTypeGroups: [
      fs.XTypeGroup(label: 'CSV', extensions: ['csv']),
    ],
  );

  if (loc == null) return;

  await File(loc.path!).writeAsBytes(csvBytes);

  if (!mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('History exported as CSV')),
  );
}


  String _csvEscape(String s) {
    final needsQuotes = s.contains(',') || s.contains('"') || s.contains('\n');
    final escaped = s.replaceAll('"', '""');
    return needsQuotes ? '"$escaped"' : escaped;
  }

Future<void> _printHistoryAndGraph() async {
  final fontData = await rootBundle.load('assets/fonts/DejaVuSans.ttf');
  final ttf = pw.Font.ttf(fontData);

  final baseStyle = pw.TextStyle(font: ttf);
  final boldStyle = pw.TextStyle(font: ttf, fontWeight: pw.FontWeight.bold);

  final doc = pw.Document();

  Uint8List? graphPng;
  if (_hasSolved && _hasPlotted && _showGraph) {
    graphPng = await _captureGraphPngBytes();
  }

  doc.addPage(
    pw.MultiPage(
      build: (context) => [
        pw.Text('Polynomial Solver History',
            style: boldStyle.copyWith(fontSize: 16)),
        pw.SizedBox(height: 8),
        if (_history.isEmpty) pw.Text('No history yet.'),
        for (final item in _history)
          pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 8),
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(border: pw.Border.all()),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  '${item.userName} | ${_formatTimestamp(item.timestamp)}',
                  style: boldStyle,
                ),
                pw.SizedBox(height: 4),
                pw.Text(_caretToSuperscript(item.equation), style: baseStyle),
                pw.SizedBox(height: 6),
                pw.Text('Real roots: ${item.realRootsText}',
                    style: baseStyle),
                pw.Text('Complex roots: ${item.complexRootsText}',
                    style: baseStyle),
              ],
            ),
          ),
        if (graphPng != null) pw.SizedBox(height: 12),
        if (graphPng != null) pw.Image(pw.MemoryImage(graphPng)),
      ],
    ),
  );

  final pdfBytes = await doc.save();


// MOBILE WEB (iOS / Android) → SHARE SHEET
if (_isMobileWeb) {
  await Printing.sharePdf(
    bytes: pdfBytes,
    filename: 'polynomial_history.pdf',
  );
  return;
}


  // DESKTOP → PRINT
  await Printing.layoutPdf(
    onLayout: (_) async => pdfBytes,
  );
}


  String _formatTimestamp(DateTime dt) {
    final d = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }
Future<void> _loadHistoryFromServer() async {
  try {
    List<Map<String, dynamic>> result;

    // Try admin history first
    try {
      result = await widget.session.api.adminHistory(limit: 100);
    } catch (_) {
      // Fallback to normal user history
      result = await widget.session.api.history(limit: 100);
    }

    final items = <_HistoryItem>[];

    for (final h in result) {
      final roots = h.containsKey('roots') ? h['roots'] as List : [];

      final realRoots = roots
          .where((r) => (r['im'] as num).toDouble().abs() < 1e-8)
          .map((r) => 'x = ${(r['re'] as num).toDouble()}')
          .toList();

      final complexRoots = roots
          .where((r) => (r['im'] as num).toDouble().abs() >= 1e-8)
          .map((r) {
            final re = (r['re'] as num).toDouble();
            final im = (r['im'] as num).toDouble();
            final sign = im >= 0 ? '+' : '-';
            return 'x = $re $sign ${im.abs()}i';
          })
          .toList();

      items.add(
        _HistoryItem(
          timestamp: DateTime.parse(h['created_at']),
          userName: h['username'] ?? widget.userName ?? 'Unknown',
          equation: h['equation'],
          realRootsText:
              realRoots.isEmpty ? 'None' : realRoots.join('\n'),
          complexRootsText:
              complexRoots.isEmpty ? 'None' : complexRoots.join('\n'),
        ),
      );
    }

    items.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    setState(() {
      _history
        ..clear()
        ..addAll(items);
    });
  } catch (_) {
    // silent fail
  }
}

  Widget _equationBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.blueGrey.shade200),
        borderRadius: BorderRadius.circular(6),
        color: Colors.blue.shade50.withOpacity(0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Equation', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            _equation.isEmpty ? 'Solve to generate equation' : _equation,
            style: const TextStyle(fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _rootsBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Real roots', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(_realRootsText.isEmpty ? 'Solve to generate roots' : _realRootsText),
          const SizedBox(height: 12),
          const Text('Complex roots', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(_complexRootsText.isEmpty ? 'Solve to generate roots' : _complexRootsText),
        ],
      ),
    );
  }

  Widget _historyBox() {
    return Container(
      height: 220,
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('History', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Expanded(
            child: _history.isEmpty
                ? const Text('No history yet.')
                : ListView.builder(
                    itemCount: _history.length,
                    itemBuilder: (_, i) {
                      final h = _history[i];
                      return Card(
                        elevation: 0,
                        child: ListTile(
                          dense: true,
                          title: Text(_formatTimestamp(h.timestamp)),
                          subtitle: Text('${h.userName} | ${_caretToSuperscript(h.equation)}'),

                          trailing: IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () {
                              setState(() {
                                _history.removeAt(i);
                              });
                            },
                          ),
                          onTap: () {
                            setState(() {
                              _equation = h.equation;
                              _realRootsText = h.realRootsText;
                              _complexRootsText = h.complexRootsText;
                            });
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _graphArea() {
    if (!_hasSolved) {
      return Container(
        height: 600,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text('Solve first, then press Plot'),
      );
    }

    if (!_hasPlotted || _curve.isEmpty) {
      return Container(
        height: 600,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text('Press Plot to draw the graph'),
      );
    }

    final rootDots = _realRoots
        .where((x) => x >= _viewXMin && x <= _viewXMax)
        .map((x) => FlSpot(x, 0))
        .toList();

    final xSpan = (_viewXMax - _viewXMin).abs();
    final ySpan = (_viewYMax - _viewYMin).abs();
    final xInterval = _niceInterval(xSpan);
    final yInterval = _niceInterval(ySpan);

    return RepaintBoundary(
      key: _graphKey,
      child: Container(
        height: 600,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(6),
          color: const Color(0xFFF3F7FF),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _equation,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: LineChart(
                LineChartData(
                  minX: _viewXMin,
                  maxX: _viewXMax,
                  minY: _viewYMin,
                  maxY: _viewYMax,
                  gridData: FlGridData(show: true),
                  borderData: FlBorderData(show: true),

                  /// Stops the vertical indicator line and coordinate box.
                  lineTouchData: const LineTouchData(enabled: false),

                  titlesData: FlTitlesData(
leftTitles: AxisTitles(
  axisNameWidget: const Padding(
    padding: EdgeInsets.only(right: 8),
    child: Text(
      'y axis',
      style: TextStyle(fontSize: 12),
    ),
  ),
  axisNameSize: 40,
  sideTitles: SideTitles(
    showTitles: true,
    reservedSize: 60,
    interval: yInterval,
    getTitlesWidget: (value, meta) {
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Text(
          _fmtAxis(value),
          style: const TextStyle(fontSize: 11),
        ),
      );
    },
  ),
),

bottomTitles: AxisTitles(
  axisNameWidget: const Padding(
    padding: EdgeInsets.only(top: 12),
    child: Text('x axis'),
  ),
  axisNameSize: 32,

                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        interval: xInterval,
                        getTitlesWidget: (value, meta) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              _fmtAxis(value),
                              style: const TextStyle(fontSize: 11),
                            ),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  extraLinesData: ExtraLinesData(
                    extraLinesOnTop: true,
                    verticalLines: [
                      VerticalLine(x: 0, color: Colors.black54, strokeWidth: 2),
                    ],
                    horizontalLines: [
                      HorizontalLine(y: 0, color: Colors.black54, strokeWidth: 2),
                    ],
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: _curve,
                      isCurved: true,
                      color: const Color(0xFF7A1E1E),
                      barWidth: 3,
                      dotData: FlDotData(show: false),
                    ),
                    LineChartBarData(
                      spots: rootDots,
                      isCurved: false,
                      color: Colors.transparent,
                      barWidth: 0,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, bar, index) {
                          return FlDotCirclePainter(
                            radius: 5,
                            color: const Color(0xFF7A1E1E),
                            strokeWidth: 0,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Real roots are marked as dots on the x axis.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

void _logout() {
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(
      builder: (_) => LoginScreen(session: widget.session),
    ),
    (route) => false,
  );
}

  @override
  void dispose() {
    _degreeCtrl.dispose();
    _coeffsCtrl.dispose();
    super.dispose();
  }

@override
@override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(
      title: const Text('Polynomial Solver'),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: _showGraph ? 'Close graph' : 'Open graph',
          onPressed: () {
            setState(() {
              _showGraph = !_showGraph;
            });
          },
          icon: Icon(_showGraph ? Icons.close_fullscreen : Icons.open_in_full),
        ),
PopupMenuButton<String>(
  onSelected: (value) {
    if (value == 'print') _printHistoryAndGraph();
    if (value == 'image') _exportGraphJpeg();
    if (value == 'csv') _exportHistoryCsv();
    if (value == 'logout') _logout();
  },
  itemBuilder: (_) => [
PopupMenuItem(
  value: 'print',
  child: Text(_isMobileWeb ? 'Download PDF' : 'Print'),
),


    if (!kIsWeb)
      const PopupMenuItem(
        value: 'image',
        child: Text('Export graph'),
      ),

    if (!kIsWeb)
      const PopupMenuItem(
        value: 'csv',
        child: Text('Export history'),
      ),

    const PopupMenuItem(
      value: 'logout',
      child: Text('Logout'),
    ),
  ],
),

      ],
    ),
body: SafeArea(
  top: true,
  child: LayoutBuilder(

      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 900;

// ---------- LEFT / MAIN CONTENT ----------
final leftPanel = SingleChildScrollView(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 10), // ADD THIS LINE ONLY
      TextField(
        controller: _degreeCtrl,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'Degree',
          border: OutlineInputBorder(),
          floatingLabelBehavior: FloatingLabelBehavior.always,
          contentPadding: EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _coeffsCtrl,
        decoration: const InputDecoration(
          labelText:
              'Coefficients (comma separated, highest degree first)',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: _loading ? null : _solvePressed,
              child: _loading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('SOLVE'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton(
              onPressed: !_hasSolved ? null : _plotPressed,
              child: const Text('PLOT'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed:
                  (!_hasSolved || !_hasPlotted) ? null : () => _zoom(true),
              child: const Text('ZOOM IN'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton(
              onPressed:
                  (!_hasSolved || !_hasPlotted) ? null : () => _zoom(false),
              child: const Text('ZOOM OUT'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed:
              (!_hasSolved || !_hasPlotted) ? null : _fitView,
          child: const Text('FIT VIEW'),
        ),
      ),
      const SizedBox(height: 16),
      _equationBox(),
      const SizedBox(height: 12),
      _rootsBox(),
      const SizedBox(height: 12),
      _historyBox(),
    ],
  ),
);

        // ---------- GRAPH ----------
        final graphPanel = _showGraph
            ? SizedBox(
                height: isMobile ? 360 : double.infinity,
                child: _graphArea(),
              )
            : const SizedBox.shrink();

if (isMobile) {
  return Stack(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          controller: _mobileScrollCtrl,
          children: [
            leftPanel,
            const SizedBox(height: 12),
            graphPanel,
            const SizedBox(height: 24),
          ],
        ),
      ),

      // Scroll UP
      Positioned(
        right: 12,
        bottom: 90,
        child: FloatingActionButton(
          mini: true,
          onPressed: () {
            _mobileScrollCtrl.animateTo(
              0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          },
          child: const Icon(Icons.keyboard_arrow_up),
        ),
      ),

      // Scroll DOWN
      Positioned(
        right: 12,
        bottom: 30,
        child: FloatingActionButton(
          mini: true,
          onPressed: () {
            _mobileScrollCtrl.animateTo(
              _mobileScrollCtrl.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          },
          child: const Icon(Icons.keyboard_arrow_down),
        ),
      ),
    ],
  );
}




        // ---------- DESKTOP LAYOUT ----------
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
SizedBox(
  width: 520,
  child: SingleChildScrollView(
    child: leftPanel,
  ),
),

              const SizedBox(width: 20),
              Expanded(child: graphPanel),
            ],
          ),
        );
      },
    ),
  ),
); 
}
bool get _isMobileWeb {
  if (!kIsWeb) return false;
  final width = MediaQuery.of(context).size.width;
  return width < 900;
}



}
