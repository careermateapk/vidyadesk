import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../services/location.dart';
import '../services/olamaps.dart';
import '../ui/widgets.dart';
import 'common.dart';

/// Map picture of the coaching with its allowed circle, and (optionally) where the phone is.
class MapPreview extends StatelessWidget {
  const MapPreview({super.key, required this.lat, required this.lng, required this.radius, this.youLat, this.youLng, this.height = 190});
  final double lat, lng;
  final int radius;
  final double? youLat, youLng;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: height,
        child: LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth;
          final h = height;
          // pick a zoom where the circle (and the phone, if far) fit nicely
          var need = radius.toDouble();
          double? dx, dy;
          if (youLat != null && youLng != null) {
            dx = (youLng! - lng) * math.cos(lat * math.pi / 180) * 111320;
            dy = (youLat! - lat) * 110540;
            need = math.max(need, math.sqrt(dx * dx + dy * dy) * 1.15);
          }
          final mpp0 = need / (h * .36);
          final zoom = (math.log(78271.517 * math.cos(lat * math.pi / 180) / mpp0) / math.ln2).floor().clamp(3, 18);
          final mpp = metersPerPixel(lat, zoom);
          final rPx = radius / mpp;
          Offset? you;
          if (dx != null && dy != null) {
            you = Offset((w / 2 + dx / mpp).clamp(10.0, w - 10).toDouble(), (h / 2 - dy / mpp).clamp(10.0, h - 10).toDouble());
          }
          final grid = Container(
            color: p.dark ? const Color(0xFF1E2230) : const Color(0xFFEEF2EA),
            child: CustomPaint(size: Size(w, h), painter: _GridPainter(p.dark)),
          );
          return Stack(children: [
            Positioned.fill(
              child: mapsReady
                  ? Image.network(
                      staticMapUrl(lat, lng, width: (w * 2).round().clamp(100, 1280), height: (h * 2).round().clamp(100, 1280), zoom: zoom + 1),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => grid,
                      loadingBuilder: (_, child, prog) => prog == null ? child : grid,
                    )
                  : grid,
            ),
            Positioned.fill(child: CustomPaint(painter: _ZonePainter(rPx, p.brand, you))),
            Positioned(
              left: w / 2 - 20,
              top: h / 2 - 40,
              child: Icon(Icons.location_on_rounded, size: 40, color: p.brand, shadows: const [Shadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))]),
            ),
          ]);
        }),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.dark);
  final bool dark;
  @override
  void paint(Canvas canvas, Size s) {
    final road = Paint()
      ..color = dark ? const Color(0xFF2C3243) : Colors.white
      ..strokeWidth = 12;
    canvas.drawLine(Offset(0, s.height * .56), Offset(s.width, s.height * .56), road);
    canvas.drawLine(Offset(s.width * .38, 0), Offset(s.width * .38, s.height), road..strokeWidth = 10);
    canvas.drawLine(Offset(0, s.height * .15), Offset(s.width, s.height * .95), road..strokeWidth = 7);
    final park = Paint()..color = dark ? const Color(0xFF203126) : const Color(0xFFD5EBCB);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(s.width * .66, 14, s.width * .26, s.height * .3), const Radius.circular(8)), park);
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.dark != dark;
}

class _ZonePainter extends CustomPainter {
  _ZonePainter(this.r, this.c, this.you);
  final double r;
  final Color c;
  final Offset? you;
  @override
  void paint(Canvas canvas, Size s) {
    final ctr = Offset(s.width / 2, s.height / 2);
    canvas.drawCircle(ctr, r, Paint()..color = c.withValues(alpha: .16));
    canvas.drawCircle(
        ctr,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = c);
    final y = you;
    if (y != null) {
      canvas.drawCircle(y, 18, Paint()..color = const Color(0x333B9EF5));
      canvas.drawCircle(y, 9, Paint()..color = Colors.white);
      canvas.drawCircle(y, 6.5, Paint()..color = const Color(0xFF3B9EF5));
    }
  }

  @override
  bool shouldRepaint(_ZonePainter old) => old.r != r || old.you != you;
}

String locErrorText(LocError e) => switch (e) {
      LocError.serviceOff => tr('loc_off'),
      LocError.denied => tr('loc_denied'),
      LocError.deniedForever => tr('loc_denied_forever'),
      LocError.mocked => tr('loc_mocked'),
      LocError.timeout => tr('loc_timeout'),
    };

/// Shows why location failed, with a button to fix it.
Future<void> showLocError(BuildContext context, LocError e) async {
  final fix = e == LocError.serviceOff
      ? openLocationSettings
      : (e == LocError.deniedForever ? openAppSettings : null);
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr('location')),
      content: Text(locErrorText(e)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('ok'))),
        if (fix != null)
          TextButton(
            onPressed: () {
              Navigator.pop(c);
              fix();
            },
            child: Text(tr('open_settings')),
          ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Admin: check-in rules
// ---------------------------------------------------------------------------

class CheckInRulesScreen extends StatefulWidget {
  const CheckInRulesScreen({super.key, required this.m});
  final Membership m;
  @override
  State<CheckInRulesScreen> createState() => _CheckInRulesScreenState();
}

class _CheckInRulesScreenState extends State<CheckInRulesScreen> {
  Institute? _inst;
  List<Membership> _teachers = [];
  bool _geo = false, _online = false, _busy = false, _locating = false;
  double _lat = 0, _lng = 0;
  int _radius = 100;
  String _addr = '';
  Set<String> _onlineUids = {};
  bool _allOnline = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final b = context.appRead.backend;
    final i = await b.institute(widget.m.instituteId);
    final members = await b.members(widget.m.instituteId);
    if (!mounted || i == null) return;
    setState(() {
      _inst = i;
      _teachers = members.where((x) => x.role == Role.teacher && x.approved).toList();
      _geo = i.geoCheckin;
      _online = i.onlineCheckin;
      _lat = i.geoLat;
      _lng = i.geoLng;
      _radius = i.geoRadius;
      _addr = i.geoAddress;
      _onlineUids = i.onlineUids.toSet();
      _allOnline = i.onlineUids.isEmpty;
    });
  }

  Future<void> _here() async {
    setState(() => _locating = true);
    final r = await currentLocation();
    if (!mounted) return;
    setState(() => _locating = false);
    if (!r.ok) {
      await showLocError(context, r.error!);
      return;
    }
    setState(() {
      _lat = r.lat;
      _lng = r.lng;
    });
    final a = mapsReady ? await addressOf(r.lat, r.lng) : '';
    if (mounted) setState(() => _addr = a);
  }

  Future<void> _search() async {
    final hit = await showModalBottomSheet<(double, double, String)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PlaceSearch(nearLat: _lat == 0 ? null : _lat, nearLng: _lng == 0 ? null : _lng),
    );
    if (hit != null && mounted) {
      setState(() {
        _lat = hit.$1;
        _lng = hit.$2;
        _addr = hit.$3;
      });
    }
  }

  Future<void> _save() async {
    if (_geo && _lat == 0 && _lng == 0) {
      toast(context, tr('err_no_place'));
      return;
    }
    setState(() => _busy = true);
    try {
      await context.appRead.backend.updateInstitute(_inst!.copyWith(
        geoCheckin: _geo,
        geoLat: _lat,
        geoLng: _lng,
        geoRadius: _radius,
        geoAddress: _addr,
        onlineCheckin: _online,
        onlineUids: _allOnline ? const [] : _onlineUids.toList(),
      ));
      if (!mounted) return;
      toast(context, tr('saved'));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) toast(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _switchCard(Palette p, IconData icon, Color c, String title, String sub, bool v, ValueChanged<bool> on) => AppCard(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          IconBox(icon, fg: c, bg: c.withValues(alpha: .13)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              Text(sub, style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ]),
          ),
          Switch(value: v, onChanged: on),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AppScaffold(
      title: tr('checkin_rules'),
      subtitle: widget.m.instituteName,
      bottom: PrimaryButton(label: tr('save'), arrow: false, busy: _busy, onPressed: _inst == null ? null : _save),
      body: _inst == null
          ? const LoadingView()
          : ListView(padding: const EdgeInsets.fromLTRB(18, 4, 18, 20), children: [
              _switchCard(p, Icons.location_on_outlined, p.brand, tr('geo_checkin'), tr('geo_checkin_sub'), _geo, (v) => setState(() => _geo = v)),
              if (_geo) ...[
                FieldLabel(tr('coaching_location')),
                if (_lat == 0 && _lng == 0)
                  AppCard(
                    color: p.cardAlt,
                    child: Row(children: [
                      Icon(Icons.wrong_location_outlined, color: p.warn),
                      const SizedBox(width: 10),
                      Expanded(child: Text(tr('no_place_yet'), style: TextStyle(color: p.ink2, fontWeight: FontWeight.w700))),
                    ]),
                  )
                else ...[
                  MapPreview(lat: _lat, lng: _lng, radius: _radius, height: 210),
                  if (_addr.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_addr, style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600))),
                ],
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: SoftButton(
                      label: _locating ? tr('finding') : tr('im_here'),
                      icon: Icons.my_location_rounded,
                      onPressed: _locating ? null : _here,
                    ),
                  ),
                  if (mapsReady) ...[
                    const SizedBox(width: 8),
                    Expanded(child: SoftButton(label: tr('search_map'), icon: Icons.search_rounded, color: p.card, textColor: p.ink, onPressed: _search)),
                  ],
                ]),
                Padding(padding: const EdgeInsets.only(top: 6), child: Text(tr('im_here_tip'), style: TextStyle(color: p.muted, fontSize: 12))),
                FieldLabel(tr('allowed_distance')),
                Row(children: [
                  for (final r in [50, 100, 200, 500]) ...[
                    if (r != 50) const SizedBox(width: 8),
                    Expanded(child: ChoicePill(label: '$r m', selected: _radius == r, onTap: () => setState(() => _radius = r))),
                  ],
                ]),
              ],
              const SizedBox(height: 16),
              _switchCard(p, Icons.home_work_outlined, p.indigo, tr('online_checkin'), tr('online_checkin_sub'), _online, (v) => setState(() => _online = v)),
              if (_online) ...[
                FieldLabel(tr('who_online')),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  ChoicePill(label: tr('all_teachers'), selected: _allOnline, onTap: () => setState(() => _allOnline = true)),
                  for (final t in _teachers)
                    ChoicePill(
                      label: t.name,
                      selected: !_allOnline && _onlineUids.contains(t.uid),
                      onTap: () => setState(() {
                        _allOnline = false;
                        _onlineUids.contains(t.uid) ? _onlineUids.remove(t.uid) : _onlineUids.add(t.uid);
                      }),
                    ),
                ]),
              ],
            ]),
    );
  }
}

class _PlaceSearch extends StatefulWidget {
  const _PlaceSearch({this.nearLat, this.nearLng});
  final double? nearLat, nearLng;
  @override
  State<_PlaceSearch> createState() => _PlaceSearchState();
}

class _PlaceSearchState extends State<_PlaceSearch> {
  final _q = TextEditingController();
  Timer? _deb;
  List<PlaceHit> _hits = [];
  bool _loading = false;
  String? _err;

  @override
  void dispose() {
    _deb?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _changed(String v) {
    _deb?.cancel();
    _deb = Timer(const Duration(milliseconds: 450), () async {
      if (v.trim().length < 3) return;
      setState(() {
        _loading = true;
        _err = null;
      });
      try {
        final h = await searchPlaces(v.trim(), nearLat: widget.nearLat, nearLng: widget.nearLng);
        if (mounted) setState(() => _hits = h);
      } catch (_) {
        if (mounted) setState(() => _err = tr('err_search'));
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * .7,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
            child: TextField(
              controller: _q,
              autofocus: true,
              onChanged: _changed,
              decoration: InputDecoration(hintText: tr('search_place_hint'), prefixIcon: const Icon(Icons.search_rounded), suffixIcon: _loading ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))) : null),
            ),
          ),
          if (_err != null) Padding(padding: const EdgeInsets.all(12), child: Text(_err!, style: TextStyle(color: p.danger))),
          Expanded(
            child: ListView(children: [
              for (final h in _hits)
                ListTile(
                  leading: IconBox(Icons.place_outlined, fg: p.brand, bg: p.brandTint),
                  title: Text(h.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: h.subtitle.isEmpty ? null : Text(h.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: () async {
                    try {
                      final loc = await placeLocation(h);
                      if (!context.mounted) return;
                      if (loc == null) {
                        toast(context, tr('err_search'));
                        return;
                      }
                      Navigator.pop(context, (loc.$1, loc.$2, [h.title, h.subtitle].where((x) => x.isNotEmpty).join(', ')));
                    } catch (_) {
                      if (context.mounted) toast(context, tr('err_search'));
                    }
                  },
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
