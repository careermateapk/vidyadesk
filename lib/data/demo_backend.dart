import 'backend.dart';
import 'models.dart';

/// Works without internet and without Firebase: sample institute, batches,
/// students and fees kept in memory, so the app can be tried right away.
/// Everything resets when the app is closed.
class DemoBackend implements Backend {
  SignedIn? _current;
  final Map<String, AppUser> _users = {};
  final Map<String, String> _passwords = {}; // email -> password
  final Map<String, String> _emailUid = {};
  final Map<String, Institute> _institutes = {};
  final Map<String, Membership> _members = {};
  final Map<String, JoinCode> _codes = {};
  final Map<String, Batch> _batches = {};
  final Map<String, AttendanceDay> _attendance = {};
  final Map<String, FeeRecord> _fees = {};
  final Map<String, List<Notice>> _notices = {};

  static const demoInstituteCode = 'SHRM-4821';
  static const demoBatchCode = 'ECO-TTS-5PM-38';
  static const demoStudentCode = 'STU-AK-4417';

  @override
  bool get isDemo => true;

  @override
  SignedIn? get current => _current;

  Future<void> _wait() => Future<void>.delayed(const Duration(milliseconds: 350));

  @override
  Future<void> init() async {
    _seed();
  }

  void _seed() {
    const instId = 'demo-inst';
    const owner = 'demo-owner';
    _institutes[instId] = const Institute(id: instId, name: 'Sharma Classes', city: 'Darbhanga', code: demoInstituteCode, ownerUid: owner);
    _codes[demoInstituteCode] = const JoinCode(code: demoInstituteCode, type: CodeType.institute, instituteId: instId, instituteName: 'Sharma Classes');
    final now = DateTime.now().millisecondsSinceEpoch;
    _members['${owner}_$instId'] = Membership(
        uid: owner, instituteId: instId, instituteName: 'Sharma Classes', role: Role.admin, status: MemberStatus.approved, name: 'Rakesh Sharma', phone: '+919876543210', teaches: true, subjects: ['Economics'], createdAt: now);
    final b1 = Batch(id: 'b1', instituteId: instId, subject: 'Economics', className: 'Class 12', days: [2, 4, 6], startMin: 17 * 60, endMin: 18 * 60 + 30, teacherUid: owner, teacherName: 'Rakesh Sharma', code: demoBatchCode);
    final b2 = Batch(id: 'b2', instituteId: instId, subject: 'Accounts', className: 'Class 11', days: [1, 3, 5], startMin: 7 * 60, endMin: 8 * 60 + 30, teacherUid: 't1', teacherName: 'Anil Verma', code: 'ACC-MWF-7AM-14');
    _batches[b1.id] = b1;
    _batches[b2.id] = b2;
    _codes[b1.code] = JoinCode(code: b1.code, type: CodeType.batch, instituteId: instId, instituteName: 'Sharma Classes', batchId: b1.id, batchTitle: '${b1.title} · TTS · 5:00 PM', teacherName: 'Rakesh Sharma');
    _codes[b2.code] = JoinCode(code: b2.code, type: CodeType.batch, instituteId: instId, instituteName: 'Sharma Classes', batchId: b2.id, batchTitle: '${b2.title} · MWF · 7:00 AM', teacherName: 'Anil Verma');
    _members['t1_$instId'] = Membership(
        uid: 't1', instituteId: instId, instituteName: 'Sharma Classes', role: Role.teacher, status: MemberStatus.approved, name: 'Anil Verma', phone: '+919431122558', subjects: ['Accounts'], createdAt: now);
    final names = ['Aarav Kumar', 'Priya Jha', 'Rohit Mishra', 'Sneha Karn', 'Ankit Yadav', 'Neha Thakur', 'Vikas Sah'];
    for (var i = 0; i < names.length; i++) {
      final uid = 's$i';
      final m = Membership(
        uid: uid,
        instituteId: instId,
        instituteName: 'Sharma Classes',
        role: Role.student,
        status: MemberStatus.approved,
        name: names[i],
        phone: '+91987650${1000 + i}',
        batchIds: [i.isEven ? 'b1' : 'b2'],
        studentCode: i == 0 ? demoStudentCode : 'STU-${names[i].substring(0, 2).toUpperCase()}-${5000 + i}',
        monthlyFee: i.isEven ? 1500 : 1200,
        createdAt: now,
      );
      _members[m.id] = m;
      _codes[m.studentCode] = JoinCode(code: m.studentCode, type: CodeType.student, instituteId: instId, instituteName: 'Sharma Classes', studentUid: uid, studentName: names[i]);
    }
    // A parent of Aarav, already approved
    _members['par0_$instId'] = Membership(
        uid: 'par0', instituteId: instId, instituteName: 'Sharma Classes', role: Role.parent, status: MemberStatus.approved, name: 'Manoj Kumar', phone: '+919801234567', childUids: ['s0'], childNames: ['Aarav Kumar'], relation: 'father', joinedVia: demoStudentCode, createdAt: now);
    // Ready-made accounts for "try as ..." on the login screen
    const addr = Address(block: 'Ward 12', street: 'Laheriasarai Road', pincode: '846001', state: 'Bihar', city: 'Darbhanga');
    for (final u in [
      const AppUser(uid: owner, name: 'Rakesh Sharma', email: 'rakesh@demo.in', countryCode: '+91', phone: '9876543210', address: addr),
      const AppUser(uid: 't1', name: 'Anil Verma', email: 'anil@demo.in', countryCode: '+91', phone: '9431122558', address: addr),
      const AppUser(uid: 's0', name: 'Aarav Kumar', email: 'aarav@demo.in', countryCode: '+91', phone: '9876501000', address: addr),
      const AppUser(uid: 'par0', name: 'Manoj Kumar', email: 'manoj@demo.in', countryCode: '+91', phone: '9801234567', address: addr),
    ]) {
      _users[u.uid] = u;
      _emailUid[u.email] = u.uid;
      _passwords[u.email] = 'demo123';
    }
    // Two people waiting for approval
    _members['p1_$instId'] = Membership(
        uid: 'p1', instituteId: instId, instituteName: 'Sharma Classes', role: Role.student, status: MemberStatus.pending, name: 'Rahul Kumar', phone: '+919812345210', batchIds: ['b1'], joinedVia: b1.code, createdAt: now);
    _members['p2_$instId'] = Membership(
        uid: 'p2', instituteId: instId, instituteName: 'Sharma Classes', role: Role.parent, status: MemberStatus.pending, name: 'Suresh Choudhary', phone: '+919431122558', childUids: ['s1'], childNames: ['Priya Jha'], relation: 'father', joinedVia: 'STU-PR-5001', createdAt: now);

    // Attendance for the last two weeks, fees for this month and last month
    final today = DateTime.now();
    for (var d = 1; d <= 14; d++) {
      final day = today.subtract(Duration(days: d));
      for (final b in [b1, b2]) {
        if (!b.runsOn(day)) continue;
        final studs = _members.values.where((m) => m.role == Role.student && m.approved && m.batchIds.contains(b.id)).map((m) => m.uid).toList();
        final present = studs.where((u) => (u.hashCode + d) % 5 != 0).toList();
        final a = AttendanceDay(batchId: b.id, dateKey: dateKey(day), marked: studs, present: present);
        _attendance['${instId}_${a.id}'] = a;
      }
    }
    final thisMonth = monthKey(today);
    final lastMonth = monthKey(DateTime(today.year, today.month - 1, 1));
    for (final m in _members.values.where((m) => m.role == Role.student && m.approved).toList()) {
      final last = FeeRecord(studentUid: m.uid, studentName: m.name, month: lastMonth, amount: m.monthlyFee, paid: true, paidOn: now - 20 * 86400000, mode: 'UPI', receiptNo: 'R-${1900 + m.uid.hashCode % 99}');
      _fees['${instId}_${last.id}'] = last;
      final paid = m.uid.hashCode % 3 != 0;
      final cur = FeeRecord(studentUid: m.uid, studentName: m.name, month: thisMonth, amount: m.monthlyFee, paid: paid, paidOn: paid ? now - 3 * 86400000 : 0, mode: paid ? 'Cash' : '', receiptNo: paid ? 'R-${2200 + m.uid.hashCode % 99}' : '');
      _fees['${instId}_${cur.id}'] = cur;
    }
    _notices[instId] = [
      Notice(id: 'n1', text: 'Diwali ke avsar par 29 Oct se 2 Nov tak coaching band rahegi. 3 November se sabhi class apne samay par.', kind: 'holiday', byName: 'Rakesh Sharma', createdAt: now - 3600000),
      Notice(id: 'n2', text: 'November ki fees 5 tareekh tak jama karein.', kind: 'fees', byName: 'Rakesh Sharma', createdAt: now - 86400000),
    ];
  }

  // ---------- login ----------

  @override
  Future<SignedIn> signInEmail(String email, String password) async {
    await _wait();
    final e = email.trim().toLowerCase();
    final uid = _emailUid[e];
    if (uid == null) throw BackendError('no-account-or-wrong');
    if (_passwords[e] != password) throw BackendError('no-account-or-wrong');
    _current = SignedIn(uid: uid, email: e, name: _users[uid]?.name ?? '', viaGoogle: false);
    return _current!;
  }

  @override
  Future<SignedIn> signUpEmail(String email, String password) async {
    await _wait();
    final e = email.trim().toLowerCase();
    if (!e.contains('@')) throw BackendError('invalid-email');
    if (_emailUid.containsKey(e)) throw BackendError('email-in-use');
    if (password.length < 6) throw BackendError('weak-password');
    final uid = 'u${_emailUid.length + 1}';
    _emailUid[e] = uid;
    _passwords[e] = password;
    _current = SignedIn(uid: uid, email: e, name: '', viaGoogle: false);
    return _current!;
  }

  @override
  Future<SignedIn> signInGoogle() async {
    await _wait();
    const e = 'demo.user@gmail.com';
    final uid = _emailUid.putIfAbsent(e, () => 'g1');
    _current = SignedIn(uid: uid, email: e, name: 'Demo User', viaGoogle: true);
    return _current!;
  }

  @override
  Future<void> resetPassword(String email) async => _wait();

  @override
  Future<void> signOut() async {
    _current = null;
  }

  // ---------- profile ----------

  @override
  Future<AppUser?> profile(String uid) async => _users[uid];

  @override
  Future<void> saveProfile(AppUser user) async {
    await _wait();
    _users[user.uid] = user;
  }

  // ---------- memberships ----------

  @override
  Future<List<Membership>> myMemberships() async {
    final me = _current?.uid;
    if (me == null) return [];
    return _members.values.where((m) => m.uid == me).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  @override
  Future<List<Membership>> members(String instituteId) async =>
      _members.values.where((m) => m.instituteId == instituteId).toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  @override
  Future<void> decide(Membership m, bool approve) async {
    await _wait();
    final real = _members[m.id] ?? m;
    real.status = approve ? MemberStatus.approved : MemberStatus.rejected;
    if (approve && real.role == Role.student && real.studentCode.isEmpty) {
      real.studentCode = studentCodeFor(real.name);
      _codes[real.studentCode] = JoinCode(
          code: real.studentCode, type: CodeType.student, instituteId: real.instituteId, instituteName: real.instituteName, studentUid: real.uid, studentName: real.name);
    }
    m.status = real.status;
    m.studentCode = real.studentCode;
  }

  @override
  Future<void> setMonthlyFee(Membership m, int fee) async {
    (_members[m.id] ?? m).monthlyFee = fee;
    m.monthlyFee = fee;
  }

  // ---------- institute & codes ----------

  @override
  Future<Membership> createInstitute({required AppUser owner, required String name, required String city, required bool teaches, required List<String> subjects}) async {
    await _wait();
    final id = 'inst${_institutes.length + 1}';
    final code = instituteCodeFor(name);
    _institutes[id] = Institute(id: id, name: name, city: city, code: code, ownerUid: owner.uid);
    _codes[code] = JoinCode(code: code, type: CodeType.institute, instituteId: id, instituteName: name);
    final m = Membership(
      uid: owner.uid,
      instituteId: id,
      instituteName: name,
      role: Role.admin,
      status: MemberStatus.approved,
      name: owner.name,
      phone: owner.fullPhone,
      email: owner.email,
      city: owner.address.city,
      teaches: teaches,
      subjects: subjects,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    _members[m.id] = m;
    _notices[id] = [];
    return m;
  }

  @override
  Future<Institute?> institute(String id) async => _institutes[id];

  @override
  Future<String> newInstituteCode(Institute inst) async {
    await _wait();
    final code = instituteCodeFor(inst.name);
    _codes.remove(inst.code);
    _codes[code] = JoinCode(code: code, type: CodeType.institute, instituteId: inst.id, instituteName: inst.name);
    _institutes[inst.id] = Institute(id: inst.id, name: inst.name, city: inst.city, code: code, ownerUid: inst.ownerUid);
    return code;
  }

  @override
  Future<JoinCode?> lookupCode(String code) async {
    await _wait();
    return _codes[normaliseCode(code)];
  }

  @override
  Future<Membership> requestJoin({required AppUser user, required JoinCode code, String relation = '', List<String> subjects = const []}) async {
    await _wait();
    final id = '${user.uid}_${code.instituteId}';
    final existing = _members[id];
    if (existing != null) {
      if (code.type == CodeType.batch && !existing.batchIds.contains(code.batchId)) existing.batchIds = [...existing.batchIds, code.batchId];
      return existing;
    }
    final role = switch (code.type) { CodeType.institute => Role.teacher, CodeType.batch => Role.student, CodeType.student => Role.parent };
    final m = Membership(
      uid: user.uid,
      instituteId: code.instituteId,
      instituteName: code.instituteName,
      role: role,
      status: MemberStatus.pending,
      name: user.name,
      phone: user.fullPhone,
      email: user.email,
      city: user.address.city,
      subjects: subjects,
      batchIds: code.type == CodeType.batch ? [code.batchId] : const [],
      childUids: code.type == CodeType.student ? [code.studentUid] : const [],
      childNames: code.type == CodeType.student ? [code.studentName] : const [],
      relation: relation,
      joinedVia: code.code,
      monthlyFee: role == Role.student ? 1500 : 0,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    _members[id] = m;
    return m;
  }

  // ---------- batches ----------

  @override
  Future<List<Batch>> batches(String instituteId) async =>
      _batches.values.where((b) => b.instituteId == instituteId).toList()..sort((a, b) => a.startMin.compareTo(b.startMin));

  @override
  Future<Batch> createBatch({
    required String instituteId,
    required String instituteName,
    required String subject,
    required String className,
    required List<int> days,
    required int startMin,
    required int endMin,
    required String teacherUid,
    required String teacherName,
  }) async {
    await _wait();
    final b = Batch(
      id: newId(),
      instituteId: instituteId,
      subject: subject,
      className: className,
      days: [...days]..sort(),
      startMin: startMin,
      endMin: endMin,
      teacherUid: teacherUid,
      teacherName: teacherName,
      code: batchCodeFor(subject, days, startMin),
    );
    _batches[b.id] = b;
    _codes[b.code] = JoinCode(
        code: b.code,
        type: CodeType.batch,
        instituteId: instituteId,
        instituteName: instituteName,
        batchId: b.id,
        batchTitle: '${b.title} · ${daysCode(b.days)} · ${timeLabel(b.startMin)}',
        teacherName: teacherName);
    return b;
  }

  // ---------- attendance ----------

  @override
  Future<AttendanceDay?> attendance(String instituteId, String batchId, String dk) async => _attendance['${instituteId}_${batchId}_$dk'];

  @override
  Future<void> saveAttendance(String instituteId, AttendanceDay day) async {
    await _wait();
    _attendance['${instituteId}_${day.id}'] = day;
  }

  @override
  Future<List<AttendanceDay>> attendanceForBatch(String instituteId, String batchId) async =>
      _attendance.entries.where((e) => e.key.startsWith('${instituteId}_') && e.value.batchId == batchId).map((e) => e.value).toList()
        ..sort((a, b) => b.dateKey.compareTo(a.dateKey));

  @override
  Future<List<AttendanceDay>> attendanceForStudent(String instituteId, String studentUid) async =>
      _attendance.entries.where((e) => e.key.startsWith('${instituteId}_') && e.value.marked.contains(studentUid)).map((e) => e.value).toList()
        ..sort((a, b) => b.dateKey.compareTo(a.dateKey));

  // ---------- fees ----------

  @override
  Future<List<FeeRecord>> feesForMonth(String instituteId, String month) async =>
      _fees.entries.where((e) => e.key.startsWith('${instituteId}_') && e.value.month == month).map((e) => e.value).toList();

  @override
  Future<List<FeeRecord>> feesForStudent(String instituteId, String studentUid) async =>
      _fees.entries.where((e) => e.key.startsWith('${instituteId}_') && e.value.studentUid == studentUid).map((e) => e.value).toList()
        ..sort((a, b) => b.month.compareTo(a.month));

  @override
  Future<void> saveFee(String instituteId, FeeRecord fee) async {
    await _wait();
    _fees['${instituteId}_${fee.id}'] = fee;
  }

  // ---------- notices ----------

  @override
  Future<List<Notice>> notices(String instituteId) async => [...(_notices[instituteId] ?? <Notice>[])]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Future<void> postNotice(String instituteId, Notice n) async {
    await _wait();
    (_notices[instituteId] ??= []).add(n);
  }

  /// Demo only: log in straight away as the sample admin / teacher / student / parent.
  Future<SignedIn> signInSample(Role r) async {
    await _wait();
    final uid = switch (r) { Role.admin => 'demo-owner', Role.teacher => 't1', Role.student => 's0', Role.parent => 'par0' };
    final u = _users[uid]!;
    _current = SignedIn(uid: uid, email: u.email, name: u.name, viaGoogle: false);
    return _current!;
  }

  /// Demo only: lets the person approve their own pending request.
  Future<void> demoApprove(Membership m) => decide(m, true);
}
