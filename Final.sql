-- ═══════════════════════════════════════════════════════════════════════════
-- CU-iHouse Reservation System — Database Schema
-- Version: 3.0 (Final)
-- DBMS: PostgreSQL 17 (Supabase)
-- ───────────────────────────────────────────────────────────────────────────
-- คำอธิบายโดยรวม:
--   ระบบฐานข้อมูลสำหรับการจองหอพัก CU-iHouse ประกอบด้วย 10 ตาราง
--   แบ่งเป็น 4 กลุ่มตามหน้าที่:
--     1) ผู้ใช้ระบบ      — UserAccount, Member, Staff
--     2) ห้องพัก         — RoomType, Room
--     3) การจอง+ชำระเงิน — Reservation, ReservationGuest, ApprovalLog, Payment
--     4) แจ้งเตือน       — Notification
--
--   เหตุผลในการออกแบบ:
--     • แยก UserAccount ออกจาก Member/Staff เพื่อให้ระบบ Authentication
--       เป็นอิสระจากข้อมูล profile (Single Responsibility)
--     • RoomType แยกจาก Room เพื่อหลีกเลี่ยง data redundancy
--       (ห้อง 800+ ห้องใช้ราคาเดียวกัน ไม่ต้องเก็บราคาทุกห้อง)
--     • ใช้ AuthUID (UUID) เป็นสะพานเชื่อม auth.users (Supabase Auth)
--       กับ public.UserAccount — แยก credentials ออกจาก business data
-- ═══════════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════════
-- TABLE 1: UserAccount  (บัญชีผู้ใช้ระบบ)
-- ───────────────────────────────────────────────────────────────────────────
-- หน้าที่: เก็บข้อมูลพื้นฐานสำหรับการ login (username, role)
-- เหตุผลแยกตาราง: ผู้ใช้ทุกประเภท (นิสิต/บุคลากร/บุคคลทั่วไป/เจ้าหน้าที่)
--                ต้องมีบัญชี login → แยกตารางกลางเพื่อความง่าย
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE "UserAccount" (                                -- สร้างตาราง UserAccount

    -- Primary Key — รหัสเฉพาะของผู้ใช้แต่ละคน เพิ่มอัตโนมัติ (1, 2, 3, ...)
    "UserID"        SERIAL          PRIMARY KEY,            -- SERIAL = auto-increment integer, PRIMARY KEY = ห้ามซ้ำ ห้าม NULL

    -- ชื่อสำหรับ login — ต้องไม่ซ้ำใคร (UNIQUE) เพื่อป้องกันการปลอมแปลง
    "Username"      VARCHAR(50)     NOT NULL UNIQUE,        -- VARCHAR(50) = ข้อความสูงสุด 50 ตัวอักษร, UNIQUE = ห้ามซ้ำในตาราง

    -- ประเภทผู้ใช้ — ใช้กำหนดสิทธิ์การเข้าถึงในระบบ
    "Role"          VARCHAR(20)     NOT NULL                -- VARCHAR(20) = ข้อความสูงสุด 20 ตัวอักษร, NOT NULL = ต้องมีค่าเสมอ
                    CHECK ("Role" IN ('student','faculty','guest','staff')),
                                                            -- CHECK = จำกัดค่าให้เป็น 1 ใน 4 อย่างนี้เท่านั้น ป้องกัน role ปลอม

    -- สถานะบัญชี — สามารถระงับ (banned) ผู้ใช้ที่ทำผิดได้
    "Status"        VARCHAR(20)     NOT NULL DEFAULT 'active'  -- DEFAULT 'active' = ค่าเริ่มต้นเมื่อสร้างบัญชีใหม่คือ active
                    CHECK ("Status" IN ('active','inactive','banned')),
                                                            -- CHECK = จำกัดสถานะให้เป็น 3 ค่านี้เท่านั้น

    -- AuthUID — UUID ที่ได้จาก Supabase Auth ใช้เชื่อม auth.users กับตารางนี้
    "AuthUID"       UUID            UNIQUE,                 -- UUID = รหัสแบบ 128-bit (เช่น a1b2c3d4-...), UNIQUE = 1 user 1 AuthUID, NULL ได้ (ก่อน verify)

    -- วันเวลาสร้างบัญชี — บันทึกอัตโนมัติตอน INSERT ไม่ต้องส่งค่ามาเอง
    "CreatedAt"     TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP  -- TIMESTAMP = วันที่+เวลา, CURRENT_TIMESTAMP = เวลา ณ ตอนที่ INSERT
);                                                          -- ปิดนิยามตาราง UserAccount


--- ═══════════════════════════════════════════════════════════════════════════
-- TABLE 2: Member  (ข้อมูลผู้เช่า)
-- ───────────────────────────────────────────────────────────────────────────
-- หน้าที่: เก็บข้อมูล profile ของผู้เช่า (นิสิต/บุคลากร/บุคคลทั่วไป)
-- ความสัมพันธ์: 1 UserAccount = 1 Member (1:1) — ผู้ใช้คนเดียวมี profile เดียว
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE "Member" (                                     -- สร้างตาราง Member เก็บ profile ผู้เช่า

    "MemberID"      SERIAL          PRIMARY KEY,            -- รหัส member เพิ่มอัตโนมัติ

    -- Foreign Key → UserAccount
    -- UNIQUE เพื่อ enforce ความสัมพันธ์ 1:1 (1 user มีได้แค่ 1 member)
    -- ON DELETE CASCADE: ถ้าลบ UserAccount → ลบ Member ตามอัตโนมัติ (data integrity)
    "UserID"        INTEGER         NOT NULL UNIQUE          -- INTEGER = ตัวเลขจำนวนเต็ม, UNIQUE = กัน 1 user ไม่ให้มี member 2 คน
                    REFERENCES "UserAccount"("UserID") ON DELETE CASCADE,
                                                            -- REFERENCES = FK เชื่อมกับ UserAccount.UserID, CASCADE = ลบตามเมื่อ parent ถูกลบ

    "FullName"      VARCHAR(100)    NOT NULL,               -- ชื่อ-นามสกุลเต็ม สูงสุด 100 ตัวอักษร ห้าม NULL

    -- Email ห้ามซ้ำ — ใช้ติดต่อกลับและส่งแจ้งเตือน
    "Email"         VARCHAR(100)    NOT NULL UNIQUE,        -- email สูงสุด 100 ตัวอักษร, UNIQUE = ห้ามมี email ซ้ำในระบบ

    "Phone"         VARCHAR(20),                            -- เบอร์โทรศัพท์ สูงสุด 20 ตัวอักษร, NULL ได้ (ไม่บังคับ)

    -- เลขบัตรประชาชนหรือพาสปอร์ต — ใช้ยืนยันตัวตนของสมาชิก
    -- NULL ได้ เพราะผู้ใช้บางคนอาจยังไม่กรอกข้อมูลเอกสารตอนสมัคร
    -- UNIQUE ถ้ามีค่า เพื่อไม่ให้สมาชิก 2 คนใช้เลขเอกสารเดียวกัน
    "IDCardNumber"  VARCHAR(13)     UNIQUE,                 -- เลขบัตรประชาชน 13 หลัก หรือเลขพาสปอร์ตไม่เกิน 13 ตัวอักษร, NULL ได้, UNIQUE = ห้ามซ้ำถ้ากรอก

    -- เพศ — ใช้จับคู่กับ Room.GenderRestriction ตอนจอง
    -- เช่น ผู้ชายจองห้อง male/any ได้ แต่จองห้อง female ไม่ได้
    "Gender"        VARCHAR(10)                             -- VARCHAR(10) เพียงพอสำหรับ 'male'/'female', NULL ได้
                    CHECK ("Gender" IN ('male','female')),  -- CHECK = จำกัดให้เป็น 2 ค่านี้เท่านั้น (ป้องกันค่าผิด)

    "CreatedAt"     TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,  -- วันเวลาสมัครสมาชิก บันทึกอัตโนมัติ
    "UpdatedAt"     TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP   -- วันเวลาแก้ไขข้อมูลล่าสุด (update ด้วย trigger หรือ app)
);                                                          -- ปิดนิยามตาราง Member


-- ═══════════════════════════════════════════════════════════════════════════
-- TABLE 3: Staff  (ข้อมูลเจ้าหน้าที่)
-- ───────────────────────────────────────────────────────────────────────────
-- หน้าที่: เก็บข้อมูล profile ของเจ้าหน้าที่หอพัก
-- ทำไมแยกจาก Member: เจ้าหน้าที่มีสิทธิ์อื่น (อนุมัติ/ปฏิเสธการจอง,
--                   ตรวจสลิป) ที่ Member ไม่มี — แยกเพื่อความชัดเจน
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE "Staff" (                                      -- สร้างตาราง Staff เก็บ profile เจ้าหน้าที่

    "StaffID"       SERIAL          PRIMARY KEY,            -- รหัส staff เพิ่มอัตโนมัติ

    "UserID"        INTEGER         NOT NULL UNIQUE          -- FK → UserAccount, UNIQUE = 1 user เป็น staff ได้แค่คนเดียว
                    REFERENCES "UserAccount"("UserID") ON DELETE CASCADE,
                                                            -- ลบ UserAccount → ลบ Staff ตามอัตโนมัติ

    "FullName"      VARCHAR(100)    NOT NULL,               -- ชื่อ-นามสกุลเจ้าหน้าที่ ห้าม NULL

    "Email"         VARCHAR(100)    NOT NULL UNIQUE,        -- email เจ้าหน้าที่ ห้ามซ้ำในระบบ

    "Phone"         VARCHAR(20),                            -- เบอร์โทรศัพท์ NULL ได้

    -- ตำแหน่งงาน — officer (ทั่วไป), admin (ผู้ดูแล), supervisor (หัวหน้า)
    "StaffRole"     VARCHAR(50)     NOT NULL DEFAULT 'officer',  -- DEFAULT 'officer' = เพิ่ม staff ใหม่เป็น officer ก่อน

    "Status"        VARCHAR(20)     NOT NULL DEFAULT 'active'   -- สถานะการทำงาน DEFAULT active
                    CHECK ("Status" IN ('active','inactive')),  -- CHECK = active หรือ inactive เท่านั้น (ไม่มี banned เพราะ staff ไม่ได้ใช้)

    "CreatedAt"     TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP  -- วันเวลาสร้างบัญชี staff บันทึกอัตโนมัติ
);                                                          -- ปิดนิยามตาราง Staff


-- ═══════════════════════════════════════════════════════════════════════════
-- TABLE 4: RoomType  (ประเภทห้อง)
-- ───────────────────────────────────────────────────────────────────────────
-- หน้าที่: เก็บราคาฐานและเงื่อนไขของห้องแต่ละประเภท
-- ตัวอย่าง: Studio รายเดือน 13,000 บาท / Studio รายวัน 1,400 บาท / 1 Bedroom 22,000 บาท
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE "RoomType" (                                   -- สร้างตาราง RoomType เก็บข้อมูลประเภทห้อง

    "RoomTypeID"    SERIAL          PRIMARY KEY,            -- รหัสประเภทห้อง เพิ่มอัตโนมัติ

    "TypeName"      VARCHAR(100)    NOT NULL,               -- ชื่อประเภทห้อง เช่น "Studio 25 sqm (Monthly)" ห้าม NULL

    "Description"   TEXT,                                   -- คำอธิบายเพิ่มเติม TEXT = ข้อความยาวไม่จำกัด, NULL ได้

    -- ราคาฐาน — NUMERIC(10,2) = สูงสุด 99,999,999.99 บาท
    -- CHECK > 0 เพื่อกันการบันทึกราคาผิด (ห้ามฟรี ห้ามติดลบ)
    "BasePrice"     NUMERIC(10,2)   NOT NULL CHECK ("BasePrice" > 0),
                                                            -- NUMERIC(10,2) = ทศนิยม 2 ตำแหน่ง แม่นยำกว่า FLOAT สำหรับเงิน

    -- หน่วยการคิดราคา — แยก daily กับ monthly เพราะ business logic ต่างกัน
    -- 'night' = ราคาต่อคืน (สำหรับ Daily booking)
    -- 'month' = ราคาต่อเดือน (สำหรับ Monthly contract)
    "PricingUnit"   VARCHAR(10)     NOT NULL                -- ห้าม NULL เพราะทุกห้องต้องรู้หน่วยการคิดราคา
                    CHECK ("PricingUnit" IN ('night','month')),  -- CHECK = จำกัดให้เป็น 2 ค่านี้เท่านั้น

    -- จำนวนผู้พักสูงสุด — ใช้ validate ตอนกรอกฟอร์มจอง
    "MaxOccupancy"  INTEGER         NOT NULL DEFAULT 1      -- DEFAULT 1 = ถ้าไม่ระบุ ถือว่าพักได้ 1 คน
                    CHECK ("MaxOccupancy" BETWEEN 1 AND 2), -- CHECK = พักได้ 1-2 คน 

    -- รายการ Role ที่จองได้ คั่นด้วย comma เช่น "student,faculty"
    -- ใช้ string format เพื่อความง่าย ไม่ต้องสร้าง many-to-many table
    "AllowedRoles"  VARCHAR(100)    NOT NULL                -- ห้าม NULL เพราะทุกประเภทห้องต้องกำหนดว่าใครจองได้
);                                                          -- ปิดนิยามตาราง RoomType


-- ═══════════════════════════════════════════════════════════════════════════
-- TABLE 5: Room  (ห้องพัก)
-- ───────────────────────────────────────────────────────────────────────────
-- หน้าที่: เก็บข้อมูลห้องพักแต่ละห้องในระบบ
-- หมายเหตุ: ระบบออกแบบตามอาคาร 26 ชั้น และใช้เลขห้อง 4 หลักเสมอ เช่น 0201, 0219, 1401
-- ความสัมพันธ์: 1 RoomType มีหลาย Room (1:M) — เช่น Studio Monthly มีหลายห้อง
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE "Room" (                                       -- สร้างตาราง Room เก็บข้อมูลห้องพักแต่ละห้อง

    "RoomID"             SERIAL          PRIMARY KEY,       -- รหัสห้องพัก เพิ่มอัตโนมัติ

    -- FK → RoomType — กำหนดประเภทห้อง ราคา เงื่อนไขผู้จอง และจำนวนผู้พักสูงสุดของห้องนี้
    "RoomTypeID"         INTEGER         NOT NULL            -- ห้าม NULL เพราะทุกห้องต้องมีประเภทห้อง
                         REFERENCES "RoomType"("RoomTypeID"),  -- FK เชื่อมกับ RoomType.RoomTypeID

    -- หมายเลขห้อง (UNIQUE) ใช้รูปแบบ 4 หลักเสมอ เช่น 0201, 0219, 1401, 2201, 2401
    "RoomNumber"         VARCHAR(10)     NOT NULL UNIQUE,   -- เลขห้องสูงสุด 10 ตัวอักษร, UNIQUE = ห้ามมีเลขห้องซ้ำกัน

    -- ชั้น — CHECK 1-26 เพราะระบบออกแบบตามอาคาร 26 ชั้น
    "Floor"              INTEGER         NOT NULL CHECK ("Floor" BETWEEN 1 AND 26),
                                                            -- INTEGER = จำนวนเต็ม, CHECK = จำกัดให้อยู่ในช่วง 1-26 เท่านั้น

    -- ข้อจำกัดเรื่องเพศของห้อง
    -- 'male' = ห้องชาย เช่น ห้องฝั่งชายของชั้นนิสิต
    -- 'female' = ห้องหญิง เช่น ห้องฝั่งหญิงของชั้นนิสิต
    -- 'any' = ไม่จำกัดเพศ เช่น ห้องบุคลากรหรือห้องรายวัน
    "GenderRestriction"  VARCHAR(10)     NOT NULL DEFAULT 'any'  -- DEFAULT 'any' = ถ้าไม่ระบุถือว่าไม่จำกัดเพศ
                         CHECK ("GenderRestriction" IN ('male','female','any')),
                                                            -- CHECK = จำกัดให้เป็น 3 ค่านี้เท่านั้น

    -- สถานะห้อง — ใช้ใน UI เพื่อบอกว่าห้องนั้นสามารถจองได้หรือไม่
    -- available   = ว่าง จองได้
    -- occupied    = มีผู้พักอยู่
    -- reserved    = ถูกจองแล้วหรือรอเข้าพัก
    -- maintenance = อยู่ระหว่างซ่อมบำรุง
    "Status"             VARCHAR(20)     NOT NULL DEFAULT 'available'  -- DEFAULT 'available' = ห้องใหม่เริ่มต้นเป็นว่าง
                         CHECK ("Status" IN ('available','occupied','reserved','maintenance'))
                                                            -- CHECK = จำกัดให้เป็น 4 สถานะนี้เท่านั้น
);                                                          -- ปิดนิยามตาราง Room

-- ═══════════════════════════════════════════════════════════════════════════
-- TABLE 6: Reservation  (รายการจองห้อง)
-- ───────────────────────────────────────────────────────────────────────────
-- หน้าที่: หัวใจของระบบ — บันทึกทุกครั้งที่ผู้ใช้กดจองห้อง
-- ความสัมพันธ์:
--   M Reservation : 1 Member  (member 1 คน จองได้หลายครั้ง)
--   M Reservation : 1 Room    (ห้อง 1 ห้อง รับการจองหลายครั้ง — แต่คนละช่วงเวลา)
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE "Reservation" (                                -- สร้างตาราง Reservation บันทึกการจองทุกรายการ

    "ReservationID"   SERIAL          PRIMARY KEY,          -- รหัสการจอง เพิ่มอัตโนมัติ

    "MemberID"        INTEGER         NOT NULL               -- FK → Member, NOT NULL = ทุกการจองต้องมี member เจ้าของ
                      REFERENCES "Member"("MemberID"),      -- เชื่อมกับ Member.MemberID

    "RoomID"          INTEGER         NOT NULL               -- FK → Room, NOT NULL = ทุกการจองต้องระบุห้อง
                      REFERENCES "Room"("RoomID"),          -- เชื่อมกับ Room.RoomID

    "CheckInDate"     DATE            NOT NULL,             -- วันที่เข้าพัก DATE = เก็บแค่วัน (ไม่มีเวลา), NOT NULL = ต้องระบุ

    "CheckOutDate"    DATE            NOT NULL,             -- วันที่ออก DATE = เก็บแค่วัน, NOT NULL = ต้องระบุ

    -- วันเวลาที่ทำการจอง — DEFAULT NOW() ใส่อัตโนมัติเมื่อ INSERT
    "BookingDate"     TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
                                                            -- บันทึกเวลาที่กด Submit booking อัตโนมัติ

    -- จำนวนผู้พัก — ต้องไม่เกิน RoomType.MaxOccupancy (validate ที่ frontend ด้วย)
    "NumberOfGuests"  INTEGER         NOT NULL DEFAULT 1    -- DEFAULT 1 = ถ้าไม่ระบุถือว่าพักคนเดียว
                      CHECK ("NumberOfGuests" BETWEEN 1 AND 2),  -- CHECK = 1-2 คน สอดคล้องกับ MaxOccupancy

    -- ประเภทสัญญา — เก็บไว้เพื่อรู้ว่าเป็นสัญญาแบบไหนตอนคำนวณราคา
    -- แม้ราคาห้องจะเปลี่ยนภายหลัง ก็ยังรู้ว่าจองครั้งนั้นเป็น daily/monthly
    "ContractType"    VARCHAR(10)     NOT NULL               -- NOT NULL = ต้องระบุเสมอ
                      CHECK ("ContractType" IN ('daily','monthly')),  -- CHECK = 2 ค่านี้เท่านั้น

    -- ราคาที่ต้องชำระ — คำนวณตอนสร้างการจองแล้วเก็บเป็น snapshot
    -- ไม่ดึงจาก RoomType.BasePrice ตอน query เพื่อรับมือกรณีราคาห้องเปลี่ยนภายหลัง
    "TotalPrice"      NUMERIC(10,2)   NOT NULL CHECK ("TotalPrice" >= 0),
                                                            -- NUMERIC(10,2) = ทศนิยม 2 ตำแหน่ง, CHECK >= 0 = ห้ามติดลบ

    -- เงินมัดจำ — เฉพาะ monthly contract (เท่ากับค่าเช่า 1 เดือน)
    -- daily ไม่มีมัดจำ → ใส่ 0
    "DepositAmount"   NUMERIC(10,2)   NOT NULL DEFAULT 0    -- DEFAULT 0 = daily ไม่มีมัดจำ ไม่ต้องส่งค่ามาเอง
                      CHECK ("DepositAmount" >= 0),         -- CHECK = ห้ามมัดจำติดลบ

    -- สถานะการจอง — Workflow:
    --   pending → approved → completed   (ทางปกติ)
    --   pending → rejected               (ปฏิเสธ)
    --   approved → cancelled             (ยกเลิก เช่น ไม่จ่ายภายใน 3 วัน)
    "Status"          VARCHAR(20)     NOT NULL DEFAULT 'pending'  -- DEFAULT 'pending' = จองใหม่รอ staff อนุมัติก่อนเสมอ
                      CHECK ("Status" IN ('pending','approved','rejected','completed','cancelled')),
                                                            -- CHECK = จำกัด 5 สถานะนี้เท่านั้น

    -- วันที่ resident ยอมรับสัญญา — NULL ถ้ายังไม่ยอมรับ
    -- ใช้กำหนด step ใน flow Contract & Payment
    "ContractAgreedAt" TIMESTAMP,                           -- NULL ได้ = ยังไม่ยอมรับสัญญา, มีค่า = ยอมรับแล้วพร้อมชำระเงิน

    -- วันที่ staff อนุมัติ — ใช้นับ "เกิน 3 วันยังไม่จ่าย" สำหรับ overdue alert
    "ApprovedAt"      TIMESTAMP,                            -- NULL ได้ = ยังไม่อนุมัติ, มีค่า = อนุมัติแล้ว (เริ่มนับ 3 วัน)

    "CreatedAt"       TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,  -- วันเวลาสร้างการจอง บันทึกอัตโนมัติ
    "UpdatedAt"       TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,  -- วันเวลาแก้ไขล่าสุด (update ทุกครั้งที่ status เปลี่ยน)

    -- Constraint ระดับ row — เช็คว่า check-out > check-in ก่อน INSERT
    CONSTRAINT "chk_dates" CHECK ("CheckOutDate" > "CheckInDate")
                                                            -- ป้องกันข้อมูลผิด เช่น check-out ก่อน check-in
);                                                          -- ปิดนิยามตาราง Reservation


-- ═══════════════════════════════════════════════════════════════════════════
-- TABLE 7: ApprovalLog  (บันทึกการอนุมัติ)
-- ───────────────────────────────────────────────────────────────────────────
-- หน้าที่: เก็บประวัติทุกครั้งที่ Staff เปลี่ยนสถานะ Reservation
-- เหตุผล: เพื่อ audit trail (ตรวจสอบย้อนหลังว่าใครทำอะไร เมื่อไหร่ ทำไม)
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE "ApprovalLog" (                                -- สร้างตาราง ApprovalLog เก็บประวัติการอนุมัติ

    "LogID"          SERIAL          PRIMARY KEY,           -- รหัส log เพิ่มอัตโนมัติ

    -- FK → Reservation (1 reservation มี log หลายครั้งได้ เช่น approve → complete)
    "ReservationID"  INTEGER         NOT NULL               -- NOT NULL = ทุก log ต้องผูกกับ reservation
                     REFERENCES "Reservation"("ReservationID"),  -- FK เชื่อมกับ Reservation.ReservationID

    -- FK → Staff — รู้ว่าเจ้าหน้าที่คนไหนเป็นผู้กระทำ
    "StaffID"        INTEGER         NOT NULL               -- NOT NULL = ทุก action ต้องรู้ว่า staff คนไหนทำ
                     REFERENCES "Staff"("StaffID"),         -- FK เชื่อมกับ Staff.StaffID

    "Status"         VARCHAR(20)     NOT NULL               -- สถานะที่ถูก set ณ เวลานั้น NOT NULL = ต้องรู้ว่า action คืออะไร
                     CHECK ("Status" IN ('approved','rejected','completed','cancelled')),
                                                            -- CHECK = 4 action ที่ staff ทำได้เท่านั้น

    -- หมายเหตุ — staff สามารถใส่เหตุผลในการตัดสินใจ
    "Remark"         TEXT,                                  -- TEXT = ข้อความยาวได้, NULL ได้ (ไม่บังคับใส่เหตุผล)

    "CreatedAt"      TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP  -- วันเวลาที่ staff กด action บันทึกอัตโนมัติ
);                                                          -- ปิดนิยามตาราง ApprovalLog


-- ═══════════════════════════════════════════════════════════════════════════
-- TABLE 8: Payment  (การชำระเงิน)
-- ───────────────────────────────────────────────────────────────────────────
-- หน้าที่: เก็บข้อมูลการชำระเงินและการตรวจสอบสลิป
-- ความสัมพันธ์: 1 Reservation = 1 Payment (1:1) — ใช้ UNIQUE บน ReservationID
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE "Payment" (                                    -- สร้างตาราง Payment เก็บข้อมูลการชำระเงิน

    "PaymentID"           SERIAL          PRIMARY KEY,      -- รหัส payment เพิ่มอัตโนมัติ

    -- FK → Reservation (UNIQUE = enforce ความสัมพันธ์ 1:1)
    -- ทำไม UNIQUE? เพื่อป้องกันการมี Payment ซ้ำสำหรับ Reservation เดียวกัน
    "ReservationID"       INTEGER         NOT NULL UNIQUE   -- UNIQUE = 1 reservation มีได้แค่ 1 payment
                          REFERENCES "Reservation"("ReservationID"),  -- FK เชื่อมกับ Reservation.ReservationID

    -- FK → Staff (NULL = ยังไม่มีใครตรวจ)
    "VerifiedByStaffID"   INTEGER                           -- NULL ได้ = ยังไม่ผ่านการตรวจ, มีค่า = staff คนนี้เป็นคนตรวจ
                          REFERENCES "Staff"("StaffID"),    -- FK เชื่อมกับ Staff.StaffID

    "Amount"              NUMERIC(10,2)   NOT NULL CHECK ("Amount" > 0),
                                                            -- ยอดเงินที่ชำระ NUMERIC(10,2), CHECK > 0 = ห้ามส่งยอดเป็น 0 หรือติดลบ

    -- วิธีการชำระเงิน
    "PaymentMethod"       VARCHAR(20)     NOT NULL          -- NOT NULL = ต้องระบุวิธีชำระเสมอ
                          CHECK ("PaymentMethod" IN ('bank_transfer','qr_code','credit_card')),
                                                            -- CHECK = 3 วิธีนี้เท่านั้น

    "PaymentDate"         TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
                                                            -- วันเวลาที่ส่งสลิป บันทึกอัตโนมัติ

    -- URL รูปสลิป — เก็บ URL ไม่ใช่ไฟล์ตัวจริง
    -- ไฟล์เก็บใน Supabase Storage ส่วน DB เก็บเฉพาะ URL → DB เร็วกว่า
    "SlipImageURL"        TEXT,                             -- TEXT = URL ยาวได้ไม่จำกัด, NULL ได้ (ก่อนอัปโหลดสลิป)

    "Status"              VARCHAR(20)     NOT NULL DEFAULT 'pending'  -- DEFAULT 'pending' = ส่งสลิปแล้วรอตรวจก่อนเสมอ
                          CHECK ("Status" IN ('pending','verified','rejected')),
                                                            -- CHECK = 3 สถานะ: รอตรวจ, ผ่าน, ไม่ผ่าน

    -- วันเวลาที่ Staff ตรวจสลิป — NULL ถ้ายังไม่ตรวจ
    "VerifiedAt"          TIMESTAMP,                        -- NULL = ยังไม่ตรวจ, มีค่า = ตรวจแล้วพร้อม check-in

    -- หมายเหตุของ Staff เช่น "ยอดถูกต้อง" หรือ "สลิปไม่ชัด"
    "Note"                TEXT                              -- TEXT = ข้อความยาวได้, NULL ได้ (ไม่บังคับ)
);                                                          -- ปิดนิยามตาราง Payment


-- ═══════════════════════════════════════════════════════════════════════════
-- TABLE 9: Notification  (การแจ้งเตือน)
-- ───────────────────────────────────────────────────────────────────────────
-- หน้าที่: ส่งข้อความแจ้งเตือนผู้ใช้เมื่อมี event เกิดขึ้น
--          (จองสำเร็จ, อนุมัติ, ตรวจสลิปแล้ว, ฯลฯ)
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE "Notification" (                               -- สร้างตาราง Notification เก็บการแจ้งเตือน

    "NotificationID"  SERIAL          PRIMARY KEY,          -- รหัสการแจ้งเตือน เพิ่มอัตโนมัติ

    -- FK → Member (ผู้รับการแจ้งเตือน)
    "MemberID"        INTEGER         NOT NULL               -- NOT NULL = ทุกแจ้งเตือนต้องมีผู้รับ
                      REFERENCES "Member"("MemberID"),      -- FK เชื่อมกับ Member.MemberID

    -- FK → Reservation — ทุกการแจ้งเตือนต้องเกี่ยวข้องกับรายการจอง
    "ReservationID"   INTEGER         NOT NULL
                      REFERENCES "Reservation"("ReservationID"),  -- FK เชื่อมกับ Reservation.ReservationID

    -- ประเภทการแจ้งเตือน — string format เพื่อยืดหยุ่น
    -- เพิ่มประเภทใหม่ได้โดยไม่ต้อง ALTER TABLE
    -- ตัวอย่าง: 'booking_confirm', 'booking_approved', 'payment_verified'
    "Type"            VARCHAR(50)     NOT NULL,             -- NOT NULL = ต้องรู้ว่าเป็นการแจ้งเตือนประเภทอะไร

    "Message"         TEXT            NOT NULL,             -- ข้อความแจ้งเตือน TEXT = ยาวได้ไม่จำกัด, NOT NULL = ต้องมีข้อความ

    -- ช่องทางการส่ง — ปัจจุบันใช้ in_app เท่านั้น (เผื่อขยายในอนาคต)
    "Channel"         VARCHAR(20)     NOT NULL DEFAULT 'in_app'  -- DEFAULT 'in_app' = ส่งผ่านแอปก่อน เผื่อขยาย email/sms ทีหลัง
                      CHECK ("Channel" IN ('in_app','email','sms')),
                                                            -- CHECK = 3 ช่องทางนี้เท่านั้น

    "IsRead"          BOOLEAN         NOT NULL DEFAULT false,  -- false = ยังไม่อ่าน (default), true = อ่านแล้ว ใช้แสดง unread badge

    "SentAt"          TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,  -- วันเวลาส่งแจ้งเตือน บันทึกอัตโนมัติ
    "ReadAt"          TIMESTAMP                             -- NULL = ยังไม่อ่าน, มีค่า = วันเวลาที่ member เปิดอ่าน
);                                                          -- ปิดนิยามตาราง Notification


-- ═══════════════════════════════════════════════════════════════════════════
-- TABLE 10: ReservationGuest  (ข้อมูลรูมเมท)
-- ───────────────────────────────────────────────────────────────────────────
-- หน้าที่: เก็บข้อมูลผู้พักทั้งหมดในห้อง (รวมคนจองหลัก + รูมเมท)
-- เหตุผลแยกตาราง: 1 Reservation อาจมี 1-2 คน → many-to-one กับ Reservation
--                 ไม่ควรเก็บ array ใน Reservation (1NF normalization)
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE "ReservationGuest" (                           -- สร้างตาราง ReservationGuest เก็บข้อมูลผู้พักทุกคน

    "GuestID"        SERIAL          PRIMARY KEY,           -- รหัสผู้พัก เพิ่มอัตโนมัติ

    -- FK → Reservation
    -- ON DELETE CASCADE: ถ้าลบ Reservation → ลบข้อมูลผู้พักตามอัตโนมัติ
    "ReservationID"  INTEGER         NOT NULL               -- NOT NULL = ทุก guest ต้องผูกกับ reservation
                     REFERENCES "Reservation"("ReservationID") ON DELETE CASCADE,
                                                            -- CASCADE = ลบ Reservation ปุ๊บลบ guest ในห้องนั้นทั้งหมดตาม

    "FullName"       VARCHAR(100)    NOT NULL,              -- ชื่อ-นามสกุลผู้พัก ห้าม NULL (ต้องรู้ว่าใครพักอยู่)

    "IDCardNumber"   VARCHAR(13)     NOT NULL,              -- VARCHAR(13) = เลขบัตร 13 หลัก, หรือเลขพาสปอร์ต (ชาวต่างชาติไม่มีบัตรไทย)

    "Phone"          VARCHAR(20)     NOT NULL,              -- เบอร์โทรศัพท์ของผู้พัก ห้าม NULL

    -- IsPrimary — ระบุว่าใครเป็นผู้ทำสัญญาหลัก
    -- true  = คนจอง (ผู้รับผิดชอบสัญญา)
    -- false = รูมเมท (อยู่ร่วมในห้อง แต่ไม่ใช่ผู้รับผิดชอบ)
    "IsPrimary"      BOOLEAN         NOT NULL DEFAULT false,  -- DEFAULT false = ถ้าไม่ระบุถือว่าเป็นรูมเมท ป้องกันลืม set

    "CreatedAt"      TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP  -- วันเวลาเพิ่มข้อมูลผู้พัก บันทึกอัตโนมัติ
);                                                          -- ปิดนิยามตาราง ReservationGuest


-- ═══════════════════════════════════════════════════════════════════════════
-- INDEXES — เพิ่มประสิทธิภาพการ query
-- ───────────────────────────────────────────────────────────────────────────
-- เหตุผล: PostgreSQL จะ scan ทั้งตารางถ้าไม่มี index → ช้ามากเมื่อมีข้อมูลเยอะ
--         การสร้าง index บน column ที่ใช้ค้นหาบ่อยจะเร็วขึ้นเป็น 10-1000 เท่า
-- ═══════════════════════════════════════════════════════════════════════════

-- Index สำหรับ JOIN ระหว่าง Member/Staff กับ UserAccount (ใช้ตอน login)
CREATE INDEX idx_member_userid        ON "Member"("UserID");       -- เร็วขึ้นตอน SELECT Member WHERE UserID = ?
CREATE INDEX idx_staff_userid         ON "Staff"("UserID");        -- เร็วขึ้นตอน SELECT Staff WHERE UserID = ?

-- Index สำหรับ filter ห้องในหน้า Find a room (ฝั่ง resident)
CREATE INDEX idx_room_status          ON "Room"("Status");         -- เร็วขึ้นตอน filter WHERE Status = 'available'
CREATE INDEX idx_room_floor           ON "Room"("Floor");          -- เร็วขึ้นตอน filter ชั้น WHERE Floor = ?
CREATE INDEX idx_room_typeid          ON "Room"("RoomTypeID");     -- เร็วขึ้นตอน JOIN กับ RoomType

-- Index สำหรับ "My bookings" (filter การจองของ user คนเดียว)
CREATE INDEX idx_reservation_member   ON "Reservation"("MemberID");  -- เร็วขึ้นตอน WHERE MemberID = ? (ดูการจองของตัวเอง)
CREATE INDEX idx_reservation_room     ON "Reservation"("RoomID");    -- เร็วขึ้นตอน JOIN กับ Room
CREATE INDEX idx_reservation_status   ON "Reservation"("Status");    -- เร็วขึ้นตอน filter สถานะ WHERE Status = ?

-- Index สำหรับ Payment lookup
CREATE INDEX idx_payment_reservation  ON "Payment"("ReservationID"); -- เร็วขึ้นตอนหา payment ของการจองนั้น
CREATE INDEX idx_payment_status       ON "Payment"("Status");        -- เร็วขึ้นตอน filter WHERE Status = 'pending'

-- Index สำหรับการแสดง notification
CREATE INDEX idx_notification_member  ON "Notification"("MemberID"); -- เร็วขึ้นตอนดึงแจ้งเตือนของ member คนนั้น
CREATE INDEX idx_notification_isread  ON "Notification"("IsRead");   -- เร็วขึ้นตอนนับ unread badge WHERE IsRead = false

-- Index สำหรับดึงรูมเมทของ reservation
CREATE INDEX idx_resguest_reservation ON "ReservationGuest"("ReservationID"); -- เร็วขึ้นตอนดึงผู้พักทุกคนในห้องนั้น


-- ═══════════════════════════════════════════════════════════════════════════
-- หมายเหตุ:
--   ไฟล์นี้เป็น schema only — ไม่มี INSERT statement
--   สำหรับ sample data ดูที่ Data Dictionary ในรายงาน
-- ═══════════════════════════════════════════════════════════════════════════
