import 'package:flutter_test/flutter_test.dart';
import 'package:exampilot/services/class_period_time_mapper.dart';

void main() {
  group('ClassPeriodTimeMapper - Quy đổi khung giờ chính thức (Phase 6D.2)', () {
    // -----------------------------------------------------------------------
    // 1. Tiết 1–2 → 07:00–08:30
    // -----------------------------------------------------------------------
    test('Case 1: Tiết 1–2 quy đổi thành 07:00–08:30', () {
      final res = ClassPeriodTimeMapper.mapPeriodsToTime(1, 2);
      expect(res, isNotNull);
      expect(res!.startTime, '07:00');
      expect(res.endTime, '08:30');
      expect(res.actualStudyMinutes, 90); // 2 * 45
      expect(res.totalSpanMinutes, 90);
      expect(res.hasBreak, isFalse);
      expect(res.breakMinutes, 0);
    });

    // -----------------------------------------------------------------------
    // 2. Tiết 3–4 → 09:00–10:30
    // -----------------------------------------------------------------------
    test('Case 2: Tiết 3–4 quy đổi thành 09:00–10:30', () {
      final res = ClassPeriodTimeMapper.mapPeriodsToTime(3, 4);
      expect(res, isNotNull);
      expect(res!.startTime, '09:00');
      expect(res.endTime, '10:30');
      expect(res.actualStudyMinutes, 90); // 2 * 45
      expect(res.totalSpanMinutes, 90);
      expect(res.hasBreak, isFalse);
      expect(res.breakMinutes, 0);
    });

    // -----------------------------------------------------------------------
    // 3. Tiết 1–4 → 07:00–10:30
    // -----------------------------------------------------------------------
    test('Case 3: Tiết 1–4 quy đổi thành 07:00–10:30', () {
      final res = ClassPeriodTimeMapper.mapPeriodsToTime(1, 4);
      expect(res, isNotNull);
      expect(res!.startTime, '07:00');
      expect(res.endTime, '10:30');
      expect(res.actualStudyMinutes, 180); // 4 * 45 = 180 phút
      expect(res.totalSpanMinutes, 210); // 07:00 đến 10:30 = 210 phút
      expect(res.hasBreak, isTrue); // Nghỉ giữa tiết 2 và 3 (08:30-09:00)
      expect(res.breakMinutes, 30);
    });

    // -----------------------------------------------------------------------
    // 4. Tiết 7–8 → 13:30–15:00
    // -----------------------------------------------------------------------
    test('Case 4: Tiết 7–8 quy đổi thành 13:30–15:00', () {
      final res = ClassPeriodTimeMapper.mapPeriodsToTime(7, 8);
      expect(res, isNotNull);
      expect(res!.startTime, '13:30');
      expect(res.endTime, '15:00');
      expect(res.actualStudyMinutes, 90);
      expect(res.totalSpanMinutes, 90);
      expect(res.hasBreak, isFalse);
      expect(res.breakMinutes, 0);
    });

    // -----------------------------------------------------------------------
    // 5. Tiết 9–10 → 15:30–17:00
    // -----------------------------------------------------------------------
    test('Case 5: Tiết 9–10 quy đổi thành 15:30–17:00', () {
      final res = ClassPeriodTimeMapper.mapPeriodsToTime(9, 10);
      expect(res, isNotNull);
      expect(res!.startTime, '15:30');
      expect(res.endTime, '17:00');
      expect(res.actualStudyMinutes, 90);
      expect(res.totalSpanMinutes, 90);
      expect(res.hasBreak, isFalse);
      expect(res.breakMinutes, 0);
    });

    // -----------------------------------------------------------------------
    // 6. Tiết 7–10 → 13:30–17:00
    // -----------------------------------------------------------------------
    test('Case 6: Tiết 7–10 quy đổi thành 13:30–17:00', () {
      final res = ClassPeriodTimeMapper.mapPeriodsToTime(7, 10);
      expect(res, isNotNull);
      expect(res!.startTime, '13:30');
      expect(res.endTime, '17:00');
      expect(res.actualStudyMinutes, 180); // 4 * 45 = 180 phút
      expect(res.totalSpanMinutes, 210); // 13:30 đến 17:00 = 210 phút
      expect(res.hasBreak, isTrue); // Nghỉ giữa tiết 8 và 9 (15:00-15:30)
      expect(res.breakMinutes, 30);
    });

    // -----------------------------------------------------------------------
    // 7. Tiết 5–6 → không có cấu hình, không tự sinh giờ
    // -----------------------------------------------------------------------
    test('Case 7: Tiết 5, 6 hoặc chứa 5, 6 trả về null (chưa có cấu hình)', () {
      expect(ClassPeriodTimeMapper.mapPeriodsToTime(5, 6), isNull);
      expect(ClassPeriodTimeMapper.mapPeriodsToTime(5, 5), isNull);
      expect(ClassPeriodTimeMapper.mapPeriodsToTime(6, 6), isNull);
      expect(ClassPeriodTimeMapper.mapPeriodsToTime(1, 5), isNull);
      expect(ClassPeriodTimeMapper.mapPeriodsToTime(4, 6), isNull);
      expect(ClassPeriodTimeMapper.mapPeriodsToTime(6, 8), isNull);
      expect(ClassPeriodTimeMapper.isConfiguredPeriod(5), isFalse);
      expect(ClassPeriodTimeMapper.isConfiguredPeriod(6), isFalse);
    });

    // -----------------------------------------------------------------------
    // 8. Tiết bắt đầu lớn hơn tiết kết thúc → dữ liệu không hợp lệ
    // -----------------------------------------------------------------------
    test('Case 8: Tiết bắt đầu > tiết kết thúc trả về null', () {
      expect(ClassPeriodTimeMapper.mapPeriodsToTime(4, 2), isNull);
      expect(ClassPeriodTimeMapper.mapPeriodsToTime(10, 7), isNull);
      expect(ClassPeriodTimeMapper.mapPeriodsToTime(3, 1), isNull);
      expect(ClassPeriodTimeMapper.mapPeriodsToTime(8, 7), isNull);
    });

    // -----------------------------------------------------------------------
    // 9. Kiểm tra thời lượng thực học không bao gồm giờ nghỉ giải lao
    // -----------------------------------------------------------------------
    test('Case 9: Thời lượng học thực tế không bao gồm thời gian giải lao 30 phút', () {
      // Tiết 1-4: tổng khoảng 210p, thực học 180p
      final res14 = ClassPeriodTimeMapper.mapPeriodsToTime(1, 4);
      expect(res14!.actualStudyMinutes, 180);
      expect(res14.totalSpanMinutes - res14.actualStudyMinutes, 30);
      expect(ClassPeriodTimeMapper.getActualStudyMinutes(1, 4), 180);

      // Tiết 7-10: tổng khoảng 210p, thực học 180p
      final res710 = ClassPeriodTimeMapper.mapPeriodsToTime(7, 10);
      expect(res710!.actualStudyMinutes, 180);
      expect(res710.totalSpanMinutes - res710.actualStudyMinutes, 30);
      expect(ClassPeriodTimeMapper.getActualStudyMinutes(7, 10), 180);

      // Tiết 1-3: Tiết 1 (45p) + Tiết 2 (45p) + Giải lao (30p) + Tiết 3 (45p) = Tổng 165p, thực học 135p
      final res13 = ClassPeriodTimeMapper.mapPeriodsToTime(1, 3);
      expect(res13!.actualStudyMinutes, 135);
      expect(res13.totalSpanMinutes, 165);
      expect(res13.hasBreak, isTrue);
      expect(res13.breakMinutes, 30);

      // Tiết 7-9: Tổng 165p, thực học 135p
      final res79 = ClassPeriodTimeMapper.mapPeriodsToTime(7, 9);
      expect(res79!.actualStudyMinutes, 135);
      expect(res79.totalSpanMinutes, 165);
      expect(res79.hasBreak, isTrue);
      expect(res79.breakMinutes, 30);
    });

    // -----------------------------------------------------------------------
    // 10. Kiểm tra không làm thay đổi số tiết gốc sau khi quy đổi
    // -----------------------------------------------------------------------
    test('Case 10: Số tiết gốc startPeriod và endPeriod được bảo toàn chính xác', () {
      const origStart = 1;
      const origEnd = 4;
      final res = ClassPeriodTimeMapper.mapPeriodsToTime(origStart, origEnd);
      expect(res!.startPeriod, origStart);
      expect(res.endPeriod, origEnd);
      expect(res.periodRangeText, 'Tiết 1-4');
    });

    // -----------------------------------------------------------------------
    // 11. Kiểm tra tiết học đơn lẻ (tiết 1, 2, 3, 4, 7, 8, 9, 10)
    // -----------------------------------------------------------------------
    test('Case 11: Tiết học đơn lẻ 1 tiết', () {
      final t1 = ClassPeriodTimeMapper.mapPeriodsToTime(1, 1);
      expect(t1!.startTime, '07:00');
      expect(t1.endTime, '07:45');
      expect(t1.actualStudyMinutes, 45);

      final t2 = ClassPeriodTimeMapper.mapPeriodsToTime(2, 2);
      expect(t2!.startTime, '07:45');
      expect(t2.endTime, '08:30');
      expect(t2.actualStudyMinutes, 45);

      final t3 = ClassPeriodTimeMapper.mapPeriodsToTime(3, 3);
      expect(t3!.startTime, '09:00');
      expect(t3.endTime, '09:45');
      expect(t3.actualStudyMinutes, 45);

      final t4 = ClassPeriodTimeMapper.mapPeriodsToTime(4, 4);
      expect(t4!.startTime, '09:45');
      expect(t4.endTime, '10:30');
      expect(t4.actualStudyMinutes, 45);

      final t7 = ClassPeriodTimeMapper.mapPeriodsToTime(7, 7);
      expect(t7!.startTime, '13:30');
      expect(t7.endTime, '14:15');
      expect(t7.actualStudyMinutes, 45);

      final t8 = ClassPeriodTimeMapper.mapPeriodsToTime(8, 8);
      expect(t8!.startTime, '14:15');
      expect(t8.endTime, '15:00');
      expect(t8.actualStudyMinutes, 45);

      final t9 = ClassPeriodTimeMapper.mapPeriodsToTime(9, 9);
      expect(t9!.startTime, '15:30');
      expect(t9.endTime, '16:15');
      expect(t9.actualStudyMinutes, 45);

      final t10 = ClassPeriodTimeMapper.mapPeriodsToTime(10, 10);
      expect(t10!.startTime, '16:15');
      expect(t10.endTime, '17:00');
      expect(t10.actualStudyMinutes, 45);
    });

    // -----------------------------------------------------------------------
    // 12. Trường hợp ngoại lệ & vắt ca sáng chiều
    // -----------------------------------------------------------------------
    test('Case 12: Trường hợp ngoại lệ (khoảng tiết vắt qua sáng chiều, số âm, null)', () {
      expect(ClassPeriodTimeMapper.mapPeriodsToTime(null, 4), isNull);
      expect(ClassPeriodTimeMapper.mapPeriodsToTime(1, null), isNull);
      expect(ClassPeriodTimeMapper.mapPeriodsToTime(-1, 2), isNull);
      expect(ClassPeriodTimeMapper.mapPeriodsToTime(0, 4), isNull);
      expect(ClassPeriodTimeMapper.mapPeriodsToTime(1, 11), isNull);
      expect(ClassPeriodTimeMapper.mapPeriodsToTime(4, 7), isNull); // Vắt sáng sang chiều
      expect(ClassPeriodTimeMapper.mapPeriodsToTime(3, 8), isNull);
      expect(ClassPeriodTimeMapper.getActualStudyMinutes(null, null), isNull);
    });
  });
}
