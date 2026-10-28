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
  });
  final String id, name, city, code, ownerUid;
  final String address, phone, upiId, upiName;

  Institute copyWith({String? name, String? city, String? code, String? address, String? phone, String? upiId, String? upiName}) => Institute(
        id: id,
        ownerUid: ownerUid,
        name: name ?? this.name,
        city: city ?? this.city,
        code: code ?? this.code,
        address: address ?? this.address,
        phone: phone ?? this.phone,
        upiId: upiId ?? this.upiId,
        upiName: upiName ?? this.upiName,
      );

  Map<String, dynamic> toMap() =>
      {'id': id, 'name': name, 'city': city, 'code': code, 'ownerUid': ownerUid, 'address': address, 'phone': phone, 'upiId': upiId, 'upiName': upiName};
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
      );
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
  });

  final String uid, instituteId, instituteName;
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
  });

  final String studentUid, studentName, month;
  final int amount;
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
        kind: _s(m['kind']).isEmpty ? 'notes' : _s(m['kind']),
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
  }) : marks = marks ?? {};
  final String id, batchId, title, subject, byName;
  final int maxMarks;
  final int date; // ms
  bool published;
  final Map<String, double> marks; // studentUid -> marks

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
