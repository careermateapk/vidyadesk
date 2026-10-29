// VidyaDesk subscription plans: what each plan gives and where a coaching stands.

/// UPI ID where coachings pay for VidyaDesk.
const ownerUpi = '7827862630@ptaxis';
const ownerPayee = 'VidyaDesk';

/// Accounts that see the owner panel (VidyaDesk owner).
const ownerEmails = {'support.sangam360@gmail.com'};

/// Test accounts: buying a plan takes no money (demo payment).
const demoPayEmails = {'ksuraj.th@gmail.com'};

/// True while the active coaching's plan has ended (3 days view-only).
bool planReadOnly = false;

/// True while the owner is looking at a coaching as its admin (nothing can be saved).
bool viewOnly = false;

const trialDays = 30;
const graceDays = 3;
const keepDataDays = 90;

/// Coachings made before plans existed get their trial until this date.
final legacyTrialEnd = DateTime(2026, 12, 1).millisecondsSinceEpoch;

enum Plan { trial, basic, standard, pro }

Plan planFrom(String s) => Plan.values.where((p) => p.name == s).firstOrNull ?? Plan.trial;

/// Paid plans in order.
const paidPlans = [Plan.basic, Plan.standard, Plan.pro];

/// (per month, per year) in rupees.
/// Changed by the owner (Owner panel → Plan prices); these are the starting values.
final Map<Plan, (int, int)> planPrice = {
  Plan.basic: (299, 2990),
  Plan.standard: (599, 5990),
  Plan.pro: (999, 9990),
};

/// (students, teachers). -1 = no limit.
final Map<Plan, (int, int)> planLimit = {
  Plan.trial: (-1, -1),
  Plan.basic: (50, 2),
  Plan.standard: (200, 10),
  Plan.pro: (-1, -1),
};

int planAmount(Plan p, bool yearly) => yearly ? planPrice[p]!.$2 : planPrice[p]!.$1;

/// Features that need a bigger plan.
enum Feature {
  upiFees, // students pay fees by UPI in the app
  feePlan, // fee plan, instalments, late fee, reminders
  tests, // tests, results, report cards
  doubts, // doubt box, leaderboard, badges
  accounts, // income-expenses
  payroll, // teacher salary by UPI
  admissions, // admissions CRM
  risk, // risk alert
  reports, // PDF / Excel reports
  checkin, // teacher location check-in
}

Plan minPlan(Feature f) => switch (f) {
      Feature.upiFees || Feature.feePlan || Feature.tests || Feature.doubts => Plan.standard,
      _ => Plan.pro,
    };

/// Feature list rows for the plan screens: (key, basic, standard, pro).
const planFeatureRows = [
  ('pf_attendance', true, true, true),
  ('pf_notices', true, true, true),
  ('pf_fees', true, true, true),
  ('pf_study', true, true, true),
  ('pf_apps', true, true, true),
  ('pf_upi', false, true, true),
  ('pf_feeplan', false, true, true),
  ('pf_tests', false, true, true),
  ('pf_doubts', false, true, true),
  ('pf_money', false, false, true),
  ('pf_crm', false, false, true),
  ('pf_reports', false, false, true),
  ('pf_checkin', false, false, true),
  ('pf_support', false, false, true),
];

enum PlanState { active, grace, locked }

/// Where one coaching's plan stands right now.
class PlanStatus {
  PlanStatus(this.plan, int until, {DateTime? now})
      : until = until <= 0 ? legacyTrialEnd : until,
        now = (now ?? DateTime.now()).millisecondsSinceEpoch;
  final Plan plan;
  final int until, now;

  static const _day = 86400000;

  PlanState get state => now < until
      ? PlanState.active
      : now < until + graceDays * _day
          ? PlanState.grace
          : PlanState.locked;

  bool get active => state == PlanState.active;
  bool get locked => state == PlanState.locked;
  bool get grace => state == PlanState.grace;
  bool get trial => plan == Plan.trial;

  /// Whole days left (rounded up). Negative after the end.
  int get daysLeft => ((until - now) / _day).ceil();

  /// Days left in the grace period before the app locks.
  int get graceLeft => ((until + graceDays * _day - now) / _day).ceil();

  /// Days left before data is deleted (after lock).
  int get dataLeft => ((until + keepDataDays * _day - now) / _day).ceil();

  DateTime get endDate => DateTime.fromMillisecondsSinceEpoch(until);

  /// Show the warning banner to the admin.
  bool get warn => trial || daysLeft <= 7;

  bool has(Feature f) {
    if (plan == Plan.trial) return true;
    return plan.index >= minPlan(f).index;
  }

  int get maxStudents => planLimit[plan]!.$1;
  int get maxTeachers => planLimit[plan]!.$2;

  /// The plan to renew with: the current paid plan, or Standard after a trial.
  Plan get renewPlan => plan == Plan.trial ? Plan.standard : plan;
}

/// Next end date after paying for [yearly] / monthly from [currentUntil].
int extendUntil(int currentUntil, bool yearly, {DateTime? now}) {
  final n = (now ?? DateTime.now()).millisecondsSinceEpoch;
  final from = DateTime.fromMillisecondsSinceEpoch(currentUntil > n ? currentUntil : n);
  final to = yearly ? DateTime(from.year + 1, from.month, from.day, from.hour, from.minute) : DateTime(from.year, from.month + 1, from.day, from.hour, from.minute);
  return to.millisecondsSinceEpoch;
}


/// Owner's price list from the server: {basic: [month, year, students, teachers], …}.
void applyPrices(Map<String, dynamic>? prices) {
  if (prices == null) return;
  for (final p in paidPlans) {
    final v = prices[p.name];
    if (v is List && v.length >= 4) {
      int n(Object? x) => x is num ? x.toInt() : int.tryParse('$x') ?? 0;
      planPrice[p] = (n(v[0]), n(v[1]));
      planLimit[p] = (n(v[2]), n(v[3]));
    }
  }
}

/// Features the owner can switch on/off (for everyone, some coachings, or nobody).
const flagFeatures = ['banners', 'doubtCrop', 'doubts', 'checkin', 'admissions', 'coupons'];
