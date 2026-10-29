import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../data/models.dart';

/// Indian number words, e.g. 1500 -> "One Thousand Five Hundred".
String amountInWords(int n) {
  const ones = ['', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'];
  const tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];
  String two(int x) => x < 20 ? ones[x] : '${tens[x ~/ 10]}${x % 10 == 0 ? '' : ' ${ones[x % 10]}'}';
  String three(int x) => x >= 100 ? '${ones[x ~/ 100]} Hundred${x % 100 == 0 ? '' : ' ${two(x % 100)}'}' : two(x);
  if (n == 0) return 'Zero';
  final parts = <String>[];
  final crore = n ~/ 10000000, lakh = (n ~/ 100000) % 100, thousand = (n ~/ 1000) % 100, rest = n % 1000;
  if (crore > 0) parts.add('${three(crore)} Crore');
  if (lakh > 0) parts.add('${two(lakh)} Lakh');
  if (thousand > 0) parts.add('${two(thousand)} Thousand');
  if (rest > 0) parts.add(three(rest));
  return parts.join(' ');
}

String _money(int n) {
  final s = n.toString();
  if (s.length <= 3) return s;
  final last = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final out = <String>[];
  while (rest.length > 2) {
    out.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) out.insert(0, rest);
  return '${out.join(',')},$last';
}

const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

String _monthName(String key) {
  final p = key.split('-');
  if (p.length != 2) return key;
  return '${_months[(int.tryParse(p[1]) ?? 1) - 1]} ${p[0]}';
}

String _date(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms == 0 ? DateTime.now().millisecondsSinceEpoch : ms);
  return '${d.day} ${_months[d.month - 1].substring(0, 3)} ${d.year}';
}

/// Builds the fee receipt PDF.
Future<Uint8List> buildReceipt({required Institute inst, required FeeRecord fee, String studentCode = '', String batch = ''}) async {
  final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/HankenGrotesk-400.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/HankenGrotesk-700.ttf'));
  final noto = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansDevanagari-400.ttf'));
  final notoBold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansDevanagari-700.ttf'));
  const purple = PdfColor.fromInt(0xFF5545D6);
  const mint = PdfColor.fromInt(0xFF12B886);
  const muted = PdfColor.fromInt(0xFF8A87A6);
  const ink = PdfColor.fromInt(0xFF17153A);

  final doc = pw.Document(title: 'Fee receipt ${fee.receiptNo}', author: inst.name, creator: 'VidyaDesk');
  pw.MemoryImage? logo;
  try {
    if (inst.logo.isNotEmpty) logo = pw.MemoryImage(base64Decode(inst.logo));
  } catch (_) {}
  final gst = inst.gstOn && inst.gstin.trim().isNotEmpty;
  // Fees include GST: split the total into fee + CGST 9% + SGST 9%.
  final paise = fee.amount * 100;
  final basePaise = (paise / 1.18).round();
  final cgst = ((paise - basePaise) / 2).round();
  final sgst = paise - basePaise - cgst;
  String rs(int p) => '₹${_money(p ~/ 100)}.${(p % 100).toString().padLeft(2, '0')}';
  final theme = pw.ThemeData.withFont(base: regular, bold: bold, fontFallback: [noto, notoBold]);

  pw.Widget row(String k, String v) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 5),
        child: pw.Row(children: [
          pw.Expanded(child: pw.Text(k, style: const pw.TextStyle(color: muted, fontSize: 11))),
          pw.Text(v, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11.5, color: ink)),
        ]),
      );

  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a5,
    theme: theme,
    margin: const pw.EdgeInsets.all(24),
    build: (c) => pw.Container(
      decoration: pw.BoxDecoration(borderRadius: pw.BorderRadius.circular(14), border: pw.Border.all(color: const PdfColor.fromInt(0xFFECEAF5))),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Container(
          padding: const pw.EdgeInsets.all(16),
          decoration: const pw.BoxDecoration(color: purple, borderRadius: pw.BorderRadius.only(topLeft: pw.Radius.circular(14), topRight: pw.Radius.circular(14))),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            if (logo != null) ...[
              pw.Container(
                width: 52,
                height: 52,
                padding: const pw.EdgeInsets.all(3),
                decoration: pw.BoxDecoration(color: PdfColors.white, borderRadius: pw.BorderRadius.circular(10)),
                child: pw.ClipRRect(horizontalRadius: 8, verticalRadius: 8, child: pw.Image(logo, fit: pw.BoxFit.cover)),
              ),
              pw.SizedBox(width: 12),
            ],
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(inst.name, style: pw.TextStyle(color: PdfColors.white, fontSize: 18, fontWeight: pw.FontWeight.bold)),
                if (inst.address.isNotEmpty || inst.city.isNotEmpty)
                  pw.Text(inst.address.isNotEmpty ? inst.address : inst.city, style: const pw.TextStyle(color: PdfColor.fromInt(0xDDFFFFFF), fontSize: 9.5)),
                if (inst.phone.isNotEmpty) pw.Text(inst.phone, style: const pw.TextStyle(color: PdfColor.fromInt(0xDDFFFFFF), fontSize: 9.5)),
                if (gst) pw.Text('GSTIN: ${inst.gstin}', style: pw.TextStyle(color: PdfColors.white, fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
              ]),
            ),
          ]),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(16),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
            pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Expanded(
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('FEE RECEIPT', style: pw.TextStyle(color: muted, fontSize: 9, fontWeight: pw.FontWeight.bold, letterSpacing: 1.2)),
                  pw.Text(fee.receiptNo.isEmpty ? '—' : fee.receiptNo, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: ink)),
                ]),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: pw.BoxDecoration(border: pw.Border.all(color: mint, width: 2), borderRadius: pw.BorderRadius.circular(6)),
                child: pw.Text('PAID', style: pw.TextStyle(color: mint, fontWeight: pw.FontWeight.bold, fontSize: 13)),
              ),
              pw.SizedBox(width: 16),
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                pw.Text('Date', style: const pw.TextStyle(color: muted, fontSize: 9)),
                pw.Text(_date(fee.paidOn), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: ink)),
              ]),
            ]),
            pw.Divider(color: const PdfColor.fromInt(0xFFECEAF5), height: 20),
            row('Student', fee.studentName),
            if (studentCode.isNotEmpty) row('Student code', studentCode),
            if (batch.isNotEmpty) row('Batch', batch),
            row('Fee for', _monthName(fee.month)),
            row('Paid by', [fee.mode, if (fee.paidBy.isNotEmpty) fee.paidBy].where((e) => e.isNotEmpty).join(' · ')),
            if (fee.utr.isNotEmpty) row('UTR', fee.utr),
            if (gst) ...[
              pw.SizedBox(height: 6),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: pw.BoxDecoration(color: const PdfColor.fromInt(0xFFF4F2FF), borderRadius: pw.BorderRadius.circular(8)),
                child: pw.Column(children: [row('Tuition fee', rs(basePaise)), row('CGST 9%', rs(cgst)), row('SGST 9%', rs(sgst))]),
              ),
            ],
            pw.SizedBox(height: 10),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(color: const PdfColor.fromInt(0xFFE3F8F0), borderRadius: pw.BorderRadius.circular(10)),
              child: pw.Row(children: [
                pw.Expanded(child: pw.Text('Amount received', style: pw.TextStyle(color: mint, fontWeight: pw.FontWeight.bold, fontSize: 12))),
                pw.Text('₹${_money(fee.amount)}', style: pw.TextStyle(color: mint, fontWeight: pw.FontWeight.bold, fontSize: 20)),
              ]),
            ),
            pw.SizedBox(height: 6),
            pw.Center(child: pw.Text('Rupees ${amountInWords(fee.amount)} only', style: const pw.TextStyle(color: muted, fontSize: 10))),
            pw.SizedBox(height: 28),
            pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Expanded(child: pw.Text('Computer generated receipt\nby VidyaDesk', style: const pw.TextStyle(color: muted, fontSize: 9))),
              pw.Column(children: [
                pw.Container(width: 110, height: 1, color: muted),
                pw.SizedBox(height: 3),
                pw.Text('Authorised sign', style: const pw.TextStyle(color: muted, fontSize: 9)),
              ]),
            ]),
          ]),
        ),
      ]),
    ),
  ));
  return doc.save();
}

/// Makes the PDF and opens the phone's share sheet (WhatsApp, Gmail, Files…).
Future<void> shareReceipt({required Institute inst, required FeeRecord fee, String studentCode = '', String batch = ''}) async {
  final bytes = await buildReceipt(inst: inst, fee: fee, studentCode: studentCode, batch: batch);
  final dir = await getTemporaryDirectory();
  final safe = fee.studentName.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
  final file = File('${dir.path}/Receipt_${safe}_${fee.month}.pdf');
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(ShareParams(
    files: [XFile(file.path, mimeType: 'application/pdf')],
    text: '${inst.name} — fee receipt ${fee.receiptNo} (${_monthName(fee.month)})',
  ));
}


/// Receipt for a coaching's VidyaDesk plan payment.
Future<Uint8List> buildPlanReceipt(SubPayment p, {required String planLabel}) async {
  final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/HankenGrotesk-400.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/HankenGrotesk-700.ttf'));
  const purple = PdfColor.fromInt(0xFF5545D6);
  const mint = PdfColor.fromInt(0xFF12B886);
  const muted = PdfColor.fromInt(0xFF8A87A6);
  const ink = PdfColor.fromInt(0xFF17153A);
  final noto = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansDevanagari-400.ttf'));
  final notoBold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansDevanagari-700.ttf'));
  final doc = pw.Document(title: 'VidyaDesk plan receipt', author: 'VidyaDesk', creator: 'VidyaDesk');
  pw.Widget row(String k, String v) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 5),
        child: pw.Row(children: [
          pw.Expanded(child: pw.Text(k, style: const pw.TextStyle(color: muted, fontSize: 11))),
          pw.Text(v, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11.5, color: ink)),
        ]),
      );
  final no = 'VD-${p.createdAt.toRadixString(36).toUpperCase()}';
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a5,
    theme: pw.ThemeData.withFont(base: regular, bold: bold, fontFallback: [noto, notoBold]),
    margin: const pw.EdgeInsets.all(24),
    build: (c) => pw.Container(
      decoration: pw.BoxDecoration(borderRadius: pw.BorderRadius.circular(14), border: pw.Border.all(color: const PdfColor.fromInt(0xFFECEAF5))),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Container(
          padding: const pw.EdgeInsets.all(16),
          decoration: const pw.BoxDecoration(color: purple, borderRadius: pw.BorderRadius.only(topLeft: pw.Radius.circular(14), topRight: pw.Radius.circular(14))),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('VidyaDesk', style: pw.TextStyle(color: PdfColors.white, fontSize: 20, fontWeight: pw.FontWeight.bold)),
            pw.Text('Coaching management app · Plan receipt', style: const pw.TextStyle(color: PdfColor.fromInt(0xDDFFFFFF), fontSize: 10)),
          ]),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(16),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
            pw.Row(children: [
              pw.Expanded(child: pw.Text(no, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: ink))),
              pw.Text(_date(p.createdAt), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: ink)),
            ]),
            pw.Divider(color: const PdfColor.fromInt(0xFFECEAF5), height: 20),
            row('Coaching', p.instituteName),
            if (p.adminName.isNotEmpty) row('Admin', p.adminName),
            row('Plan', '$planLabel · ${p.yearly ? '1 year' : '1 month'}'),
            if (p.newUntil > 0) row('Valid till', _date(p.newUntil)),
            if (p.via.isNotEmpty) row('Paid via', p.via),
            if (p.utr.isNotEmpty) row('UPI ref', p.utr),
            if (p.demo) row('Note', 'Demo payment (no money taken)'),
            pw.SizedBox(height: 10),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(color: const PdfColor.fromInt(0xFFE3F8F0), borderRadius: pw.BorderRadius.circular(10)),
              child: pw.Row(children: [
                pw.Expanded(child: pw.Text('Amount paid', style: pw.TextStyle(color: mint, fontWeight: pw.FontWeight.bold, fontSize: 12))),
                pw.Text('₹${_money(p.demo ? 0 : p.amount)}', style: pw.TextStyle(color: mint, fontWeight: pw.FontWeight.bold, fontSize: 20)),
              ]),
            ),
            pw.SizedBox(height: 24),
            pw.Text('Computer generated receipt by VidyaDesk', style: const pw.TextStyle(color: muted, fontSize: 9)),
          ]),
        ),
      ]),
    ),
  ));
  return doc.save();
}
