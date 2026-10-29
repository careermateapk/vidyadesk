import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../ui/widgets.dart';
import 'common.dart';
import 'geo.dart';
import 'money.dart' show MonthBar;
import '../services/location.dart';
import 'dart:math' as math;

String clock(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return timeLabel(d.hour * 60 + d.minute);
}

/// Teacher home: one tap to check in when arriving and out when leaving.
/// When the admin has turned on "location check-in", it works only near the coaching
/// (or from home, if online classes are allowed for this teacher).
class CheckInCard extends StatefulWidget {
  const CheckInCard({super.key, required this.m});
  final Membership m;
  @override
  State<CheckInCard> createState() => _CheckInCardState();
}

class _CheckInCardState extends State<CheckInCard> {
  CheckIn? _today;
  Institute? _inst;
  int _days = 0;
  bool _loaded = false, _ready = false, _busy = false, _locating = false;
  LocResult? _loc;

  bool get _geo => _inst != null && _inst!.geoCheckin && _inst!.hasPlace;
  double? get _dist => _loc == null || !_loc!.ok || !_geo ? null : distanceMeters(_loc!.lat, _loc!.lng, _inst!.geoLat, _inst!.geoLng);
  bool get _inside => _dist != null && _dist! <= _inst!.geoRadius + math.min(_loc!.accuracy, 50);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) _load();
  }

  Future<void> _load() async {
    _loaded = true;
    try {
      final b = context.appRead.backend;
      final now = DateTime.now();
      final list = await b.checkIns(widget.m.instituteId, monthKey(now), uid: widget.m.uid);
      final inst = await b.institute(widget.m.instituteId);
      if (!mounted) return;
      setState(() {
        _inst = inst;
        _today = list.where((c) => c.dateKey == dateKey(now)).firstOrNull;
        _days = list.length;
        _ready = true;
      });
      if (_geo && _today == null) _locate();
    } catch (_) {}
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    LocResult r;
    if (context.appRead.isDemo) {
      // Demo: pretend the phone is 35 m from the coaching.
      await Future<void>.delayed(const Duration(milliseconds: 700));
      r = LocResult(lat: _inst!.geoLat + .0002, lng: _inst!.geoLng + .00022, accuracy: 12);
    } else {
      r = await currentLocation();
    }
    if (!mounted) return;
    setState(() {
      _loc = r;
      _locating = false;
    });
  }

  Future<void> _checkIn(String mode) async {
    final app = context.appRead;
    final now = DateTime.now();
    setState(() => _busy = true);
    try {
      final c = CheckIn(
        uid: widget.m.uid,
        name: app.profile?.name ?? widget.m.name,
        dateKey: dateKey(now),
        inAt: now.millisecondsSinceEpoch,
        mode: mode,
        dist: mode == 'coaching' && _dist != null ? _dist!.round() : -1,
      );
      await app.backend.saveCheckIn(widget.m.instituteId, c);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() {
        _days++;
        _today = c;
      });
      toast(context, trf('checked_in_at', {'t': clock(c.inAt)}));
    } catch (e) {
      if (mounted) toast(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkOut() async {
    final c = _today;
    if (c == null) return;
    setState(() => _busy = true);
    try {
      c.outAt = DateTime.now().millisecondsSinceEpoch;
      await context.appRead.backend.saveCheckIn(widget.m.instituteId, c);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() {});
      toast(context, trf('checked_out_at', {'t': clock(c.outAt)}));
    } catch (e) {
      c.outAt = 0;
      if (mounted) toast(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _btn(Palette p, String label, IconData icon, Color c, VoidCallback? onTap, {bool soft = false}) => GestureDetector(
        onTap: _busy ? null : onTap,
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: onTap == null ? p.cardAlt : (soft ? c.withValues(alpha: .13) : c),
            borderRadius: BorderRadius.circular(14),
            boxShadow: onTap == null || soft ? null : p.glow(c),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (_busy && onTap != null)
              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: soft ? c : Colors.white))
            else
              Icon(icon, size: 18, color: onTap == null ? p.muted : (soft ? c : Colors.white)),
            const SizedBox(width: 6),
            Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: onTap == null ? p.muted : (soft ? c : Colors.white)))),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final t = _today;
    final inNow = t != null && t.outAt == 0;
    final done = t != null && t.outAt > 0;
    final online = _inst?.canCheckInOnline(widget.m.uid) ?? false;
    final head = Row(children: [
      IconBox(done ? Icons.task_alt_rounded : Icons.how_to_reg_rounded, fg: done ? p.success : p.brand, bg: done ? p.successTint : p.brandTint),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            t == null ? tr('not_checked_in') : (done ? '${clock(t.inAt)} – ${clock(t.outAt)}' : trf('in_since', {'t': clock(t.inAt)})),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
          ),
          Text(
            [trf('checkins_this_month', {'n': '$_days'}), if (t != null && t.mode == 'online') tr('online_from_home')].join(' · '),
            style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ]),
      ),
      if (done) Tag(tr('done'), fg: p.success, bg: p.successTint),
      if (inNow && !_geo) ...[const SizedBox(width: 8), SizedBox(width: 120, child: _btn(p, tr('check_out'), Icons.logout_rounded, p.danger, _checkOut))],
      if (t == null && !_geo) ...[const SizedBox(width: 8), SizedBox(width: 120, child: _btn(p, tr('check_in'), Icons.login_rounded, p.success, _ready ? () => _checkIn(online ? 'online' : '') : null))],
    ]);
    if (!_geo || done || (inNow && !_geo)) return AppCard(padding: const EdgeInsets.all(14), child: head);

    // location rule is on
    final i = _inst!;
    final d = _dist;
    Widget status;
    if (inNow) {
      status = const SizedBox.shrink();
    } else if (_locating) {
      status = Row(children: [
        const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 10),
        Text(tr('finding_you'), style: TextStyle(color: p.muted, fontWeight: FontWeight.w700)),
      ]);
    } else if (_loc != null && !_loc!.ok) {
      status = Row(children: [
        Icon(Icons.location_disabled_rounded, color: p.warn),
        const SizedBox(width: 10),
        Expanded(child: Text(locErrorText(_loc!.error!), style: TextStyle(color: p.warn, fontWeight: FontWeight.w700, fontSize: 13))),
      ]);
    } else if (d != null) {
      status = Row(children: [
        IconBox(_inside ? Icons.check_rounded : Icons.warning_amber_rounded, fg: _inside ? p.success : p.danger, bg: _inside ? p.successTint : p.dangerTint, size: 34),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_inside ? tr('at_coaching') : trf('away_from_coaching', {'d': distanceText(d)}), style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(_inside ? trf('meters_from', {'d': distanceText(d), 'inst': i.name}) : trf('come_within', {'r': '${i.geoRadius} m'}),
                style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        ),
      ]);
    } else {
      status = const SizedBox.shrink();
    }
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        head,
        if (t == null) ...[
          const SizedBox(height: 12),
          MapPreview(lat: i.geoLat, lng: i.geoLng, radius: i.geoRadius, youLat: _loc?.ok == true ? _loc!.lat : null, youLng: _loc?.ok == true ? _loc!.lng : null, height: 150),
          const SizedBox(height: 12),
          status,
          const SizedBox(height: 12),
          if (online)
            Row(children: [
              Expanded(child: _btn(p, tr('from_coaching'), Icons.location_on_rounded, p.success, _inside ? () => _checkIn('coaching') : null)),
              const SizedBox(width: 8),
              Expanded(child: _btn(p, tr('from_home'), Icons.home_rounded, p.indigo, () => _checkIn('online'), soft: true)),
            ])
          else
            _btn(p, _inside || _loc == null ? tr('check_in') : tr('checkin_locked'), _inside ? Icons.location_on_rounded : Icons.lock_outline_rounded, p.success, _inside ? () => _checkIn('coaching') : null),
          if (!_inside && !_locating)
            TextButton.icon(
              onPressed: () async {
                if (_loc != null && !_loc!.ok) {
                  final e = _loc!.error!;
                  if (e == LocError.serviceOff || e == LocError.deniedForever) {
                    await showLocError(context, e);
                    return;
                  }
                }
                _locate();
              },
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(tr('check_location_again')),
            ),
        ],
        if (inNow) ...[
          const SizedBox(height: 12),
          _btn(p, tr('check_out'), Icons.logout_rounded, p.danger, _checkOut),
        ],
      ]),
    );
  }
}

/// Admin: who came today and how many days each teacher came this month.
class CheckInsScreen extends StatefulWidget {
  const CheckInsScreen({super.key, required this.m});
  final Membership m;
  @override
  State<CheckInsScreen> createState() => _CheckInsScreenState();
}

class _CheckInsScreenState extends State<CheckInsScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  int _v = 0;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AppScaffold(
      title: tr('teacher_checkins'),
      subtitle: widget.m.instituteName,
      actions: [
        if (widget.m.role == Role.admin)
          IconBtn(
            icon: Icons.tune_rounded,
            tooltip: tr('checkin_rules'),
            onTap: () async {
              final ok = await push<bool>(context, CheckInRulesScreen(m: widget.m));
              if (ok == true) setState(() => _v++);
            },
          ),
      ],
      body: Column(children: [
        MonthBar(
          month: _month,
          onShift: (d) => setState(() {
            _month = DateTime(_month.year, _month.month + d);
            _v++;
          }),
        ),
        Expanded(
          child: Loader<(List<CheckIn>, List<Membership>)>(
            key: ValueKey(_v),
            load: () async {
              final b = context.appRead.backend;
              return (await b.checkIns(widget.m.instituteId, monthKey(_month)), await b.members(widget.m.instituteId));
            },
            builder: (context, d, reload) {
              final teachers = d.$2.where((x) => x.role == Role.teacher && x.approved).toList();
              final todayKey = dateKey(DateTime.now());
              final today = d.$1.where((c) => c.dateKey == todayKey).toList();
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
                children: [
                  if (monthKey(_month) == monthKey(DateTime.now())) ...[
                    SectionTitle(tr('today')),
                    const SizedBox(height: 6),
                    for (final t in teachers)
                      Builder(builder: (context) {
                        final c = today.where((x) => x.uid == t.uid).firstOrNull;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: AppCard(
                            padding: const EdgeInsets.all(12),
                            child: Row(children: [
                              Avatar(t.name, size: 40, photo: t.photo),
                              const SizedBox(width: 10),
                              Expanded(child: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w800))),
                              c == null
                                  ? Tag(tr('not_yet'), fg: p.muted, bg: p.cardAlt)
                                  : Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                      Tag(c.outAt > 0 ? '${clock(c.inAt)} – ${clock(c.outAt)}' : '${tr('in_word')} ${clock(c.inAt)}', fg: p.success, bg: p.successTint),
                                      if (c.mode.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Tag(c.mode == 'online' ? tr('online_home_tag') : (c.dist >= 0 ? '${tr('coaching_tag')} · ${c.dist} m' : tr('coaching_tag')),
                                            fg: c.mode == 'online' ? p.indigo : p.brand, bg: c.mode == 'online' ? p.indigoTint : p.brandTint),
                                      ],
                                    ]),
                            ]),
                          ),
                        );
                      }),
                    const SizedBox(height: 12),
                  ],
                  SectionTitle(tr('this_month')),
                  const SizedBox(height: 6),
                  if (teachers.isEmpty) EmptyState(icon: Icons.badge_outlined, text: tr('no_teachers')),
                  for (final t in teachers)
                    Builder(builder: (context) {
                      final mine = d.$1.where((x) => x.uid == t.uid).toList();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: AppCard(
                          padding: const EdgeInsets.all(12),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Avatar(t.name, size: 40, photo: t.photo),
                              const SizedBox(width: 10),
                              Expanded(child: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w800))),
                              Text(trf('n_days', {'n': '${mine.length}'}), style: TextStyle(fontWeight: FontWeight.w800, color: p.brand)),
                            ]),
                            if (mine.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Wrap(spacing: 6, runSpacing: 6, children: [
                                for (final c in mine.reversed)
                                  Tooltip(
                                    message: '${clock(c.inAt)}${c.outAt > 0 ? ' – ${clock(c.outAt)}' : ''}',
                                    child: Container(
                                      width: 30,
                                      height: 30,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(color: c.mode == 'online' ? p.indigoTint : p.successTint, borderRadius: BorderRadius.circular(9)),
                                      child: Text(c.dateKey.substring(6), style: TextStyle(color: c.mode == 'online' ? p.indigo : p.success, fontWeight: FontWeight.w800, fontSize: 12)),
                                    ),
                                  ),
                              ]),
                            ],
                          ]),
                        ),
                      );
                    }),
                ],
              );
            },
          ),
        ),
      ]),
    );
  }
}
