Cativerse 🐾

Cativerse เป็นแอปพลิเคชันบนสมาร์ทโฟนที่พัฒนาด้วย Flutter ออกแบบมาเพื่อเป็นแอปพลิเคชันสำหรับคนรักแมว (Cat Community & Matchmaking) ให้ผู้ใช้สามารถสร้างโปรไฟล์ให้น้องแมว หาเพื่อนใหม่ จับคู่ (Match) และพูดคุยกับเจ้าของแมวตัวอื่นได้

ฟีเจอร์หลัก (Key Features)

ระบบสมาชิก (Authentication):** สมัครสมาชิก เข้าสู่ระบบ และกู้คืนรหัสผ่านด้วย Firebase Auth
โปรไฟล์แมว (Cat Profiles):** สร้าง แก้ไข อัปโหลดรูปภาพ และจัดการข้อมูลของน้องแมว
ระบบค้นหาและจับคู่ (Explore & Match):** ค้นหาและปัดหน้าจอ (Swipe) เพื่อถูกใจและจับคู่น้องแมว (Tinder-style) ด้วยแพ็กเกจ `swipable_stack`
ระบบแชทแบบเรียลไทม์ (Real-time Chat):** พูดคุยกับเจ้าของแมวตัวอื่นๆ ที่แมตช์กันแล้วผ่าน Firebase Chat Core
บันทึกสุขภาพ (Cat Health Tracker):** จดบันทึกและติดตามข้อมูลสุขภาพ วัคซีน และประวัติของน้องแมว
ระบบโลเคชัน (Location-based):** ใช้ `geolocator` เพื่อช่วยค้นหาและแสดงผลน้องแมวในบริเวณใกล้เคียง

เทคโนโลยีที่ใช้งาน (Tech Stack)

Frontend:** Flutter (Dart)
Backend / Database:** Firebase (Authentication, Cloud Firestore, Firebase Storage)
Push Notifications:** Firebase Cloud Messaging (FCM)
UI / UX:** 
   `flutter_chat_ui` สำหรับหน้าต่างแชท
   `flutter_card_swiper`, `swipable_stack` สำหรับระบบปัดไพ่จับคู่
   `custom_clippers` สำหรับตกแต่ง UI ให้สวยงาม

การติดตั้งและการรันโปรเจค (Getting Started)

สิ่งที่ต้องมีก่อนติดตั้ง (Prerequisites)
   [Flutter SDK](https://docs.flutter.dev/get-started/install) 
   เชื่อมต่อโปรเจคกับ Firebase (ต้องมีไฟล์ `google-services.json` สำหรับ Android และ `GoogleService-Info.plist` สำหรับ iOS)

ขั้นตอนการรันโปรเจค

1. ดาวน์โหลดหรือโคลนโปรเจคนี้
2. ติดตั้งแพ็กเกจที่จำเป็น (Dependencies):
   ```bash
   flutter pub get
   ```
3. รันแอปพลิเคชันลงบน Emulator หรืออุปกรณ์จริง:
   ```bash
   flutter run
   ```
