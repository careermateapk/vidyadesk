import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

/// A simple table report that can be saved as PDF or as an Excel-friendly CSV.
class TableReport {
  TableReport({
    required this.title,
    required this.institute,
    required this.headers,
    required this.rows,
    this.subtitle = '',
    this.summary = const [],
    this.footer = '',
    this.numeric = const {},
    this.extra = const [],
  });
  final String title, institute, subtitle, footer;
  final List<String> headers;
  final List<List<String>> rows;

  /// Big numbers shown above the table, e.g. ("Collected", "₹45,000").
  final List<(String, String)> summary;

  /// Column indexes that hold numbers (right-aligned in the PDF).
  final Set<int> numeric;

  /// More tables after the main one: (heading, headers, rows).
  final List<(String, List<String>, List<List<String>>)> extra;

  String get fileBase => title.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_').replaceAll(RegExp(r'_+$'), '');
}

/// Excel opens this directly (UTF-8 with BOM so ₹ and Hindi show correctly).
Uint8List reportCsv(TableReport r) {
  String cell(String v) => (v.contains(',') || v.contains('"') || v.contains('\n')) ? '"${v.replaceAll('"', '""')}"' : v;
  final b = StringBuffer('﻿');
  b.writeln(cell(r.title));
  if (r.subtitle.isNotEmpty) b.writeln(cell(r.subtitle));
  b.writeln(cell(r.institute));
  b.writeln();
  for (final s in r.summary) {
    b.writeln('${cell(s.$1)},${cell(s.$2)}');
  }
  if (r.summary.isNotEmpty) b.writeln();
  b.writeln(r.headers.map(cell).join(','));
  for (final row in r.rows) {
    b.writeln(row.map(cell).join(','));
  }
  for (final t in r.extra) {
    b.writeln();
    b.writeln(cell(t.$1));
    b.writeln(t.$2.map(cell).join(','));
    for (final row in t.$3) {
      b.writeln(row.map(cell).join(','));
    }
  }
  return Uint8List.fromList(utf8.encode(b.toString()));
}

Future<Uint8List> reportPdf(TableReport r) async {
  final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/HankenGrotesk-400.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/HankenGrotesk-700.ttf'));
  final noto = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansDevanagari-400.ttf'));
  final notoBold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansDevanagari-700.ttf'));
  const purple = PdfColor.fromInt(0xFF5545D6);
  const tint = PdfColor.fromInt(0xFFEFEDFF);
  const muted = PdfColor.fromInt(0xFF8A87A6);
  const ink = PdfColor.fromInt(0xFF17153A);
  const line = PdfColor.fromInt(0xFFECEAF5);
  final now = DateTime.now();
  final made = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

  final doc = pw.Document(title: r.title, author: r.institute, creator: 'VidyaDesk');
  final align = {for (var i = 0; i < r.headers.length; i++) i: r.numeric.contains(i) ? pw.Alignment.centerRight : pw.Alignment.centerLeft};
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    theme: pw.ThemeData.withFont(base: regular, bold: bold, fontFallback: [noto, notoBold]),
    margin: const pw.EdgeInsets.fromLTRB(32, 30, 32, 30),
    header: (c) => c.pageNumber == 1
        ? pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Row(children: [
              pw.Expanded(
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text(r.institute, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: purple)),
                  pw.SizedBox(height: 2),
                  pw.Text(r.title, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: ink)),
                  if (r.subtitle.isNotEmpty) pw.Text(r.subtitle, style: const pw.TextStyle(fontSize: 10, color: muted)),
                ]),
              ),
              pw.Text('Made on $made', style: const pw.TextStyle(fontSize: 9, color: muted)),
            ]),
            pw.SizedBox(height: 12),
            if (r.summary.isNotEmpty)
              pw.Row(children: [
                for (final s in r.summary)
                  pw.Expanded(
                    child: pw.Container(
                      margin: const pw.EdgeInsets.only(right: 8),
                      padding: const pw.EdgeInsets.all(10),
                      decoration: pw.BoxDecoration(color: tint, borderRadius: pw.BorderRadius.circular(8)),
                      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                        pw.Text(s.$1, style: const pw.TextStyle(fontSize: 9, color: muted)),
                        pw.SizedBox(height: 2),
                        pw.Text(s.$2, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: ink)),
                      ]),
                    ),
                  ),
              ]),
            pw.SizedBox(height: 12),
          ])
        : pw.SizedBox(),
    footer: (c) => pw.Row(children: [
      pw.Expanded(child: pw.Text(r.footer.isEmpty ? 'VidyaDesk' : r.footer, style: const pw.TextStyle(fontSize: 8.5, color: muted))),
      pw.Text('Page ${c.pageNumber} of ${c.pagesCount}', style: const pw.TextStyle(fontSize: 8.5, color: muted)),
    ]),
    build: (c) => [
      if (r.rows.isEmpty)
        pw.Padding(padding: const pw.EdgeInsets.all(20), child: pw.Text('No entries', style: const pw.TextStyle(color: muted)))
      else
        pw.TableHelper.fromTextArray(
          headers: r.headers,
          data: r.rows,
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9.5),
          headerDecoration: const pw.BoxDecoration(color: purple),
          cellStyle: const pw.TextStyle(fontSize: 9.5, color: ink),
          cellAlignments: align,
          headerAlignments: align,
          rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: line, width: .6))),
          oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF8F7FD)),
          border: null,
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        ),
      for (final t in r.extra) ...[
        pw.SizedBox(height: 18),
        pw.Text(t.$1, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: purple)),
        pw.SizedBox(height: 6),
        if (t.$3.isEmpty)
          pw.Text('No entries', style: const pw.TextStyle(color: muted, fontSize: 10))
        else
          pw.TableHelper.fromTextArray(
            headers: t.$2,
            data: t.$3,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9.5),
            headerDecoration: const pw.BoxDecoration(color: purple),
            cellStyle: const pw.TextStyle(fontSize: 9.5, color: ink),
            rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: line, width: .6))),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF8F7FD)),
            border: null,
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          ),
      ],
    ],
  ));
  return doc.save();
}

/// Save to a temp file and open the share sheet.
Future<void> shareBytes(Uint8List bytes, String fileName, String mime, {String text = ''}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: mime)], text: text.isEmpty ? null : text));
}

Future<void> shareReportPdf(TableReport r) async => shareBytes(await reportPdf(r), '${r.fileBase}.pdf', 'application/pdf', text: r.title);

Future<void> shareReportCsv(TableReport r) async => shareBytes(reportCsv(r), '${r.fileBase}.csv', 'text/csv', text: r.title);
