import 'package:flutter_test/flutter_test.dart';
import 'package:focus_my_time/data/sync/sync_service.dart';

void main() {
  group('SyncService Encryption', () {
    test('Encrypts and decrypts normal password correctly', () {
      const password = 'my_super_secret_password_123!';
      final encrypted = SyncService.encryptForTesting(password);
      
      expect(encrypted, isNotEmpty);
      expect(encrypted, isNot(equals(password)));

      final decrypted = SyncService.decryptForTesting(encrypted);
      expect(decrypted, equals(password));
    });

    test('Encrypts and decrypts empty password as empty string', () {
      final encrypted = SyncService.encryptForTesting('');
      expect(encrypted, isEmpty);

      final decrypted = SyncService.decryptForTesting('');
      expect(decrypted, isEmpty);
    });

    test('Decrypts invalid base64 string as empty string safely', () {
      final decrypted = SyncService.decryptForTesting('invalid_base64_string_!!!!');
      expect(decrypted, isEmpty);
    });

    test('Encrypts and decrypts password containing unicode/chinese characters', () {
      const password = '密码123456★😊';
      final encrypted = SyncService.encryptForTesting(password);
      final decrypted = SyncService.decryptForTesting(encrypted);
      expect(decrypted, equals(password));
    });
  });
}
