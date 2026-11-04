// Rules for the password of the encrypted backups (T002, round 4). Anyone holding a
// copy can try passwords offline, so length is what counts: a phrase is recommended.
const kMinBackupPasswordLength = 12;

/// A phrase of this many words is enough even if it is shorter than
/// [kMinBackupPasswordLength].
const kMinBackupPassphraseWords = 4;

const _minWordLength = 2;

enum BackupPasswordStrength { weak, fair, strong }

/// Number of words of at least two characters separated by spaces.
int backupPasswordWords(String password) => password
    .split(RegExp(r'\s+'))
    .where((word) => word.length >= _minWordLength)
    .length;

/// At least [kMinBackupPasswordLength] characters, or [kMinBackupPassphraseWords]
/// words.
bool isValidBackupPassword(String password) =>
    password.length >= kMinBackupPasswordLength ||
    backupPasswordWords(password) >= kMinBackupPassphraseWords;

/// A simple indicator: a valid password is fair, a long one or a phrase of five words
/// is strong.
BackupPasswordStrength backupPasswordStrength(String password) {
  if (!isValidBackupPassword(password)) return BackupPasswordStrength.weak;

  final kinds = [
    RegExp('[a-z]'),
    RegExp('[A-Z]'),
    RegExp('[0-9]'),
    RegExp('[^A-Za-z0-9]'),
  ].where((r) => r.hasMatch(password)).length;

  if (password.length >= 20 ||
      backupPasswordWords(password) >= kMinBackupPassphraseWords + 1 ||
      (password.length >= 16 && kinds >= 3)) {
    return BackupPasswordStrength.strong;
  }
  return BackupPasswordStrength.fair;
}
