# My-sidenotes

แอปจดโน้ตแบบแผงด้านข้างจอสำหรับ macOS (แนว SideNotes) เขียนด้วย Swift + SwiftUI/AppKit

- แผงโน้ตเลื่อนออกมาจากขอบจอ ดีไซน์ Liquid Glass
- แถบเล็ก ๆ ที่ขอบจอทุกจอ กดจากจอไหนแผงก็เปิดที่จอนั้น
- โฟลเดอร์แยกสี, ค้นหา, ติดดาว, ลากจัดลำดับ
- Checklist ติ๊กได้, ลิงก์กดได้, รายการ/เลขลำดับต่อบรรทัดอัตโนมัติ
- คีย์ลัดทั้งระบบ (เปิด/ปิดแผง, จดโน้ตด่วน) ตั้งเองได้
- ตั้งค่าโหมดสว่าง/มืด, สีพื้นหลัง, ความโปร่งใส, แผงซ้าย/ขวา

## ความต้องการของระบบ

- macOS 14 ขึ้นไป (เอฟเฟกต์ Liquid Glass ต้องใช้ macOS 26 ขึ้นไป)
- Command Line Tools ของ Xcode สำหรับ build (ไม่ต้องติดตั้ง Xcode เต็มตัว)

```bash
xcode-select --install
```

## ติดตั้ง

### วิธีที่ 1: Build จากซอร์ส (แนะนำ)

```bash
git clone https://github.com/ChaipatCasP/My-sidenotes.git
cd My-sidenotes
./scripts/build-app.sh --install
```

สคริปต์จะ build แบบ release แล้วคัดลอก `MySideNotes.app` ไปไว้ที่ `/Applications` และเปิดแอปให้ทันที

ถ้าต้องการแค่ build โดยไม่ติดตั้ง ให้รัน `./scripts/build-app.sh` ไฟล์จะอยู่ที่ `build/MySideNotes.app`

### วิธีที่ 2: คัดลอกไฟล์ .app ไปเครื่องอื่น

ที่เครื่องที่ build แล้ว:

```bash
./scripts/build-app.sh
cd build && ditto -c -k --keepParent MySideNotes.app MySideNotes.zip
```

ที่เครื่องปลายทาง แตก zip แล้ววาง `MySideNotes.app` ใน `/Applications` จากนั้นปลดการบล็อกของ Gatekeeper (แอปไม่ได้ลงนามด้วย Apple Developer ID):

```bash
xattr -dr com.apple.quarantine /Applications/MySideNotes.app
```

> ไฟล์ที่ build จะเป็นสถาปัตยกรรมเดียวกับเครื่องที่ build (Apple Silicon → ใช้ได้กับ Mac M1 ขึ้นไปเท่านั้น) ถ้าเครื่องปลายทางเป็น Intel ให้ใช้วิธีที่ 1

### อัปเดตเวอร์ชัน

```bash
git pull
./scripts/build-app.sh --install
```

โน้ตและการตั้งค่าเดิมจะยังอยู่ครบ

## หลังติดตั้ง

1. แผงโน้ตจะเลื่อนออกมาที่ขอบขวาของจอทันที
2. แอปนี้**ไม่มีหน้าต่างหลักและไม่มีไอคอนใน Dock** — มีแค่ไอคอนโน้ตบนแถบเมนูด้านบน และแถบเล็ก ๆ ที่ขอบขวาของจอ
3. เปิดแผงแล้วกด ⚙ → เปิด **"เปิดอัตโนมัติเมื่อเข้าสู่ระบบ"** เพื่อให้แอปเปิดเองทุกครั้งที่เปิดเครื่อง

## แก้ปัญหา

**ติดตั้งแล้วไม่เห็นอะไรเลย**

- กด `⌃⌥N` หรือเปิด "MySideNotes" จาก Launchpad / Spotlight อีกครั้ง แผงจะเด้งขึ้นมา
- บน MacBook ที่มีรอยบาก ไอคอนบนแถบเมนูอาจถูกซ่อนหลังรอยบากถ้ามีไอคอนเยอะ — ใช้คีย์ลัดหรือแถบที่ขอบจอแทน
- เช็กว่าแอปทำงานอยู่ไหม: `pgrep -lx MySideNotes`
- ถ้าแอปไม่ทำงาน ให้รันตรง ๆ เพื่อดู error:

  ```bash
  /Applications/MySideNotes.app/Contents/MacOS/MySideNotes --show
  ```

**`fatal: destination path 'My-sidenotes' already exists`**

เคย clone ไว้แล้ว ให้อัปเดตโค้ดในโฟลเดอร์เดิมแทน:

```bash
cd My-sidenotes
git pull
./scripts/build-app.sh --install
```

**`swift build` ขึ้น `Invalid manifest` / `Undefined symbols ... PackageDescription`**

Command Line Tools ในเครื่องติดตั้งไม่สมบูรณ์ (มักเกิดหลังอัปเดต macOS) — `scripts/build-app.sh` คอมไพล์ด้วย `swiftc` ตรง ๆ จึงไม่โดนปัญหานี้ แต่ถ้าต้องการใช้ `swift build` ให้ติดตั้ง Command Line Tools ใหม่ตามด้านล่าง

**Build ไม่ผ่าน**

- เช็กเวอร์ชัน: `sw_vers -productVersion` (ต้อง 14 ขึ้นไป) และ `swift --version`
- อัปเดต Command Line Tools ผ่าน System Settings → General → Software Update หรือ

  ```bash
  sudo rm -rf /Library/Developer/CommandLineTools && xcode-select --install
  ```

## วิธีใช้

| การกระทำ | วิธี |
| --- | --- |
| เปิด/ปิดแผง | `⌃⌥N`, คลิกไอคอนบนแถบเมนู หรือคลิกแถบที่ขอบจอ |
| จดโน้ตด่วน | `⌃⌥⇧N` |
| โน้ตใหม่ (ในโฟลเดอร์) | `⌘N` |
| สลับบรรทัดเป็น checklist | `⇧⌘L` หรือพิมพ์ `[]` แล้วเว้นวรรค |
| ย้อนกลับ / ซ่อนแผง | `Esc` หรือคลิกที่อื่น |
| ค้างแผงไว้ไม่ให้ซ่อน | ปุ่มหมุดด้านล่าง |
| เมนูเพิ่มเติม | คลิกขวาที่โฟลเดอร์/โน้ต หรือคลิกขวาที่ไอคอนบนแถบเมนู |

คีย์ลัดทั้งหมดเปลี่ยนได้ในหน้าตั้งค่า

## ข้อมูลโน้ต

โน้ตเก็บเป็นไฟล์ JSON ที่

```
~/Library/Application Support/MySideNotes/notes.json
```

ย้ายโน้ตไปเครื่องใหม่หรือสำรองข้อมูลได้โดยคัดลอกไฟล์นี้ (ปิดแอปก่อนคัดลอกทับ)

## ถอนการติดตั้ง

```bash
pkill -x MySideNotes
rm -rf /Applications/MySideNotes.app
# ลบโน้ตและการตั้งค่าด้วย (ถ้าต้องการ)
rm -rf ~/Library/Application\ Support/MySideNotes
defaults delete com.chaipat.mysidenotes
```

## สำหรับนักพัฒนา

```bash
swift build                      # build แบบ debug
swift run MySideNotes --show     # รันและเปิดแผงทันที
```

โครงสร้างหลัก:

- `Sources/MySideNotes/AppDelegate.swift` — จุดเริ่มต้นแอป, ไอคอนแถบเมนู, คีย์ลัด
- `Sources/MySideNotes/SidePanelController.swift` — หน้าต่างแผงและแอนิเมชันเลื่อนเข้า/ออก
- `Sources/MySideNotes/EdgeHandles.swift` — แถบที่ขอบจอทุกจอ
- `Sources/MySideNotes/NoteStore.swift` — โหลด/บันทึกโน้ต
- `Sources/MySideNotes/Settings.swift` — ค่าตั้งค่าและคีย์ลัด
- `Sources/MySideNotes/Views/` — หน้าจอ SwiftUI ทั้งหมด

> หมายเหตุ: เครื่องที่มีแค่ Command Line Tools จะใช้ `@State` ของ SwiftUI ไม่ได้ (macro plugin มากับ Xcode เต็มตัวเท่านั้น) โปรเจกต์นี้จึงเก็บ state ของ view ไว้ใน `ObservableObject` + `@StateObject` แทน
