// Module chuẩn hóa và xác thực dữ liệu phản hồi từ AI phía server

const PROHIBITED_SUBJECT_NAMES = new Set([
  "thứ",
  "thứ hai",
  "thứ 2",
  "thứ ba",
  "thứ 3",
  "thứ tư",
  "thứ 4",
  "thứ năm",
  "thứ 5",
  "thứ sáu",
  "thứ 6",
  "thứ bảy",
  "thứ 7",
  "chủ nhật",
  "t2",
  "t3",
  "t4",
  "t5",
  "t6",
  "t7",
  "cn",
  "buổi",
  "sáng",
  "chiều",
  "tối",
  "tiết",
  "stt",
  "hp",
  "mã hp",
  "tên hp",
  "học phần",
  "giảng viên",
  "gv",
  "phòng",
  "phòng học",
  "hình thức",
  "thời khóa biểu",
  "lịch học",
  "tuần",
  "ngày",
]);

export interface NormalizedClass {
  subject: string;
  classDate: string | null;
  weekday: number | null;
  session: "morning" | "afternoon" | "evening" | null;
  startPeriod: number | null;
  endPeriod: number | null;
  startTime: string | null;
  endTime: string | null;
  teacher: string | null;
  location: string | null;
  format: "offline" | "online" | "hybrid" | null;
  notes: string | null;
  confidence: number;
  needsReview: boolean;
  reviewReasons: string[];
}

export interface NormalizedWeek {
  startDate: string | null;
  endDate: string | null;
  weekNumber: number | null;
  classes: NormalizedClass[];
}

export interface NormalizedTimetableResult {
  success: boolean;
  message: string;
  weeks: NormalizedWeek[];
  warnings: string[];
  summary: {
    totalDetected: number;
    validCount: number;
    needsReviewCount: number;
    ignoredCount: number;
  };
}

export function validateAndNormalizeAiResponse(raw: any): NormalizedTimetableResult {
  const warnings: string[] = Array.isArray(raw?.warnings)
    ? raw.warnings.map((w: any) => String(w).trim()).filter(Boolean)
    : [];

  const rawWeeks = Array.isArray(raw?.weeks) ? raw.weeks : [];
  const normalizedWeeks: NormalizedWeek[] = [];

  let totalDetected = 0;
  let validCount = 0;
  let needsReviewCount = 0;
  let ignoredCount = 0;

  for (const w of rawWeeks) {
    const rawClasses = Array.isArray(w?.classes) ? w.classes : [];
    const normalizedClasses: NormalizedClass[] = [];

    for (const c of rawClasses) {
      let subject = typeof c?.subject === "string" ? c.subject.trim() : "";
      
      // Lọc bỏ tiền tố HP:, Học phần: nếu Gemini chưa lọc hết
      subject = subject.replace(/^(?:HP|Học\s*phần|Tên\s*HP|Môn\s*học|Môn)\s*[:\.\-]\s*/i, "").trim();

      // Kiểm tra tên môn học rác / tiêu đề
      if (!subject || PROHIBITED_SUBJECT_NAMES.has(subject.toLowerCase())) {
        ignoredCount++;
        continue;
      }

      // Chuẩn hóa ngày (YYYY-MM-DD)
      let classDate: string | null = null;
      if (typeof c?.classDate === "string" && /^\d{4}-\d{2}-\d{2}$/.test(c.classDate.trim())) {
        classDate = c.classDate.trim();
      }

      // Chuẩn hóa thứ trong tuần (1..7)
      let weekday: number | null = null;
      const parsedWeekday = Number(c?.weekday);
      if (parsedWeekday >= 1 && parsedWeekday <= 7) {
        weekday = parsedWeekday;
      }

      // Chuẩn hóa buổi
      let session: "morning" | "afternoon" | "evening" | null = null;
      const s = String(c?.session || "").toLowerCase();
      if (s.includes("morn") || s.includes("sáng")) session = "morning";
      else if (s.includes("after") || s.includes("chiều")) session = "afternoon";
      else if (s.includes("even") || s.includes("tối")) session = "evening";

      // Chuẩn hóa tiết học
      let startPeriod: number | null = null;
      let endPeriod: number | null = null;
      if (c?.startPeriod != null && Number(c.startPeriod) > 0) {
        startPeriod = Number(c.startPeriod);
      }
      if (c?.endPeriod != null && Number(c.endPeriod) > 0) {
        endPeriod = Number(c.endPeriod);
      }

      // Chuẩn hóa giờ đồng hồ
      let startTime: string | null = null;
      let endTime: string | null = null;
      if (typeof c?.startTime === "string" && /^\d{1,2}:\d{2}$/.test(c.startTime.trim())) {
        startTime = c.startTime.trim();
      }
      if (typeof c?.endTime === "string" && /^\d{1,2}:\d{2}$/.test(c.endTime.trim())) {
        endTime = c.endTime.trim();
      }

      // Chuẩn hóa độ tin cậy (0..1)
      let confidence = Number(c?.confidence);
      if (isNaN(confidence) || confidence < 0) confidence = 0.5;
      if (confidence > 1) confidence = 1.0;

      const reviewReasons: string[] = Array.isArray(c?.reviewReasons)
        ? c.reviewReasons.map((r: any) => String(r).trim()).filter(Boolean)
        : [];

      let needsReview = Boolean(c?.needsReview);

      if (weekday === null) {
        needsReview = true;
        reviewReasons.push("Chưa xác định được Thứ trong tuần");
      }
      if (classDate === null) {
        needsReview = true;
        reviewReasons.push("Chưa xác định được ngày học cụ thể");
      }
      if (startTime === null || endTime === null) {
        needsReview = true;
        if (startPeriod !== null && endPeriod !== null) {
          reviewReasons.push(`Chưa có giờ cụ thể (Tiết ${startPeriod}-${endPeriod})`);
        } else {
          reviewReasons.push("Thiếu thông tin giờ học");
        }
      }

      const normalizedItem: NormalizedClass = {
        subject,
        classDate,
        weekday,
        session,
        startPeriod,
        endPeriod,
        startTime,
        endTime,
        teacher: typeof c?.teacher === "string" && c.teacher.trim() ? c.teacher.trim() : null,
        location: typeof c?.location === "string" && c.location.trim() ? c.location.trim() : null,
        format: c?.format === "online" ? "online" : c?.format === "hybrid" ? "hybrid" : "offline",
        notes: typeof c?.notes === "string" && c.notes.trim() ? c.notes.trim() : null,
        confidence,
        needsReview,
        reviewReasons,
      };

      normalizedClasses.push(normalizedItem);
      totalDetected++;

      if (needsReview) {
        needsReviewCount++;
      } else {
        validCount++;
      }
    }

    if (normalizedClasses.length > 0) {
      let startDate: string | null = null;
      let endDate: string | null = null;
      if (typeof w?.startDate === "string" && /^\d{4}-\d{2}-\d{2}$/.test(w.startDate.trim())) {
        startDate = w.startDate.trim();
      }
      if (typeof w?.endDate === "string" && /^\d{4}-\d{2}-\d{2}$/.test(w.endDate.trim())) {
        endDate = w.endDate.trim();
      }

      normalizedWeeks.push({
        startDate,
        endDate,
        weekNumber: w?.weekNumber ? Number(w.weekNumber) : null,
        classes: normalizedClasses,
      });
    }
  }

  const success = totalDetected > 0;
  const message = success
    ? `Đã phân tích thành công ${totalDetected} buổi học (${validCount} hợp lệ, ${needsReviewCount} cần xác nhận)`
    : "Không tìm thấy buổi học hợp lệ trong hình ảnh.";

  return {
    success,
    message,
    weeks: normalizedWeeks,
    warnings,
    summary: {
      totalDetected,
      validCount,
      needsReviewCount,
      ignoredCount,
    },
  };
}
