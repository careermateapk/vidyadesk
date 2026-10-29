import 'dart:typed_data';

import 'package:flutter/services.dart';

/// A UPI app on this phone (its own name and icon). Empty package = let Android show its chooser.
class UpiApp {
  const UpiApp(this.name, this.package, this.letter, this.color, {this.activity = '', this.icon});
  final String name, package, letter, activity;
  final int color;
  final Uint8List? icon;
}

const _chooser = UpiApp('Other UPI app', '', '⋯', 0xFF8A87A6);

/// UPI apps installed on this phone (filled by [loadUpiApps]); the last one opens Android's chooser.
List<UpiApp> upiApps = const [_chooser];

const _preferred = ['com.google.android.apps.nbu.paisa.user', 'com.phonepe.app', 'net.one97.paytm', 'in.org.npci.upiapp', 'in.amazon.mShop.android.shopping'];

/// Reads the UPI apps really installed on the phone.
Future<void> loadUpiApps() async {
  try {
    final list = await _ch.invokeListMethod<Map<dynamic, dynamic>>('apps') ?? [];
    final found = <UpiApp>[
      for (final m in list)
        UpiApp(
          '${m['label'] ?? 'UPI'}',
          '${m['package'] ?? ''}',
          '${m['label'] ?? 'U'}'.characters1,
          0xFF6C5CE7,
          activity: '${m['activity'] ?? ''}',
          icon: m['icon'] is Uint8List ? m['icon'] as Uint8List : null,
        ),
    ];
    int rank(UpiApp a) {
      final i = _preferred.indexOf(a.package);
      return i < 0 ? 99 : i;
    }

    found.sort((a, b) => rank(a).compareTo(rank(b)));
    upiApps = [...found, if (found.length != 1) _chooser];
  } catch (_) {}
}

extension on String {
  String get characters1 => isEmpty ? 'U' : substring(0, 1).toUpperCase();
}

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
  String activity = '',
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
    final reply = await _ch.invokeMethod<String>('pay', {'url': url, 'package': package, 'activity': activity}) ?? '';
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
