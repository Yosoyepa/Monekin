// Pickers leave a temporary copy of the chosen file in the app cache. Once the app has its own copy, that one goes.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Deletes the picker copy at [path] and returns true, only when the file really is inside the app cache
/// ([cacheDir], the temporary directory by default). Files anywhere else, such as the user's own file, are never touched.
Future<bool> deletePickerCopy(String? path, {Directory? cacheDir}) async {
  if (path == null || path.isEmpty) return false;
  try {
    final file = File(path);
    if (!await file.exists()) return false;
    final cache = cacheDir ?? await getTemporaryDirectory();
    final realCache = await cache.resolveSymbolicLinks();
    final realFile = await file.resolveSymbolicLinks();
    if (!p.isWithin(realCache, realFile)) return false;
    await file.delete();
    return true;
  } on Exception {
    // A copy that cannot be removed only stays in the cache until the system clears it.
    return false;
  }
}
