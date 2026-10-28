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
  const AppUser({required this.uid, required this.name, required this.email, required this.countryCode, required this.phone, required this.address, this.viaGoogle = false});
  final String uid, name, email, countryCode, phone;
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
      };

  factory AppUser.fromMap(Map<String, dynamic> m) => AppUser(
        uid: _s(m['uid']),
        name: _s(m['name']),
        email: _s(m['email']),
        countryCode: _s(m['countryCode']).isEmpty ? '+91' : _s(m['countryCode']),
        phone: _s(m['phone']),
        address: Address.fromMap(m['address'] is Map ? Map<String, dynamic>.from(m['address'] as Map) : null),
        viaGoogle: _b(m['viaGoogle']),
      );
}

class Institute {
  const Institute({required this.id, required this.name, required this.city, required this.code, required this.ownerUid});
  final String id, name, city, code, ownerUid;

  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'city': city, 'code': code, 'ownerUid': ownerUid};
  factory Institute.fromMap(Map<String, dynamic> m) =>
      Institute(id: _s(m['id']), name: _s(m['name']), city: _s(m['city']), code: _s(m['code']), ownerUid: _s(m['ownerUid']));
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
  });

  final String uid, instituteId, instituteName;
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
  });

  final String studentUid, studentName, month;
  final int amount;
  bool paid;
  int paidOn;
  String mode, receiptNo;

  String get id => '${studentUid}_$month';

  Map<String, dynamic> toMap() => {
        'studentUid': studentUid,
        'studentName': studentName,
        'month': month,
        'amount': amount,
        'paid': paid,
        'paidOn': paidOn,
        'mode': mode,
        'receiptNo': receiptNo,
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
