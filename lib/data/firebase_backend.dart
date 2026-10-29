import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/config.dart';
import 'backend.dart';
import 'models.dart';

/// Online store on the Firebase free plan.
///
/// Layout:
///   users/{uid}                         profile (only the person can read it)
///   memberships/{uid_instituteId}       role in an institute
///   codes/{CODE}                        what a join code points to
///   institutes/{id}                     institute
///   institutes/{id}/batches/{batchId}
///   institutes/{id}/attendance/{batchId_yyyymmdd}
///   institutes/{id}/fees/{studentUid_yyyy-mm}
///   institutes/{id}/notices/{id}
class FirebaseBackend implements Backend {
  FirebaseBackend();

  late FirebaseAuth _auth;
  late FirebaseFirestore _db;
  bool _googleReady = false;

  @override
  bool get isDemo => false;

  @override
  SignedIn? get current {
    final u = _auth.currentUser;
    if (u == null) return null;
    final google = u.providerData.any((p) => p.providerId == 'google.com');
    return SignedIn(uid: u.uid, email: u.email ?? '', name: u.displayName ?? '', viaGoogle: google);
  }

  @override
  Future<void> init() async {
    await Firebase.initializeApp(
      options: const FirebaseOptions(apiKey: fbApiKey, appId: fbAppId, messagingSenderId: fbSender, projectId: fbProject),
    );
    _auth = FirebaseAuth.instance;
    _db = FirebaseFirestore.instance;
  }

  BackendError _map(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
      case 'invalid-credential':
      case 'INVALID_LOGIN_CREDENTIALS':
        return BackendError('no-account-or-wrong', e.code);
      case 'wrong-password':
        return BackendError('wrong-password', e.code);
      case 'email-already-in-use':
        return BackendError('email-in-use', e.code);
      case 'weak-password':
        return BackendError('weak-password', e.code);
      case 'invalid-email':
        return BackendError('invalid-email', e.code);
      case 'network-request-failed':
        return BackendError('network', e.code);
      case 'too-many-requests':
        return BackendError('too-many', e.code);
      default:
        return BackendError('unknown', '${e.code} ${e.message ?? ''}');
    }
  }

  SignedIn _signed(User u, {required bool google}) =>
      SignedIn(uid: u.uid, email: u.email ?? '', name: u.displayName ?? '', viaGoogle: google);

  @override
  Future<SignedIn> signInEmail(String email, String password) async {
    try {
      final r = await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
      return _signed(r.user!, google: false);
    } on FirebaseAuthException catch (e) {
      throw _map(e);
    }
  }

  @override
  Future<SignedIn> signUpEmail(String email, String password) async {
    try {
      final r = await _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
      return _signed(r.user!, google: false);
    } on FirebaseAuthException catch (e) {
      throw _map(e);
    }
  }

  @override
  Future<SignedIn> signInGoogle() async {
    if (googleClientId.trim().isEmpty) throw BackendError('google-off');
    try {
      if (!_googleReady) {
        await GoogleSignIn.instance.initialize(serverClientId: googleClientId.trim());
        _googleReady = true;
      }
      final account = await GoogleSignIn.instance.authenticate();
      final token = account.authentication.idToken;
      if (token == null || token.isEmpty) throw BackendError('unknown', 'no token');
      final r = await _auth.signInWithCredential(GoogleAuthProvider.credential(idToken: token));
      final u = r.user!;
      return SignedIn(uid: u.uid, email: u.email ?? account.email, name: u.displayName ?? account.displayName ?? '', viaGoogle: true);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) throw BackendError('cancelled');
      throw BackendError('unknown', '${e.code}: ${e.description}');
    } on FirebaseAuthException catch (e) {
      throw _map(e);
    }
  }

  @override
  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw _map(e);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      if (_googleReady) await GoogleSignIn.instance.signOut();
    } catch (_) {}
    await _auth.signOut();
  }

  // ---------- profile ----------

  @override
  Future<AppUser?> profile(String uid) async {
    final d = await _db.collection('users').doc(uid).get();
    if (!d.exists || d.data() == null) return null;
    return AppUser.fromMap(d.data()!);
  }

  @override
  Future<void> saveProfile(AppUser user) => _db.collection('users').doc(user.uid).set(user.toMap());

  @override
  Future<void> setPhoto(String photo) async {
    final me = _auth.currentUser!.uid;
    await _db.collection('users').doc(me).set({'photo': photo}, SetOptions(merge: true));
    final q = await _mem.where('uid', isEqualTo: me).get();
    for (final d in q.docs) {
      await d.reference.update({'photo': photo});
    }
  }

  // ---------- memberships ----------

  CollectionReference<Map<String, dynamic>> get _mem => _db.collection('memberships');
  DocumentReference<Map<String, dynamic>> _inst(String id) => _db.collection('institutes').doc(id);

  @override
  Future<List<Membership>> myMemberships() async {
    final me = _auth.currentUser;
    if (me == null) return [];
    final q = await _mem.where('uid', isEqualTo: me.uid).get();
    final list = q.docs.map((d) => Membership.fromMap(d.data())).toList();
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  @override
  Future<List<Membership>> members(String instituteId) async {
    final q = await _mem.where('instituteId', isEqualTo: instituteId).get();
    final list = q.docs.map((d) => Membership.fromMap(d.data())).toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  @override
  Future<void> decide(Membership m, bool approve) async {
    if (!approve) {
      await _mem.doc(m.id).update({'status': MemberStatus.rejected.name});
      return;
    }
    final update = <String, dynamic>{'status': MemberStatus.approved.name};
    if (m.role == Role.student && m.studentCode.isEmpty) {
      final code = studentCodeFor(m.name);
      await _db.collection('codes').doc(code).set(JoinCode(
            code: code,
            type: CodeType.student,
            instituteId: m.instituteId,
            instituteName: m.instituteName,
            studentUid: m.uid,
            studentName: m.name,
            createdBy: _auth.currentUser?.uid ?? '',
          ).toMap());
      update['studentCode'] = code;
      m.studentCode = code;
    }
    await _mem.doc(m.id).update(update);
    m.status = MemberStatus.approved;
  }

  @override
  Future<void> setMonthlyFee(Membership m, int fee) async {
    await _mem.doc(m.id).update({'monthlyFee': fee});
    m.monthlyFee = fee;
  }

  @override
  Future<void> setFeePlan(Membership m, {required int monthlyFee, required int discount, required String note}) async {
    await _mem.doc(m.id).update({'monthlyFee': monthlyFee, 'discount': discount, 'feeNote': note});
    m
      ..monthlyFee = monthlyFee
      ..discount = discount
      ..feeNote = note;
  }

  @override
  Future<void> setPay(Membership m, {required int salary, required String payType}) async {
    await _mem.doc(m.id).update({'salary': salary, 'payType': payType});
    m
      ..salary = salary
      ..payType = payType;
  }

  @override
  Future<void> setUpi(Membership m, String upi) async {
    await _mem.doc(m.id).update({'upiId': upi});
    m.upiId = upi;
  }

  @override
  Future<void> leave(Membership m) => _mem.doc(m.id).delete();

  Future<void> _deleteAll(List<DocumentReference<Map<String, dynamic>>> refs) async {
    for (var i = 0; i < refs.length; i += 400) {
      final b = _db.batch();
      for (final r in refs.skip(i).take(400)) {
        b.delete(r);
      }
      await b.commit();
    }
  }

  @override
  Future<void> deleteInstitute(String instituteId) async {
    final me = _auth.currentUser!.uid;
    final inst = _inst(instituteId);
    final instDoc = await inst.get();
    final members = await _mem.where('instituteId', isEqualTo: instituteId).get();
    final batches = await inst.collection('batches').get();
    // 1. everything inside the institute
    final inside = <DocumentReference<Map<String, dynamic>>>[];
    for (final c in ['batches', 'attendance', 'fees', 'notices']) {
      final q = c == 'batches' ? batches : await inst.collection(c).get();
      inside.addAll(q.docs.map((d) => d.reference));
    }
    await _deleteAll(inside);
    // 2. its join codes
    final codes = <String>{
      (instDoc.data()?['code'] ?? '').toString(),
      ...batches.docs.map((d) => (d.data()['code'] ?? '').toString()),
      ...members.docs.map((d) => (d.data()['studentCode'] ?? '').toString()),
    }..removeWhere((c) => c.isEmpty);
    await _deleteAll([for (final c in codes) _db.collection('codes').doc(c)]);
    // 3. everyone's membership, mine last
    await _deleteAll(members.docs.where((d) => d.id != '${me}_$instituteId').map((d) => d.reference).toList());
    await _mem.doc('${me}_$instituteId').delete();
    // 4. the institute itself
    await inst.delete();
  }

  // ---------- institute & codes ----------

  @override
  Future<Membership> createInstitute({required AppUser owner, required String name, required String city, required bool teaches, required List<String> subjects}) async {
    final ref = _db.collection('institutes').doc();
    var code = instituteCodeFor(name);
    for (var i = 0; i < 5; i++) {
      final taken = await _db.collection('codes').doc(code).get();
      if (!taken.exists) break;
      code = instituteCodeFor(name);
    }
    final inst = Institute(id: ref.id, name: name, city: city, code: code, ownerUid: owner.uid);
    await ref.set(inst.toMap());
    final m = Membership(
      uid: owner.uid,
      instituteId: inst.id,
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
      photo: owner.photo,
    );
    await _mem.doc(m.id).set(m.toMap());
    await _db.collection('codes').doc(code).set(JoinCode(code: code, type: CodeType.institute, instituteId: inst.id, instituteName: name, createdBy: owner.uid).toMap());
    return m;
  }

  @override
  Future<Institute?> institute(String id) async {
    final d = await _inst(id).get();
    if (!d.exists || d.data() == null) return null;
    return Institute.fromMap(d.data()!);
  }

  @override
  Future<void> updateInstitute(Institute inst) =>
      _inst(inst.id).update({'name': inst.name, 'city': inst.city, 'address': inst.address, 'phone': inst.phone, 'upiId': inst.upiId, 'upiName': inst.upiName, 'dueDay': inst.dueDay, 'lateFee': inst.lateFee, ...inst.geoMap});

  @override
  Future<String> newInstituteCode(Institute inst) async {
    final code = instituteCodeFor(inst.name);
    await _db.collection('codes').doc(code).set(JoinCode(code: code, type: CodeType.institute, instituteId: inst.id, instituteName: inst.name, createdBy: _auth.currentUser?.uid ?? '').toMap());
    try {
      await _db.collection('codes').doc(inst.code).delete();
    } catch (_) {}
    await _inst(inst.id).update({'code': code});
    return code;
  }

  @override
  Future<JoinCode?> lookupCode(String code) async {
    final d = await _db.collection('codes').doc(normaliseCode(code)).get();
    if (!d.exists || d.data() == null) return null;
    return JoinCode.fromMap(d.data()!);
  }

  @override
  Future<Membership> requestJoin({required AppUser user, required JoinCode code, String relation = '', List<String> subjects = const []}) async {
    final id = '${user.uid}_${code.instituteId}';
    final existing = await _mem.doc(id).get();
    if (existing.exists && existing.data() != null) {
      final m = Membership.fromMap(existing.data()!);
      // Same person adds one more batch / child in the same institute.
      if (code.type == CodeType.batch && m.role == Role.student && !m.batchIds.contains(code.batchId)) {
        await _mem.doc(id).update({'batchIds': FieldValue.arrayUnion([code.batchId])});
        m.batchIds = [...m.batchIds, code.batchId];
      } else if (code.type == CodeType.student && m.role == Role.parent && !m.childUids.contains(code.studentUid)) {
        await _mem.doc(id).update({
          'childUids': FieldValue.arrayUnion([code.studentUid]),
          'childNames': FieldValue.arrayUnion([code.studentName]),
        });
      }
      return m;
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
      createdAt: DateTime.now().millisecondsSinceEpoch,
      photo: user.photo,
    );
    await _mem.doc(id).set(m.toMap());
    return m;
  }

  // ---------- batches ----------

  @override
  Future<List<Batch>> batches(String instituteId) async {
    final q = await _inst(instituteId).collection('batches').get();
    final list = q.docs.map((d) => Batch.fromMap(d.data())).toList();
    list.sort((a, b) => a.startMin.compareTo(b.startMin));
    return list;
  }

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
    final ref = _inst(instituteId).collection('batches').doc();
    var code = batchCodeFor(subject, days, startMin);
    for (var i = 0; i < 5; i++) {
      final taken = await _db.collection('codes').doc(code).get();
      if (!taken.exists) break;
      code = batchCodeFor(subject, days, startMin);
    }
    final b = Batch(
      id: ref.id,
      instituteId: instituteId,
      subject: subject,
      className: className,
      days: [...days]..sort(),
      startMin: startMin,
      endMin: endMin,
      teacherUid: teacherUid,
      teacherName: teacherName,
      code: code,
    );
    await ref.set(b.toMap());
    await _db.collection('codes').doc(code).set(JoinCode(
          code: code,
          type: CodeType.batch,
          instituteId: instituteId,
          instituteName: instituteName,
          batchId: b.id,
          batchTitle: '${b.title} · ${daysCode(b.days)} · ${timeLabel(b.startMin)}',
          teacherName: teacherName,
          createdBy: teacherUid,
        ).toMap());
    return b;
  }

  // ---------- attendance ----------

  @override
  Future<AttendanceDay?> attendance(String instituteId, String batchId, String dateKey) async {
    final d = await _inst(instituteId).collection('attendance').doc('${batchId}_$dateKey').get();
    if (!d.exists || d.data() == null) return null;
    return AttendanceDay.fromMap(d.data()!);
  }

  @override
  Future<void> saveAttendance(String instituteId, AttendanceDay day) =>
      _inst(instituteId).collection('attendance').doc(day.id).set({...day.toMap(), 'instituteId': instituteId});

  @override
  Future<List<AttendanceDay>> attendanceForBatch(String instituteId, String batchId) async {
    final q = await _inst(instituteId).collection('attendance').where('batchId', isEqualTo: batchId).get();
    final list = q.docs.map((d) => AttendanceDay.fromMap(d.data())).toList();
    list.sort((a, b) => b.dateKey.compareTo(a.dateKey));
    return list;
  }

  // ---------- fees ----------

  @override
  Future<List<FeeRecord>> feesForMonth(String instituteId, String month) async {
    final q = await _inst(instituteId).collection('fees').where('month', isEqualTo: month).get();
    return q.docs.map((d) => FeeRecord.fromMap(d.data())).toList();
  }

  @override
  Future<List<AttendanceDay>> attendanceForStudent(String instituteId, String studentUid) async {
    final q = await _inst(instituteId).collection('attendance').where('marked', arrayContains: studentUid).get();
    final list = q.docs.map((d) => AttendanceDay.fromMap(d.data())).toList();
    list.sort((a, b) => b.dateKey.compareTo(a.dateKey));
    return list;
  }

  @override
  Future<List<FeeRecord>> feesForStudent(String instituteId, String studentUid) async {
    final q = await _inst(instituteId).collection('fees').where('studentUid', isEqualTo: studentUid).get();
    final list = q.docs.map((d) => FeeRecord.fromMap(d.data())).toList();
    list.sort((a, b) => b.month.compareTo(a.month));
    return list;
  }

  @override
  Future<void> claimFee(String instituteId, FeeRecord fee) => _inst(instituteId).collection('fees').doc(fee.id).set(fee.toMap());

  @override
  Future<List<FeeRecord>> feeClaims(String instituteId) async {
    final q = await _inst(instituteId).collection('fees').where('claimed', isEqualTo: true).get();
    final list = q.docs.map((d) => FeeRecord.fromMap(d.data())).where((f) => f.waiting).toList();
    list.sort((a, b) => b.claimAt.compareTo(a.claimAt));
    return list;
  }

  @override
  Future<void> saveFee(String instituteId, FeeRecord fee) => _inst(instituteId).collection('fees').doc(fee.id).set(fee.toMap());

  // ---------- study material ----------

  @override
  Future<List<Resource>> resources(String instituteId) async {
    final q = await _inst(instituteId).collection('resources').get();
    final list = q.docs.map((d) => Resource.fromMap(d.data())).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  Future<void> saveResource(String instituteId, Resource r) => _inst(instituteId).collection('resources').doc(r.id).set(r.toMap());

  @override
  Future<void> deleteResource(String instituteId, String id) => _inst(instituteId).collection('resources').doc(id).delete();

  @override
  Future<List<Submission>> submissionsFor(String instituteId, String resourceId) async {
    final q = await _inst(instituteId).collection('submissions').where('resourceId', isEqualTo: resourceId).get();
    return q.docs.map((d) => Submission.fromMap(d.data())).toList();
  }

  @override
  Future<Submission?> mySubmission(String instituteId, String resourceId, String studentUid) async {
    try {
      final d = await _inst(instituteId).collection('submissions').doc('${resourceId}_$studentUid').get();
      if (!d.exists || d.data() == null) return null;
      return Submission.fromMap(d.data()!);
    } on FirebaseException catch (e) {
      // a parent may not see a missing answer of their child
      if (e.code == 'permission-denied') return null;
      rethrow;
    }
  }

  @override
  Future<void> saveSubmission(String instituteId, Submission s) => _inst(instituteId).collection('submissions').doc(s.id).set(s.toMap());

  // ---------- tests ----------

  @override
  Future<List<TestPaper>> tests(String instituteId, {bool publishedOnly = false}) async {
    Query<Map<String, dynamic>> c = _inst(instituteId).collection('tests');
    if (publishedOnly) c = c.where('published', isEqualTo: true);
    final q = await c.get();
    final list = q.docs.map((d) => TestPaper.fromMap(d.data())).toList();
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  @override
  Future<void> saveTest(String instituteId, TestPaper t) => _inst(instituteId).collection('tests').doc(t.id).set(t.toMap());

  @override
  Future<void> deleteTest(String instituteId, String id) => _inst(instituteId).collection('tests').doc(id).delete();

  // ---------- doubts ----------

  @override
  Future<List<Doubt>> doubts(String instituteId, {String? studentUid}) async {
    Query<Map<String, dynamic>> q = _inst(instituteId).collection('doubts');
    if (studentUid != null) q = q.where('studentUid', isEqualTo: studentUid);
    final r = await q.get();
    final list = r.docs.map((d) => Doubt.fromMap(d.data())).toList();
    list.sort((a, b) => b.lastAt.compareTo(a.lastAt));
    return list;
  }

  @override
  Future<void> saveDoubt(String instituteId, Doubt d) => _inst(instituteId).collection('doubts').doc(d.id).set(d.toMap());

  // ---------- notices ----------

  @override
  Future<List<Notice>> notices(String instituteId) async {
    final q = await _inst(instituteId).collection('notices').get();
    final list = q.docs.map((d) => Notice.fromMap(d.data())).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  Future<void> postNotice(String instituteId, Notice n) => _inst(instituteId).collection('notices').doc(n.id).set(n.toMap());

  // ---------- money ----------

  @override
  Future<List<Txn>> ledger(String instituteId, String month) async {
    final q = await _inst(instituteId).collection('ledger').where('month', isEqualTo: month).get();
    return q.docs.map((d) => Txn.fromMap(d.data())).toList()..sort((a, b) => b.date.compareTo(a.date));
  }

  @override
  Future<void> saveTxn(String instituteId, Txn t) => _inst(instituteId).collection('ledger').doc(t.id).set(t.toMap());

  @override
  Future<void> deleteTxn(String instituteId, String id) => _inst(instituteId).collection('ledger').doc(id).delete();

  @override
  Future<List<Txn>> payslips(String instituteId, String uid) async {
    final q = await _inst(instituteId).collection('ledger').where('refUid', isEqualTo: uid).get();
    return q.docs.map((d) => Txn.fromMap(d.data())).toList()..sort((a, b) => b.date.compareTo(a.date));
  }

  // ---------- admissions ----------

  @override
  Future<List<Lead>> leads(String instituteId) async {
    final q = await _inst(instituteId).collection('leads').get();
    return q.docs.map((d) => Lead.fromMap(d.data())).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<void> saveLead(String instituteId, Lead l) => _inst(instituteId).collection('leads').doc(l.id).set(l.toMap());

  @override
  Future<void> deleteLead(String instituteId, String id) => _inst(instituteId).collection('leads').doc(id).delete();

  // ---------- check-in ----------

  @override
  Future<List<CheckIn>> checkIns(String instituteId, String month, {String? uid}) async {
    Query<Map<String, dynamic>> q = _inst(instituteId).collection('checkins').where('month', isEqualTo: month);
    if (uid != null) q = q.where('uid', isEqualTo: uid);
    final r = await q.get();
    return r.docs.map((d) => CheckIn.fromMap(d.data())).toList()..sort((a, b) => b.inAt.compareTo(a.inAt));
  }

  @override
  Future<void> saveCheckIn(String instituteId, CheckIn c) => _inst(instituteId).collection('checkins').doc(c.id).set(c.toMap());

  // ---------- syllabus ----------

  @override
  Future<Syllabus?> syllabus(String instituteId, String batchId) async {
    final d = await _inst(instituteId).collection('syllabus').doc(batchId).get();
    if (!d.exists || d.data() == null) return null;
    return Syllabus.fromMap(d.data()!);
  }

  @override
  Future<void> saveSyllabus(String instituteId, Syllabus s) => _inst(instituteId).collection('syllabus').doc(s.batchId).set(s.toMap());
}
