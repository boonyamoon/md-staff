# md-staff

แอป Flutter สำหรับพนักงานเสิร์ฟของระบบ MeeD POS พนักงานถือมือถือเดินรับออเดอร์ที่โต๊ะ
ใบออเดอร์พิมพ์อัตโนมัติที่เครื่อง POS และ **การชำระเงินทำที่เครื่อง POS เท่านั้น**

ทำงานคู่กับ `pos-services` (backend), iPad POS (`myapp`) และตู้ `kiosk-kotlin`

## ความสามารถหลัก

- **ผูกเครื่อง (ครั้งเดียวต่อเครื่อง):** ผู้จัดการเข้าสู่ระบบด้วยอีเมล → เลือกสาขา → เลือกเครื่อง → ผูกเครื่อง
  เหมือนขั้นตอนตั้งค่าของ `kiosk-kotlin` โดย staff token อยู่แค่ในหน่วยความจำ ไม่เคยเขียนลงดิสก์
- **เข้ากะด้วยอีเมล:** พนักงานเข้าสู่ระบบด้วยอีเมล/รหัสผ่านเดียวกับที่ใช้กับ POS ได้ shift token อายุ 12 ชั่วโมง
- **เลือกโซน → เลือกโต๊ะ → สั่งอาหาร → ดูตะกร้า → ส่งเข้าครัว**
- **สั่งได้ทีละเครื่อง:** เครื่องที่เปิดโต๊ะจะถือสิทธิ์ (lease 3 นาที ต่ออายุอัตโนมัติทุก 1 นาที)
  เครื่องอื่นเห็นว่า "พนักงาน A กำลังสั่งโต๊ะนี้" และแย่งได้เฉพาะเมื่อใส่ PIN ผู้จัดการ
- **พิมพ์ออเดอร์อัตโนมัติที่ POS:** ออเดอร์ที่ส่งจากแอปนี้สร้าง kitchen print job บนเซิร์ฟเวอร์
  เครื่อง POS ที่เฝ้าอยู่จะ claim แล้วพิมพ์ให้เอง แอปนี้ไม่ต่อเครื่องพิมพ์เลย
- **ดูบิล:** เห็นรายการที่สั่งแล้วแยกตามรอบ พร้อมยอดสุทธิ แต่ยกเลิก/ลดราคา/รับเงิน ทำที่ POS
- **ภาษา:** ไทยและอังกฤษ
- **รองรับเฉพาะมือถือแนวตั้ง** iPhone และ Android (ล็อกไว้ทั้งใน manifest, Info.plist และใน `main.dart`)

## สิ่งที่ต้องมี

| เครื่องมือ | เวอร์ชัน |
|---|---|
| Flutter | 3.38.x (Dart 3.10) |
| Android SDK | Platform 34 ขึ้นไป (`flutter doctor` จะบอกถ้ายังขาด) |
| Xcode | 15 ขึ้นไป สำหรับ build iOS |
| เครื่องที่รันแอป | iOS 13+ หรือ Android 7.0 (API 24) ขึ้นไป |

โปรเจกต์นี้ **ไม่ใช้ build_runner หรือ codegen** โคลนแล้ว `flutter pub get` แล้วรันได้เลย
(`json_serializable` resolve กับ Flutter SDK รุ่นนี้ไม่ได้ เพราะชนกับ `test` ที่ SDK pin ไว้
จึงเขียน `fromJson` ด้วยมือใน `lib/data/dto/` ซึ่งอ่านง่ายกว่าและไม่ต้องมีขั้น build)

## รัน

```sh
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080/
```

URL ของ backend ถูกฝังตอน build เหมือน `kioskApiBaseUrl` ของ kiosk — เปลี่ยนแล้วต้อง build ใหม่
และต้องลงท้ายด้วย `/`

| แอปรันบน | `API_BASE_URL` | หมายเหตุ |
|---|---|---|
| Android emulator | `http://10.0.2.2:8080/` | `10.0.2.2` คือเครื่องคอมที่รัน emulator |
| iOS simulator | `http://localhost:8080/` | |
| เครื่องจริงต่อ USB (Android) | `http://localhost:8080/` | รัน `adb reverse tcp:8080 tcp:8080` ก่อน |
| เครื่องจริงผ่าน Wi-Fi | `http://<IP เครื่องคอม>:8080/` | ต้องอยู่ในวง Wi-Fi เดียวกัน |
| Production | `https://api.meedeepos.com/` | |

ถ้าไม่ส่ง `--dart-define` จะใช้ `https://api.meedeepos.com/`

> `http://` ใช้ได้เฉพาะตอน debug — release build บน Android บล็อก cleartext ตามค่า default
> ของ Flutter และ iOS บล็อกด้วย ATS

## Build สำหรับติดตั้งจริง

```sh
# Android — Google Play
flutter build appbundle --release --dart-define=API_BASE_URL=https://api.meedeepos.com/

# Android — ติดตั้งเอง
flutter build apk --release --dart-define=API_BASE_URL=https://api.meedeepos.com/

# iOS
flutter build ipa --release --dart-define=API_BASE_URL=https://api.meedeepos.com/
```

ยังไม่ได้ตั้งค่า signing (keystore / provisioning profile) — ต้องทำก่อนปล่อยจริง

## เริ่มใช้งานเครื่องใหม่

1. ฝั่ง backend: สาขาต้องมี terminal ชนิด **`STAFF`** (สร้างที่ backoffice, `POST /api/v1/pos-terminals`
   ด้วย `terminal_type: "STAFF"`) หนึ่งเครื่องต่อหนึ่งมือถือ
2. ตั้งค่า `STAFF_APP_JWT_SECRET` บน `pos-services` (ดู `.env.example` ของ repo นั้น)
   ถ้าไม่ตั้ง ทุก endpoint `/api/v1/staff-app` จะตอบ `503 STAFF_APP_NOT_CONFIGURED`
3. บัญชีพนักงานต้องมี `allow_pos_login` (ค่า default เป็น true) และถูก assign เข้าสาขานั้น
4. เปิดแอป → เข้าสู่ระบบด้วยบัญชีผู้จัดการ → เลือกสาขา → เลือกเครื่อง → ผูกเครื่อง
5. ส่งมือถือให้พนักงาน แล้วพนักงานเข้ากะด้วยอีเมลของตัวเอง

การ "แย่งโต๊ะ" ใช้ PIN ของพนักงานที่มี `is_super_admin`, `allow_backoffice_login`
หรือ `allow_manage_app_login` (PIN เดียวกับที่ใช้กับ POS) และ PIN `0000` ใช้ไม่ได้

## ทดสอบ

```sh
flutter analyze   # ไม่มี issue
flutter test      # 68 tests
```

## โครงสร้างโปรเจกต์

Riverpod + go_router + dio จัดแบบ MVVM + Clean Architecture ใกล้เคียง `kiosk-kotlin`
(Riverpod ทำหน้าที่แทน ViewModel/StateFlow, dio + interceptor แทน Retrofit/OkHttp,
flutter_secure_storage แทน DataStore + TokenCipher)

```text
lib/
├── core/
│   ├── config/        API base URL และค่าคงที่ของ build
│   ├── network/       dio client, interceptor แนบ token, ApiFailure
│   ├── storage/       เก็บ token ใน keystore/keychain + device install id
│   ├── theme/         สี MeeD และธีม
│   ├── l10n/          ข้อความไทย/อังกฤษ
│   ├── widgets/       widget ที่ใช้ร่วมกัน
│   └── providers.dart DI ทั้งหมด (repository, package info, device name)
├── data/
│   ├── dto/           model + fromJson (เขียนมือ) และ CartLine
│   └── repositories/  setup, shift, floor, menu
├── features/
│   ├── bootstrap/     ตัดสินว่าแอปอยู่สถานะไหน (ผูกเครื่อง / เข้ากะ / พร้อมใช้)
│   ├── setup/         ผูกเครื่อง
│   ├── login/         เข้ากะ
│   ├── zones/         เลือกโซน
│   ├── tables/        เลือกโต๊ะ, สิทธิ์โต๊ะ, แย่งโต๊ะ, บิล
│   ├── menu/          เมนูและตัวเลือกสินค้า
│   ├── cart/          ตะกร้าและส่งเข้าครัว
│   └── settings/      ตั้งค่า, ออกจากกะ, ยกเลิกการผูกเครื่อง
└── router/            go_router และ redirect ตามสถานะ
```

### สิ่งที่แอปนี้ตั้งใจ "ทำไม่ได้"

- **รับเงิน** ไม่มี endpoint และไม่มีหน้าจอ การชำระเงินอยู่ที่ POS เท่านั้น
- **ยกเลิกรายการ / ลดราคา / ปิดโต๊ะ** เป็นงานของแคชเชียร์
- **ต่อเครื่องพิมพ์** ใบออเดอร์ออกที่ POS โดย POS เป็นคน claim print job เอง
- **ถือ hybrid grant ของสาขา** terminal ชนิด `STAFF` ไม่แตะ branch execution policy
  จึงไม่แย่งสิทธิ์ของ iPad

## API ที่ใช้ (`pos-services`)

| ชั้น auth | endpoint |
|---|---|
| staff JWT (ตอนผูกเครื่อง) | `POST /api/v1/auth/login`, `GET /api/v1/branches-access/snapshot?platform=staff_app`, `GET /api/v1/staff-app/pairing/terminals`, `POST /api/v1/staff-app/pair` |
| device token | `POST /api/v1/staff-app/token/refresh`, `POST /api/v1/staff-app/login` |
| shift token | `GET /session`, `POST /logout`, `GET /config`, `GET /zones`, `GET /tables/:id`, `POST /tables/:id/claim`, `POST /tables/:id/claim/renew`, `POST /tables/:id/claim/release`, `POST /tables/:id/orders`, `GET /menu/*` |

การส่งออเดอร์ต้องมี header `X-Claim-Lease` (lease token ของสิทธิ์โต๊ะ) และ `Idempotency-Key`
(UUID เดียวต่อหนึ่งรอบ ใช้ซ้ำตอน retry — ฝั่งเซิร์ฟเวอร์บันทึกใน `sales_order_commands`
จึงส่งซ้ำไม่ได้ออเดอร์ซ้ำ)

## ปัญหาที่พบบ่อย

| อาการ | วิธีแก้ |
|---|---|
| `503 STAFF_APP_NOT_CONFIGURED` | ยังไม่ตั้ง `STAFF_APP_JWT_SECRET` บน backend |
| `NO_STAFF_TERMINAL_AVAILABLE` | สาขานั้นยังไม่มี terminal ชนิด `STAFF` ที่ว่าง |
| `STAFF_APP_LOGIN_NOT_ALLOWED` | บัญชีนั้นไม่มี `allow_pos_login` หรือไม่ถูก assign เข้าสาขานั้น |
| เข้าสู่ระบบแล้วเด้งกลับหน้าผูกเครื่อง | เครื่องถูก unpair ที่ backoffice หรือ terminal ถูกปิด |
| แตะโต๊ะแล้วขึ้น "มีคนกำลังสั่ง" ทั้งที่ไม่มีใครถือ | lease ยังไม่หมดอายุ (3 นาที) ให้รอ หรือใช้ PIN ผู้จัดการแย่ง |
| ส่งเข้าครัวแล้วไม่มีใบออเดอร์ออก | สาขาไม่มีเครื่องพิมพ์ ORDER_SLIP/BOTH — ดูที่หน้าตั้งค่าของแอป จะบอกไว้ |
| เปลี่ยน URL แล้วแอปยังเรียกที่เดิม | URL ฝังตอน build ต้อง build และติดตั้งใหม่ |
