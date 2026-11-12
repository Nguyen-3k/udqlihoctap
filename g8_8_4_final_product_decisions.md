# EXAMPILOT – G8.8.4: FINAL PRODUCT DECISION CONFIRMATION

> **Mã tài liệu:** `g8_8_4_final_product_decisions.md`  
> **Cơ sở cập nhật:** [`g8_8_1_architecture_decisions_study_experience.md`](file:///c:/Flutter%20PJ/exampilot/g8_8_1_architecture_decisions_study_experience.md), [`g8_8_2_final_architecture_consistency_review.md`](file:///c:/Flutter%20PJ/exampilot/g8_8_2_final_architecture_consistency_review.md), [`g8_8_3_product_rules_integration.md`](file:///c:/Flutter%20PJ/exampilot/g8_8_3_product_rules_integration.md)  
> **Loại hình:** Final Architecture & Product Lock (**DESIGN ONLY – Không sửa mã nguồn**)

---

## 1. HAI QUYẾT ĐỊNH CHÍNH THỨC ĐÃ TÍCH HỢP

### Quyết định 1 – Chính sách Study Streak với dữ liệu cũ (Chốt Phương án A + Bảo toàn lịch sử cũ)
- **Nguồn tính Streak duy nhất:** Verified Study Streak theo quy tắc mới **CHỈ được tính từ `study_sessions` (`status = 'completed'`)** khi tổng thời gian học thực tế (`verified_study_seconds`) trong 1 ngày lịch địa phương (`study_date`) đạt **$\ge 900$ giây (15 phút)**.
- **Không tạo dữ liệu giả & Không tạo cơ chế phụ:**
  - Tuyệt đối không chuyển đổi `study_activities` hay `actual_minutes` cũ thành `study_sessions` giả.
  - Không dùng thời gian nhập thủ công để tính hay chứng minh Streak mới.
  - Không tạo cơ chế cộng Streak thứ hai song song làm sai lệch chuẩn 15 phút/ngày.
- **Bảo toàn 100% lịch sử cũ & Hiển thị chuyển tiếp minh bạch:**
  1. Giữ nguyên toàn bộ `study_activities` và `study_tasks.actual_minutes` cũ trong SQLite, Web Storage và Backup v1/v2.
  2. Không xóa các ngày hoàn thành lịch sử cũ khi nâng cấp Schema v7.
  3. Phân tách rạch ròi trên giao diện (UX Transition Display):
     - **Thẻ Study Streak trên Tổng quan:** Hiển thị số ngày Streak chính thức từ `study_sessions` ($\ge 15\text{p}$ Đồng hồ/ngày). Nếu tồn tại dữ liệu lịch sử cũ trong `study_activities`, hiển thị kèm **nhãn/ghi chú chuyển tiếp rõ ràng**: *"Quy tắc mới: Cần $\ge 15$ phút học bằng Đồng hồ mỗi ngày. Lịch sử X ngày hoàn thành công việc cũ (Y phút) vẫn được bảo toàn nguyên vẹn trong mục Thống kê."*
     - **Mục Thống kê:** Hiển thị đầy đủ cả 2 sổ cái tách biệt (*Thời gian đo từ Đồng hồ* và *Thời gian thủ công & lịch sử cũ*), không gắn nhãn "Đã xác minh bằng Timer" cho dữ liệu nhập tay cũ.
  4. Backup/Restore v2 bảo toàn đồng thời cả `activities` cũ lẫn `sessions` mới; khôi phục Backup v1 vẫn nạp đủ lịch sử cũ mà không tự sinh Streak mới sai quy tắc.

### Quyết định 2 – Giới hạn học mặc định cho Lập lịch (`daily_study_limit_minutes = 240`)
- **Giá trị cấu hình:** Thêm `daily_study_limit_minutes` (mặc định **`240` phút = 4 giờ/ngày**) vào `user_profile`; người dùng có thể tự do thay đổi trong Cài đặt.
- **Phạm vi tác động:**
  - Là **ngưỡng tham khảo (Soft Reference Cap) DÀNH RIÊNG cho thuật toán AI / Smart Rescheduling (G9.0)** để tránh nhồi nhét quá nhiều buổi học gợi ý vào cùng một ngày.
  - Khi lập lịch bù, thuật toán tính:
    $$\text{AvailableBudget}(d) = \max\Big(0,\ \text{daily\_study\_limit\_minutes} - \big(\text{alreadyStudiedMinutes}(d) + \text{confirmedScheduledMinutes}(d)\big)\Big)$$
    Nếu ngày $d$ đã chạm hoặc vượt ngưỡng $240$ phút, thuật toán không đề xuất thêm buổi học thông thường vào ngày $d$ (tự dời sang ngày rảnh tiếp theo, hoặc cảnh báo trễ hạn nếu không đủ chỗ trước deadline), trừ khi người dùng chủ động tăng giới hạn hoặc tự đặt lịch tay.
  - **KHÔNG giới hạn Study Timer:** Timer không bao giờ bị khóa hay tự dừng khi vượt 240 phút. Nếu sinh viên chủ động học thêm (kể cả vượt lịch hay vượt 240 phút), toàn bộ phiên học vẫn được ghi nhận 100% vào `study_sessions`, Thống kê và Study Streak.

---

## 2. QUY TẮC NGÀY STREAK, DST & CHUYỂN MÚI GIỜ (`StudyStreak.parseDateKey`)

- **Định dạng ngày Streak:** Ngày lịch địa phương chuẩn `YYYY-MM-DD`, đóng dấu vào `study_date` tại thời điểm `started_at` (theo đúng G8.8.2).
- **Quy tắc Pure Calendar-Day Stepping (Sửa triệt để logic cũ trong `study_streak.dart`):**
  - **Cấm tuyệt đối** lấy chênh lệch mili giây chia cho 24 giờ (`a.difference(b).inDays`) hay trừ `Duration(days: 1)` trên `DateTime` địa phương để xác định 2 ngày liên tiếp (vì vào ngày đổi giờ DST dài 23h hoặc 25h, 24 giờ thực tế sẽ bị lệch sang 0 ngày hoặc 2 ngày lịch!).
  - Phải sử dụng bộ đại diện **Ngày Lịch Thuần Túy `(int year, int month, int day)`**:
    - `previousCalendarDay(y, m, d)` và `nextCalendarDay(y, m, d)` tính bằng phép tính số ngày thực tế trong tháng và năm nhuận của lịch Gregorian (hoặc chuẩn hóa tham số lịch `DateTime(y, m, d - 1)` chỉ để lấy `.year/.month/.day` rồi so sánh đẳng thức trực tiếp 3 thành phần `year, month, day`, **không dùng `difference().inDays` hay `Duration`**).
- **Xử lý thay đổi múi giờ thiết bị (Timezone Change):**
  - Mọi `study_date` lịch sử giữ cố định theo ngày lịch địa phương tại lúc bắt đầu học (`started_at`), không tự viết lại quá khứ khi thiết bị chuyển múi giờ.
  - Khi kiểm tra Streak hiện tại, ngày "hôm nay" là ngày lịch địa phương hiện hành của thiết bị (`DateTime.now().toLocal()`).
  - Tập hợp các ngày hợp lệ là `Set<String> ActiveStreakDates`: nhờ Pure Calendar Stepping và khóa chuỗi duy nhất `'YYYY-MM-DD'`, thay đổi DST hay thay đổi múi giờ không bao giờ tạo thêm ngày Streak giả hoặc làm mất chuỗi do chênh lệch giờ.

---

## 3. KIỂM TRA ĐỐI CHIẾU 8 TÌNH HUỐNG BẮT BUỘC

| STT | Tình huống kiểm thử | Xử lý theo Thiết kế cuối cùng | Kết quả mong đợi |
| :-: | :--- | :--- | :--- |
| **1** | Có `60 phút actual_minutes` cũ nhưng không có Timer | Dữ liệu giữ nguyên trong `study_activities`/`study_tasks`. Không sinh `study_session` giả. | Thống kê hiển thị **60 phút lịch sử cũ**. Verified Study Streak = **0** (không tạo Streak Timer mới). |
| **2** | Có ngày Streak lịch sử trước nâng cấp | Dữ liệu cũ nằm nguyên trong `study_activities`. | **Lịch sử cũ được bảo toàn 100%** và hiển thị chú thích chuyển tiếp rõ ràng trên UI; không bị đánh dấu nhầm là ngày Timer. |
| **3** | Học Timer 10 phút + 5 phút trong cùng ngày | `S1 (600s, completed)` + `S2 (300s, completed)` cùng `study_date`. | Tổng ngày = `900s` (15 phút) $\ge 900\text{s}$ $\rightarrow$ **Đạt +1 ngày Study Streak**. |
| **4** | Học Timer 60 phút trong ngày | `S1 (3600s, completed)` tại `study_date`. | `'YYYY-MM-DD'` chỉ xuất hiện 1 lần trong `Set<String>` $\rightarrow$ **Chỉ +1 ngày Streak**. |
| **5** | Đã học 240 phút nhưng vẫn mở Timer học thêm | Timer không bị chặn bởi `daily_study_limit_minutes`. User học thêm 45 phút. | Toàn bộ `285 phút` được **lưu đầy đủ** vào `study_sessions`, cộng đủ vào Thống kê (không xóa/từ chối). |
| **6** | AI đề xuất lịch khi ngày đã đạt giới hạn `240 phút` | `AvailableBudget(d) <= 0`. | AI **không tự đề xuất thêm lịch thông thường** vào ngày $d$ (trừ khi user tăng giới hạn hoặc tự chọn giờ thủ công). |
| **7** | Thay đổi giờ mùa hè (DST — ngày 23h hoặc 25h) | Pure Calendar Stepping (`(y, m, d)`), không chia mili giây cho 24h. | Chuyển tiếp giữa 2 ngày DST luôn đếm đúng 1 ngày liên tiếp, **0 ngày mất, 0 ngày Streak giả**. |
| **8** | Khôi phục Backup (v1 hoặc v2) | Backup chứa cả `activities` cũ và `sessions` mới; nạp trong 1 Transaction ACID. | **Bảo toàn nguyên vẹn lịch sử cũ**, không tạo session giả, Streak tái tính từ `sessions` `completed` theo `Set` ngày $\rightarrow$ **0 cộng trùng Streak**. |

---

## 4. BÁO CÁO XÁC NHẬN & TRẠNG THÁI SẴN SÀNG PHASE 1

1. **Xác nhận tích hợp đủ 2 quyết định cuối cùng:**
   - Đã cập nhật đồng bộ vào cả [`g8_8_1_architecture_decisions_study_experience.md`](file:///c:/Flutter%20PJ/exampilot/g8_8_1_architecture_decisions_study_experience.md) và [`g8_8_3_product_rules_integration.md`](file:///c:/Flutter%20PJ/exampilot/g8_8_3_product_rules_integration.md).
2. **Xác nhận tính nhất quán toàn diện (0 Mâu thuẫn):**
   - Khớp 100% với **G8.8.2** (`study_date` tại `started_at`, Timestamp UTC `...Z`, mô hình Timer Single Checkpoint Anchor, Sổ cái Thống kê tách biệt không ghi đè `actual_minutes`, Alarm State Machine không auto-timeout, Backup 7 bước).
   - Khớp 100% với **G8.8.3** (Study Streak 15p/ngày, phân tách 3 thực thể Task/Scheduled/Actual, AI là đề xuất, Smart Rescheduling).
3. **Các điểm còn chờ quyết định trước khi triển khai:**
   - **Không còn bất kỳ điểm mở hoặc mâu thuẫn nào cần xác nhận thêm.** Toàn bộ thiết kế đã hoàn tất và đồng bộ 100%.
4. **Khả năng khởi động Phase 1:**
   - **Đã đủ điều kiện để bắt đầu Phase 1 ngay sau khi bạn phê duyệt tài liệu này.** *(Hiện tại chưa chỉnh sửa source code, chưa nâng cấp SQLite Schema v6, chưa cài package và chưa build APK theo đúng quy tắc DESIGN ONLY).*

---
*Hoàn tất G8.8.4. Dừng lại để chờ người dùng xem xét và phê duyệt triển khai Phase 1.*
