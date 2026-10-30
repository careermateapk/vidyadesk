import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../services/receipt.dart';
import '../services/upi.dart';
import '../services/push.dart';
import '../ui/widgets.dart';
import 'common.dart';
import 'file_sheet.dart';

/// Receipt PDF for a paid fee: download it or share it.
Future<void> shareFeeReceipt(BuildContext context, String instituteId, FeeRecord fee, {Institute? inst, String studentCode = ''}) async {
  try {
    final i = inst ?? await context.appRead.backend.institute(instituteId);
    if (i == null) throw Exception('no institute');
    if (!context.mounted) return;
    final safe = fee.studentName.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    await showFileSheet(context, title: tr('receipt_pdf'), subtitle: '${fee.studentName} · ${monthLabel(fee.month)}', files: [
      FileOption(
        label: 'PDF',
        name: 'Receipt_${safe}_${fee.month}.pdf',
        mime: 'application/pdf',
        make: () => buildReceipt(inst: i, fee: fee, studentCode: studentCode),
        text: '${i.name} — fee receipt ${fee.receiptNo}',
      ),
    ]);
  } catch (e) {
    if (context.mounted) toast(context, errorMessage(e));
  }
}

// ---------------------------------------------------------------------------
// Pay by UPI (student or parent)
// ---------------------------------------------------------------------------

Future<bool?> showPayFee(
  BuildContext context, {
  required Membership m,
  required Institute inst,
  required String studentUid,
  required String studentName,
  required String month,
  required int amount,
  FeeRecord? existing,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _PaySheet(m: m, inst: inst, studentUid: studentUid, studentName: studentName, month: month, amount: amount, existing: existing),
  );
}

class _PaySheet extends StatefulWidget {
  const _PaySheet({required this.m, required this.inst, required this.studentUid, required this.studentName, required this.month, required this.amount, this.existing});
  final Membership m;
  final Institute inst;
  final String studentUid, studentName, month;
  final int amount;
  final FeeRecord? existing;
  @override
  State<_PaySheet> createState() => _PaySheetState();
}

class _PaySheetState extends State<_PaySheet> {
  int _app = 0;
  bool _busy = false;

  Future<void> _pay() async {
    final app = context.appRead;
    final upi = upiApps[_app];
    setState(() => _busy = true);
    try {
      final ref = 'VD${DateTime.now().millisecondsSinceEpoch}';
      UpiResult r;
      if (app.isDemo) {
        // Demo: never open a real payment — pretend it worked.
        await Future<void>.delayed(const Duration(milliseconds: 900));
        r = UpiResult(UpiStatus.success, utr: '${DateTime.now().millisecondsSinceEpoch}'.substring(1, 13));
      } else {
        r = await payByUpi(
          vpa: widget.inst.upiId,
          payee: widget.inst.upiName.isEmpty ? widget.inst.name : widget.inst.upiName,
          amount: widget.amount,
          note: '${widget.studentName} ${monthLabel(widget.month)} fee',
          ref: ref,
          package: upi.package,
          activity: upi.activity,
        );
      }
      if (!mounted) return;
      switch (r.status) {
        case UpiStatus.noApp:
          toast(context, trf('upi_no_app', {'app': upi.name}));
          return;
        case UpiStatus.failed:
          toast(context, tr('upi_failed'));
          return;
        case UpiStatus.success:
        case UpiStatus.unknown:
          var utr = r.utr;
          if (utr.isEmpty || r.status == UpiStatus.unknown) {
            final typed = await askUtr(context, utr);
            if (typed == null) return;
            utr = typed;
          }
          await _claim(utr, upi.name);
      }
    } catch (e) {
      if (mounted) toast(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _claim(String utr, String via) async {
    final app = context.appRead;
    final e = widget.existing;
    final me = app.profile;
    final rel = widget.m.role == Role.parent ? ' (${tr('rel_${widget.m.relation.isEmpty ? 'guardian' : widget.m.relation}')})' : '';
    final f = FeeRecord(
      studentUid: widget.studentUid,
      studentName: widget.studentName,
      month: widget.month,
      amount: e?.amount ?? widget.amount,
      claimed: true,
      claimUtr: cleanUtr(utr),
      claimBy: '${me?.name ?? widget.m.name}$rel',
      claimByUid: app.signedIn?.uid ?? widget.m.uid,
      claimVia: via,
      claimAt: DateTime.now().millisecondsSinceEpoch,
      lateFee: e?.lateFee ?? 0,
      parts: e?.parts,
    );
    await app.backend.claimFee(widget.m.instituteId, f);
    Push.send(
      inst: widget.m.instituteId,
      kind: 'fee_claim',
      title: '💰 ${trf('fee_received_from', {'name': widget.studentName})}',
      body: '${rupees(widget.amount)} · ${monthLabel(widget.month)} · UTR ${cleanUtr(utr)} — ${tr('tap_to_confirm')}',
      topics: [Push.admins(widget.m.instituteId)],
    );
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    await showThanks(context, tr('thanks'), sub: tr('payment_sent'));
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .88),
        child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('pay_fees'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          Text('${widget.studentName} · ${monthLabel(widget.month)}', style: TextStyle(color: p.muted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          AppCard(
            child: Column(children: [
              Text(rupees(widget.amount), style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w800, letterSpacing: -1.5)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(color: p.cardAlt, borderRadius: BorderRadius.circular(12)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.verified_user_outlined, color: p.success, size: 18),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text('${tr('paying_to')} ${widget.inst.upiId}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: p.ink2)),
                  ),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          FieldLabel(tr('pay_with')),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: upiApps.length,
              itemBuilder: (_, i) =>
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _app = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: p.card,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _app == i ? p.brand : p.border, width: _app == i ? 2 : 1),
                      ),
                      child: Row(children: [
                        UpiIcon(upiApps[i], size: 40),
                        const SizedBox(width: 12),
                        Expanded(child: Text(upiApps[i].name, style: const TextStyle(fontWeight: FontWeight.w800))),
                        Icon(_app == i ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: _app == i ? p.brand : p.border),
                      ]),
                    ),
                  ),
                ),
            ),
          ),
          const SizedBox(height: 6),
          PrimaryButton(label: trf('pay_amount_with', {'amt': rupees(widget.amount), 'app': upiApps[_app].name}), busy: _busy, arrow: false, onPressed: _pay),
          if (context.app.demoFeeLeft) ...[
            const SizedBox(height: 8),
            SoftButton(
              label: tr('demo_fee_pay'),
              icon: Icons.science_outlined,
              color: p.warnTint,
              textColor: p.warn,
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      try {
                        context.appRead.useDemoFee();
                        await _claim('DEMO${DateTime.now().millisecondsSinceEpoch % 100000000}', 'Demo');
                      } catch (e) {
                        if (mounted) toast(context, errorMessage(e));
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
            ),
          ],
          const SizedBox(height: 8),
          Text(tr('utr_auto_note'), textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
      ),
    );
  }
}

/// Asks for the UTR when the UPI app did not send it back.
Future<String?> askUtr(BuildContext context, String guess) {
  final c = TextEditingController(text: guess);
  return showDialog<String>(
    context: context,
    builder: (d) {
      final p = d.pal;
      String? err;
      return StatefulBuilder(builder: (d, set) {
        return AlertDialog(
          title: Text(tr('enter_utr')),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('enter_utr_sub'), style: TextStyle(color: p.muted, fontSize: 13, height: 1.4)),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(hintText: '4318 2290 7712', errorText: err),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('not_paid'))),
            FilledButton(
              onPressed: () {
                if (!validUtr(c.text)) {
                  set(() => err = tr('err_utr'));
                  return;
                }
                Navigator.pop(d, cleanUtr(c.text));
              },
              child: Text(tr('send')),
            ),
          ],
        );
      });
    },
  );
}

// ---------------------------------------------------------------------------
// Admin: confirm UPI payments
// ---------------------------------------------------------------------------

class ConfirmPaymentsScreen extends StatefulWidget {
  const ConfirmPaymentsScreen({super.key, required this.m});
  final Membership m;
  @override
  State<ConfirmPaymentsScreen> createState() => _ConfirmPaymentsScreenState();
}

class _ConfirmPaymentsScreenState extends State<ConfirmPaymentsScreen> {
  final Set<String> _busy = {};
  final Map<String, bool> _done = {};

  Future<void> _decide(FeeRecord f, bool ok) async {
    if (ok && !await ensureReceiptAddress(context, widget.m)) return;
    if (!mounted) return;
    setState(() => _busy.add(f.id));
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final rec = ok
          ? FeeRecord(
              studentUid: f.studentUid,
              studentName: f.studentName,
              month: f.month,
              amount: f.amount,
              paid: true,
              paidOn: now,
              mode: 'UPI',
              receiptNo: 'R-${now.toString().substring(6)}',
              utr: f.claimUtr,
              paidBy: f.claimBy,
              claimed: false,
              lateFee: f.lateFee,
              parts: f.parts,
            )
          : FeeRecord(studentUid: f.studentUid, studentName: f.studentName, month: f.month, amount: f.amount, lateFee: f.lateFee, parts: f.parts);
      await context.appRead.backend.saveFee(widget.m.instituteId, rec);
      Push.send(
        inst: widget.m.instituteId,
        kind: ok ? 'fee_paid' : 'fee_rejected',
        title: ok ? '✅ ${tr('push_fee_confirmed')}' : '⚠️ ${tr('push_fee_not_received')}',
        body: '${f.studentName} · ${rupees(f.amount)} · ${monthLabel(f.month)}',
        topics: [Push.person(widget.m.instituteId, f.studentUid)],
      );
      HapticFeedback.mediumImpact();
      setState(() => _done[f.id] = ok);
      if (ok) showCoinDrop(context, f.amount, title: f.studentName);
    } catch (e) {
      if (mounted) toast(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy.remove(f.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AppScaffold(
      title: tr('payments_confirm'),
      body: Loader<List<FeeRecord>>(
        load: () => context.appRead.backend.feeClaims(widget.m.instituteId),
        builder: (context, list, reload) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 30),
          children: [
            if (list.isEmpty) EmptyState(icon: Icons.verified_outlined, text: tr('no_payments_confirm')),
            for (var i = 0; i < list.length; i++)
              FadeIn(
                delay: stagger(i),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: _done.containsKey(list[i].id) ? .55 : 1,
                    child: AppCard(
                      border: _done[list[i].id] == null ? null : (_done[list[i].id]! ? p.success : p.danger),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(children: [
                          Avatar(list[i].studentName, size: 46, index: i),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(list[i].studentName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                              Text('${monthLabel(list[i].month)} · ${list[i].claimVia} · ${list[i].claimBy}',
                                  maxLines: 2, style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
                            ]),
                          ),
                          Text(rupees(list[i].amount), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
                        ]),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                          decoration: BoxDecoration(color: p.cardAlt, borderRadius: BorderRadius.circular(14)),
                          child: Row(children: [
                            Text('UTR', style: TextStyle(color: p.muted, fontWeight: FontWeight.w700, fontSize: 12.5)),
                            const SizedBox(width: 10),
                            Expanded(child: Text(list[i].claimUtr.isEmpty ? '—' : list[i].claimUtr, style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1, fontSize: 15))),
                            IconButton(onPressed: () => copyText(context, list[i].claimUtr), icon: Icon(Icons.copy_rounded, size: 18, color: p.muted)),
                          ]),
                        ),
                        const SizedBox(height: 6),
                        Text(tr('check_utr_bank'), style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 12),
                        if (_done.containsKey(list[i].id))
                          Row(children: [
                            Icon(_done[list[i].id]! ? Icons.check_circle_rounded : Icons.cancel_rounded, color: _done[list[i].id]! ? p.success : p.danger),
                            const SizedBox(width: 6),
                            Text(_done[list[i].id]! ? tr('marked_paid') : tr('marked_not_received'),
                                style: TextStyle(fontWeight: FontWeight.w800, color: _done[list[i].id]! ? p.success : p.danger)),
                          ])
                        else
                          Row(children: [
                            Expanded(
                              child: SoftButton(
                                label: tr('not_received'),
                                color: p.dangerTint,
                                textColor: p.danger,
                                onPressed: _busy.contains(list[i].id) ? null : () => _decide(list[i], false),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: SoftButton(
                                label: tr('confirm'),
                                icon: Icons.check_rounded,
                                color: p.success,
                                textColor: Colors.white,
                                onPressed: _busy.contains(list[i].id) ? null : () => _decide(list[i], true),
                              ),
                            ),
                          ]),
                      ]),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Admin: institute details & UPI
// ---------------------------------------------------------------------------

class InstituteSettingsScreen extends StatefulWidget {
  const InstituteSettingsScreen({super.key, required this.m});
  final Membership m;
  @override
  State<InstituteSettingsScreen> createState() => _InstituteSettingsScreenState();
}

class _InstituteSettingsScreenState extends State<InstituteSettingsScreen> {
  Institute? _inst;
  final _name = TextEditingController(), _city = TextEditingController(), _addr = TextEditingController();
  final _phone = TextEditingController(), _upi = TextEditingController(), _upiName = TextEditingController();
  final _late = TextEditingController(), _gst = TextEditingController();
  int _dueDay = 10;
  bool _busy = false;
  String? _upiErr, _gstErr, _addrErr;
  String _logo = '';
  bool _gstOn = false;

  Future<void> _pickLogo() async {
    try {
      final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 320, maxHeight: 320, imageQuality: 75);
      if (f == null) return;
      final b = await f.readAsBytes();
      setState(() => _logo = base64Encode(b));
    } catch (_) {
      if (mounted) toast(context, tr('err_photo'));
    }
  }

  @override
  void initState() {
    super.initState();
    context.appRead.backend.institute(widget.m.instituteId).then((i) {
      if (!mounted || i == null) return;
      setState(() {
        _inst = i;
        _name.text = i.name;
        _city.text = i.city;
        _addr.text = i.address;
        _phone.text = i.phone;
        _upi.text = i.upiId;
        _upiName.text = i.upiName;
        _dueDay = i.dueDay;
        _late.text = i.lateFee == 0 ? '' : '${i.lateFee}';
        _logo = i.logo;
        _gstOn = i.gstOn;
        _gst.text = i.gstin;
      });
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _city, _addr, _phone, _upi, _upiName, _late, _gst]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final upi = _upi.text.trim();
    if (upi.isNotEmpty && !RegExp(r'^[\w.\-]{2,}@[A-Za-z]{2,}$').hasMatch(upi)) {
      setState(() => _upiErr = tr('err_upi'));
      return;
    }
    final gst = _gst.text.trim().toUpperCase();
    if (_gstOn && !RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$').hasMatch(gst)) {
      setState(() => _gstErr = tr('err_gstin'));
      return;
    }
    setState(() {
      _busy = true;
      _upiErr = null;
      _gstErr = null;
      _addrErr = null;
    });
    try {
      final i = _inst!.copyWith(
        name: _name.text.trim().isEmpty ? _inst!.name : _name.text.trim(),
        city: _city.text.trim(),
        address: _addr.text.trim(),
        phone: _phone.text.trim(),
        upiId: upi,
        upiName: _upiName.text.trim(),
        dueDay: _dueDay,
        lateFee: int.tryParse(_late.text.trim()) ?? 0,
        logo: _logo,
        gstOn: _gstOn,
        gstin: _gstOn ? gst : '',
      );
      await context.appRead.backend.updateInstitute(i);
      if (!mounted) return;
      toast(context, tr('saved'));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) toast(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _f(String label, TextEditingController c, IconData icon, {String? hint, TextInputType? type, String? err}) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FieldLabel(label),
          TextField(controller: c, keyboardType: type, decoration: InputDecoration(hintText: hint, prefixIcon: Icon(icon), errorText: err)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AppScaffold(
      title: tr('institute_details'),
      bottom: PrimaryButton(label: tr('save'), arrow: false, busy: _busy, onPressed: _inst == null ? null : _save),
      body: _inst == null
          ? const LoadingView()
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 20),
              children: [
                Text(tr('receipt_details_sub'), style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.4)),
                const SizedBox(height: 12),
                AppCard(
                  padding: const EdgeInsets.all(14),
                  onTap: _pickLogo,
                  child: Row(children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(color: p.brandTint, borderRadius: BorderRadius.circular(18), border: Border.all(color: p.brand, width: 1.5)),
                      clipBehavior: Clip.antiAlias,
                      child: Avatar.bytesOf(_logo) == null ? Icon(Icons.add_photo_alternate_outlined, color: p.brand, size: 28) : Image.memory(Avatar.bytesOf(_logo)!, fit: BoxFit.cover),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(tr('coaching_logo'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        Text(tr('coaching_logo_sub'), style: TextStyle(color: p.muted, fontSize: 12.5)),
                        const SizedBox(height: 6),
                        Row(children: [
                          Tag(_logo.isEmpty ? tr('add_logo') : tr('change_logo'), fg: Colors.white, bg: p.brand, leading: const Icon(Icons.photo_camera_outlined, size: 13, color: Colors.white)),
                          if (_logo.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            GestureDetector(onTap: () => setState(() => _logo = ''), child: Text(tr('remove'), style: TextStyle(color: p.danger, fontWeight: FontWeight.w800, fontSize: 12.5))),
                          ],
                        ]),
                      ]),
                    ),
                  ]),
                ),
                const SizedBox(height: 14),
                _f(tr('inst_name'), _name, Icons.apartment_rounded),
                _f(tr('city'), _city, Icons.location_city_rounded),
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    FieldLabel('${tr('full_address')} *'),
                    TextField(controller: _addr, minLines: 2, maxLines: 3, decoration: InputDecoration(hintText: tr('street_hint'), prefixIcon: const Icon(Icons.place_outlined), errorText: _addrErr, helperText: tr('address_on_receipt'))),
                  ]),
                ),
                _f(tr('mobile'), _phone, Icons.call_outlined, type: TextInputType.phone),
                AppCard(
                  padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _gstOn,
                    onChanged: (v) => setState(() => _gstOn = v),
                    title: Text(tr('gst_registered_q'), style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(tr('gst_not_needed_small')),
                  ),
                ),
                if (_gstOn) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _gst,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 15,
                    decoration: InputDecoration(hintText: '10ABCDE1234F1Z5', prefixIcon: const Icon(Icons.receipt_long_outlined), errorText: _gstErr, labelText: 'GSTIN', helperText: tr('gst_help')),
                  ),
                ],
                const SizedBox(height: 14),
                const SizedBox(height: 4),
                SectionTitle(tr('upi_for_fees')),
                const SizedBox(height: 4),
                Text(tr('upi_for_fees_sub'), style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.4)),
                const SizedBox(height: 12),
                _f(tr('upi_id'), _upi, Icons.account_balance_outlined, hint: 'sharmaclasses@ybl', type: TextInputType.emailAddress, err: _upiErr),
                _f(tr('upi_name'), _upiName, Icons.badge_outlined, hint: 'Sharma Classes'),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: p.warnTint, borderRadius: BorderRadius.circular(14)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.lightbulb_outline_rounded, color: p.warn, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(tr('upi_business_tip'), style: TextStyle(color: p.warn, fontWeight: FontWeight.w700, fontSize: 12.5, height: 1.4))),
                  ]),
                ),
                const SizedBox(height: 20),
                SectionTitle(tr('fee_rules')),
                const SizedBox(height: 4),
                Text(tr('fee_rules_sub'), style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.4)),
                const SizedBox(height: 12),
                FieldLabel(tr('due_day')),
                AppCard(
                  padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                  child: Row(children: [
                    Icon(Icons.event_rounded, color: p.brand),
                    const SizedBox(width: 10),
                    Expanded(child: Text(trf('due_day_n', {'n': '$_dueDay'}), style: const TextStyle(fontWeight: FontWeight.w800))),
                    IconButton(onPressed: _dueDay <= 1 ? null : () => setState(() => _dueDay--), icon: const Icon(Icons.remove_circle_outline_rounded)),
                    IconButton(onPressed: _dueDay >= 28 ? null : () => setState(() => _dueDay++), icon: const Icon(Icons.add_circle_outline_rounded)),
                  ]),
                ),
                const SizedBox(height: 14),
                FieldLabel(tr('late_fee')),
                TextField(
                  controller: _late,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(prefixText: '₹ ', hintText: '0', helperText: tr('late_fee_help')),
                ),
              ],
            ),
    );
  }
}


/// Admin: fees can be collected only after the coaching's address is set (it goes on every receipt).
/// Asks for it once, saves it and returns true; false when the admin cancels.
Future<bool> ensureReceiptAddress(BuildContext context, Membership m) async {
  final app = context.appRead;
  Institute? inst;
  try {
    inst = await app.backend.institute(m.instituteId);
  } catch (_) {
    return true;
  }
  if (inst == null || inst.receiptReady) return true;
  if (!context.mounted) return false;
  final c = TextEditingController(text: inst.address);
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (s) {
      final p = s.pal;
      String? err;
      var busy = false;
      return StatefulBuilder(
        builder: (s, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.of(s).viewInsets.bottom),
          child: SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(child: IconBox(Icons.place_rounded, fg: p.warn, bg: p.warnTint, size: 60)),
              const SizedBox(height: 12),
              Text(tr('need_address_title'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(tr('need_address_sub'), textAlign: TextAlign.center, style: TextStyle(color: p.muted, height: 1.45)),
              const SizedBox(height: 14),
              FieldLabel(tr('full_address')),
              TextField(controller: c, autofocus: true, minLines: 2, maxLines: 3, decoration: InputDecoration(hintText: tr('street_hint'), errorText: err)),
              const SizedBox(height: 10),
              Row(children: [
                Icon(Icons.image_outlined, size: 18, color: p.brand),
                const SizedBox(width: 8),
                Expanded(child: Text(tr('logo_gst_later'), style: TextStyle(color: p.ink2, fontWeight: FontWeight.w600, fontSize: 12.5))),
              ]),
              const SizedBox(height: 14),
              PrimaryButton(
                label: tr('save_and_collect'),
                arrow: false,
                busy: busy,
                onPressed: () async {
                  if (c.text.trim().length < 8) {
                    set(() => err = tr('err_address'));
                    return;
                  }
                  set(() => busy = true);
                  try {
                    await app.backend.updateInstitute(inst!.copyWith(address: c.text.trim()));
                    if (s.mounted) Navigator.pop(s, true);
                  } catch (e) {
                    set(() {
                      busy = false;
                      err = errorMessage(e);
                    });
                  }
                },
              ),
            ]),
          ),
        ),
      );
    },
  );
  return saved == true;
}
