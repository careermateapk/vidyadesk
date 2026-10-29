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
  /// Set the signed-in person's photo on their profile and every membership.
  Future<void> setPhoto(String photo);

  // ---- memberships ----
  Future<List<Membership>> myMemberships();
  Future<List<Membership>> members(String instituteId);
  /// [batchIds]: batches picked by staff while approving (students who joined with the institute code).
  Future<void> decide(Membership m, bool approve, {List<String>? batchIds});
  Future<void> setMonthlyFee(Membership m, int fee);
  /// Admin: a student's fee plan. [monthlyFee] is the final amount after [discount].
  Future<void> setFeePlan(Membership m, {required int monthlyFee, required int discount, required String note});
  /// Admin: a teacher's pay — fixed monthly, or per class when [payType] is "class".
  Future<void> setPay(Membership m, {required int salary, required String payType});
  /// Teacher's UPI ID for salary (the teacher or the admin can set it).
  Future<void> setUpi(Membership m, String upi);
  /// Remove one of my roles (also cancels a pending request).
  Future<void> leave(Membership m);
  /// Owner only: remove the whole institute with all its data.
  Future<void> deleteInstitute(String instituteId);

  // ---- institute & codes ----
  Future<Membership> createInstitute({required AppUser owner, required String name, required String city, required bool teaches, required List<String> subjects});
  Future<Institute?> institute(String id);
  Future<void> updateInstitute(Institute inst);
  Future<String> newInstituteCode(Institute inst);
  Future<JoinCode?> lookupCode(String code);
  /// [role]: who is joining. Students may join with a batch code or the institute code.
  Future<Membership> requestJoin({required AppUser user, required JoinCode code, String relation = '', List<String> subjects = const [], Role? role, String childUid = '', String childName = ''});
  /// Puts my photo where my coaching's members can see it (parents see their child's).
  Future<void> sharePhoto(String instituteId, String photo);
  /// Parent: profile photos of my children (uid → base64 photo).
  Future<Map<String, String>> childPhotos(String instituteId, List<String> uids);
  /// Staff: writes each batch's student list into its batch code (parents pick their child from it).
  Future<void> syncRoster(String instituteId);
  /// Admin: removes a person from the coaching completely (and tells them).
  Future<void> removeMember(Membership m, {bool deleteFees = false});

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
  /// Every class day where this student was on the list (newest first).
  Future<List<AttendanceDay>> attendanceForStudent(String instituteId, String studentUid);

  // ---- fees ----
  Future<List<FeeRecord>> feesForMonth(String instituteId, String month);
  Future<List<FeeRecord>> feesForStudent(String instituteId, String studentUid);
  Future<void> saveFee(String instituteId, FeeRecord fee);
  /// Student/parent says "I paid by UPI" (waits for the institute to confirm).
  Future<void> claimFee(String instituteId, FeeRecord fee);
  /// UPI payments waiting for confirmation.
  Future<List<FeeRecord>> feeClaims(String instituteId);

  // ---- study material ----
  Future<List<Resource>> resources(String instituteId);
  Future<void> saveResource(String instituteId, Resource r);
  Future<void> deleteResource(String instituteId, String id);
  Future<List<Submission>> submissionsFor(String instituteId, String resourceId);
  Future<Submission?> mySubmission(String instituteId, String resourceId, String studentUid);
  Future<void> saveSubmission(String instituteId, Submission s);

  // ---- tests ----
  /// Students and parents must pass publishedOnly: true.
  Future<List<TestPaper>> tests(String instituteId, {bool publishedOnly = false});
  Future<void> saveTest(String instituteId, TestPaper t);
  Future<void> deleteTest(String instituteId, String id);

  // ---- doubts ----
  /// Staff: every doubt. Student: pass [studentUid] to get only theirs.
  Future<List<Doubt>> doubts(String instituteId, {String? studentUid});
  Future<void> saveDoubt(String instituteId, Doubt d);

  // ---- money (admin) ----
  Future<List<Txn>> ledger(String instituteId, String month);
  Future<void> saveTxn(String instituteId, Txn t);
  Future<void> deleteTxn(String instituteId, String id);
  /// A teacher's own salary entries.
  Future<List<Txn>> payslips(String instituteId, String uid);

  // ---- admissions ----
  Future<List<Lead>> leads(String instituteId);
  Future<void> saveLead(String instituteId, Lead l);
  Future<void> deleteLead(String instituteId, String id);

  // ---- teacher check-in ----
  /// Admin: everyone's (pass [uid] for one teacher). Teacher must pass own uid.
  Future<List<CheckIn>> checkIns(String instituteId, String month, {String? uid});
  Future<void> saveCheckIn(String instituteId, CheckIn c);

  // ---- syllabus ----
  Future<Syllabus?> syllabus(String instituteId, String batchId);
  Future<void> saveSyllabus(String instituteId, Syllabus s);

  // ---- VidyaDesk subscription ----
  /// Admin: "I paid for this plan, here is the UTR". The owner confirms it.
  Future<void> claimSubscription(SubPayment p);
  /// Admin paid in a UPI app. [paidOk]: the UPI app said success → the plan starts now;
  /// otherwise it waits for the owner. Returns the saved payment.
  Future<SubPayment> startPlan({required Membership admin, required String plan, required bool yearly, required bool paidOk, String ref = '', String via = '', String coupon = ''});
  /// Looks up a discount code (null = no such code).
  Future<Coupon?> coupon(String code);

  // ---- owner only ----
  Future<List<Coupon>> coupons();
  Future<void> saveCoupon(Coupon c);
  Future<void> deleteCoupon(String code);
  /// Owner: give / renew / extend trial / stop a coaching's plan. Kept in its history.
  Future<void> ownerSetPlan(String instituteId, {required String action, required String plan, required int until, int days = 0, String note = ''});
  Future<List<PlanAction>> planHistory(String instituteId);

  // ---- home banners ----
  /// Banners that are on (everyone).
  Future<List<AppBanner>> banners();
  /// Owner: every banner, on or off.
  Future<List<AppBanner>> allBanners();
  Future<void> saveBanner(AppBanner b);
  Future<void> deleteBanner(String id);
  /// Admin: own payments for this coaching (newest first).
  Future<List<SubPayment>> mySubPayments(String instituteId);
  /// Owner only: all coachings, payments waiting for a check, income this month.
  Future<OwnerStats> ownerStats();
  /// Owner only: payment received (plan starts / extends) or not received.
  Future<void> decideSubPayment(SubPayment p, bool ok);

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
