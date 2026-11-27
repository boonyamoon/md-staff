# md-staff

แอป Flutter สำหรับพนักงานเสิร์ฟของระบบ MeeD POS พนักงานถือมือถือเดินรับออเดอร์ที่โต๊ะ
ใบออเดอร์พิมพ์อัตโนมัติที่เครื่อง POS และ **การชำระเงินทำที่เครื่อง POS เท่านั้น**

ทำงานคู่กับ `pos-services` (backend), iPad POS (`myapp`) และตู้ `kiosk-kotlin`

## ความสามารถหลัก

- **เข้าสู่ระบบครั้งเดียวใช้ได้ตลอด:** พนักงานใส่อีเมล/รหัสผ่านของตัวเอง (ตัวเดียวกับที่ใช้กับ POS)
  → เลือกสาขา → เลือกเครื่อง → ผูกเครื่องและเข้าใช้งานในขั้นเดียว เหมือน setup ของ `kiosk-kotlin`
  หลังจากนั้น**ไม่ต้องเข้าสู่ระบบอีก** แอปหมุน refresh token ให้เองเงียบ ๆ
  staff JWT อยู่แค่ในหน่วยความจำ ไม่เคยเขียนลงดิสก์
- **1 เครื่อง = 1 คน:** ออเดอร์จึงระบุได้ว่าใครเป็นคนสั่ง session จะจบเมื่อกด "ออกจากระบบ",
  ถอดการผูกเครื่อง, หรือพนักงานคนนั้นถูก deactivate / ลบ / ล็อก / ถอนออกจากสาขา /
  ปิดสิทธิ์ `allow_staff_login` — ทั้งหมด**มีผลทันทีที่ request ถัดไป**
  เพราะเซิร์ฟเวอร์อ่าน `pos_terminals` + `user_staff` ใหม่ทุก request
- **เลือกโซน → เลือกโต๊ะ → สั่งอาหาร → ดูตะกร้า → ส่งเข้าครัว**
- **สั่งได้ทีละเครื่อง:** เครื่องที่เปิดโต๊ะจะถือสิทธิ์ (lease 3 นาที ต่ออายุอัตโนมัติทุก 1 นาที)
  เครื่องอื่นเห็นว่า "พนักงาน A กำลังสั่งโต๊ะนี้" และแย่งได้เฉพาะเมื่อใส่ PIN ผู้จัดการ
- **พิมพ์ออเดอร์อัตโนมัติที่ POS:** ออเดอร์ที่ส่งจากแอปนี้สร้าง kitchen print job บนเซิร์ฟเวอร์
  เครื่อง POS ที่เฝ้าอยู่จะ claim แล้วพิมพ์ให้เอง แอปนี้ไม่ต่อเครื่องพิมพ์เลย
- **ดูบิล:** เห็นรายการที่สั่งแล้วแยกตามรอบ พร้อมยอดสุทธิ แต่ยกเลิก/ลดราคา/รับเงิน ทำที่ POS
- **เสิร์ฟแล้ว:** ในหน้ารายการที่สั่ง กดได้ทีละรายการหรือทั้งรอบ (ถามยืนยันก่อน) ตั้งแต่
  "ส่งเข้าครัวแล้ว" เพราะบางร้านไม่มีจอครัว ไม่ต้องถือสิทธิ์โต๊ะ และเปลี่ยนกลับไม่ได้
- **ภาษา:** ไทยและอังกฤษ
- **รองรับเฉพาะมือถือแนวตั้ง** iPhone และ Android (ล็อกไว้ทั้งใน manifest, Info.plist และใน `main.dart`)

## สิ่งที่ต้องมี

| เครื่องมือ | เวอร์ชัน |
|---|---|
| Flutter | 3.38.x (Dart 3.10) |
| Android SDK | Platform 34 ขึ้นไป (`flutter doctor` จะบอกถ้ายังขาด) |
| Xcode | 15 ขึ้นไป สำหรับ build iOS |
| เครื่องที่รันแอป | iPhone ที่ใช้ iOS 15+ หรือ Android 7.0 (API 24) ขึ้นไป |
| สิทธิ์พนักงาน | `user_staff.allow_staff_login = true` (ค่า default เป็น `false`) หรือเป็น super admin |

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

1. ตั้งค่า `STAFF_APP_JWT_SECRET` บน `pos-services` (ดู `.env.example` ของ repo นั้น)
   ถ้าไม่ตั้ง ทุก endpoint `/api/v1/staff-app` จะตอบ `503 STAFF_APP_NOT_CONFIGURED`
2. รัน migration `20261125090000_staff_app_sessions` (เพิ่มคอลัมน์ `allow_staff_login`
   และตาราง `staff_app_sessions`) — ต้องรันก่อน deploy โค้ด เพราะ `fetchStaffAccess`
   อ่านคอลัมน์นี้ในเส้นทางของ web และ kiosk ด้วย
3. สาขาต้องมี terminal ชนิด **`STAFF`** (สร้างที่ backoffice, `POST /api/v1/pos-terminals`
   ด้วย `terminal_type: "STAFF"`) **หนึ่งเครื่องต่อหนึ่งมือถือ**
4. เปิดสิทธิ์ให้พนักงานเป็นคน ๆ ไป: `PUT /api/v1/user-staff/:id` ด้วย `allow_staff_login: true`
   และต้องถูก assign เข้าสาขานั้น (`user_branch_assignments.is_active = true`)
   — ค่า default เป็น `false` จึงต้องเปิดเอง ส่วน super admin ถูกยกเว้นอยู่แล้ว
5. ส่งมือถือให้พนักงาน แล้วพนักงานเข้าสู่ระบบด้วยอีเมลตัวเอง **ครั้งเดียว**

> `pos-web` ยังไม่มี checkbox สำหรับ flag กลุ่มนี้ (`allow_kiosk_login` ก็เหมือนกัน)
> วันนี้จึงต้องเปิดผ่าน API หรือ DB

การ "แย่งโต๊ะ" ใช้ PIN ของพนักงานที่มี `is_super_admin`, `allow_backoffice_login`
หรือ `allow_manage_app_login` (PIN เดียวกับที่ใช้กับ POS) และ PIN `0000` ใช้ไม่ได้
— สังเกตว่า `allow_staff_login` **ไม่ได้**ให้สิทธิ์แย่งโต๊ะ มันหมายถึง "ใช้เครื่องพนักงานได้" เท่านั้น

## ทดสอบ

```sh
flutter analyze   # ไม่มี issue
flutter test      # 80 tests
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
│   ├── storage/       เก็บ access + refresh token ใน keystore/keychain + device install id
│   ├── theme/         สี MeeD และธีม
│   ├── l10n/          ข้อความไทย/อังกฤษ
│   ├── widgets/       widget ที่ใช้ร่วมกัน
│   └── providers.dart DI ทั้งหมด (repository, package info, device name)
├── data/
│   ├── dto/           model + fromJson (เขียนมือ) และ CartLine
│   └── repositories/  setup, session, floor, menu
├── features/
│   ├── bootstrap/     ตัดสินว่าแอปอยู่สถานะไหน (ต้องเข้าสู่ระบบ / พร้อมใช้)
│   ├── setup/         เข้าสู่ระบบ: อีเมล → สาขา → เครื่อง (ผูกเครื่องในขั้นเดียวกัน)
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
| staff JWT (ตอนเข้าสู่ระบบ อยู่ในหน่วยความจำเท่านั้น) | `POST /api/v1/auth/login`, `GET /api/v1/branches-access/snapshot?platform=staff_app`, `GET /api/v1/staff-app/pairing/terminals`, `POST /api/v1/staff-app/login` |
| refresh token (อยู่ใน body ไม่มี bearer) | `POST /api/v1/staff-app/token/refresh` |
| access token | `GET /session`, `POST /logout`, `GET /config`, `GET /zones`, `GET /tables/:id`, `POST /tables/:id/claim`, `POST /tables/:id/claim/renew`, `POST /tables/:id/claim/release`, `POST /tables/:id/orders`, `POST /tables/:id/served`, `GET /menu/*` |

`POST /api/v1/staff-app/login` ผูกเครื่อง**และ**ออก token ในขั้นเดียว

เรื่อง token:

- **access token** อายุ 1 ชม. (`STAFF_APP_ACCESS_HOURS`) แอป refresh ล่วงหน้าเมื่อเหลือ ≤ 5 นาที
  ไม่ใช่รอ 401 — `STAFF_APP_TOKEN_EXPIRED` คือสัญญาณให้ refresh **ไม่ใช่**ให้เด้งไปหน้า login
- **refresh token** อายุ 180 วัน (`STAFF_APP_REFRESH_DAYS`) หมุนทุกครั้งที่ใช้ และ**ต่ออายุใหม่ทุกครั้ง**
  เปิดแอปภายใน 180 วันก็ใช้ได้ตลอด เซิร์ฟเวอร์เก็บแค่ sha256 ไม่เก็บตัว token
- ถ้า response ของ refresh หายกลางทาง แอป retry ด้วย token เดิมได้ภายใน 120 วินาที
  (`STAFF_APP_REFRESH_GRACE_SECONDS`) จะได้ token ชุดใหม่ ไม่ถูกเตะออก
  แต่ถ้า token ที่ตายแล้วถูกใช้ซ้ำ 3 ครั้งติด (`STAFF_APP_REPLAY_REVOKE_THRESHOLD`) session จะถูก revoke

การส่งออเดอร์ต้องมี header `X-Claim-Lease` (lease token ของสิทธิ์โต๊ะ) และ `Idempotency-Key`
(UUID เดียวต่อหนึ่งรอบ ใช้ซ้ำตอน retry — ฝั่งเซิร์ฟเวอร์บันทึกใน `sales_order_commands`
จึงส่งซ้ำไม่ได้ออเดอร์ซ้ำ)

## ปัญหาที่พบบ่อย

| อาการ | วิธีแก้ |
|---|---|
| `503 STAFF_APP_NOT_CONFIGURED` | ยังไม่ตั้ง `STAFF_APP_JWT_SECRET` บน backend |
| `NO_STAFF_TERMINAL_AVAILABLE` | สาขานั้นยังไม่มี terminal ชนิด `STAFF` ที่ว่าง |
| `403 STAFF_APP_LOGIN_NOT_ALLOWED` | บัญชีนั้นยังไม่ได้เปิด `allow_staff_login` หรือไม่ถูก assign เข้าสาขานั้น |
| เข้าสู่ระบบแล้วเด้งกลับหน้าเข้าสู่ระบบ | เครื่องถูก unpair, terminal ถูกปิด, หรือสิทธิ์พนักงานถูกถอน |
| `409 STAFF_APP_UPGRADE_REQUIRED` | แอปเวอร์ชันเก่าที่ยังใช้ device token ให้อัปเดตแอป |
| แตะโต๊ะแล้วขึ้น "มีคนกำลังสั่ง" ทั้งที่ไม่มีใครถือ | lease ยังไม่หมดอายุ (3 นาที) ให้รอ หรือใช้ PIN ผู้จัดการแย่ง |
| ส่งเข้าครัวแล้วไม่มีใบออเดอร์ออก | สาขาไม่มีเครื่องพิมพ์ ORDER_SLIP/BOTH — ดูที่หน้าตั้งค่าของแอป จะบอกไว้ |
| เปลี่ยน URL แล้วแอปยังเรียกที่เดิม | URL ฝังตอน build ต้อง build และติดตั้งใหม่ |
