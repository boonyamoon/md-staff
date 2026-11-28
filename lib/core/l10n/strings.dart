import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_failure.dart';

/// Thai and English, Thai first — the same two languages, in the same order of priority, as the
/// POS, the kiosk and the customer QR app. Kept as a plain map rather than ARB/gen-l10n so the
/// whole app's copy is readable in one file; there are only a few dozen strings.
enum AppLanguage {
  th('ไทย', Locale('th')),
  en('English', Locale('en'));

  const AppLanguage(this.label, this.locale);

  final String label;
  final Locale locale;
}

final languageProvider = NotifierProvider<LanguageController, AppLanguage>(
  LanguageController.new,
);

class LanguageController extends Notifier<AppLanguage> {
  @override
  AppLanguage build() => AppLanguage.th;

  void set(AppLanguage language) => state = language;

  void toggle() => state = state == AppLanguage.th ? AppLanguage.en : AppLanguage.th;
}

final stringsProvider = Provider<AppStrings>(
  (ref) => AppStrings(ref.watch(languageProvider)),
);

/// Looks a key up in the current language, falling back to Thai and then to the key itself, so a
/// missing translation shows readable text instead of an empty label.
class AppStrings {
  const AppStrings(this.language);

  final AppLanguage language;

  bool get isThai => language == AppLanguage.th;

  String call(String key) {
    final table = language == AppLanguage.en ? _en : _th;
    return table[key] ?? _th[key] ?? key;
  }

  /// The text to show staff for a failed call. The server's own `message` is English and, for a
  /// missing endpoint, a developer-facing "Route not found" — so the cases the app can recognise
  /// are phrased here, in the current language, and only an unrecognised one falls back to what
  /// the server said.
  String failure(ApiFailure failure) {
    if (failure.isOffline) return call('error.offline');
    if (failure.endsSession) return call('error.sessionEnded');
    if (failure.isMissingRoute) return call('error.serviceUnavailable');
    final known = _failureKeys[failure.code];
    if (known != null) return call(known);
    if (failure.code == 'RATE_LIMIT_EXCEEDED') return call('error.rateLimited');
    if (failure.code == 'SERVER_ERROR') return call('error.server');
    return failure.message;
  }

  /// Refusals the table menu can meet, phrased here rather than in the server's English.
  static const Map<String, String> _failureKeys = {
    'TABLE_HAS_ORDER': 'error.tableHasOrder',
    'TABLE_SESSION_CHANGED': 'error.tableChanged',
    'ORDER_ITEM_NOT_ON_TABLE': 'error.tableChanged',
    'TABLE_NOT_OPEN': 'error.tableChanged',
    'TABLE_NOT_MERGED': 'error.tableChanged',
    'TABLE_NOT_AVAILABLE': 'error.tableChanged',
    'SESSION_NOT_ACTIVE': 'error.tableChanged',
    'CANNOT_UNMERGE_LAST_TABLE': 'error.tableChanged',
    'CANNOT_UNMERGE_PRIMARY_TABLE': 'error.unmergePrimary',
    'DESTINATION_TABLE_NOT_AVAILABLE': 'error.destinationBusy',
    'TABLE_ALREADY_MAPPED': 'error.destinationBusy',
    'DESTINATION_TABLE_CLAIMED': 'error.destinationClaimed',
    'SESSION_PENDING_PAYMENT': 'error.pendingPayment',
    'CONCURRENT_MODIFICATION': 'error.concurrent',
  };

  /// [call], with `{0}`, `{1}`… replaced by [values].
  String format(String key, List<Object> values) {
    var text = call(key);
    for (var i = 0; i < values.length; i++) {
      text = text.replaceAll('{$i}', '${values[i]}');
    }
    return text;
  }

  /// When a table was opened and how long ago: `Today 12:00 (5 min)`.
  String since(DateTime openedAt, {required DateTime now}) {
    final elapsed = now.difference(openedAt);
    final minutes = elapsed.isNegative ? 0 : elapsed.inMinutes;
    final duration = switch (minutes) {
      < 60 => '$minutes ${call('sheet.minutes')}',
      < 24 * 60 => '${minutes ~/ 60} ${call('sheet.hours')}'
          '${minutes % 60 == 0 ? '' : ' ${minutes % 60} ${call('sheet.minutes')}'}',
      _ => '${elapsed.inDays} ${call('sheet.days')}',
    };
    final at = time(openedAt, now: now);
    // [time] puts the date in front itself on any other day.
    final day = at.contains('/') ? at : '${call('sheet.today')} $at';
    return '$day ($duration)';
  }

  /// A time of day as `14:32`, with the date in front when it was not today.
  String time(DateTime at, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final clock = '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    final sameDay = at.year == today.year && at.month == today.month && at.day == today.day;
    return sameDay ? clock : '${at.day}/${at.month} $clock';
  }

  /// Money, always with two decimals: `1,250.00`.
  String money(num amount) {
    // Rounded first, so that a stray fraction below zero cannot print as "-0.00".
    final parts = ((amount * 100).round() / 100).toStringAsFixed(2).split('.');
    final digits = parts.first.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (m) => '${m[1]},',
    );
    return '$digits.${parts.last}';
  }

  static const Map<String, String> _th = {
    'app.name': 'MeeD Staff',
    'common.ok': 'ตกลง',
    'common.cancel': 'ยกเลิก',
    'common.back': 'ย้อนกลับ',
    'common.retry': 'ลองใหม่',
    'common.close': 'ปิด',
    'common.confirm': 'ยืนยัน',
    'common.loading': 'กำลังโหลด',
    'common.search': 'ค้นหา',
    'common.total': 'รวม',
    'common.baht': 'บาท',
    'common.items': 'รายการ',
    'common.offline': 'ไม่ได้เชื่อมต่อเซิร์ฟเวอร์',
    'common.offlineShort': 'ออฟไลน์',
    'common.dataAsOf': 'ข้อมูลเมื่อ',
    'common.refresh': 'รีเฟรช',
    'floor.title': 'ผังโต๊ะ',
    'common.tryAgain': 'กรุณาลองใหม่',
    'common.required': 'จำเป็น',
    'common.optional': 'ไม่บังคับ',
    'common.note': 'หมายเหตุ',
    'setup.title': 'เข้าสู่ระบบพนักงาน',
    'setup.signIn': 'เข้าสู่ระบบ',
    'setup.email': 'อีเมล',
    'setup.password': 'รหัสผ่าน',
    'setup.missingCredentials': 'กรุณากรอกอีเมลและรหัสผ่าน',
    'setup.chooseBranch': 'เลือกสาขา',
    'setup.chooseTerminal': 'เลือกเครื่อง',
    'setup.autoTerminal': 'ให้ระบบเลือกเครื่องที่ว่าง',
    'setup.deviceName': 'ชื่อเครื่อง',
    'setup.finish': 'เข้าใช้งาน',
    'setup.noBusiness': 'บัญชีนี้ยังไม่มีร้าน',
    'setup.noPermission': 'บัญชีนี้ไม่ได้รับสิทธิ์ใช้เครื่องพนักงาน\nให้ผู้จัดการเปิดสิทธิ์ "ใช้แอปพนักงาน" ให้ที่ backoffice',
    'setup.noTerminal': 'สาขานี้ยังไม่มีเครื่องพนักงานที่ว่าง\nให้สร้าง terminal ชนิด STAFF ใน backoffice ก่อน',
    'setup.terminalTaken': 'เครื่องนี้ถูกผูกกับอุปกรณ์อื่นแล้ว',
    'setup.terminalFree': 'ว่าง',
    'setup.allTaken': 'ไม่มีเครื่องว่าง ระบบจะใช้เครื่องที่ไม่ได้ใช้งานนานที่สุด และอุปกรณ์เดิมจะถูกออกจากระบบ',
    'setup.intro': 'เข้าสู่ระบบด้วยอีเมลของคุณ ทำครั้งเดียวต่อเครื่อง หลังจากนี้ไม่ต้องเข้าสู่ระบบอีก',
    'login.wrongCredentials': 'อีเมลหรือรหัสผ่านไม่ถูกต้อง',
    'login.signedOut': 'เครื่องนี้ถูกออกจากระบบแล้ว กรุณาเข้าสู่ระบบใหม่',
    'zones.empty': 'สาขานี้ยังไม่มีโซนหรือโต๊ะ',
    'tables.empty': 'โซนนี้ยังไม่มีโต๊ะ',
    'tables.free': 'ว่าง',
    'tables.notOrdered': 'ยังไม่ได้สั่ง',
    'tables.waiting': 'รออาหาร',
    'tables.served': 'เสิร์ฟครบแล้ว',
    'tables.outOfService': 'งดใช้',
    'tables.heldByMe': 'คุณกำลังสั่ง',
    'tables.heldBy': 'กำลังสั่งโดย',
    'tables.pendingPayment': 'กำลังชำระที่แคชเชียร์',
    'tables.guests': 'ที่นั่ง',
    'tables.round': 'รอบ',
    'claim.held.title': 'โต๊ะนี้มีคนกำลังสั่ง',
    'claim.held.body': 'กำลังสั่งอยู่ที่เครื่องอื่น รอให้เสร็จ หรือให้ผู้จัดการใส่ PIN เพื่อแย่งสิทธิ์',
    'claim.takeOver': 'แย่งสิทธิ์ด้วย PIN ผู้จัดการ',
    'claim.managerPin': 'PIN ผู้จัดการ',
    'claim.tookOver': 'รับสิทธิ์โต๊ะนี้แล้ว',
    'claim.lost.title': 'โต๊ะนี้ไม่ใช่ของคุณแล้ว',
    'claim.lost.body': 'มีผู้จัดการแย่งสิทธิ์โต๊ะนี้ไป รายการในตะกร้ายังไม่ถูกส่งเข้าครัว',
    'claim.releasing': 'กำลังคืนโต๊ะ',
    'claim.pinRequired': 'กรุณาใส่ PIN ผู้จัดการ 4-10 หลัก',
    'claim.pinWrong': 'PIN ไม่ถูกต้อง หรือพนักงานคนนั้นไม่มีสิทธิ์แย่งโต๊ะ',
    'menu.title': 'เมนู',
    'menu.all': 'ทั้งหมด',
    'menu.empty': 'ไม่พบสินค้า',
    'menu.soldOut': 'หมด',
    'menu.addToCart': 'เพิ่มลงตะกร้า',
    'menu.chooseOptions': 'เลือกตัวเลือก',
    'menu.chooseSize': 'เลือกขนาด',
    'menu.notePlaceholder': 'เช่น ไม่ใส่ผัก',
    'menu.searchPlaceholder': 'ค้นหาเมนู',
    'cart.title': 'ตะกร้า',
    'cart.empty': 'ยังไม่มีรายการในตะกร้า',
    'cart.send': 'ส่งเข้าครัว',
    'cart.sending': 'กำลังส่ง',
    'cart.sent': 'ส่งเข้าครัวแล้ว',
    'cart.sentPrinting': 'ส่งเข้าครัวแล้ว ใบออเดอร์จะพิมพ์ที่เครื่อง POS',
    'cart.noPrinter': 'ส่งเข้าครัวแล้ว แต่สาขานี้ยังไม่ได้ตั้งเครื่องพิมพ์ใบออเดอร์',
    'cart.alreadySent': 'รอบนี้ถูกส่งไปแล้ว ไม่ได้ส่งซ้ำ',
    'cart.clear': 'ล้างตะกร้า',
    'cart.clearConfirm': 'ล้างรายการทั้งหมดในตะกร้า',
    'cart.guests': 'จำนวนลูกค้า',
    'kitchen.pending': 'รอส่งเข้าครัว',
    'kitchen.sent': 'ส่งเข้าครัวแล้ว',
    'kitchen.preparing': 'กำลังทำ',
    'kitchen.ready': 'พร้อมเสิร์ฟ',
    'kitchen.served': 'เสิร์ฟแล้ว',
    'kitchen.cancelled': 'ยกเลิก',
    'bill.title': 'รายการที่สั่งแล้ว',
    'bill.empty': 'โต๊ะนี้ยังไม่มีรายการ',
    'bill.serve': 'เสิร์ฟ',
    'bill.serveAll': 'เสิร์ฟทั้งหมด',
    'bill.serveAllTitle': 'เสิร์ฟทั้งหมดของรอบที่ {0}?',
    'bill.serveAllBody': '{0} รายการจะเปลี่ยนเป็นเสิร์ฟแล้ว และเปลี่ยนกลับไม่ได้',
    'bill.round': 'รอบที่',
    'bill.subtotal': 'ยอดรวม',
    'bill.discount': 'ส่วนลด',
    'bill.serviceCharge': 'ค่าบริการ',
    'bill.tax': 'ภาษี',
    'bill.total': 'ยอดสุทธิ',
    'bill.payAtPos': 'ชำระเงินที่เครื่อง POS เท่านั้น',
    'bill.orderNumber': 'เลขที่ออเดอร์',
    'settings.title': 'ตั้งค่า',
    'settings.account': 'บัญชีและเครื่อง',
    'settings.language': 'ภาษา',
    'settings.terminal': 'เครื่อง',
    'settings.branch': 'สาขา',
    'settings.staff': 'พนักงาน',
    'settings.version': 'เวอร์ชัน',
    'settings.signOut': 'ออกจากระบบ',
    'settings.signOutHint': 'คืนโต๊ะที่ถืออยู่ และปลดเครื่องนี้ให้คนอื่นเข้าใช้ได้',
    'settings.signOutConfirm': 'ออกจากระบบเครื่องนี้ คืนโต๊ะที่กำลังถืออยู่ทั้งหมด และต้องเข้าสู่ระบบใหม่ด้วยอีเมลเมื่อจะใช้งานอีก',
    'settings.printing': 'พิมพ์ใบออเดอร์ที่ POS',
    'settings.printingOn': 'เปิดใช้งาน',
    'settings.printingOff': 'สาขานี้ยังไม่ได้ตั้งเครื่องพิมพ์',
    'error.offline': 'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ กรุณาตรวจสอบอินเทอร์เน็ตแล้วลองใหม่',
    'error.serviceUnavailable': 'เซิร์ฟเวอร์ยังไม่รองรับการใช้งานนี้ กรุณาติดต่อผู้ดูแลระบบ',
    'error.rateLimited': 'ทำรายการถี่เกินไป กรุณารอสักครู่แล้วลองใหม่',
    'error.server': 'เซิร์ฟเวอร์ขัดข้อง กรุณาลองใหม่อีกครั้ง',
    'error.needOnline': 'ต้องออนไลน์จึงจะเปิดโต๊ะได้',
    'settings.menuData': 'ข้อมูลเมนู',
    'settings.updatedAt': 'อัปเดตล่าสุด',
    'settings.neverUpdated': 'ยังไม่เคยอัปเดต',
    'cart.earlierSent': 'ออเดอร์ชุดก่อนหน้าส่งเข้าครัวไปแล้ว ตรวจรายการที่สั่งแล้ว และลบรายการที่ซ้ำออกจากตะกร้าก่อนกดส่งอีกครั้ง',
    'table.gone.title': 'โต๊ะนี้เปลี่ยนไปแล้ว',
    'table.gone.body': 'ออเดอร์ของโต๊ะนี้ถูกยกเลิกหรือปิดแล้ว รายการในตะกร้ายังไม่ได้ส่งเข้าครัว และถูกล้างออก',
    'sheet.today': 'วันนี้',
    'sheet.minutes': 'นาที',
    'sheet.hours': 'ชม.',
    'sheet.days': 'วัน',
    'sheet.notOpened': 'ยังไม่ได้เปิดโต๊ะ',
    'sheet.notOrdered': 'ยังไม่ได้สั่งอาหาร',
    'sheet.order': 'สั่งอาหาร',
    'sheet.orderMore': 'สั่งเพิ่ม',
    'sheet.bill': 'บิล',
    'sheet.people': 'คน',
    'sheet.guests': 'จำนวนคน',
    'sheet.guestsFor': 'จำนวนลูกค้าโต๊ะ {0}',
    'sheet.qr': 'Mobile Order',
    'sheet.cancel': 'ยกเลิกโต๊ะ',
    'sheet.transfer': 'เปลี่ยนโต๊ะ',
    'sheet.merge': 'รวมโต๊ะ',
    'sheet.unmerge': 'แยกโต๊ะ',
    'sheet.heldNote': '{0} กำลังสั่งอยู่ · การแก้ไขต้องใช้ PIN ผู้จัดการ',
    'sheet.why.offline': 'ต้องออนไลน์จึงจะทำรายการได้',
    'sheet.why.free': 'โต๊ะนี้ยังไม่ได้เปิด',
    'sheet.why.hasOrder': 'โต๊ะมีรายการแล้ว ยกเลิกบิลได้ที่ POS',
    'sheet.cancelTitle': 'ยกเลิกโต๊ะ {0}?',
    'sheet.cancelBody': 'โต๊ะนี้ยังไม่ได้สั่งอาหาร ยกเลิกแล้วโต๊ะจะกลับเป็นว่าง',
    'sheet.cancelled': 'ยกเลิกโต๊ะ {0} แล้ว',
    'sheet.openTitle': 'เปิดโต๊ะ {0}',
    'sheet.openAndQr': 'เปิดโต๊ะและสร้าง QR',
    'sheet.guestsSaved': 'บันทึกจำนวนคนแล้ว',
    'sheet.transferPick': 'ย้ายโต๊ะ {0} ไปที่',
    'sheet.mergePick': 'เลือกโต๊ะว่างมารวมกับ {0}',
    'sheet.unmergePick': 'เลือกโต๊ะที่จะแยกออก',
    'sheet.noFreeTable': 'ไม่มีโต๊ะว่าง',
    'sheet.transferConfirm': 'ย้ายจากโต๊ะ {0} ไปโต๊ะ {1}?',
    'sheet.mergeConfirm': 'รวมโต๊ะ {1} เข้ากับโต๊ะ {0}?',
    'sheet.unmergeConfirm': 'แยกโต๊ะ {0} ออกจากกลุ่ม?',
    'sheet.transferred': 'ย้ายไปโต๊ะ {0} แล้ว',
    'sheet.merged': 'รวมโต๊ะ {0} แล้ว',
    'sheet.unmerged': 'แยกโต๊ะ {0} แล้ว',
    'qr.scan': 'ให้ลูกค้าสแกนเพื่อสั่งอาหาร',
    'qr.validUntil': 'ใช้ได้ถึง',
    'tables.mergedWith': 'รวมกับโต๊ะ',
    'error.tableHasOrder': 'โต๊ะมีรายการแล้ว ยกเลิกบิลได้ที่ POS',
    'error.tableChanged': 'โต๊ะนี้เปลี่ยนไปแล้ว กรุณาตรวจสอบอีกครั้ง',
    'error.destinationBusy': 'โต๊ะปลายทางไม่ว่างแล้ว กรุณาเลือกโต๊ะอื่น',
    'error.destinationClaimed': 'มีเครื่องอื่นกำลังใช้โต๊ะปลายทาง',
    'error.unmergePrimary': 'แยกโต๊ะหลักไม่ได้ ให้เปลี่ยนโต๊ะก่อน',
    'error.sessionEnded': 'เครื่องนี้ถูกออกจากระบบ กรุณาเข้าสู่ระบบใหม่',
    'error.pendingPayment': 'โต๊ะนี้กำลังชำระเงินที่ POS ยังเพิ่มรายการไม่ได้',
    'error.outOfStock': 'สินค้าบางรายการมีไม่พอ',
    'error.concurrent': 'มีคนแก้โต๊ะนี้พร้อมกัน กรุณาลองใหม่',
  };

  static const Map<String, String> _en = {
    'app.name': 'MeeD Staff',
    'common.ok': 'OK',
    'common.cancel': 'Cancel',
    'common.back': 'Back',
    'common.retry': 'Retry',
    'common.close': 'Close',
    'common.confirm': 'Confirm',
    'common.loading': 'Loading',
    'common.search': 'Search',
    'common.total': 'Total',
    'common.baht': 'THB',
    'common.items': 'items',
    'common.offline': 'No connection to the server',
    'common.offlineShort': 'Offline',
    'common.dataAsOf': 'as of',
    'common.refresh': 'Refresh',
    'floor.title': 'Floor',
    'common.tryAgain': 'Please try again',
    'common.required': 'Required',
    'common.optional': 'Optional',
    'common.note': 'Note',
    'setup.title': 'Staff sign-in',
    'setup.signIn': 'Sign in',
    'setup.email': 'Email',
    'setup.password': 'Password',
    'setup.missingCredentials': 'Enter an email and password',
    'setup.chooseBranch': 'Choose a branch',
    'setup.chooseTerminal': 'Choose a terminal',
    'setup.autoTerminal': 'Let the server pick a free terminal',
    'setup.deviceName': 'Device name',
    'setup.finish': 'Start using it',
    'setup.noBusiness': 'This account has no store yet',
    'setup.noPermission': 'This account may not use staff handsets.\nAsk a manager to switch on staff-app login for it in the back office.',
    'setup.noTerminal': 'No free staff terminal in this branch.\nCreate one (type STAFF) in the back office first.',
    'setup.terminalTaken': 'That terminal is already paired with another device',
    'setup.terminalFree': 'Available',
    'setup.allTaken': 'No terminal is free. The one idle the longest will be used, and the device on it will be signed out.',
    'setup.intro': 'Sign in with your own email. Once per phone — you will not be asked again.',
    'login.wrongCredentials': 'Wrong email or password',
    'login.signedOut': 'This handset was signed out. Please sign in again.',
    'zones.empty': 'This branch has no zones or tables yet',
    'tables.empty': 'This zone has no tables yet',
    'tables.free': 'Free',
    'tables.notOrdered': 'Not ordered',
    'tables.waiting': 'Waiting for food',
    'tables.served': 'All served',
    'tables.outOfService': 'Out of service',
    'tables.heldByMe': 'You are ordering',
    'tables.heldBy': 'Ordering:',
    'tables.pendingPayment': 'Paying at the POS',
    'tables.guests': 'seats',
    'tables.round': 'Round',
    'claim.held.title': 'Someone is ordering at this table',
    'claim.held.body':
        'Another handset has this table. Wait for them to finish, or have a manager enter their PIN to take it over.',
    'claim.takeOver': 'Take over with a manager PIN',
    'claim.managerPin': 'Manager PIN',
    'claim.tookOver': 'You have this table now',
    'claim.lost.title': 'This table is no longer yours',
    'claim.lost.body': 'A manager took this table over. Nothing in your cart was sent to the kitchen.',
    'claim.releasing': 'Giving the table back',
    'claim.pinRequired': 'Enter a manager PIN of 4 to 10 digits',
    'claim.pinWrong': 'Wrong PIN, or that staff member may not take over a table',
    'menu.title': 'Menu',
    'menu.all': 'All',
    'menu.empty': 'No products found',
    'menu.soldOut': 'Sold out',
    'menu.addToCart': 'Add to cart',
    'menu.chooseOptions': 'Choose options',
    'menu.chooseSize': 'Choose a size',
    'menu.notePlaceholder': 'e.g. no vegetables',
    'menu.searchPlaceholder': 'Search the menu',
    'cart.title': 'Cart',
    'cart.empty': 'Nothing in the cart yet',
    'cart.send': 'Send to kitchen',
    'cart.sending': 'Sending',
    'cart.sent': 'Sent to the kitchen',
    'cart.sentPrinting': 'Sent to the kitchen. The slip prints at the POS.',
    'cart.noPrinter': 'Sent to the kitchen, but this branch has no order-slip printer set up',
    'cart.alreadySent': 'This round was already sent — nothing was sent twice',
    'cart.clear': 'Clear cart',
    'cart.clearConfirm': 'Remove everything from the cart',
    'cart.guests': 'Guests',
    'kitchen.pending': 'Not sent yet',
    'kitchen.sent': 'Sent to kitchen',
    'kitchen.preparing': 'Preparing',
    'kitchen.ready': 'Ready',
    'kitchen.served': 'Served',
    'kitchen.cancelled': 'Cancelled',
    'bill.title': 'Already ordered',
    'bill.empty': 'Nothing ordered at this table yet',
    'bill.serve': 'Serve',
    'bill.serveAll': 'Serve all',
    'bill.serveAllTitle': 'Serve everything in round {0}?',
    'bill.serveAllBody': 'Items to be marked served: {0}. This cannot be undone.',
    'bill.round': 'Round',
    'bill.subtotal': 'Subtotal',
    'bill.discount': 'Discount',
    'bill.serviceCharge': 'Service charge',
    'bill.tax': 'Tax',
    'bill.total': 'Total',
    'bill.payAtPos': 'Payment is taken at the POS only',
    'bill.orderNumber': 'Order',
    'settings.title': 'Settings',
    'settings.account': 'Account and device',
    'settings.language': 'Language',
    'settings.terminal': 'Terminal',
    'settings.branch': 'Branch',
    'settings.staff': 'Staff',
    'settings.version': 'Version',
    'settings.signOut': 'Sign out',
    'settings.signOutHint': 'Gives back any tables held, and frees this phone for someone else',
    'settings.signOutConfirm':
        'Sign this handset out, give back every table it is holding, and require an email sign-in to use it again.',
    'settings.printing': 'Order slips at the POS',
    'settings.printingOn': 'On',
    'settings.printingOff': 'No printer configured for this branch',
    'error.offline': 'Cannot reach the server. Check the internet connection and try again.',
    'error.serviceUnavailable': 'The server does not support this yet. Please contact your administrator.',
    'error.rateLimited': 'Too many attempts. Please wait a moment and try again.',
    'error.server': 'Something went wrong on the server. Please try again.',
    'error.needOnline': 'You need to be online to open a table',
    'settings.menuData': 'Menu data',
    'settings.updatedAt': 'Last updated',
    'settings.neverUpdated': 'Not updated yet',
    'cart.earlierSent': 'An earlier send already reached the kitchen. Check the ordered items and remove duplicates from the cart before sending again.',
    'table.gone.title': 'This table has changed',
    'table.gone.body': 'Its order was cancelled or closed. The cart was not sent to the kitchen and has been cleared.',
    'sheet.today': 'Today',
    'sheet.minutes': 'min',
    'sheet.hours': 'h',
    'sheet.days': 'days',
    'sheet.notOpened': 'Not opened yet',
    'sheet.notOrdered': 'Nothing ordered yet',
    'sheet.order': 'Order',
    'sheet.orderMore': 'Order more',
    'sheet.bill': 'Bill',
    'sheet.people': 'guests',
    'sheet.guests': 'Guests',
    'sheet.guestsFor': 'Guests at table {0}',
    'sheet.qr': 'Mobile Order',
    'sheet.cancel': 'Cancel table',
    'sheet.transfer': 'Move table',
    'sheet.merge': 'Merge tables',
    'sheet.unmerge': 'Split table',
    'sheet.heldNote': '{0} is ordering · changes need a manager PIN',
    'sheet.why.offline': 'You need to be online to do that',
    'sheet.why.free': 'This table has not been opened',
    'sheet.why.hasOrder': 'This table has an order — cancel its bill at the POS',
    'sheet.cancelTitle': 'Cancel table {0}?',
    'sheet.cancelBody': 'Nothing has been ordered. The table will be free again.',
    'sheet.cancelled': 'Table {0} cancelled',
    'sheet.openTitle': 'Open table {0}',
    'sheet.openAndQr': 'Open the table and show the QR',
    'sheet.guestsSaved': 'Guest count saved',
    'sheet.transferPick': 'Move table {0} to',
    'sheet.mergePick': 'Pick a free table to merge with {0}',
    'sheet.unmergePick': 'Pick the table to split off',
    'sheet.noFreeTable': 'No free tables',
    'sheet.transferConfirm': 'Move from table {0} to table {1}?',
    'sheet.mergeConfirm': 'Merge table {1} into table {0}?',
    'sheet.unmergeConfirm': 'Split table {0} off the group?',
    'sheet.transferred': 'Moved to table {0}',
    'sheet.merged': 'Table {0} merged',
    'sheet.unmerged': 'Table {0} split off',
    'qr.scan': 'Guests scan this to order',
    'qr.validUntil': 'Valid until',
    'tables.mergedWith': 'Merged with table',
    'error.tableHasOrder': 'This table has an order — cancel its bill at the POS',
    'error.tableChanged': 'This table has changed. Please check it again.',
    'error.destinationBusy': 'That table is no longer free. Pick another one.',
    'error.destinationClaimed': 'Another handset is using that table',
    'error.unmergePrimary': 'The primary table cannot be split off — move the party first',
    'error.sessionEnded': 'This handset was signed out. Please sign in again.',
    'error.pendingPayment': 'This table is being paid for at the POS — items cannot be added',
    'error.outOfStock': 'Some items do not have enough stock',
    'error.concurrent': 'Someone changed this table at the same moment. Please try again.',
  };
}
