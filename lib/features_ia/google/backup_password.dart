// Rules for the password of the encrypted backups (T002, round 3).
const kMinBackupPasswordLength = 10;

enum BackupPasswordStrength { weak, fair, strong }

bool isValidBackupPassword(String password) =>
    password.length >= kMinBackupPasswordLength;

/// A simple indicator: length first, then how many kinds of characters it mixes.
BackupPasswordStrength backupPasswordStrength(String password) {
  if (!isValidBackupPassword(password)) return BackupPasswordStrength.weak;

  final kinds = [
    RegExp('[a-z]'),
    RegExp('[A-Z]'),
    RegExp('[0-9]'),
    RegExp('[^A-Za-z0-9]'),
  ].where((r) => r.hasMatch(password)).length;

  if (password.length >= 16 || (password.length >= 12 && kinds >= 3)) {
    return BackupPasswordStrength.strong;
  }
  return kinds >= 2 ? BackupPasswordStrength.fair : BackupPasswordStrength.weak;
}
