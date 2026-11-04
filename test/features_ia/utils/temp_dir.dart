import 'dart:io';

/// Deletes the temporary folder of a test.
///
/// On Windows a file can stay locked for a moment after the code under test closes it (antivirus,
/// indexer or a write that is still finishing), and `deleteSync` then throws errno 32. A leftover
/// temporary folder is not a test failure, so this retries for about a second and then gives up
/// quietly.
Future<void> deleteTempDir(Directory dir) async {
  for (var attempt = 0; attempt < 10; attempt++) {
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      return;
    } on FileSystemException {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}
