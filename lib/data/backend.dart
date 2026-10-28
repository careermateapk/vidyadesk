import 'dart:math';

import 'models.dart';

/// A login/storage problem with a short code the screens turn into a message.
class BackendError implements Exception {
  BackendError(this.code, [this.detail = '']);
  final String code; // e.g. no-account, wrong-password, email-in-use, weak-password, cancelled, network, not-found
  final String detail;
  @override
  String toString() => 'BackendError($code $detail)';
}

class SignedIn {
  const SignedIn({required this.uid, required this.email, required this.name, required this.viaGoogle});
  final String uid, email, name;
  final bool viaGoogle;
}

/// Everything the screens need from "the server".
/// [FirebaseBackend] talks to Firebase; [DemoBackend] keeps sample data on the phone.
abstract class Backend {
  bool get isDemo;
  SignedIn? get current;

  Future<void> init();

  // ---- login ----
  Future<SignedIn> signInEmail(String email, String password);
  Future<SignedIn> signUpEmail(String email, String password);
  Future<SignedIn> signInGoogle();
  Future<void> resetPassword(String email);
  Future<void> signOut();

  // ---- profile ----
  Future<AppUser?> profile(String uid);
  Future<void> saveProfile(AppUser user);

  // ---- memberships ----
  Future<List<Membership>> myMemberships();
  Future<List<Membership>> members(String instituteId);
  Future<void> decide(Membership m, bool approve);
  Future<void> setMonthlyFee(Membership m, int fee);

  // ---- institute & codes ----
  Future<Membership> createInstitute({required AppUser owner, required String name, required String city, required bool teaches, required List<String> subjects});
  Future<Institute?> institute(String id);
  Future<String> newInstituteCode(Institute inst);
  Future<JoinCode?> lookupCode(String code);
  Future<Membership> requestJoin({required AppUser user, required JoinCode code, String relation = '', List<String> subjects = const []});

  // ---- batches ----
  Future<List<Batch>> batches(String instituteId);
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
  });

  // ---- attendance ----
  Future<AttendanceDay?> attendance(String instituteId, String batchId, String dateKey);
  Future<void> saveAttendance(String instituteId, AttendanceDay day);
  Future<List<AttendanceDay>> attendanceForBatch(String instituteId, String batchId);

  // ---- fees ----
  Future<List<FeeRecord>> feesForMonth(String instituteId, String month);
  Future<List<FeeRecord>> feesForStudent(String instituteId, String studentUid);
  Future<void> saveFee(String instituteId, FeeRecord fee);

  // ---- notices ----
  Future<List<Notice>> notices(String instituteId);
  Future<void> postNotice(String instituteId, Notice n);
}

// ---------- code helpers ----------

final _rnd = Random.secure();
const _letters = 'ABCDEFGHJKLMNPQRSTUVWXYZ';

String _digits(int n) => List.generate(n, (_) => _rnd.nextInt(10)).join();

String _prefix(String text, int len) {
  final clean = text.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
  if (clean.isEmpty) return List.generate(len, (_) => _letters[_rnd.nextInt(_letters.length)]).join();
  if (clean.length >= len) {
    // Keep first letter, then consonants, e.g. SHARMA -> SHRM
    final first = clean[0];
    final rest = clean.substring(1).replaceAll(RegExp(r'[AEIOU]'), '');
    final s = (first + rest + clean).substring(0, len);
    return s;
  }
  return clean.padRight(len, 'X');
}

String instituteCodeFor(String name) => '${_prefix(name, 4)}-${_digits(4)}';

String batchCodeFor(String subject, List<int> days, int startMin) {
  final sub = _prefix(subject, 3);
  final d = daysCode(days);
  final dc = d == 'MWF' || d == 'TTS' ? d : (d == 'Mon–Sat' ? 'MSA' : (d == 'Daily' ? 'DLY' : 'CUS'));
  final h = (startMin ~/ 60) % 12 == 0 ? 12 : (startMin ~/ 60) % 12;
  final ap = startMin >= 720 ? 'PM' : 'AM';
  return '$sub-$dc-$h$ap-${_digits(2)}';
}

String studentCodeFor(String name) => 'STU-${_prefix(name, 2)}-${_digits(4)}';

String newId() => '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${_digits(4)}';

String normaliseCode(String c) => c.trim().toUpperCase().replaceAll(' ', '');
