import 'package:flutter_test/flutter_test.dart';
import 'package:setsuna/services/update_check_service.dart';

void main() {
  group('isNewerVersion', () {
    test('compares dotted versions numerically', () {
      expect(isNewerVersion('1.2.3', '1.2.4'), isTrue);
      expect(isNewerVersion('1.10.0', '1.9.9'), isFalse);
      expect(isNewerVersion('0.0.0+12', 'v1.0.5'), isTrue);
      expect(isNewerVersion('2.5.5', '2.5.5'), isFalse);
      // Short versions are padded with zeros.
      expect(isNewerVersion('1.2', '1.2.0'), isFalse);
      expect(isNewerVersion('1.2', '1.2.1'), isTrue);
    });
  });
}
