import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/backend.dart';
import '../data/demo_backend.dart';
import '../data/models.dart';
import '../data/places.dart';
import '../ui/widgets.dart';
import '../ui/mascot.dart';
import 'common.dart';
import 'onboarding.dart';

String errorText(Object e) {
  if (e is BackendError) {
    const known = {'no-account-or-wrong', 'wrong-password', 'email-in-use', 'weak-password', 'invalid-email', 'network', 'too-many', 'cancelled', 'google-off'};
    if (known.contains(e.code)) return tr('err_${e.code}');
  }
  return tr('err_unknown');
}

// ---------------------------------------------------------------------------
// Login / Signup
// ---------------------------------------------------------------------------

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  int _tab = 0; // 0 login, 1 signup
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _hide = true;
  bool _busy = false;
  bool _gBusy = false;
  String? _error;
  int _shake = 0;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _fail(String msg) {
    setState(() {
      _error = msg;
      _shake++;
    });
    HapticFeedback.mediumImpact();
  }

  Future<void> _google({required bool login}) async {
    final app = context.appRead;
    setState(() {
      _gBusy = true;
      _error = null;
    });
    try {
      final s = await app.backend.signInGoogle();
      final prof = await app.backend.profile(s.uid);
      if (login && prof == null) {
        await app.backend.signOut();
        _fail(tr('err_no_account_google'));
        return;
      }
      if (!login && prof != null && mounted) toast(context, tr('already_account'));
      await app.loadAccount();
    } catch (e) {
      if (e is BackendError && e.code == 'cancelled') return;
      _fail(errorText(e));
    } finally {
      if (mounted) setState(() => _gBusy = false);
    }
  }

  Future<void> _emailLogin() async {
    final app = context.appRead;
    final email = _email.text.trim();
    if (!email.contains('@') || _pass.text.isEmpty) {
      _fail(tr('err_fill_email_pass'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await app.backend.signInEmail(email, _pass.text);
      await app.loadAccount();
    } catch (e) {
      _fail(errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    final app = context.appRead;
    final email = _email.text.trim();
    if (!email.contains('@')) {
      _fail(tr('err_enter_email_first'));
      return;
    }
    try {
      await app.backend.resetPassword(email);
      if (mounted) toast(context, tr('reset_sent'));
    } catch (e) {
      _fail(errorText(e));
    }
  }

  Future<void> _sample(Role r) async {
    final app = context.appRead;
    final b = app.backend;
    if (b is! DemoBackend) return;
    setState(() => _busy = true);
    await b.signInSample(r);
    await app.chooseRole(r);
    await app.loadAccount();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final app = context.app;
    final role = app.chosenRole ?? Role.student;
    final rc = roleColors(p, role);
    return Scaffold(
      backgroundColor: p.bg,
      body: PageBg(
        height: 420,
        child: ListView(
          padding: EdgeInsets.fromLTRB(18, MediaQuery.of(context).padding.top + 8, 18, 30),
          children: [
            Row(children: [
              IconBtn(icon: Icons.chevron_left_rounded, size: 26, tooltip: tr('back'), onTap: () => app.chooseRole(null)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(999), boxShadow: p.shadow),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(roleIcon(role), size: 15, color: rc.$1),
                  const SizedBox(width: 6),
                  Text(roleName(role), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: rc.$1)),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(_tab == 0 ? tr('welcome_back') : tr('create_account'),
                        key: ValueKey(_tab), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1)),
                  ),
                  const SizedBox(height: 4),
                  Text(_tab == 0 ? tr('login_sub') : tr('signup_sub'), style: TextStyle(color: p.muted, fontSize: 14.5, height: 1.35, fontWeight: FontWeight.w500)),
                ]),
              ),
              const Floaty(child: Mascot(size: 92, book: false, wave: true)),
            ]),
            const SizedBox(height: 16),
            const DemoBanner(),
            Segmented(items: [tr('login'), tr('signup')], index: _tab, onChanged: (i) => setState(() {
                  _tab = i;
                  _error = null;
                })),
            const SizedBox(height: 18),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 380),
              transitionBuilder: (c, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween(begin: const Offset(.06, 0), end: Offset.zero).animate(a), child: c)),
              child: _tab == 0 ? _loginBody(p) : _signupBody(p),
            ),
            _ErrorBox(text: _error, shake: _shake),
            if (app.isDemo) ...[
              const SizedBox(height: 18),
              _SampleAccounts(onPick: _busy ? null : _sample),
            ],
          ],
        ),
      ),
    );
  }

  Widget _orLine(Palette p, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(children: [
          Expanded(child: Divider(color: p.border)),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text(text, style: TextStyle(color: p.muted, fontSize: 13, fontWeight: FontWeight.w600))),
          Expanded(child: Divider(color: p.border)),
        ]),
      );

  Widget _loginBody(Palette p) {
    return Column(key: const ValueKey('login'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      GoogleButton(label: tr('google_login'), busy: _gBusy, onPressed: () => _google(login: true)),
      _orLine(p, tr('or_email')),
      FieldLabel(tr('email')),
      TextField(
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        decoration: InputDecoration(hintText: 'name@gmail.com', prefixIcon: Icon(Icons.mail_outline_rounded, color: p.muted)),
      ),
      const SizedBox(height: 12),
      FieldLabel(tr('password')),
      TextField(
        controller: _pass,
        obscureText: _hide,
        onSubmitted: (_) => _emailLogin(),
        decoration: InputDecoration(
          hintText: '••••••••',
          prefixIcon: Icon(Icons.lock_outline_rounded, color: p.muted),
          suffixIcon: IconButton(onPressed: () => setState(() => _hide = !_hide), icon: Icon(_hide ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: p.muted)),
        ),
      ),
      Align(alignment: Alignment.centerRight, child: TextButton(onPressed: _forgot, child: Text(tr('forgot_password')))),
      const SizedBox(height: 4),
      PrimaryButton(label: tr('login'), busy: _busy, onPressed: _emailLogin),
      const SizedBox(height: 12),
      Center(
        child: TextButton(onPressed: () => setState(() => _tab = 1), child: Text(tr('no_account_signup'))),
      ),
    ]);
  }

  Widget _signupBody(Palette p) {
    return Column(key: const ValueKey('signup'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      GoogleButton(label: tr('google_signup'), busy: _gBusy, onPressed: () => _google(login: false)),
      const SizedBox(height: 8),
      Text(tr('google_signup_note'), textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontSize: 12.5)),
      _orLine(p, tr('or')),
      PrimaryButton(
        label: tr('email_signup'),
        icon: Icons.mail_rounded,
        onPressed: () => push(context, const ProfileFormScreen(withEmail: true)),
      ),
      const SizedBox(height: 12),
      Center(child: TextButton(onPressed: () => setState(() => _tab = 0), child: Text(tr('have_account_login')))),
    ]);
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.text, required this.shake});
  final String? text;
  final int shake;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      child: text == null
          ? const SizedBox(width: double.infinity)
          : TweenAnimationBuilder<double>(
              key: ValueKey(shake),
              tween: Tween(begin: 1, end: 0),
              duration: const Duration(milliseconds: 500),
              builder: (context, v, child) => Transform.translate(offset: Offset(8 * v * ((v * 10).floor().isEven ? 1 : -1), 0), child: child),
              child: Container(
                margin: const EdgeInsets.only(top: 14),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: p.dangerTint, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.danger.withValues(alpha: .35))),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.error_rounded, color: p.danger, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(text!, style: TextStyle(color: p.danger, fontWeight: FontWeight.w700, fontSize: 13.5, height: 1.35))),
                ]),
              ),
            ),
    );
  }
}

class _SampleAccounts extends StatelessWidget {
  const _SampleAccounts({required this.onPick});
  final void Function(Role r)? onPick;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AppCard(
      color: p.cardAlt,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconBox(Icons.play_arrow_rounded, fg: p.warn, bg: p.warnTint, size: 38),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('try_sample'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
              Text(tr('try_sample_sub'), style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final r in Role.values)
            Builder(builder: (context) {
              final c = roleColors(p, r);
              return SoftButton(label: roleName(r), icon: roleIcon(r), height: 40, color: c.$2, textColor: c.$1, onPressed: onPick == null ? null : () => onPick!(r));
            }),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Profile form (signup details)
// ---------------------------------------------------------------------------

const countryCodes = [
  ('+91', 'India', '🇮🇳'),
  ('+977', 'Nepal', '🇳🇵'),
  ('+880', 'Bangladesh', '🇧🇩'),
  ('+971', 'UAE', '🇦🇪'),
  ('+966', 'Saudi Arabia', '🇸🇦'),
  ('+974', 'Qatar', '🇶🇦'),
  ('+965', 'Kuwait', '🇰🇼'),
  ('+968', 'Oman', '🇴🇲'),
  ('+1', 'USA / Canada', '🇺🇸'),
  ('+44', 'UK', '🇬🇧'),
  ('+61', 'Australia', '🇦🇺'),
  ('+65', 'Singapore', '🇸🇬'),
];

class ProfileFormScreen extends StatefulWidget {
  const ProfileFormScreen({super.key, required this.withEmail, this.existing});
  final bool withEmail;
  final AppUser? existing;
  @override
  State<ProfileFormScreen> createState() => _ProfileFormScreenState();
}

class _ProfileFormScreenState extends State<ProfileFormScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _block = TextEditingController();
  final _street = TextEditingController();
  final _pin = TextEditingController();
  final _otherCity = TextEditingController();
  final _otherState = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  String _cc = '+91';
  String? _state;
  String? _city;
  bool _hide = true;
  bool _busy = false;
  bool _pinBusy = false;
  String? _pinMsg;
  String? _error;
  int _shake = 0;
  final Map<String, String> _fieldErr = {};

  static const _other = '__other__';

  @override
  void initState() {
    super.initState();
    final app = context.appRead;
    final e = widget.existing;
    if (e != null) {
      _name.text = e.name;
      _cc = e.countryCode;
      _phone.text = e.phone;
      _block.text = e.address.block;
      _street.text = e.address.street;
      _pin.text = e.address.pincode;
      if (indiaPlaces.containsKey(e.address.state)) {
        _state = e.address.state;
        if (indiaPlaces[_state]!.contains(e.address.city)) {
          _city = e.address.city;
        } else if (e.address.city.isNotEmpty) {
          _city = _other;
          _otherCity.text = e.address.city;
        }
      } else if (e.address.state.isNotEmpty) {
        _state = _other;
        _otherState.text = e.address.state;
        _otherCity.text = e.address.city;
      }
    } else {
      _name.text = app.signedIn?.name ?? '';
    }
    _pin.addListener(_onPin);
  }

  String _lastPin = '';
  void _onPin() {
    final pin = _pin.text.trim();
    if (pin == _lastPin) return;
    _lastPin = pin;
    if (pin.length != 6) {
      if (_pinMsg != null) setState(() => _pinMsg = null);
      return;
    }
    setState(() => _pinBusy = true);
    lookupPincode(pin).then((r) {
      if (!mounted || _pin.text.trim() != pin) return;
      setState(() {
        _pinBusy = false;
        if (r == null) {
          _pinMsg = tr('pin_not_found');
          return;
        }
        _state = r.state;
        final cities = indiaPlaces[r.state] ?? const [];
        final match = cities.where((c) => c.toLowerCase() == r.city.toLowerCase()).firstOrNull;
        if (match != null) {
          _city = match;
        } else {
          _city = _other;
          _otherCity.text = r.city;
        }
        _pinMsg = '✓ ${r.city}, ${r.state}';
      });
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _block, _street, _pin, _otherCity, _otherState, _email, _pass, _pass2]) {
      c.dispose();
    }
    super.dispose();
  }

  bool _validate() {
    _fieldErr.clear();
    if (_name.text.trim().length < 2) _fieldErr['name'] = tr('err_name');
    final ph = _phone.text.trim();
    if (_cc == '+91' ? !RegExp(r'^[6-9][0-9]{9}$').hasMatch(ph) : !RegExp(r'^[0-9]{6,13}$').hasMatch(ph)) _fieldErr['phone'] = tr('err_phone');
    if (_street.text.trim().isEmpty) _fieldErr['street'] = tr('err_required');
    if (_state == null || (_state == _other && _otherState.text.trim().isEmpty)) _fieldErr['state'] = tr('err_pick_state');
    if (_state != _other && (_city == null || (_city == _other && _otherCity.text.trim().isEmpty))) _fieldErr['city'] = tr('err_pick_city');
    if (_state == _other && _otherCity.text.trim().isEmpty) _fieldErr['city'] = tr('err_pick_city');
    if (widget.withEmail) {
      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email.text.trim())) _fieldErr['email'] = tr('err_invalid-email');
      if (_pass.text.length < 6) _fieldErr['pass'] = tr('err_weak-password');
      if (_pass2.text != _pass.text) _fieldErr['pass2'] = tr('err_pass_match');
    }
    setState(() {});
    return _fieldErr.isEmpty;
  }

  Future<void> _save() async {
    if (!_validate()) {
      setState(() {
        _error = tr('err_fix_fields');
        _shake++;
      });
      HapticFeedback.mediumImpact();
      return;
    }
    final app = context.appRead;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final state = _state == _other ? _otherState.text.trim() : _state!;
      final city = (_state == _other || _city == _other) ? _otherCity.text.trim() : _city!;
      final address = Address(block: _block.text.trim(), street: _street.text.trim(), pincode: _pin.text.trim(), state: state, city: city);
      if (widget.withEmail) {
        final s = await app.backend.signUpEmail(_email.text.trim(), _pass.text);
        final u = AppUser(uid: s.uid, name: _name.text.trim(), email: s.email, countryCode: _cc, phone: _phone.text.trim(), address: address);
        await app.backend.saveProfile(u);
        await app.loadAccount();
        if (mounted) backToRoot(context);
      } else {
        final s = app.signedIn!;
        final old = widget.existing;
        final u = AppUser(uid: s.uid, name: _name.text.trim(), email: old?.email ?? s.email, countryCode: _cc, phone: _phone.text.trim(), address: address, viaGoogle: old?.viaGoogle ?? s.viaGoogle);
        await app.saveProfile(u);
        if (mounted && widget.existing != null) {
          toast(context, tr('saved'));
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      setState(() {
        _error = errorText(e);
        _shake++;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick({required String title, required List<String> items, required ValueChanged<String> onPick}) async {
    final v = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SearchSheet(title: title, items: items, otherLabel: tr('other_type')),
    );
    if (v != null) onPick(v);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final app = context.app;
    final editing = widget.existing != null;
    final cities = _state != null && _state != _other ? indiaPlaces[_state]! : const <String>[];
    var i = 0;
    Widget item(Widget w) => FadeIn(delay: stagger(i++, stepMs: 45), child: Padding(padding: const EdgeInsets.only(bottom: 14), child: w));

    return Scaffold(
      appBar: InnerBar(
        title: editing ? tr('edit_profile') : tr('your_details'),
        showBack: true,
      ),
      body: PopScope(
        canPop: widget.withEmail || editing,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) app.signOut();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
          children: [
            if (!editing)
              item(Row(children: [
                Expanded(child: _StepDot(n: 1, label: tr('step_details'), on: true)),
                Expanded(child: _StepDot(n: 2, label: tr('step_join'), on: false)),
                Expanded(child: _StepDot(n: 3, label: tr('step_approval'), on: false)),
              ])),
            if (!widget.withEmail && !editing && app.signedIn != null)
              item(AppCard(
                color: p.cardAlt,
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  const GoogleG(size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(app.signedIn!.email, style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text(tr('google_email_used'), style: TextStyle(color: p.muted, fontSize: 12)),
                    ]),
                  ),
                  Icon(Icons.verified_rounded, color: p.success),
                ]),
              )),
            item(_field(tr('full_name'), _name, 'name', icon: Icons.person_rounded, hint: 'Rakesh Sharma', caps: TextCapitalization.words)),
            item(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FieldLabel(tr('mobile')),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _pick(
                    title: tr('country_code'),
                    items: [for (final c in countryCodes) '${c.$3} ${c.$1}  ${c.$2}'],
                    onPick: (v) {
                      final m = countryCodes.where((c) => v.contains(' ${c.$1} ')).firstOrNull;
                      if (m != null) setState(() => _cc = m.$1);
                    },
                  ),
                  child: Container(
                    height: 56,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: p.border)),
                    child: Row(children: [
                      Text(countryCodes.firstWhere((c) => c.$1 == _cc, orElse: () => countryCodes.first).$3, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 6),
                      Text(_cc, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      Icon(Icons.arrow_drop_down_rounded, color: p.muted),
                    ]),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(13)],
                    decoration: InputDecoration(hintText: '98765 43210', errorText: _fieldErr['phone']),
                  ),
                ),
              ]),
            ])),
            item(SectionTitle(tr('address'))),
            item(_field(tr('house_block'), _block, 'block', icon: Icons.home_rounded, hint: tr('house_block_hint'))),
            item(_field(tr('street_area'), _street, 'street', icon: Icons.signpost_rounded, hint: tr('street_hint'))),
            item(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FieldLabel(tr('pincode')),
              TextField(
                controller: _pin,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                decoration: InputDecoration(
                  hintText: '846004',
                  prefixIcon: Icon(Icons.pin_drop_rounded, color: p.muted),
                  suffixIcon: _pinBusy ? Padding(padding: const EdgeInsets.all(14), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: p.brand))) : null,
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                child: _pinMsg == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: 6, left: 4),
                        child: Text(_pinMsg!, style: TextStyle(color: _pinMsg!.startsWith('✓') ? p.success : p.muted, fontWeight: FontWeight.w700, fontSize: 12.5)),
                      ),
              ),
              Padding(padding: const EdgeInsets.only(top: 4, left: 4), child: Text(tr('pincode_note'), style: TextStyle(color: p.muted, fontSize: 12))),
            ])),
            item(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: _PickerField(
                  label: tr('state'),
                  value: _state == _other ? tr('other') : _state,
                  hint: tr('choose'),
                  error: _fieldErr['state'],
                  onTap: () => _pick(
                    title: tr('state'),
                    items: [...stateNames, _other],
                    onPick: (v) => setState(() {
                      if (v != _state) _city = null;
                      _state = v;
                    }),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PickerField(
                  label: tr('city_district'),
                  value: _city == _other ? tr('other') : _city,
                  hint: _state == null ? tr('state_first') : tr('choose'),
                  error: _fieldErr['city'],
                  onTap: _state == null || _state == _other
                      ? null
                      : () => _pick(title: tr('city_district'), items: [...cities, _other], onPick: (v) => setState(() => _city = v)),
                ),
              ),
            ])),
            if (_state == _other) item(_field(tr('state_name'), _otherState, 'ostate', caps: TextCapitalization.words)),
            if (_state == _other || _city == _other) item(_field(tr('city_name'), _otherCity, 'ocity', caps: TextCapitalization.words)),
            if (widget.withEmail) ...[
              item(SectionTitle(tr('login_details'))),
              item(_field(tr('email'), _email, 'email', icon: Icons.mail_outline_rounded, hint: 'name@gmail.com', type: TextInputType.emailAddress)),
              item(_field(tr('password'), _pass, 'pass', icon: Icons.lock_outline_rounded, obscure: true, hint: tr('min_6'))),
              item(_field(tr('confirm_password'), _pass2, 'pass2', icon: Icons.lock_outline_rounded, obscure: true)),
            ],
            _ErrorBox(text: _error, shake: _shake),
            const SizedBox(height: 14),
            PrimaryButton(label: editing ? tr('save') : (widget.withEmail ? tr('create_account') : tr('continue')), busy: _busy, onPressed: _save),
            if (!widget.withEmail && !editing) ...[
              const SizedBox(height: 10),
              Center(child: TextButton(onPressed: () => app.signOut(), child: Text(tr('use_other_account')))),
            ],
          ],
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController c, String key,
      {IconData? icon, String? hint, bool obscure = false, TextInputType? type, TextCapitalization caps = TextCapitalization.sentences}) {
    final p = context.pal;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      FieldLabel(label),
      TextField(
        controller: c,
        obscureText: obscure && _hide,
        keyboardType: type,
        textCapitalization: caps,
        decoration: InputDecoration(
          hintText: hint,
          errorText: _fieldErr[key],
          prefixIcon: icon == null ? null : Icon(icon, color: p.muted),
          suffixIcon: obscure ? IconButton(onPressed: () => setState(() => _hide = !_hide), icon: Icon(_hide ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: p.muted)) : null,
        ),
      ),
    ]);
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({required this.n, required this.label, required this.on});
  final int n;
  final String label;
  final bool on;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Column(children: [
      Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(shape: BoxShape.circle, color: on ? p.brand : p.cardAlt, border: Border.all(color: on ? p.brand : p.border)),
        alignment: Alignment.center,
        child: Text('$n', style: TextStyle(fontWeight: FontWeight.w800, color: on ? (p.dark ? const Color(0xFF0B1220) : Colors.white) : p.muted)),
      ),
      const SizedBox(height: 4),
      Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: on ? p.brand : p.muted)),
    ]);
  }
}

class _PickerField extends StatelessWidget {
  const _PickerField({required this.label, required this.value, required this.hint, required this.onTap, this.error});
  final String label, hint;
  final String? value, error;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      FieldLabel(label),
      InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: onTap == null ? p.cardAlt : p.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: error != null ? p.danger : p.border),
          ),
          child: Row(children: [
            Expanded(
              child: Text(value ?? hint,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: value == null ? FontWeight.w500 : FontWeight.w700, color: value == null ? p.muted : p.ink)),
            ),
            Icon(Icons.keyboard_arrow_down_rounded, color: p.muted),
          ]),
        ),
      ),
      if (error != null) Padding(padding: const EdgeInsets.only(top: 6, left: 12), child: Text(error!, style: TextStyle(color: p.danger, fontSize: 12))),
    ]);
  }
}

class _SearchSheet extends StatefulWidget {
  const _SearchSheet({required this.title, required this.items, required this.otherLabel});
  final String title, otherLabel;
  final List<String> items;
  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final list = widget.items.where((e) => e == '__other__' || e.toLowerCase().contains(_q.toLowerCase())).toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * .75,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            if (widget.items.length > 8)
              TextField(
                autofocus: false,
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(hintText: tr('search'), prefixIcon: Icon(Icons.search_rounded, color: p.muted)),
              ),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 20),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final v = list[i];
              final other = v == '__other__';
              return ListTile(
                title: Text(other ? widget.otherLabel : v, style: TextStyle(fontWeight: FontWeight.w600, color: other ? p.brand : p.ink)),
                leading: other ? Icon(Icons.edit_rounded, color: p.brand) : null,
                onTap: () => Navigator.of(context).pop(v),
              );
            },
          ),
        ),
      ]),
    );
  }
}
