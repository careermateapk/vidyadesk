import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/strings.dart';
import '../core/theme.dart';
import '../services/files.dart';
import '../services/reports.dart';
import '../ui/widgets.dart';
import 'common.dart';

/// A file the user can download or share. [make] builds the bytes only when needed.
class FileOption {
  const FileOption({required this.label, required this.name, required this.mime, required this.make, this.text = ''});
  final String label, name, mime, text;
  final Future<Uint8List> Function() make;
  bool get isPdf => mime == 'application/pdf';
}

FileOption pdfOption(TableReport r) => FileOption(label: 'PDF', name: '${r.fileBase}.pdf', mime: 'application/pdf', make: () => reportPdf(r), text: r.title);
FileOption excelOption(TableReport r) => FileOption(label: 'Excel', name: '${r.fileBase}.csv', mime: 'text/csv', make: () async => reportCsv(r), text: r.title);

/// Save to Download/VidyaDesk and show a message with OPEN.
Future<void> downloadFile(BuildContext context, FileOption f) async {
  final messenger = ScaffoldMessenger.of(context);
  toast(context, tr('making_report'));
  try {
    final bytes = await f.make();
    final uri = await saveToDownloads(bytes, f.name, f.mime);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 6),
        content: Text('${tr('saved_to_downloads')}\n${f.name}'),
        action: uri == null ? null : SnackBarAction(label: tr('open_caps'), onPressed: () => openSaved(uri, f.mime)),
      ));
  } on PlatformException catch (e) {
    messenger.hideCurrentSnackBar();
    if (context.mounted) toast(context, e.code == 'need_permission' ? tr('allow_storage') : tr('err_save_file'));
  } catch (_) {
    messenger.hideCurrentSnackBar();
    if (context.mounted) toast(context, tr('err_save_file'));
  }
}

Future<void> shareFile(BuildContext context, FileOption f) async {
  toast(context, tr('making_report'));
  try {
    await shareBytes(await f.make(), f.name, f.mime, text: f.text);
  } catch (e) {
    if (context.mounted) toast(context, errorMessage(e));
  }
}

/// Row: [PDF/Excel label] [Download] [Share]
class FileActionsRow extends StatelessWidget {
  const FileActionsRow({super.key, required this.f, this.outer});
  final FileOption f;

  /// When shown in a bottom sheet: close it and show messages on this screen instead.
  final BuildContext? outer;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final c = f.isPdf ? p.danger : p.success;
    Widget b(String label, IconData icon, Color fg, Color bg, VoidCallback onTap, {bool border = false}) => Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              height: 42,
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: border ? Border.all(color: p.border) : null),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 17, color: fg),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: fg)),
              ]),
            ),
          ),
        );
    return Row(children: [
      SizedBox(
        width: 72,
        child: Row(children: [
          Icon(f.isPdf ? Icons.picture_as_pdf_outlined : Icons.grid_on_rounded, size: 17, color: c),
          const SizedBox(width: 5),
          Text(f.label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: c)),
        ]),
      ),
      b(tr('download'), Icons.download_rounded, c, c.withValues(alpha: .1), () => _run(context, downloadFile)),
      const SizedBox(width: 8),
      b(tr('share'), Icons.share_rounded, p.ink, p.cardAlt, () => _run(context, shareFile), border: true),
    ]);
  }
}

extension on FileActionsRow {
  void _run(BuildContext context, Future<void> Function(BuildContext, FileOption) job) {
    final o = outer;
    if (o != null) {
      Navigator.of(context).pop();
      if (o.mounted) job(o, f);
    } else {
      job(context, f);
    }
  }
}

/// Bottom sheet with Download / Share for each format.
Future<void> showFileSheet(BuildContext context, {required String title, String subtitle = '', required List<FileOption> files}) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          if (subtitle.isNotEmpty) Text(subtitle, style: TextStyle(color: c.pal.muted, fontWeight: FontWeight.w600, fontSize: 12.5)),
          const SizedBox(height: 14),
          for (final f in files) Padding(padding: const EdgeInsets.only(bottom: 10), child: FileActionsRow(f: f, outer: context)),
          Text(tr('downloads_where'), style: TextStyle(color: c.pal.muted, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
    ),
  );
}
