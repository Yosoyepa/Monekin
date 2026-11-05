import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/core/database/backup/restore_lock.dart';
import 'package:path/path.dart' as p;

Future<bool> _triesInOtherIsolate(String dbPath) => Isolate.run(() async {
  final lock = await RestoreLock.tryAcquire(dbPath);
  await lock?.release();
  return lock != null;
});

/// The token of a process that is not this one: the next pid.
String anotherProcess() => '${int.parse(processToken().split(':').first) + 1}';

void main() {
  late Directory root;
  late String dbPath;

  setUp(() {
    root = Directory.systemTemp.createTempSync('restore_lock_test');
    dbPath = p.join(root.path, 'monekin.db');
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('is free until someone takes it', () async {
    expect(await RestoreLock.isHeld(dbPath), isFalse);

    final lock = await RestoreLock.tryAcquire(dbPath);

    expect(lock, isNotNull);
    expect(await RestoreLock.isHeld(dbPath), isTrue);
    expect(File(RestoreLock.lockPath(dbPath)).existsSync(), isTrue);

    await lock!.release();
    expect(await RestoreLock.isHeld(dbPath), isFalse);
  });

  test('the holder leaves a file that isHeld reads, gone on release', () async {
    final lock = (await RestoreLock.tryAcquire(dbPath))!;
    expect(File(RestoreLock.heldPath(dbPath)).existsSync(), isTrue);

    await lock.release();
    expect(File(RestoreLock.heldPath(dbPath)).existsSync(), isFalse);
  });

  test('a holder file of this process counts, whatever its date', () async {
    // What another engine of the process sees: the file, and free locks.
    final held = File(RestoreLock.heldPath(dbPath))
      ..writeAsStringSync(processToken());

    expect(await RestoreLock.isHeld(dbPath), isTrue);

    held.setLastModifiedSync(
      DateTime.now().subtract(const Duration(minutes: 10)),
    );
    expect(await RestoreLock.isHeld(dbPath), isTrue, reason: 'dated long ago');

    held.setLastModifiedSync(DateTime.now().add(const Duration(minutes: 10)));
    expect(await RestoreLock.isHeld(dbPath), isTrue, reason: 'dated ahead');
  });

  test(
    'a holder file of another process does not count and is deleted',
    () async {
      File(RestoreLock.heldPath(dbPath)).writeAsStringSync(anotherProcess());

      expect(await RestoreLock.isHeld(dbPath), isFalse);
      expect(File(RestoreLock.heldPath(dbPath)).existsSync(), isFalse);
    },
  );

  test('isHeld itself leaves no trace', () async {
    expect(await RestoreLock.isHeld(dbPath), isFalse);

    expect(File(RestoreLock.heldPath(dbPath)).existsSync(), isFalse);
  });

  test('a second taker in the same isolate does not get it', () async {
    final lock = (await RestoreLock.tryAcquire(dbPath))!;

    expect(await RestoreLock.tryAcquire(dbPath), isNull);

    await lock.release();
    final next = await RestoreLock.tryAcquire(dbPath);
    expect(next, isNotNull);
    await next!.release();
  });

  test('another isolate does not get it while it is held', () async {
    final lock = (await RestoreLock.tryAcquire(dbPath))!;

    expect(await _triesInOtherIsolate(dbPath), isFalse);

    await lock.release();
    expect(await _triesInOtherIsolate(dbPath), isTrue);
  });

  test('held by another isolate, this one does not get it', () async {
    final taken = ReceivePort();
    final released = ReceivePort();

    await Isolate.spawn(_holdUntilTold, [
      dbPath,
      taken.sendPort,
      null,
      released.sendPort,
    ]);
    // The helper isolate replies with the port it listens on to be told to stop.
    final events = StreamIterator(taken);
    await events.moveNext();
    expect(events.current, isTrue, reason: 'the other isolate took it');
    await events.moveNext();
    final tellStop = events.current as SendPort;

    expect(await RestoreLock.tryAcquire(dbPath), isNull);
    expect(await RestoreLock.isHeld(dbPath), isTrue);

    tellStop.send('stop');
    await released.first;
    final lock = await RestoreLock.tryAcquire(dbPath);
    expect(lock, isNotNull);
    await lock!.release();

    await events.cancel();
    released.close();
  });

  test('acquire gives up with RestoreBusyException', () async {
    final lock = (await RestoreLock.tryAcquire(dbPath))!;

    await expectLater(
      RestoreLock.acquire(
        dbPath,
        timeout: const Duration(milliseconds: 250),
        poll: const Duration(milliseconds: 50),
      ),
      throwsA(isA<RestoreBusyException>()),
    );

    await lock.release();
  });

  test('acquire waits for a lock that frees up', () async {
    final lock = (await RestoreLock.tryAcquire(dbPath))!;
    Future<void>.delayed(const Duration(milliseconds: 200), lock.release);

    final next = await RestoreLock.acquire(
      dbPath,
      timeout: const Duration(seconds: 5),
      poll: const Duration(milliseconds: 50),
    );

    await next.release();
  });

  test('releasing twice is harmless', () async {
    final lock = (await RestoreLock.tryAcquire(dbPath))!;

    await lock.release();
    await lock.release();

    expect(await RestoreLock.isHeld(dbPath), isFalse);
  });

  group('the process that a holder file or a flag names', () {
    test('is the same from another isolate', () async {
      expect(await Isolate.run(processToken), processToken());
    });

    test(
      'is ours only when the pid, and the starttime if both carry one, agree',
      () {
        expect(isOwnToken('42', '42'), isTrue);
        expect(isOwnToken('42:7', '42:7'), isTrue);
        expect(isOwnToken('42:7', '42:8'), isFalse, reason: 'another start');
        expect(isOwnToken('43:7', '42:7'), isFalse, reason: 'another pid');
        expect(isOwnToken('42', '42:7'), isTrue, reason: 'nothing to compare');
        expect(isOwnToken('', '42'), isFalse, reason: 'no token at all');
      },
    );

    test(
      'takes the starttime, field 22, after the last ")" of /proc/self/stat',
      () {
        const plain =
            '4321 (com.yosoyepa.finanzas) S 1234 4321 4321 0 -1 4194560 12345 0 0 0 '
            '10 5 0 0 20 0 15 0 98765 1234567890 2000';
        const tricky =
            '77 (a) (b) c) S 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 555';
        expect(parseStarttime(plain), 98765);
        expect(parseStarttime(tricky), 555);
        expect(parseStarttime('no parenthesis'), isNull);
      },
    );
  });

  test('the locks of two databases do not meet', () async {
    final other = p.join(root.path, 'other', 'monekin.db');
    final lock = (await RestoreLock.tryAcquire(dbPath))!;

    final second = await RestoreLock.tryAcquire(other);

    expect(second, isNotNull);
    await second!.release();
    await lock.release();
  });
}

void _holdUntilTold(List<Object?> args) => unawaited(_hold(args));

Future<void> _hold(List<Object?> args) async {
  final dbPath = args[0] as String;
  final report = args[1] as SendPort;
  final released = args[3] as SendPort;
  final lock = await RestoreLock.tryAcquire(dbPath);
  final inbox = ReceivePort();
  report
    ..send(lock != null)
    ..send(inbox.sendPort);
  await inbox.first;
  await lock?.release();
  released.send(true);
}
