// Schema định nghĩa cấu trúc dữ liệu trả về từ Gemini Vision Structured Output
export const TIMETABLE_JSON_SCHEMA = {
  type: "OBJECT",
  properties: {
    success: {
      type: "BOOLEAN",
      description: "True nếu nhận diện thành công ít nhất một bảng hoặc buổi học hợp lệ",
    },
    message: {
      type: "STRING",
      description: "Thông điệp tóm tắt kết quả phân tích thời khóa biểu",
    },
    weeks: {
      type: "ARRAY",
      description: "Danh sách các bảng thời khóa biểu theo từng tuần",
      items: {
        type: "OBJECT",
        properties: {
          startDate: {
            type: "STRING",
            description: "Ngày bắt đầu tuần (YYYY-MM-DD) nếu tiêu đề có ghi (ví dụ: 'Từ ngày 16/11/2026'). Để chuỗi rỗng nếu không có.",
          },
          endDate: {
            type: "STRING",
            description: "Ngày kết thúc tuần (YYYY-MM-DD) nếu có. Để chuỗi rỗng nếu không có.",
          },
          weekNumber: {
            type: "INTEGER",
            description: "Số thứ tự tuần nếu có (ví dụ 1, 2, 3), để 0 nếu không xác định",
          },
          classes: {
            type: "ARRAY",
            description: "Danh sách các buổi học được phát hiện trong tuần này",
            items: {
              type: "OBJECT",
              properties: {
                subject: {
                  type: "STRING",
                  description: "Tên môn học / học phần, đã lược bỏ tiền tố HP:, Mã HP:, STT",
                },
                classDate: {
                  type: "STRING",
                  description: "Ngày học cụ thể (YYYY-MM-DD) tính từ ngày đầu tuần và cột Thứ. Để chuỗi rỗng nếu không xác định được ngày cụ thể.",
                },
                weekday: {
                  type: "INTEGER",
                  description: "Thứ trong tuần (1=Thứ Hai, 2=Thứ Ba, 3=Thứ Tư, 4=Thứ Năm, 5=Thứ Sáu, 6=Thứ Bảy, 7=Chủ Nhật). Để 0 nếu chưa rõ.",
                },
                session: {
                  type: "STRING",
                  description: "Buổi học: 'morning', 'afternoon', hoặc 'evening'",
                },
                startPeriod: {
                  type: "INTEGER",
                  description: "Tiết học bắt đầu (ví dụ 1, 7). Để 0 nếu không có tiết.",
                },
                endPeriod: {
                  type: "INTEGER",
                  description: "Tiết học kết thúc (ví dụ 4, 10). Để 0 nếu không có tiết.",
                },
                startTime: {
                  type: "STRING",
                  description: "Giờ bắt đầu dạng HH:mm nếu ảnh ghi rõ giờ đồng hồ. Để chuỗi rỗng nếu chỉ có tiết học.",
                },
                endTime: {
                  type: "STRING",
                  description: "Giờ kết thúc dạng HH:mm nếu ảnh ghi rõ giờ đồng hồ. Để chuỗi rỗng nếu chỉ có tiết học.",
                },
                teacher: {
                  type: "STRING",
                  description: "Tên giảng viên đứng lớp (đã bỏ tiền tố GV:, ThS, TS), để chuỗi rỗng nếu không có.",
                },
                location: {
                  type: "STRING",
                  description: "Phòng học (ví dụ: '7.3.18', 'Lab 2', 'Online'), để chuỗi rỗng nếu không có.",
                },
                format: {
                  type: "STRING",
                  description: "Hình thức học: 'offline', 'online', hoặc 'hybrid'",
                },
                notes: {
                  type: "STRING",
                  description: "Thông tin bổ sung như link Google Meet, mã phòng họp, phần mềm",
                },
                confidence: {
                  type: "NUMBER",
                  description: "Mức độ tự tin nhận diện của AI từ 0.0 đến 1.0",
                },
                needsReview: {
                  type: "BOOLEAN",
                  description: "True nếu thiếu thông tin bắt buộc hoặc AI không chắc chắn, cần người dùng xem xét",
                },
                reviewReasons: {
                  type: "ARRAY",
                  description: "Danh sách lý do cần kiểm tra lại",
                  items: {
                    type: "STRING",
                  },
                },
              },
              required: [
                "subject",
                "weekday",
                "session",
                "startPeriod",
                "endPeriod",
                "confidence",
                "needsReview",
                "reviewReasons",
              ],
            },
          },
        },
        required: ["classes"],
      },
    },
    warnings: {
      type: "ARRAY",
      description: "Các cảnh báo phát hiện trong quá trình phân tích ảnh",
      items: {
        type: "STRING",
      },
    },
    summary: {
      type: "OBJECT",
      properties: {
        totalDetected: { type: "INTEGER" },
        validCount: { type: "INTEGER" },
        needsReviewCount: { type: "INTEGER" },
        ignoredCount: { type: "INTEGER" },
      },
      required: ["totalDetected", "validCount", "needsReviewCount", "ignoredCount"],
    },
  },
  required: ["success", "weeks", "summary"],
};
