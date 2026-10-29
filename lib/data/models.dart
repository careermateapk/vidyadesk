// Plain data classes. Each has toMap/fromMap so the same shapes are
// stored in Firebase (online) and in the demo store (on the phone).

String _s(Object? v) => v == null ? '' : v.toString();
int _i(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse(_s(v)) ?? 0);
bool _b(Object? v) => v == true;
List<String> _ls(Object? v) => v is List ? v.map((e) => e.toString()).toList() : <String>[];
List<int> _li(Object? v) => v is List ? v.map((e) => _i(e)).toList() : <int>[];

enum Role { admin, teacher, student, parent }

Role roleFrom(String s) => Role.values.firstWhere((r) => r.name == s, orElse: () => Role.student);

class Address {
  const Address({this.block = '', this.street = '', this.pincode = '', this.state = '', this.city = ''});
  final String block, street, pincode, state, city;

  Map<String, dynamic> toMap() => {'block': block, 'street': street, 'pincode': pincode, 'state': state, 'city': city};
  factory Address.fromMap(Map<String, dynamic>? m) => m == null
      ? const Address()
      : Address(block: _s(m['block']), street: _s(m['street']), pincode: _s(m['pincode']), state: _s(m['state']), city: _s(m['city']));
}

class AppUser {
  const AppUser({required this.uid, required this.name, required this.email, required this.countryCode, required this.phone, required this.address, this.viaGoogle = false, this.photo = ''});
  final String uid, name, email, countryCode, phone;
  /// Small round profile photo as base64 PNG ('' = none).
  final String photo;
  final Address address;
  final bool viaGoogle;

  String get fullPhone => '$countryCode$phone';

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'name': name,
        'email': email,
        'countryCode': countryCode,
        'phone': phone,
        'address': address.toMap(),
        'viaGoogle': viaGoogle,
        'photo': photo,
      };

  AppUser withPhoto(String p) => AppUser(uid: uid, name: name, email: email, countryCode: countryCode, phone: phone, address: address, viaGoogle: viaGoogle, photo: p);

  factory AppUser.fromMap(Map<String, dynamic> m) => AppUser(
        uid: _s(m['uid']),
        name: _s(m['name']),
        email: _s(m['email']),
        countryCode: _s(m['countryCode']).isEmpty ? '+91' : _s(m['countryCode']),
        phone: _s(m['phone']),
        address: Address.fromMap(m['address'] is Map ? Map<String, dynamic>.from(m['address'] as Map) : null),
        viaGoogle: _b(m['viaGoogle']),
        photo: _s(m['photo']),
      );
}

class Institute {
  const Institute({
    required this.id,
    required this.name,
    required this.city,
    required this.code,
    required this.ownerUid,
    this.address = '',
    this.phone = '',
    this.upiId = '',
    this.upiName = '',
    this.dueDay = 10,
    this.lateFee = 0,
    this.geoCheckin = false,
    this.geoLat = 0,
    this.geoLng = 0,
    this.geoRadius = 100,
    this.geoAddress = '',
    this.onlineCheckin = false,
    this.onlineUids = const [],
    this.plan = 'trial',
    this.planUntil = 0,
    this.ownerName = '',
    this.ownerPhone = '',
    this.createdAt = 0,
  });
  final String id, name, city, code, ownerUid;

  /// Subscription: trial / basic / standard / pro, and when it ends (ms).
  /// Only the VidyaDesk owner can change these.
  final String plan;
  final int planUntil;
  final String ownerName, ownerPhone;
  final int createdAt;
  final String address, phone, upiId, upiName;
  /// Fees are due by this day of the month; after it [lateFee] is added.
  final int dueDay, lateFee;

  /// Teacher check-in only at the coaching: its point, allowed distance (m) and address.
  final bool geoCheckin;
  final double geoLat, geoLng;
  final int geoRadius;
  final String geoAddress;

  /// Teachers may check in from home (online classes). Empty list = all teachers.
  final bool onlineCheckin;
  final List<String> onlineUids;
  bool get hasPlace => geoLat != 0 || geoLng != 0;
  bool canCheckInOnline(String uid) => onlineCheckin && (onlineUids.isEmpty || onlineUids.contains(uid));

  Institute copyWith({
    String? name,
    String? city,
    String? code,
    String? address,
    String? phone,
    String? upiId,
    String? upiName,
    int? dueDay,
    int? lateFee,
    bool? geoCheckin,
    double? geoLat,
    double? geoLng,
    int? geoRadius,
    String? geoAddress,
    bool? onlineCheckin,
    List<String>? onlineUids,
  }) =>
      Institute(
        id: id,
        ownerUid: ownerUid,
        name: name ?? this.name,
        city: city ?? this.city,
        code: code ?? this.code,
        address: address ?? this.address,
        phone: phone ?? this.phone,
        upiId: upiId ?? this.upiId,
        upiName: upiName ?? this.upiName,
        dueDay: dueDay ?? this.dueDay,
        lateFee: lateFee ?? this.lateFee,
        geoCheckin: geoCheckin ?? this.geoCheckin,
        geoLat: geoLat ?? this.geoLat,
        geoLng: geoLng ?? this.geoLng,
        geoRadius: geoRadius ?? this.geoRadius,
        geoAddress: geoAddress ?? this.geoAddress,
        onlineCheckin: onlineCheckin ?? this.onlineCheckin,
        onlineUids: onlineUids ?? this.onlineUids,
        plan: plan,
        planUntil: planUntil,
        ownerName: ownerName,
        ownerPhone: ownerPhone,
        createdAt: createdAt,
      );

  Map<String, dynamic> toMap() =>
      {'id': id, 'name': name, 'city': city, 'code': code, 'ownerUid': ownerUid, 'address': address, 'phone': phone, 'upiId': upiId, 'upiName': upiName, 'dueDay': dueDay, 'lateFee': lateFee, ...geoMap, 'plan': plan, 'planUntil': planUntil, 'ownerName': ownerName, 'ownerPhone': ownerPhone, 'createdAt': createdAt};

  Map<String, dynamic> get geoMap => {
        'geoCheckin': geoCheckin,
        'geoLat': geoLat,
        'geoLng': geoLng,
        'geoRadius': geoRadius,
        'geoAddress': geoAddress,
        'onlineCheckin': onlineCheckin,
        'onlineUids': onlineUids,
      };
  factory Institute.fromMap(Map<String, dynamic> m) => Institute(
        id: _s(m['id']),
        name: _s(m['name']),
        city: _s(m['city']),
        code: _s(m['code']),
        ownerUid: _s(m['ownerUid']),
        address: _s(m['address']),
        phone: _s(m['phone']),
        upiId: _s(m['upiId']),
        upiName: _s(m['upiName']),
        dueDay: _i(m['dueDay']) == 0 ? 10 : _i(m['dueDay']).clamp(1, 28),
        lateFee: _i(m['lateFee']),
        geoCheckin: _b(m['geoCheckin']),
        geoLat: m['geoLat'] is num ? (m['geoLat'] as num).toDouble() : 0,
        geoLng: m['geoLng'] is num ? (m['geoLng'] as num).toDouble() : 0,
        geoRadius: _i(m['geoRadius']) == 0 ? 100 : _i(m['geoRadius']),
        geoAddress: _s(m['geoAddress']),
        onlineCheckin: _b(m['onlineCheckin']),
        onlineUids: _ls(m['onlineUids']),
        plan: _s(m['plan']).isEmpty ? 'trial' : _s(m['plan']),
        planUntil: _i(m['planUntil']),
        ownerName: _s(m['ownerName']),
        ownerPhone: _s(m['ownerPhone']),
        createdAt: _i(m['createdAt']),
      );
}

/// A coaching's payment for VidyaDesk (checked by the owner using the UTR).
class SubPayment {
  SubPayment({
    required this.id,
    required this.instituteId,
    required this.instituteName,
    required this.adminUid,
    required this.adminName,
    required this.phone,
    required this.plan,
    required this.yearly,
    required this.amount,
    required this.utr,
    this.status = 'pending',
    this.createdAt = 0,
    this.decidedAt = 0,
  });
  final String id, instituteId, instituteName, adminUid, adminName, phone, plan, utr;
  final bool yearly;
  final int amount, createdAt;
  String status; // pending / confirmed / rejected
  int decidedAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'instituteId': instituteId,
        'instituteName': instituteName,
        'adminUid': adminUid,
        'adminName': adminName,
        'phone': phone,
        'plan': plan,
        'yearly': yearly,
        'amount': amount,
        'utr': utr,
        'status': status,
        'createdAt': createdAt,
        'decidedAt': decidedAt,
      };
  factory SubPayment.fromMap(Map<String, dynamic> m) => SubPayment(
        id: _s(m['id']),
        instituteId: _s(m['instituteId']),
        instituteName: _s(m['instituteName']),
        adminUid: _s(m['adminUid']),
        adminName: _s(m['adminName']),
        phone: _s(m['phone']),
        plan: _s(m['plan']),
        yearly: _b(m['yearly']),
        amount: _i(m['amount']),
        utr: _s(m['utr']),
        status: _s(m['status']).isEmpty ? 'pending' : _s(m['status']),
        createdAt: _i(m['createdAt']),
        decidedAt: _i(m['decidedAt']),
      );
}

/// Numbers for the owner panel.
class OwnerStats {
  const OwnerStats({required this.institutes, required this.pending, required this.monthIncome, required this.students});
  final List<Institute> institutes;
  final List<SubPayment> pending;
  final int monthIncome, students;
}

enum MemberStatus { pending, approved, rejected }

/// One person's place in one institute (their role there).
/// Document id is "<uid>_<instituteId>".
class Membership {
  Membership({
    required this.uid,
    required this.instituteId,
    required this.instituteName,
    required this.role,
    required this.status,
    required this.name,
    this.phone = '',
    this.email = '',
    this.city = '',
    this.teaches = false,
    this.subjects = const [],
    this.batchIds = const [],
    this.childUids = const [],
    this.childNames = const [],
    this.relation = '',
    this.studentCode = '',
    this.monthlyFee = 0,
    this.joinedVia = '',
    this.createdAt = 0,
    this.photo = '',
    this.discount = 0,
    this.feeNote = '',
    this.salary = 0,
    this.payType = 'fixed',
    this.upiId = '',
  });

  final String uid, instituteId, instituteName;
  /// Fee plan (students): ₹ off every month and a note like "Merit scholarship".
  /// [monthlyFee] is always the final amount after the discount.
  int discount;
  String feeNote;
  /// Pay (teachers): fixed monthly salary, or ₹ per class when [payType] is "class".
  int salary;
  String payType;
  /// Teacher's UPI ID — the admin pays the salary to it from the app.
  String upiId;
  String photo;
  final Role role;
  MemberStatus status;
  final String name, phone, email, city;
  final bool teaches;
  final List<String> subjects;
  List<String> batchIds;
  final List<String> childUids, childNames;
  final String relation;
  String studentCode;
  int monthlyFee;
  final String joinedVia;
  final int createdAt;

  String get id => '${uid}_$instituteId';
  bool get approved => status == MemberStatus.approved;
  bool get isStaff => role == Role.admin || role == Role.teacher;
  bool get canTeach => role == Role.teacher || (role == Role.admin && teaches);

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'instituteId': instituteId,
        'instituteName': instituteName,
        'role': role.name,
        'status': status.name,
        'name': name,
        'phone': phone,
        'email': email,
        'city': city,
        'teaches': teaches,
        'subjects': subjects,
        'batchIds': batchIds,
        'childUids': childUids,
        'childNames': childNames,
        'relation': relation,
        'studentCode': studentCode,
        'monthlyFee': monthlyFee,
        'joinedVia': joinedVia,
        'createdAt': createdAt,
        'photo': photo,
        'discount': discount,
        'feeNote': feeNote,
        'salary': salary,
        'payType': payType,
        'upiId': upiId,
      };

  factory Membership.fromMap(Map<String, dynamic> m) => Membership(
        uid: _s(m['uid']),
        instituteId: _s(m['instituteId']),
        instituteName: _s(m['instituteName']),
        role: roleFrom(_s(m['role'])),
        status: MemberStatus.values.firstWhere((s) => s.name == _s(m['status']), orElse: () => MemberStatus.pending),
        name: _s(m['name']),
        phone: _s(m['phone']),
        email: _s(m['email']),
        city: _s(m['city']),
        teaches: _b(m['teaches']),
        subjects: _ls(m['subjects']),
        batchIds: _ls(m['batchIds']),
        childUids: _ls(m['childUids']),
        childNames: _ls(m['childNames']),
        relation: _s(m['relation']),
        studentCode: _s(m['studentCode']),
        monthlyFee: _i(m['monthlyFee']),
        joinedVia: _s(m['joinedVia']),
        createdAt: _i(m['createdAt']),
        photo: _s(m['photo']),
        discount: _i(m['discount']),
        feeNote: _s(m['feeNote']),
        salary: _i(m['salary']),
        payType: _s(m['payType']).isEmpty ? 'fixed' : _s(m['payType']),
        upiId: _s(m['upiId']),
      );
}

/// Days are 1 = Monday ... 7 = Sunday (same as DateTime.weekday).
class Batch {
  Batch({
    required this.id,
    required this.instituteId,
    required this.subject,
    required this.className,
    required this.days,
    required this.startMin,
    required this.endMin,
    required this.teacherUid,
    required this.teacherName,
    required this.code,
  });

  final String id, instituteId, subject, className;
  final List<int> days;
  final int startMin, endMin; // minutes from midnight
  final String teacherUid, teacherName, code;

  String get title => '$subject · $className';
  bool runsOn(DateTime d) => days.contains(d.weekday);

  Map<String, dynamic> toMap() => {
        'id': id,
        'instituteId': instituteId,
        'subject': subject,
        'className': className,
        'days': days,
        'startMin': startMin,
        'endMin': endMin,
        'teacherUid': teacherUid,
        'teacherName': teacherName,
        'code': code,
      };

  factory Batch.fromMap(Map<String, dynamic> m) => Batch(
        id: _s(m['id']),
        instituteId: _s(m['instituteId']),
        subject: _s(m['subject']),
        className: _s(m['className']),
        days: _li(m['days']),
        startMin: _i(m['startMin']),
        endMin: _i(m['endMin']),
        teacherUid: _s(m['teacherUid']),
        teacherName: _s(m['teacherName']),
        code: _s(m['code']),
      );
}

/// What a join code points to.
enum CodeType { institute, batch, student }

class JoinCode {
  const JoinCode({
    required this.code,
    required this.type,
    required this.instituteId,
    required this.instituteName,
    this.batchId = '',
    this.batchTitle = '',
    this.teacherName = '',
    this.studentUid = '',
    this.studentName = '',
    this.createdBy = '',
  });

  final String code;
  final CodeType type;
  final String instituteId, instituteName, batchId, batchTitle, teacherName, studentUid, studentName, createdBy;

  Map<String, dynamic> toMap() => {
        'code': code,
        'type': type.name,
        'instituteId': instituteId,
        'instituteName': instituteName,
        'batchId': batchId,
        'batchTitle': batchTitle,
        'teacherName': teacherName,
        'studentUid': studentUid,
        'studentName': studentName,
        'createdBy': createdBy,
      };

  factory JoinCode.fromMap(Map<String, dynamic> m) => JoinCode(
        code: _s(m['code']),
        type: CodeType.values.firstWhere((t) => t.name == _s(m['type']), orElse: () => CodeType.batch),
        instituteId: _s(m['instituteId']),
        instituteName: _s(m['instituteName']),
        batchId: _s(m['batchId']),
        batchTitle: _s(m['batchTitle']),
        teacherName: _s(m['teacherName']),
        studentUid: _s(m['studentUid']),
        studentName: _s(m['studentName']),
        createdBy: _s(m['createdBy']),
      );
}

/// Attendance of one batch on one day. Document id "<batchId>_<yyyymmdd>".
class AttendanceDay {
  AttendanceDay({required this.batchId, required this.dateKey, required this.marked, required this.present});
  final String batchId, dateKey;
  final List<String> marked, present;

  String get id => '${batchId}_$dateKey';

  Map<String, dynamic> toMap() => {'batchId': batchId, 'dateKey': dateKey, 'marked': marked, 'present': present};
  factory AttendanceDay.fromMap(Map<String, dynamic> m) =>
      AttendanceDay(batchId: _s(m['batchId']), dateKey: _s(m['dateKey']), marked: _ls(m['marked']), present: _ls(m['present']));
}

/// One student's fee for one month. Document id "<studentUid>_<yyyy-mm>".
class FeeRecord {
  FeeRecord({
    required this.studentUid,
    required this.studentName,
    required this.month,
    required this.amount,
    this.paid = false,
    this.paidOn = 0,
    this.mode = '',
    this.receiptNo = '',
    this.utr = '',
    this.paidBy = '',
    this.claimed = false,
    this.claimUtr = '',
    this.claimBy = '',
    this.claimByUid = '',
    this.claimVia = '',
    this.claimAt = 0,
    this.lateFee = 0,
    List<FeePart>? parts,
  }) : parts = parts ?? [];

  final String studentUid, studentName, month;
  final int amount;
  /// Late fee included in [amount].
  int lateFee;
  /// Part payments (instalments) received before the whole fee is paid.
  final List<FeePart> parts;
  int get paidSoFar => paid ? amount : parts.fold<int>(0, (a, p) => a + p.amount);
  int get balance => paid ? 0 : (amount - paidSoFar).clamp(0, amount);
  bool get partly => !paid && parts.isNotEmpty;
  bool paid;
  int paidOn;
  String mode, receiptNo;
  /// UTR of a confirmed UPI payment, and who paid (name).
  String utr, paidBy;
  /// A student/parent says they paid by UPI; waiting for the institute to confirm.
  bool claimed;
  String claimUtr, claimBy, claimByUid, claimVia;
  int claimAt;

  String get id => '${studentUid}_$month';
  bool get waiting => claimed && !paid;

  Map<String, dynamic> toMap() => {
        'studentUid': studentUid,
        'studentName': studentName,
        'month': month,
        'amount': amount,
        'paid': paid,
        'paidOn': paidOn,
        'mode': mode,
        'receiptNo': receiptNo,
        'utr': utr,
        'paidBy': paidBy,
        'claimed': claimed,
        'claimUtr': claimUtr,
        'claimBy': claimBy,
        'claimByUid': claimByUid,
        'claimVia': claimVia,
        'claimAt': claimAt,
        'lateFee': lateFee,
        'parts': parts.map((p) => p.toMap()).toList(),
      };

  factory FeeRecord.fromMap(Map<String, dynamic> m) => FeeRecord(
        studentUid: _s(m['studentUid']),
        studentName: _s(m['studentName']),
        month: _s(m['month']),
        amount: _i(m['amount']),
        paid: _b(m['paid']),
        paidOn: _i(m['paidOn']),
        mode: _s(m['mode']),
        receiptNo: _s(m['receiptNo']),
        utr: _s(m['utr']),
        paidBy: _s(m['paidBy']),
        claimed: _b(m['claimed']),
        claimUtr: _s(m['claimUtr']),
        claimBy: _s(m['claimBy']),
        claimByUid: _s(m['claimByUid']),
        claimVia: _s(m['claimVia']),
        claimAt: _i(m['claimAt']),
        lateFee: _i(m['lateFee']),
        parts: _lm(m['parts']).map(FeePart.fromMap).toList(),
      );
}

class Notice {
  Notice({required this.id, required this.text, required this.kind, required this.byName, required this.createdAt, this.batchId = ''});
  final String id, text, kind, byName, batchId; // kind: general | holiday | cancel | fees
  final int createdAt;

  Map<String, dynamic> toMap() => {'id': id, 'text': text, 'kind': kind, 'byName': byName, 'createdAt': createdAt, 'batchId': batchId};
  factory Notice.fromMap(Map<String, dynamic> m) => Notice(
        id: _s(m['id']),
        text: _s(m['text']),
        kind: _s(m['kind']).isEmpty ? 'general' : _s(m['kind']),
        byName: _s(m['byName']),
        createdAt: _i(m['createdAt']),
        batchId: _s(m['batchId']),
      );
}

// ---------- small helpers shared by both stores ----------

String dateKey(DateTime d) => '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
String monthKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

DateTime dateFromKey(String k) {
  if (k.length != 8) return DateTime.now();
  return DateTime(int.parse(k.substring(0, 4)), int.parse(k.substring(4, 6)), int.parse(k.substring(6, 8)));
}

String timeLabel(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  final ap = h >= 12 ? 'PM' : 'AM';
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${m.toString().padLeft(2, '0')} $ap';
}

/// Short name for a set of days: MWF, TTS, Mon–Sat, Daily or a list.
String daysCode(List<int> days) {
  final s = [...days]..sort();
  String j(List<int> x) => x.join(',');
  if (j(s) == '1,3,5') return 'MWF';
  if (j(s) == '2,4,6') return 'TTS';
  if (j(s) == '1,2,3,4,5,6') return 'Mon–Sat';
  if (j(s) == '1,2,3,4,5,6,7') return 'Daily';
  if (j(s) == '1,2,3,4,5') return 'Mon–Fri';
  const n = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return s.map((d) => n[d]).join(', ');
}

// ---------------------------------------------------------------------------
// Phase 2: study material, tests, doubts
// ---------------------------------------------------------------------------

List<Map<String, dynamic>> _lm(Object? v) => v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];

/// kinds: video | notes | homework | paper | photo | important | syllabus | link
class Resource {
  Resource({
    required this.id,
    required this.kind,
    required this.title,
    this.desc = '',
    this.batchId = '',
    this.chapter = '',
    this.url = '',
    this.images = const [],
    this.dueAt = 0,
    this.byUid = '',
    this.byName = '',
    this.createdAt = 0,
  });
  final String id, kind, title, desc, batchId, chapter, url, byUid, byName;
  final List<String> images; // small base64 JPEGs (board photos)
  final int dueAt, createdAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'kind': kind,
        'title': title,
        'desc': desc,
        'batchId': batchId,
        'chapter': chapter,
        'url': url,
        'images': images,
        'dueAt': dueAt,
        'byUid': byUid,
        'byName': byName,
        'createdAt': createdAt,
      };
  factory Resource.fromMap(Map<String, dynamic> m) => Resource(
        id: _s(m['id']),
        kind: switch (_s(m['kind'])) { '' => 'notes', 'video' => 'videos', 'link' => 'links', 'paper' => 'papers', final k => k },
        title: _s(m['title']),
        desc: _s(m['desc']),
        batchId: _s(m['batchId']),
        chapter: _s(m['chapter']),
        url: _s(m['url']),
        images: _ls(m['images']),
        dueAt: _i(m['dueAt']),
        byUid: _s(m['byUid']),
        byName: _s(m['byName']),
        createdAt: _i(m['createdAt']),
      );
}

/// A student's homework answer. Id "<resourceId>_<studentUid>".
class Submission {
  Submission({
    required this.resourceId,
    required this.studentUid,
    required this.studentName,
    this.text = '',
    this.images = const [],
    this.submittedAt = 0,
    this.checked = false,
    this.marks = '',
    this.remark = '',
  });
  final String resourceId, studentUid, studentName, text;
  final List<String> images;
  final int submittedAt;
  bool checked;
  String marks, remark;

  String get id => '${resourceId}_$studentUid';
  Map<String, dynamic> toMap() => {
        'resourceId': resourceId,
        'studentUid': studentUid,
        'studentName': studentName,
        'text': text,
        'images': images,
        'submittedAt': submittedAt,
        'checked': checked,
        'marks': marks,
        'remark': remark,
      };
  factory Submission.fromMap(Map<String, dynamic> m) => Submission(
        resourceId: _s(m['resourceId']),
        studentUid: _s(m['studentUid']),
        studentName: _s(m['studentName']),
        text: _s(m['text']),
        images: _ls(m['images']),
        submittedAt: _i(m['submittedAt']),
        checked: _b(m['checked']),
        marks: _s(m['marks']),
        remark: _s(m['remark']),
      );
}

class TestPaper {
  TestPaper({
    required this.id,
    required this.batchId,
    required this.title,
    required this.subject,
    required this.maxMarks,
    required this.date,
    this.published = false,
    Map<String, double>? marks,
    this.byName = '',
    Map<String, String>? names,
  })  : marks = marks ?? {},
        names = names ?? {};
  final String id, batchId, title, subject, byName;
  final int maxMarks;
  final int date; // ms
  bool published;
  final Map<String, double> marks; // studentUid -> marks
  final Map<String, String> names; // studentUid -> name (so students can see a leaderboard)

  double? get average => marks.isEmpty ? null : marks.values.reduce((a, b) => a + b) / marks.length;
  double? get highest => marks.isEmpty ? null : marks.values.reduce((a, b) => a > b ? a : b);
  int rankOf(String uid) {
    final m = marks[uid];
    if (m == null) return 0;
    return marks.values.where((v) => v > m).length + 1;
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'batchId': batchId,
        'title': title,
        'subject': subject,
        'maxMarks': maxMarks,
        'date': date,
        'published': published,
        'marks': marks,
        'byName': byName,
        'names': names,
      };
  factory TestPaper.fromMap(Map<String, dynamic> m) => TestPaper(
        id: _s(m['id']),
        batchId: _s(m['batchId']),
        title: _s(m['title']),
        subject: _s(m['subject']),
        maxMarks: _i(m['maxMarks']) == 0 ? 100 : _i(m['maxMarks']),
        date: _i(m['date']),
        published: _b(m['published']),
        marks: m['marks'] is Map ? (m['marks'] as Map).map((k, v) => MapEntry(k.toString(), v is num ? v.toDouble() : double.tryParse('$v') ?? 0)) : {},
        byName: _s(m['byName']),
        names: m['names'] is Map ? (m['names'] as Map).map((k, v) => MapEntry(k.toString(), v.toString())) : {},
      );
}

class DoubtReply {
  const DoubtReply({required this.byUid, required this.byName, required this.text, required this.at, this.staff = false, this.image = ''});
  final String byUid, byName, text, image;
  final int at;
  final bool staff;
  Map<String, dynamic> toMap() => {'byUid': byUid, 'byName': byName, 'text': text, 'at': at, 'staff': staff, 'image': image};
  factory DoubtReply.fromMap(Map<String, dynamic> m) =>
      DoubtReply(byUid: _s(m['byUid']), byName: _s(m['byName']), text: _s(m['text']), at: _i(m['at']), staff: _b(m['staff']), image: _s(m['image']));
}

class Doubt {
  Doubt({
    required this.id,
    required this.batchId,
    required this.subject,
    required this.studentUid,
    required this.studentName,
    required this.text,
    this.image = '',
    required this.createdAt,
    List<DoubtReply>? replies,
    this.solved = false,
  }) : replies = replies ?? [];
  final String id, batchId, subject, studentUid, studentName, text, image;
  final int createdAt;
  final List<DoubtReply> replies;
  bool solved;

  bool get answered => replies.any((r) => r.staff);
  int get lastAt => replies.isEmpty ? createdAt : replies.last.at;

  Map<String, dynamic> toMap() => {
        'id': id,
        'batchId': batchId,
        'subject': subject,
        'studentUid': studentUid,
        'studentName': studentName,
        'text': text,
        'image': image,
        'createdAt': createdAt,
        'replies': replies.map((r) => r.toMap()).toList(),
        'solved': solved,
        'answered': answered,
      };
  factory Doubt.fromMap(Map<String, dynamic> m) => Doubt(
        id: _s(m['id']),
        batchId: _s(m['batchId']),
        subject: _s(m['subject']),
        studentUid: _s(m['studentUid']),
        studentName: _s(m['studentName']),
        text: _s(m['text']),
        image: _s(m['image']),
        createdAt: _i(m['createdAt']),
        replies: _lm(m['replies']).map(DoubtReply.fromMap).toList(),
        solved: _b(m['solved']),
      );
}

/// One instalment of a month's fee.
class FeePart {
  const FeePart({required this.amount, required this.at, this.mode = '', this.receiptNo = '', this.utr = '', this.by = ''});
  final int amount, at;
  final String mode, receiptNo, utr, by;
  Map<String, dynamic> toMap() => {'amount': amount, 'at': at, 'mode': mode, 'receiptNo': receiptNo, 'utr': utr, 'by': by};
  factory FeePart.fromMap(Map<String, dynamic> m) =>
      FeePart(amount: _i(m['amount']), at: _i(m['at']), mode: _s(m['mode']), receiptNo: _s(m['receiptNo']), utr: _s(m['utr']), by: _s(m['by']));
}

/// Money in or out of the institute (besides monthly fees). Salaries are
/// "out" entries with [refUid] = the teacher and [refId] "pay_<uid>_<month>".
class Txn {
  Txn({
    required this.id,
    required this.isIncome,
    required this.category,
    required this.amount,
    required this.date,
    this.note = '',
    this.mode = '',
    this.refUid = '',
    this.refName = '',
    this.byName = '',
  });
  final String id, category, note, mode, refUid, refName, byName;
  final bool isIncome;
  final int amount, date;
  String get month => monthKey(DateTime.fromMillisecondsSinceEpoch(date));

  Map<String, dynamic> toMap() => {
        'id': id,
        'isIncome': isIncome,
        'category': category,
        'amount': amount,
        'date': date,
        'month': month,
        'note': note,
        'mode': mode,
        'refUid': refUid,
        'refName': refName,
        'byName': byName,
      };
  factory Txn.fromMap(Map<String, dynamic> m) => Txn(
        id: _s(m['id']),
        isIncome: _b(m['isIncome']),
        category: _s(m['category']),
        amount: _i(m['amount']),
        date: _i(m['date']),
        note: _s(m['note']),
        mode: _s(m['mode']),
        refUid: _s(m['refUid']),
        refName: _s(m['refName']),
        byName: _s(m['byName']),
      );
}

/// Admission enquiry (CRM). status: new | contacted | demo | joined | lost
class Lead {
  Lead({
    required this.id,
    required this.name,
    this.phone = '',
    this.className = '',
    this.subject = '',
    this.source = '',
    this.status = 'new',
    this.note = '',
    this.followUp = 0,
    required this.createdAt,
    this.byName = '',
  });
  final String id;
  String name, phone, className, subject, source, status, note, byName;
  int followUp;
  final int createdAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'className': className,
        'subject': subject,
        'source': source,
        'status': status,
        'note': note,
        'followUp': followUp,
        'createdAt': createdAt,
        'byName': byName,
      };
  factory Lead.fromMap(Map<String, dynamic> m) => Lead(
        id: _s(m['id']),
        name: _s(m['name']),
        phone: _s(m['phone']),
        className: _s(m['className']),
        subject: _s(m['subject']),
        source: _s(m['source']),
        status: _s(m['status']).isEmpty ? 'new' : _s(m['status']),
        note: _s(m['note']),
        followUp: _i(m['followUp']),
        createdAt: _i(m['createdAt']),
        byName: _s(m['byName']),
      );
}

/// Teacher arrived / left. Id "<uid>_<dateKey>".
class CheckIn {
  CheckIn({required this.uid, required this.name, required this.dateKey, required this.inAt, this.outAt = 0, this.mode = '', this.dist = -1});
  final String uid, name, dateKey;
  final int inAt;

  /// "coaching" (checked in at the coaching), "online" (from home) or "" (no location rule).
  final String mode;

  /// Metres from the coaching when checking in (-1 = not measured).
  final int dist;
  int outAt;
  String get id => '${uid}_$dateKey';
  String get month => '${dateKey.substring(0, 4)}-${dateKey.substring(4, 6)}';
  Map<String, dynamic> toMap() => {'uid': uid, 'name': name, 'dateKey': dateKey, 'month': month, 'inAt': inAt, 'outAt': outAt, 'mode': mode, 'dist': dist};
  factory CheckIn.fromMap(Map<String, dynamic> m) => CheckIn(
        uid: _s(m['uid']),
        name: _s(m['name']),
        dateKey: _s(m['dateKey']),
        inAt: _i(m['inAt']),
        outAt: _i(m['outAt']),
        mode: _s(m['mode']),
        dist: m['dist'] == null ? -1 : _i(m['dist']),
      );
}

class Chapter {
  Chapter({required this.name, this.done = false, this.doneAt = 0});
  String name;
  bool done;
  int doneAt;
  Map<String, dynamic> toMap() => {'name': name, 'done': done, 'doneAt': doneAt};
  factory Chapter.fromMap(Map<String, dynamic> m) => Chapter(name: _s(m['name']), done: _b(m['done']), doneAt: _i(m['doneAt']));
}

/// Chapters of one batch and which are finished. Id = batchId.
class Syllabus {
  Syllabus({required this.batchId, List<Chapter>? chapters, this.updatedAt = 0}) : chapters = chapters ?? [];
  final String batchId;
  final List<Chapter> chapters;
  int updatedAt;
  int get done => chapters.where((c) => c.done).length;
  double get progress => chapters.isEmpty ? 0 : done / chapters.length;
  Map<String, dynamic> toMap() => {'batchId': batchId, 'chapters': chapters.map((c) => c.toMap()).toList(), 'updatedAt': updatedAt};
  factory Syllabus.fromMap(Map<String, dynamic> m) =>
      Syllabus(batchId: _s(m['batchId']), chapters: _lm(m['chapters']).map(Chapter.fromMap).toList(), updatedAt: _i(m['updatedAt']));
}
