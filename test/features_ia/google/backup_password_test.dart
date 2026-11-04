import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/google/backup_password.dart';

void main() {
  group('isValidBackupPassword', () {
    test('needs 12 characters', () {
      expect(isValidBackupPassword(''), isFalse);
      expect(isValidBackupPassword('elevenchars'), isFalse);
      expect(isValidBackupPassword('twelve chars'), isTrue);
      expect(isValidBackupPassword('abcdefghijkl'), isTrue);
    });

    test('or 4 words, even if short', () {
      expect(isValidBackupPassword('sol luna mar rio'), isTrue);
      expect(isValidBackupPassword('sol luna ma'), isFalse);
      expect(
        isValidBackupPassword('a b c d'),
        isFalse,
        reason: 'one-letter words',
      );
      expect(isValidBackupPassword('sol  luna\tmar\nrio'), isTrue);
    });

    test('the limits are the ones the sheet announces', () {
      expect(kMinBackupPasswordLength, 12);
      expect(kMinBackupPassphraseWords, 4);
    });
  });

  group('backupPasswordStrength', () {
    test('an invalid password is weak', () {
      expect(backupPasswordStrength('short'), BackupPasswordStrength.weak);
      expect(backupPasswordStrength(''), BackupPasswordStrength.weak);
    });

    test('a valid one is at least fair', () {
      expect(
        backupPasswordStrength('abcdefghijkl'),
        BackupPasswordStrength.fair,
      );
      expect(
        backupPasswordStrength('sol luna mar rio'),
        BackupPasswordStrength.fair,
      );
    });

    test('a long one or a phrase of five words is strong', () {
      expect(
        backupPasswordStrength('abcdefghijklmnopqrst'),
        BackupPasswordStrength.strong,
      );
      expect(
        backupPasswordStrength('sol luna mar rio cielo'),
        BackupPasswordStrength.strong,
      );
      expect(
        backupPasswordStrength('Chanchi-2026-ahorro'),
        BackupPasswordStrength.strong,
      );
    });
  });
}
