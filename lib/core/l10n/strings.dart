import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  /// Money, formatted the way the POS prints it: no decimals when the amount is whole.
  String money(num amount) {
    final rounded = (amount * 100).round() / 100;
    final text = rounded == rounded.roundToDouble()
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(2);
    final parts = text.split('.');
    final digits = parts.first.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (m) => '${m[1]},',
    );
    return parts.length > 1 ? '$digits.${parts[1]}' : digits;
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
    'common.tryAgain': 'กรุณาลองใหม่',
    'common.required': 'จำเป็น',
    'common.optional': 'ไม่บังคับ',
    'common.note': 'หมายเหตุ',
    'setup.title': 'ตั้งค่าเครื่อง',
    'setup.signIn': 'เข้าสู่ระบบ',
    'setup.email': 'อีเมล',
    'setup.password': 'รหัสผ่าน',
    'setup.missingCredentials': 'กรุณากรอกอีเมลและรหัสผ่าน',
    'setup.chooseBranch': 'เลือกสาขา',
    'setup.chooseTerminal': 'เลือกเครื่อง',
    'setup.autoTerminal': 'ให้ระบบเลือกเครื่องที่ว่าง',
    'setup.deviceName': 'ชื่อเครื่อง',
    'setup.pair': 'ผูกเครื่อง',
    'setup.paired': 'ผูกเครื่องแล้ว',
    'setup.noBusiness': 'บัญชีนี้ยังไม่มีร้าน',
    'setup.noPermission': 'บัญชีนี้ไม่ได้รับสิทธิ์ใช้งานเครื่องพนักงานของสาขานี้',
    'setup.noTerminal': 'สาขานี้ยังไม่มีเครื่องพนักงานที่ว่าง\nให้สร้าง terminal ชนิด STAFF ใน backoffice ก่อน',
    'setup.terminalTaken': 'เครื่องนี้ถูกผูกกับอุปกรณ์อื่นแล้ว',
    'setup.intro': 'ผูกเครื่องนี้เข้ากับสาขา ทำครั้งเดียวต่อเครื่อง',
    'login.title': 'เข้าสู่ระบบพนักงาน',
    'login.subtitle': 'ใช้อีเมลเดียวกับที่ใช้กับ POS',
    'login.signIn': 'เข้าสู่ระบบ',
    'login.wrongCredentials': 'อีเมลหรือรหัสผ่านไม่ถูกต้อง',
    'login.shiftEnded': 'กะหมดอายุ กรุณาเข้าสู่ระบบอีกครั้ง',
    'shift.signOut': 'ออกจากกะ',
    'shift.signOutConfirm': 'ออกจากกะและคืนโต๊ะที่กำลังถืออยู่ทั้งหมด',
    'zones.title': 'เลือกโซน',
    'zones.empty': 'สาขานี้ยังไม่มีโซนหรือโต๊ะ',
    'zones.tables': 'โต๊ะ',
    'zones.free': 'ว่าง',
    'zones.busy': 'มีลูกค้า',
    'tables.title': 'เลือกโต๊ะ',
    'tables.empty': 'โซนนี้ยังไม่มีโต๊ะ',
    'tables.free': 'ว่าง',
    'tables.busy': 'มีลูกค้า',
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
    'bill.title': 'รายการที่สั่งแล้ว',
    'bill.empty': 'โต๊ะนี้ยังไม่มีรายการ',
    'bill.round': 'รอบที่',
    'bill.subtotal': 'ยอดรวม',
    'bill.discount': 'ส่วนลด',
    'bill.serviceCharge': 'ค่าบริการ',
    'bill.tax': 'ภาษี',
    'bill.total': 'ยอดสุทธิ',
    'bill.payAtPos': 'ชำระเงินที่เครื่อง POS เท่านั้น',
    'bill.orderNumber': 'เลขที่ออเดอร์',
    'settings.title': 'ตั้งค่า',
    'settings.language': 'ภาษา',
    'settings.terminal': 'เครื่อง',
    'settings.branch': 'สาขา',
    'settings.staff': 'พนักงาน',
    'settings.version': 'เวอร์ชัน',
    'settings.unpair': 'ยกเลิกการผูกเครื่อง',
    'settings.unpairConfirm': 'ยกเลิกการผูกเครื่องนี้ ต้องตั้งค่าใหม่ด้วยบัญชีผู้จัดการ',
    'settings.printing': 'พิมพ์ใบออเดอร์ที่ POS',
    'settings.printingOn': 'เปิดใช้งาน',
    'settings.printingOff': 'สาขานี้ยังไม่ได้ตั้งเครื่องพิมพ์',
    'error.deviceRevoked': 'เครื่องนี้ถูกยกเลิกการผูก กรุณาตั้งค่าใหม่',
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
    'common.tryAgain': 'Please try again',
    'common.required': 'Required',
    'common.optional': 'Optional',
    'common.note': 'Note',
    'setup.title': 'Set up this device',
    'setup.signIn': 'Sign in',
    'setup.email': 'Email',
    'setup.password': 'Password',
    'setup.missingCredentials': 'Enter an email and password',
    'setup.chooseBranch': 'Choose a branch',
    'setup.chooseTerminal': 'Choose a terminal',
    'setup.autoTerminal': 'Let the server pick a free terminal',
    'setup.deviceName': 'Device name',
    'setup.pair': 'Pair this device',
    'setup.paired': 'Device paired',
    'setup.noBusiness': 'This account has no store yet',
    'setup.noPermission': 'This account may not use staff handsets for this branch',
    'setup.noTerminal': 'No free staff terminal in this branch.\nCreate one (type STAFF) in the back office first.',
    'setup.terminalTaken': 'That terminal is already paired with another device',
    'setup.intro': 'Pair this phone with a branch. Once per device.',
    'login.title': 'Staff sign-in',
    'login.subtitle': 'The same email you use on the POS',
    'login.signIn': 'Sign in',
    'login.wrongCredentials': 'Wrong email or password',
    'login.shiftEnded': 'Your shift has ended, please sign in again',
    'shift.signOut': 'End shift',
    'shift.signOutConfirm': 'End the shift and give back every table this device is holding',
    'zones.title': 'Choose a zone',
    'zones.empty': 'This branch has no zones or tables yet',
    'zones.tables': 'tables',
    'zones.free': 'free',
    'zones.busy': 'busy',
    'tables.title': 'Choose a table',
    'tables.empty': 'This zone has no tables yet',
    'tables.free': 'Free',
    'tables.busy': 'Busy',
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
    'bill.title': 'Already ordered',
    'bill.empty': 'Nothing ordered at this table yet',
    'bill.round': 'Round',
    'bill.subtotal': 'Subtotal',
    'bill.discount': 'Discount',
    'bill.serviceCharge': 'Service charge',
    'bill.tax': 'Tax',
    'bill.total': 'Total',
    'bill.payAtPos': 'Payment is taken at the POS only',
    'bill.orderNumber': 'Order',
    'settings.title': 'Settings',
    'settings.language': 'Language',
    'settings.terminal': 'Terminal',
    'settings.branch': 'Branch',
    'settings.staff': 'Staff',
    'settings.version': 'Version',
    'settings.unpair': 'Unpair this device',
    'settings.unpairConfirm': 'Unpair this device. Setting it up again needs a manager account.',
    'settings.printing': 'Order slips at the POS',
    'settings.printingOn': 'On',
    'settings.printingOff': 'No printer configured for this branch',
    'error.deviceRevoked': 'This device was unpaired. Set it up again.',
    'error.pendingPayment': 'This table is being paid for at the POS — items cannot be added',
    'error.outOfStock': 'Some items do not have enough stock',
    'error.concurrent': 'Someone changed this table at the same moment. Please try again.',
  };
}
