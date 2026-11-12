# EXAMPILOT – G8.8.2: FINAL ARCHITECTURE CONSISTENCY REVIEW

> **Mã tài liệu:** `g8_8_2_final_architecture_consistency_review.md`  
> **Đối tượng hiệu chỉnh:** [`g8_8_1_architecture_decisions_study_experience.md`](file:///c:/Flutter%20PJ/exampilot/g8_8_1_architecture_decisions_study_experience.md)  
> **Trạng thái:** DESIGN ONLY — Đã khóa kiến trúc cuối cùng trước khi bắt đầu Phase 1

---

## 1. TỔNG HỢP CÁC ĐIỂM ĐÃ SỬA TỪ G8.8.1

| Hạng mục | Lỗ hổng / Mâu thuẫn phát hiện ở G8.8.1 | Đã hiệu chỉnh dứt điểm tại G8.8.2 |
| :--- | :--- | :--- |
| **1. Công thức Timer & Heartbeat** | Heartbeat cộng dần vào `verified_study_seconds`, nhưng công thức hiển thị lại lấy hiệu từ `last_state_changed_at` cũ $\rightarrow$ **Gây cộng trùng thời gian sau mỗi 15 giây**. | Áp dụng mô hình **Single Checkpoint Anchor (`last_heartbeat_at`)**: mọi lần cộng delta vào `verified_study_seconds` đều phải tiến mốc `last_heartbeat_at` tương ứng theo cặp nguyên tử. `last_state_changed_at` không tham gia phép tính. |
| **2. Công thức Thống kê & 60p cũ + 30p mới** | Quy tắc cũ bỏ qua toàn bộ `actualMinutes` nếu `taskId` có `study_sessions` $\rightarrow$ **Làm mất 60 phút nhập thủ công lịch sử trước G8.8**. | Áp dụng kiến trúc **Disjoint Time Ledgers (Tách sổ độc lập)**: `study_sessions` chỉ lưu giờ Timer; `study_activities.actual_minutes` chỉ lưu giờ nhập tay & dữ liệu cũ; Timer không bao giờ ghi đè vào `actualMinutes`. |
| **3. Alarm State Machine vs Quyết định D2** | G8.8.1 có dòng `Ringing --> Dismissed: Timeout 10 phút` $\rightarrow$ **Vi phạm quyết định cố định D2**. Và giả định ca sau là `+7 ngày` $\rightarrow$ **Sai khi có tuần chẵn/lẻ & ngày nghỉ**. | Loại bỏ hoàn toàn auto-timeout Dismiss; `Ringing` chỉ dừng khi thao tác tường minh (`Dismiss`, `Snooze`, `Start`). Ca tuần tiếp theo phải qua `TimetableScheduleResolver` (G9.0). |
| **4. `study_date` NOT NULL & Chuẩn Timestamp** | SQL khai báo `study_date NOT NULL` nhưng mô tả lại nói "chỉ gán khi hoàn thành". Ví dụ JSON dùng lẫn lộn chuỗi có `Z` và chuỗi không múi giờ. | Quy định gán `study_date` **ngay lúc `Start`** (giữ qua nửa đêm & reboot); chuẩn hóa toàn bộ timestamp dùng **1 chuẩn ISO-8601 UTC (`...Z`)**. |
| **5. Thứ tự Pipeline Backup v2** | Vừa cấm status ngoài 3 giá trị cuối, vừa yêu cầu chuẩn hóa `running/paused` về `interrupted_pending`. | Tách thành **Pipeline 7 bước tuần tự**: Parse $\rightarrow$ Kiểm tra kiểu/status thô $\rightarrow$ Sanitize thành `interrupted_pending` $\rightarrow$ Kiểm tra status cuối & `ended_at` $\rightarrow$ Validate FK $\rightarrow$ Preview $\rightarrow$ Restore. |
| **6. Giới hạn Android & Xóa Channel** | Xóa channel cũ ngay khi đổi chuông làm chết pending notification và mất cài đặt người dùng; tuyên bố quá mức về bảo đảm tuyệt đối của `setAlarmClock` / Foreground Service. | Chuyển sang **8 Fixed Channel Registry** (tạo mới trước, re-schedule xong mới bỏ sử dụng, không xóa thô bạo); tách rõ 4 lớp năng lực Android vs giới hạn OEM. |

---

## 2. CÁC QUYẾT ĐỊNH KIẾN TRÚC CUỐI CÙNG (FINAL LOCKED DECISIONS)

1. **D1 (Timer Scope):** `study_sessions.subject_id` (nullable sau khi xóa môn, kèm `subject_name_snapshot NOT NULL`); `task_id` nullable kèm `task_title_snapshot`. Không dùng `ON DELETE CASCADE`; bắt buộc `ON DELETE SET NULL` và bật `PRAGMA foreign_keys = ON`.
2. **D2 (Alarm Ringing):** `Ringing` lặp chuông vô thời hạn về mặt State Machine cho tới khi user bấm **Tắt**, **Nhắc lại** (tối đa 1 lần / ca gốc), hoặc **Vào học ngay**.
3. **D3 (Recovery 3 lựa chọn):** Phiên bị kill/reboot buộc phải ở trạng thái `interrupted_pending`, tách biệt *Verified seconds* và *Unverified gap*, bắt buộc hỏi user trước khi cộng giờ. Không dùng `Stopwatch` trong RAM sau khi tiến trình bị hủy.
4. **Disjoint Time Ledgers:** Timer không ghi vào `study_activities.actual_minutes`, dữ liệu cũ không tạo session giả và không bị ghi đè.

---

## 3. CÔNG THỨC TIMER ĐÃ THỐNG NHẤT (SINGLE CHECKPOINT ANCHOR)

### Quy ước bất biến tại mọi bước cập nhật
- `verified_study_seconds` và `accumulated_break_seconds` luôn khớp chính xác 1-1 đến đúng dấu thời gian `last_heartbeat_at`.
- **Khi Heartbeat (15s) / Lifecycle Paused chạy tại $t_{\text{now}}$:**
  - Nếu `status == 'running'`:
    $$\Delta = \max(0, (t_{\text{now}} - t_{\text{last\_heartbeat}}).\text{inSeconds})$$
    $$\text{verified\_study\_seconds} \mathrel{+}= \Delta \quad;\quad t_{\text{last\_heartbeat}} \mathrel{+}= \text{Duration}(\text{seconds}: \Delta)$$
  - Nếu `status == 'in_break'`:
    $$\Delta = \max(0, (t_{\text{now}} - t_{\text{last\_heartbeat}}).\text{inSeconds})$$
    $$\text{accumulated\_break\_seconds} \mathrel{+}= \Delta \quad;\quad t_{\text{last\_heartbeat}} \mathrel{+}= \text{Duration}(\text{seconds}: \Delta)$$
- **Khi chuyển pha (`Pause`, `Resume`, `StartBreak`, `EndBreak`):** Chạy Checkpoint chốt pha cũ xong mới cập nhật `status` mới và đặt `last_heartbeat_at = t_now`, `last_state_changed_at = t_now`.

### Công thức hiển thị UI theo thời gian thực
- **`Running`:** $\text{displayedStudy} = \text{verified\_study\_seconds} + \max(0, (t_{\text{now}} - t_{\text{last\_heartbeat}}).\text{inSeconds})$ ; $\text{displayedBreak} = \text{accumulated\_break\_seconds}$
- **`Paused`:** $\text{displayedStudy} = \text{verified\_study\_seconds}$ ; $\text{displayedBreak} = \text{accumulated\_break\_seconds}$
- **`InBreak`:** $\text{displayedStudy} = \text{verified\_study\_seconds}$ ; $\text{displayedBreak} = \text{accumulated\_break\_seconds} + \max(0, (t_{\text{now}} - t_{\text{last\_heartbeat}}).\text{inSeconds})$

### Chứng minh ví dụ nhanh (0 cộng trùng, 0 mất lẻ giây)
- `08:00:00.000Z` Start: `verified=0`, `last_heartbeat_at=08:00:00.000Z`.
- `08:00:15.400Z` Heartbeat 1: $\Delta = 15\text{s} \rightarrow$ `verified=15`, `last_heartbeat_at=08:00:15.000Z` (giữ `.400s` dư).
- `08:00:20.200Z` Hiển thị: `15 + (08:00:20.200Z - 08:00:15.000Z).inSeconds = 15 + 5 = 20s` (Chính xác tuyệt đối).
- Background (không bị kill): Khi `resumed`, tính từ `last_heartbeat_at` $\rightarrow$ không mất 1 giây nào.
- Kill/Reboot (tiến trình mất): `Stopwatch` RAM mất, DB giữ `verified=15` tại `08:00:15.000Z` $\rightarrow$ mở lại kích hoạt Recovery Dialog (phân tách `15s` đã xác nhận và `unverified_gap`).

---

## 4. CÔNG THỨC THỐNG KÊ ĐÃ THỐNG NHẤT & 5 TEST CASE MINH HỌA

### Công thức chuẩn hóa
$$\text{Tổng phút học trong kỳ} = \underbrace{\sum_{\substack{s \in \text{study\_sessions} \cap \text{Kỳ} \\ s.\text{status} = \text{'completed'}}} \left\lfloor \frac{s.\text{verified\_study\_seconds}}{60} \right\rfloor}_{\text{Sổ cái Timer (Không bao gồm paused/cancelled/pending)}} + \underbrace{\sum_{a \in \text{study\_activities} \cap \text{Kỳ}} a.\text{actualMinutes}}_{\text{Sổ cái Thủ công & Lịch sử G1–G8.7}} + \underbrace{\text{ExtraLegacyAllTime}}_{\text{Task cũ hoàn thành thiếu activity}}$$

$$\text{Study Streak Dates} = \{ a.\text{dateKey} \mid a \in \text{study\_activities} \} \cup \{ s.\text{study\_date} \mid s \in \text{study\_sessions} \land s.\text{status} = \text{'completed'} \land s.\text{verified\_study\_seconds} \ge 60 \}$$

### 5 Test Case Minh họa
1. **Task chỉ có thời gian thủ công (`T1`):** Nhập tay `60p` trước G8.8 (`activity = 60`), `0` session $\rightarrow$ Thống kê: `0 + 60 = 60 phút`.
2. **Task có nhiều session (`T2`):** `activity = 0`, `S1` hôm qua (`1500s = 25p`), `S2` hôm nay (`2400s = 40p`) $\rightarrow$ Thống kê: `65 phút` (biểu đồ hôm qua 25p, hôm nay 40p; cả 2 ngày có Streak).
3. **Task có CẢ 60p thủ công cũ VÀ 30p Timer mới (`T3`):** `activity = 60` (từ trước G8.8) + `S3` hoàn thành (`1800s = 30p`). Timer KHÔNG ghi đè `activity.actualMinutes` $\rightarrow$ Thống kê: `30 + 60 = 90 phút` (0 mất dữ liệu cũ, 0 đếm trùng!).
4. **Session bị hủy (`T4`):** `S4` có `verified = 900s`, `status = 'cancelled'` $\rightarrow$ Bị loại khỏi thống kê (`0 phút`), không tăng Streak.
5. **Session chờ Recovery (`T5`):** `S5` đang ở trạng thái `interrupted_pending`, `verified = 1200s` $\rightarrow$ Bị loại khỏi thống kê và Streak (`0 phút`) cho tới khi người dùng bấm Xác nhận chuyển thành `completed`.

---

## 5. ALARM STATE MACHINE CUỐI CÙNG

```mermaid
stateDiagram-v2
    [*] --> Scheduled: Lên lịch One-shot hoặc Định kỳ

    Scheduled --> Cancelled: Sửa lịch / Xóa lịch / Tắt thông báo
    Scheduled --> Ringing: Đến giờ báo thức

    Ringing --> Snoozed: Bấm [Nhắc lại] (Chỉ khi snooze_count == 0)
    Ringing --> Dismissed: Bấm [Tắt báo thức]
    Ringing --> Started: Bấm [Vào học ngay]

    Snoozed --> Scheduled: Lên lịch lại ĐÚNG 1 LẦN (+5p, snooze_count=1)
    Started --> [*]: Dừng chuông -> Mở TimerScreen
    Dismissed --> CheckLoop{Loại lịch?}
    CheckLoop -->|One-shot| [*]
    CheckLoop -->|Định kỳ G9.0| NextSlot[TimetableScheduleResolver:\nXét tuần chẵn/lẻ, ngày nghỉ, ngoại lệ]
    NextSlot --> Scheduled
    Cancelled --> [*]
```

---

## 6. QUY TẮC TIMESTAMP VÀ `study_date`

1. **Chuẩn Timestamp duy nhất:** ISO-8601 UTC **`YYYY-MM-DDTHH:mm:ss.sssZ`** cho SQLite và Backup JSON. Đổi về `.toLocal()` khi hiển thị.
2. **Gán `study_date`:** Gán **ngay lúc `Start`** theo ngày lịch địa phương (`StudyStreak.formatDateKey(startedAt.toLocal())`), luôn khác NULL.
3. **Qua nửa đêm & Reboot:** Phiên bắt đầu lúc `23:30:00+07:00` ngày `11/11/2026` kết thúc lúc `00:15:00+07:00` ngày `12/11/2026`:
   - `started_at`: `"2026-11-11T16:30:00.000Z"`
   - `ended_at`: `"2026-11-11T17:15:00.000Z"`
   - `study_date`: **`"2026-11-11"`** (Giữ nguyên ngày bắt đầu phiên). Recovery sau reboot vẫn giữ nguyên `study_date` ban đầu của phiên đó.

---

## 7. PIPELINE BACKUP VALIDATION 7 BƯỚC (FORMAT V2 & V1)

1. **Bước 1:** Parse JSON $\rightarrow$ Kiểm tra `app == 'ExamPilot'`, `formatVersion <= 2` $\rightarrow$ Xác thực Checksum trên raw data.
2. **Bước 2:** Kiểm tra cấu trúc thô: `subjects/tasks/activities` là `List`; `v1` cho phép thiếu `sessions` (`[]`), `v2` bắt buộc `sessions` là `List`; kiểm tra các trường bắt buộc và `status` thô nằm trong 6 giá trị hợp lệ.
3. **Bước 3:** Sanitize trong RAM: Mọi phiên có status thô thuộc `{'running', 'paused', 'in_break'}` chuyển thành **`interrupted_pending`** và **`ended_at = null`**. (Cấm tự hoàn thành).
4. **Bước 4:** Kiểm tra sau chuẩn hóa: Tất cả sessions chỉ còn thuộc `{'completed', 'interrupted_pending', 'cancelled'}`. Phiên `completed` bắt buộc có `ended_at != null` hợp lệ.
5. **Bước 5:** Validate FK: Nếu `subject_id` hoặc `task_id` không có trong bản sao lưu, gán thành `null` nhưng giữ nguyên snapshot (`subject_name_snapshot`, `task_title_snapshot`).
6. **Bước 6:** Hiển thị Preview (cảnh báo cam nếu có phiên `interrupted_pending`).
7. **Bước 7:** Chỉ ghi SQLite Transaction / WebStorage sau khi user bấm **Xác nhận**.

---

## 8. CÁC GIỚI HẠN ANDROID CÒN TỒN TẠI & CHIẾN LƯỢC CHANNEL

- **Quản lý Channel:** Sử dụng cố định bộ 8 Channels (`exampilot_alarm_<sound>_v1` và `exampilot_break_<sound>_v1`). Khi đổi âm thanh: Tạo channel mới trước $\rightarrow$ Re-schedule pending alarms sang channel mới $\rightarrow$ Không xóa channel cũ một cách thiếu kiểm soát để bảo toàn cài đặt DND/Rung người dùng và tránh notification bắn nhầm vào channel đã xóa.
- **Phân biệt 4 lớp năng lực Android:** Lên lịch (`SCHEDULE_EXACT_ALARM`) $\ne$ Đánh thức CPU (`setAlarmClock`) $\ne$ Hiển thị Notification (`POST_NOTIFICATIONS` / `USE_FULL_SCREEN_INTENT`) $\ne$ Phát âm thanh liên tục (`ForegroundService` + `STREAM_ALARM`).

---

## 9. DANH SÁCH VẤN ĐỀ CHƯA THỂ BẢO ĐẢM & PHƯƠNG ÁN XỬ LÝ

| Vấn đề không thể bảo đảm tuyệt đối | Nguyên nhân kỹ thuật khách quan | Phương án xử lý & Giảm thiểu rủi ro |
| :--- | :--- | :--- |
| **1. OEM tự cắt âm thanh/Background Service trên máy Trung Quốc (Xiaomi, Oppo, Vivo)** | Hệ điều hành tùy biến của hãng chặn khởi chạy ngầm hoặc tắt Foreground Service khi máy nóng/tiết kiệm pin sâu. | Cung cấp mục *"Kiểm tra quyền & Hướng dẫn tối ưu pin"* trong Cài đặt để hướng dẫn bật *Autostart* và *Không hạn chế pin*; tuyệt đối không cam kết chạy 100% trên mọi OEM. |
| **2. Người dùng Force-Stop ứng dụng** | Cơ chế bảo mật gốc của Android xóa sạch 100% PendingIntent & BootReceiver sau Force-Stop. | Cảnh báo người dùng không Force-Stop nếu cần báo thức học tập; khi mở lại app sẽ tự phục hồi lịch còn lại. |
| **3. Âm lượng Alarm = 0 hoặc máy bật DND Total Silence** | Kiểm soát phần cứng/OS ở mức cao hơn ứng dụng. | Hiển thị Banner nhắc kiểm tra âm lượng Báo thức nếu người dùng vừa bật tính năng nhắc nhở; luôn hiển thị thông báo hình ảnh + rung dự phòng. |
| **4. Đóng Tab Trình duyệt trên Web Preview** | Kiến trúc sandbox của Chrome/Edge không cho phép chạy JavaScript/Audio khi Tab đã đóng. | Ghi chú minh bạch ngay trên màn hình Web Settings; dùng `WebSessionStorage` (`localStorage`) để bảo toàn dữ liệu phiên và khôi phục Recovery khi mở lại trang. |
| **5. Điểm cần bạn xác nhận cuối cùng trước Phase 1** | (a) Quy tắc giữ `study_date` theo `started_at` cho phiên qua nửa đêm; (b) Tách riêng ô nhập tay vs dòng Timer read-only trong `TaskAssessmentDialog`. | Đợi bạn xác nhận đồng ý hai điểm này trước khi bắt đầu code Phase 1. |

---
*Hoàn tất G8.8.2 Final Architecture Consistency Review. Hệ thống giữ nguyên trạng thái DESIGN ONLY và chờ phê duyệt của bạn.*
