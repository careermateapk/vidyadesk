import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/backend.dart';
import '../data/models.dart';
import '../ui/widgets.dart';
import 'common.dart';

(IconData, Color, Color) noticeStyle(Palette p, String kind) => switch (kind) {
      'holiday' => (Icons.beach_access_rounded, p.warn, p.warnTint),
      'cancel' => (Icons.event_busy_rounded, p.danger, p.dangerTint),
      'fees' => (Icons.currency_rupee_rounded, p.success, p.successTint),
      _ => (Icons.campaign_rounded, p.brand, p.brandTint),
    };

String ago(int ms) {
  final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
  if (d.inMinutes < 1) return tr('just_now');
  if (d.inHours < 1) return trf('min_ago', {'n': '${d.inMinutes}'});
  if (d.inDays < 1) return trf('hr_ago', {'n': '${d.inHours}'});
  if (d.inDays < 7) return trf('day_ago', {'n': '${d.inDays}'});
  return prettyDate(DateTime.fromMillisecondsSinceEpoch(ms));
}

class NoticeCard extends StatelessWidget {
  const NoticeCard({super.key, required this.n, this.batchTitle, this.instituteName = ''});
  final Notice n;
  final String? batchTitle;
  final String instituteName;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = noticeStyle(p, n.kind);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconBox(s.$1, fg: s.$2, bg: s.$3),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('kind_${n.kind}'), style: TextStyle(fontWeight: FontWeight.w900, color: s.$2)),
              Text('${n.byName} · ${ago(n.createdAt)}', style: TextStyle(color: p.muted, fontSize: 12)),
            ]),
          ),
          IconButton(
            tooltip: tr('share'),
            onPressed: () => SharePlus.instance.share(ShareParams(text: '📢 ${instituteName.isEmpty ? '' : '$instituteName\n'}${n.text}\n— ${n.byName}')),
            icon: Icon(Icons.share_rounded, color: p.muted, size: 20),
          ),
        ]),
        const SizedBox(height: 10),
        Text(n.text, style: const TextStyle(fontSize: 15, height: 1.45)),
        if (batchTitle != null) ...[
          const SizedBox(height: 8),
          Tag(batchTitle!, fg: p.indigo, bg: p.indigoTint, leading: Icon(Icons.class_rounded, size: 13, color: p.indigo)),
        ],
      ]),
    );
  }
}

class NoticesPage extends StatelessWidget {
  const NoticesPage({super.key, required this.m});
  final Membership m;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      appBar: InnerBar(title: tr('nav_notices'), showBack: false),
      body: Loader<(List<Notice>, List<Batch>)>(
        load: () async {
          final b = context.appRead.backend;
          return (await b.notices(m.instituteId), await b.batches(m.instituteId));
        },
        builder: (context, d, reload) {
          final batches = {for (final b in d.$2) b.id: b};
          // students see notices for everyone and for their own batches
          final list = m.role == Role.student ? d.$1.where((n) => n.batchId.isEmpty || m.batchIds.contains(n.batchId)).toList() : d.$1;
          return Stack(children: [
            ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16, 6, 16, m.isStaff ? 110 : 30),
              children: [
                if (list.isEmpty) EmptyState(icon: Icons.notifications_none_rounded, text: tr('no_notices')),
                for (var i = 0; i < list.length; i++)
                  FadeIn(
                    delay: stagger(i),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: NoticeCard(n: list[i], batchTitle: batches[list[i].batchId]?.title, instituteName: m.instituteName),
                    ),
                  ),
              ],
            ),
            if (m.isStaff)
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: PrimaryButton(
                  label: tr('send_notice'),
                  icon: Icons.campaign_rounded,
                  arrow: false,
                  gradient: LinearGradient(colors: [p.accent, const Color(0xFFE08A0B)]),
                  onPressed: () async {
                    await push(context, PostNoticeScreen(m: m, batches: myBatches(m, d.$2)));
                    reload();
                  },
                ),
              ),
          ]);
        },
      ),
    );
  }
}

class PostNoticeScreen extends StatefulWidget {
  const PostNoticeScreen({super.key, required this.m, required this.batches});
  final Membership m;
  final List<Batch> batches;
  @override
  State<PostNoticeScreen> createState() => _PostNoticeScreenState();
}

class _PostNoticeScreenState extends State<PostNoticeScreen> {
  final _text = TextEditingController();
  String _kind = 'general';
  String _batch = '';
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _template(String kind) {
    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));
    final b = widget.batches.where((x) => x.id == _batch).firstOrNull;
    setState(() {
      _kind = kind;
      _text.text = switch (kind) {
        'holiday' => trf('tpl_holiday', {'date': prettyDate(tomorrow)}),
        'cancel' => trf('tpl_cancel', {'batch': b?.title ?? tr('todays_class'), 'date': prettyDate(now)}),
        'fees' => trf('tpl_fees', {'month': tr('m${now.month}')}),
        _ => '',
      };
    });
  }

  Future<void> _post({bool share = false}) async {
    final app = context.appRead;
    final text = _text.text.trim();
    if (text.length < 3) {
      toast(context, tr('err_notice_empty'));
      return;
    }
    setState(() => _busy = true);
    try {
      final n = Notice(id: newId(), text: text, kind: _kind, byName: app.profile?.name ?? widget.m.name, createdAt: DateTime.now().millisecondsSinceEpoch, batchId: _batch);
      await app.backend.postNotice(widget.m.instituteId, n);
      if (share) await SharePlus.instance.share(ShareParams(text: '📢 ${widget.m.instituteName}\n$text\n— ${n.byName}'));
      if (!mounted) return;
      toast(context, tr('notice_posted'));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) toast(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      appBar: InnerBar(title: tr('send_notice')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 40),
        children: [
          FieldLabel(tr('quick_templates')),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final k in ['general', 'holiday', 'cancel', 'fees'])
              Builder(builder: (context) {
                final s = noticeStyle(p, k);
                final on = _kind == k;
                return ChoiceChip(
                  avatar: Icon(s.$1, size: 18, color: on ? s.$2 : p.muted),
                  label: Text(tr('kind_$k')),
                  selected: on,
                  selectedColor: s.$3,
                  labelStyle: TextStyle(fontWeight: FontWeight.w800, color: on ? s.$2 : p.ink),
                  side: BorderSide(color: on ? s.$2 : p.border),
                  showCheckmark: false,
                  onSelected: (_) => _template(k),
                );
              }),
          ]),
          const SizedBox(height: 16),
          FieldLabel(tr('send_to')),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ChoicePill(label: tr('everyone'), selected: _batch.isEmpty, onTap: () => setState(() => _batch = '')),
            for (final b in widget.batches) ChoicePill(label: b.title, sub: daysCode(b.days), selected: _batch == b.id, onTap: () => setState(() => _batch = b.id)),
          ]),
          const SizedBox(height: 16),
          FieldLabel(tr('message')),
          TextField(controller: _text, minLines: 5, maxLines: 10, maxLength: 600, decoration: InputDecoration(hintText: tr('notice_hint'))),
          const SizedBox(height: 10),
          PrimaryButton(label: tr('post_notice'), icon: Icons.send_rounded, arrow: false, busy: _busy, onPressed: () => _post()),
          const SizedBox(height: 10),
          SoftButton(label: tr('post_and_whatsapp'), icon: Icons.chat_rounded, color: p.successTint, textColor: p.success, onPressed: _busy ? null : () => _post(share: true)),
        ],
      ),
    );
  }
}
