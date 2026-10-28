import 'package:flutter/services.dart';

/// UPI apps people can pick. Empty package = let Android show its chooser.
class UpiApp {
  const UpiApp(this.name, this.package, this.letter, this.color);
  final String name, package, letter;
  final int color;
}

const upiApps = [
  UpiApp('GPay', 'com.google.android.apps.nbu.paisa.user', 'G', 0xFF4285F4),
  UpiApp('PhonePe', 'com.phonepe.app', 'Pe', 0xFF5F259F),
  UpiApp('Paytm', 'net.one97.paytm', 'P', 0xFF00BAF2),
  UpiApp('Other UPI app', '', '⋯', 0xFF8A87A6),
];

enum UpiStatus { success, failed, unknown, noApp }

class UpiResult {
  const UpiResult(this.status, {this.utr = '', this.raw = ''});
  final UpiStatus status;
  final String utr, raw;
}

const _ch = MethodChannel('vidyadesk/upi');

/// Opens the UPI app. Reads the UTR from the app's reply when it gives one.
Future<UpiResult> payByUpi({
  required String vpa,
  required String payee,
  required int amount,
  required String note,
  required String ref,
  String package = '',
}) async {
  final url = Uri(scheme: 'upi', host: 'pay', queryParameters: {
    'pa': vpa,
    'pn': payee,
    'am': amount.toStringAsFixed(2),
    'cu': 'INR',
    'tn': note,
    'tr': ref,
  }).toString();
  try {
    final reply = await _ch.invokeMethod<String>('pay', {'url': url, 'package': package}) ?? '';
    return parseUpiReply(reply);
  } on PlatformException catch (e) {
    if (e.code == 'no_app') return const UpiResult(UpiStatus.noApp);
    return UpiResult(UpiStatus.unknown, raw: e.message ?? '');
  } on MissingPluginException {
    return const UpiResult(UpiStatus.noApp);
  }
}

/// "txnId=..&responseCode=00&Status=SUCCESS&txnRef=..&ApprovalRefNo=..."
UpiResult parseUpiReply(String reply) {
  if (reply.trim().isEmpty) return UpiResult(UpiStatus.unknown, raw: reply);
  final m = <String, String>{};
  for (final part in reply.split('&')) {
    final i = part.indexOf('=');
    if (i <= 0) continue;
    m[part.substring(0, i).trim().toLowerCase()] = Uri.decodeComponent(part.substring(i + 1).trim());
  }
  final status = (m['status'] ?? '').toUpperCase();
  final utr = [m['approvalrefno'], m['utr'], m['txnid'], m['txnref']].firstWhere((v) => v != null && v.isNotEmpty && v.toLowerCase() != 'null', orElse: () => '') ?? '';
  if (status == 'SUCCESS' || status == 'SUBMITTED') return UpiResult(UpiStatus.success, utr: utr, raw: reply);
  if (status == 'FAILURE' || status == 'FAILED') return UpiResult(UpiStatus.failed, raw: reply);
  return UpiResult(UpiStatus.unknown, utr: utr, raw: reply);
}

/// Checks a typed UTR: 12 digits (spaces allowed).
String cleanUtr(String s) => s.replaceAll(RegExp(r'\s'), '');
bool validUtr(String s) => RegExp(r'^[0-9A-Za-z]{10,22}$').hasMatch(cleanUtr(s));
