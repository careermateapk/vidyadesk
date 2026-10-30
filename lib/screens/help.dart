import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_state.dart';
import '../core/config.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../ui/mascot.dart';
import '../ui/widgets.dart';
import 'common.dart';
import 'onboarding.dart';

/// Opens the phone's email app with our support address and some details filled in.
Future<void> contactSupport(BuildContext context) async {
  final app = context.appRead;
  final name = app.profile?.name ?? '';
  final role = app.active == null ? '' : '${roleName(app.active!.role)} · ${app.active!.instituteName}';
  final body = '${tr('mail_hello')}\n\n\n\n— — —\n${tr('full_name')}: $name\n${tr('role')}: $role\nVidyaDesk $appVersion · Android';
  final uri = Uri(
    scheme: 'mailto',
    path: supportEmail,
    query: 'subject=${Uri.encodeComponent('VidyaDesk help${role.isEmpty ? '' : ' — $role'}')}&body=${Uri.encodeComponent(body)}',
  );
  final ok = await launchUrl(uri).catchError((_) => false);
  if (!ok && context.mounted) toast(context, trf('no_mail_app', {'mail': supportEmail}));
}

// ---------------------------------------------------------------------------
// FAQ
// ---------------------------------------------------------------------------

class _Faq {
  const _Faq(this.cat, this.q, this.a);
  final String cat, q, a;
}

const _faqs = [
  _Faq('codes', 'faq_q_join', 'faq_a_join'),
  _Faq('codes', 'faq_q_codes', 'faq_a_codes'),
  _Faq('codes', 'faq_q_pending', 'faq_a_pending'),
  _Faq('fees', 'faq_q_upi', 'faq_a_upi'),
  _Faq('fees', 'faq_q_bothpay', 'faq_a_bothpay'),
  _Faq('fees', 'faq_q_receipt', 'faq_a_receipt'),
  _Faq('attendance', 'faq_q_att', 'faq_a_att'),
  _Faq('attendance', 'faq_q_attwrong', 'faq_a_attwrong'),
  _Faq('account', 'faq_q_kids', 'faq_a_kids'),
  _Faq('account', 'faq_q_roles', 'faq_a_roles'),
  _Faq('account', 'faq_q_lang', 'faq_a_lang'),
  _Faq('account', 'faq_q_pass', 'faq_a_pass'),
  _Faq('account', 'faq_q_leave', 'faq_a_leave'),
  _Faq('account', 'faq_q_photo', 'faq_a_photo'),
];

class FaqScreen extends StatefulWidget {
  const FaqScreen({super.key});
  @override
  State<FaqScreen> createState() => _FaqScreenState();
}

class _FaqScreenState extends State<FaqScreen> {
  int _cat = 0;
  String _q = '';
  int _open = 0;

  static const _cats = ['all', 'fees', 'attendance', 'codes', 'account'];

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final list = _faqs.where((f) {
      if (_cat > 0 && f.cat != _cats[_cat]) return false;
      if (_q.isEmpty) return true;
      final s = _q.toLowerCase();
      return tr(f.q).toLowerCase().contains(s) || tr(f.a).toLowerCase().contains(s);
    }).toList();
    return AppScaffold(
      title: tr('help_faq'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 6, 0, 30),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: TextField(
              onChanged: (v) => setState(() {
                _q = v;
                _open = -1;
              }),
              decoration: InputDecoration(hintText: tr('faq_search'), prefixIcon: const Icon(Icons.search_rounded)),
            ),
          ),
          const SizedBox(height: 12),
          PillBar(items: [for (final c in _cats) tr('faqcat_$c')], index: _cat, onChanged: (v) => setState(() {
                _cat = v;
                _open = -1;
              })),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: list.isEmpty
                  ? EmptyState(icon: Icons.search_off_rounded, text: tr('faq_none'), search: true)
                  : Column(children: [
                      for (var i = 0; i < list.length; i++) ...[
                        if (i > 0) const Line(),
                        _FaqItem(
                          q: tr(list[i].q),
                          a: tr(list[i].a),
                          open: _open == i,
                          onTap: () => setState(() => _open = _open == i ? -1 : i),
                        ),
                      ],
                    ]),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: p.brandTint, borderRadius: BorderRadius.circular(Gap.rCard)),
              child: Row(children: [
                const Mascot(size: 46, book: false),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr('still_need_help'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                    Text(tr('reply_within_day'), style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ]),
                ),
                GestureDetector(
                  onTap: () => contactSupport(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                    decoration: BoxDecoration(color: p.brand, borderRadius: BorderRadius.circular(999), boxShadow: p.glow(p.brand)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.mail_outline_rounded, size: 16, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(tr('contact_us'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _FaqItem extends StatelessWidget {
  const _FaqItem({required this.q, required this.a, required this.open, required this.onTap});
  final String q, a;
  final bool open;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(q, style: TextStyle(fontWeight: open ? FontWeight.w800 : FontWeight.w700, fontSize: 14.5))),
            AnimatedRotation(
              turns: open ? .25 : 0,
              duration: const Duration(milliseconds: 220),
              child: Icon(Icons.chevron_right_rounded, color: open ? p.brand : p.muted),
            ),
          ]),
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            child: open
                ? Padding(padding: const EdgeInsets.only(top: 8), child: Text(a, style: TextStyle(color: p.ink2, fontSize: 13.5, height: 1.55, fontWeight: FontWeight.w500)))
                : const SizedBox(width: double.infinity),
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Terms & Privacy
// ---------------------------------------------------------------------------

class LegalScreen extends StatefulWidget {
  const LegalScreen({super.key, this.privacy = false});
  final bool privacy;
  @override
  State<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends State<LegalScreen> {
  late int _tab = widget.privacy ? 1 : 0;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final sections = _tab == 0 ? _terms : _privacy;
    return AppScaffold(
      title: _tab == 0 ? tr('terms') : tr('privacy'),
      subtitle: '${tr('last_updated')} 29 Oct 2026',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 30),
        children: [
          Segmented(items: [tr('terms'), tr('privacy')], index: _tab, onChanged: (v) => setState(() => _tab = v)),
          const SizedBox(height: 14),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (_tab == 1)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(color: p.successTint, borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    Icon(Icons.verified_user_outlined, color: p.success, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_privacyBadge, style: TextStyle(color: p.success, fontWeight: FontWeight.w700, fontSize: 12.5))),
                  ]),
                ),
              for (final s in sections) ...[
                const SizedBox(height: 12),
                Text(s.$1, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 4),
                Text(s.$2, style: TextStyle(color: p.ink2, fontSize: 13.5, height: 1.6, fontWeight: FontWeight.w500)),
              ],
              const SizedBox(height: 16),
              Text('${tr('questions_write')} $supportEmail', style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ]),
          ),
        ],
      ),
    );
  }
}

const _privacyBadge = 'We never sell your data. Only your institute can see it.';

const _terms = [
  ('1. About VidyaDesk', 'VidyaDesk is an app that helps coaching and tuition institutes manage batches, attendance, fees, notices and study material. By creating an account or using the app you agree to these terms.'),
  ('2. Accounts', 'You must give correct details (name, mobile number, address). Keep your password safe — you are responsible for what happens in your account. One person can hold several roles (admin, teacher, student, parent) with the same login.'),
  ('3. Institutes and codes', 'An admin creates an institute and shares codes. Admins and teachers decide who joins. Institute data (batches, attendance, fees, marks, notices) belongs to that institute, and its admin is responsible for keeping it correct.'),
  ('4. Fees and payments', 'Fees are paid directly to the institute (for example by cash or UPI). VidyaDesk does not hold your money. A payment shows as "paid" only after the institute confirms it. Any dispute about fees is between you and the institute.'),
  ('5. Fair use', 'Do not upload anything illegal, abusive or copied without permission, do not try to see other people\'s data, and do not misuse the app. We may suspend accounts that break these rules.'),
  ('6. Students under 18', 'Students under 18 should use VidyaDesk with the knowledge of a parent or guardian. Parents can link to their child with the student code.'),
  ('7. Changes and availability', 'We keep improving the app and may change features or these terms. We try to keep the service running, but it may sometimes be unavailable. The app is provided "as is".'),
  ('8. Leaving', 'You can leave an institute or ask us to delete your account at any time. An admin can delete their institute, which removes its data for everyone.'),
];

const _privacy = [
  ('1. What we collect', 'Your name, mobile number, address and email; your profile photo if you add one; and the attendance, fees, marks, notices and study material your institute adds.'),
  ('2. Why we collect it', 'Only to run your institute\'s attendance, fees, classes and communication, and to show you the right information for your role.'),
  ('3. Who can see it', 'Only members of your institute, according to their role. Teachers see their batches, admins see their institute, and parents see only their own child. We never sell your data or show ads based on it.'),
  ('4. Where it is stored', 'Data is stored securely with Google Firebase. Some details may be kept on your phone so the app opens faster.'),
  ('5. Your choices', 'You can edit your profile any time, remove your photo, leave an institute, or ask us to delete your account and data by writing to us.'),
  ('6. Children', 'Student information is added by the institute or by the student with a parent\'s knowledge. Parents can see their child\'s attendance and fees.'),
];

/// "By continuing you agree to our Terms and Privacy Policy · Help" line.
class LegalFooter extends StatelessWidget {
  const LegalFooter({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    TextStyle link = TextStyle(color: p.brand, fontWeight: FontWeight.w800, fontSize: 12);
    Widget l(String t, VoidCallback onTap) => GestureDetector(onTap: onTap, child: Text(t, style: link));
    final base = TextStyle(color: p.muted, fontWeight: FontWeight.w600, fontSize: 12);
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      runSpacing: 2,
      children: [
        Text(tr('agree_line'), style: base),
        l(tr('terms'), () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const Backdrop(child: LegalScreen())))),
        Text(tr('and'), style: base),
        l(tr('privacy'), () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const Backdrop(child: LegalScreen(privacy: true))))),
        Text('·', style: base),
        l(tr('help'), () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const Backdrop(child: FaqScreen())))),
      ],
    );
  }
}

/// Our own "About" page (Flutter's built-in one always shows "View licenses").
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final demo = context.appRead.isDemo;
    final feats = [
      (Icons.fact_check_outlined, tr('about_f1')),
      (Icons.account_balance_wallet_outlined, tr('about_f2')),
      (Icons.folder_copy_outlined, tr('about_f3')),
      (Icons.quiz_outlined, tr('about_f4')),
      (Icons.forum_outlined, tr('about_f5')),
      (Icons.bar_chart_rounded, tr('about_f6')),
    ];
    return AppScaffold(
      title: tr('about'),
      body: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 30), children: [
        Center(child: const AppLogo(size: 96)),
        const SizedBox(height: 14),
        const Center(child: Text('VidyaDesk', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -.4))),
        Center(child: Text('${tr('version')} $appVersion', style: TextStyle(color: p.muted, fontWeight: FontWeight.w700))),
        const SizedBox(height: 8),
        Center(child: Tag(demo ? tr('mode_demo') : tr('mode_live'), fg: demo ? p.warn : p.success, bg: demo ? p.warnTint : p.successTint)),
        const SizedBox(height: 18),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('about_text'), style: TextStyle(color: p.ink2, height: 1.45, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            for (final f in feats)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  IconBox(f.$1, fg: p.brand, bg: p.brandTint, size: 32),
                  const SizedBox(width: 10),
                  Expanded(child: Text(f.$2, style: const TextStyle(fontWeight: FontWeight.w700))),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: [
            ListTile(leading: Icon(Icons.description_outlined, color: p.indigo), title: Text(tr('terms')), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => push(context, const LegalScreen())),
            ListTile(leading: Icon(Icons.verified_user_outlined, color: p.success), title: Text(tr('privacy')), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => push(context, const LegalScreen(privacy: true))),
            ListTile(leading: Icon(Icons.mail_outline_rounded, color: p.warn), title: Text(tr('contact_us')), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => contactSupport(context)),
          ]),
        ),
        const SizedBox(height: 18),
        Center(child: Text(tr('made_in_india'), style: TextStyle(color: p.muted, fontWeight: FontWeight.w700, fontSize: 12.5))),
      ]),
    );
  }
}
