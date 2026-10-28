import 'package:flutter_test/flutter_test.dart';
import 'package:vidyadesk/data/models.dart';

void main() {
  test('days code names', () {
    expect(daysCode([1, 3, 5]), 'MWF');
    expect(daysCode([6, 2, 4]), 'TTS');
    expect(daysCode([1, 2, 3, 4, 5, 6]), 'Mon–Sat');
  });
  test('time label', () {
    expect(timeLabel(17 * 60), '5:00 PM');
    expect(timeLabel(7 * 60 + 30), '7:30 AM');
  });
}
