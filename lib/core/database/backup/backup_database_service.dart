import 'dart:io';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/core/database/backup/database_snapshot.dart';
import 'package:monekin/core/models/account/account.dart';
import 'package:monekin/core/models/transaction/transaction.dart';
import 'package:monekin/features_ia/google/backup_crypto.dart';
import 'package:monekin/features_ia/google/backup_key_store.dart';
import 'package:monekin/features_ia/google/backup_package.dart';
import 'package:monekin/features_ia/google/backup_restorer.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class BackupDatabaseService {
  AppDB db = AppDB.instance;

  File createAndReturnFile({
    required String exportPath,
    required String fileName,
  }) {
    String downloadPath = path.join(exportPath, fileName);

    File downloadFile = File(downloadPath);

    if (!downloadFile.existsSync()) {
      downloadFile.createSync(recursive: true);
    }

    return downloadFile;
  }

  Future<File> exportDatabaseFile(String exportPath) async {
    List<int> dbFileInBytes = await getDbFileInBytes(validate: false);

    final file = createAndReturnFile(
      exportPath: exportPath,
      fileName:
          "monekin-${DateFormat('yyyyMMdd-Hms').format(DateTime.now())}.db",
    );

    return file.writeAsBytes(dbFileInBytes, mode: FileMode.write);
  }

  /// The database as one consistent file: a `VACUUM INTO` snapshot, checked before it
  /// is used unless [validate] is false (the plain export, which is not meant to be
  /// restored by the app). The live file is never read directly, because a committed
  /// write may still be in its write-ahead log.
  Future<Uint8List> getDbFileInBytes({bool validate = true}) async {
    final snapshot = File(
      uniqueTempPath(await db.databasePath, kSnapshotSuffix),
    );
    try {
      await snapshotDatabase(await db.databasePath, snapshot.path);
      if (validate) {
        validateDatabaseFile(snapshot.path, schemaVersion: db.schemaVersion);
      }
      return await snapshot.readAsBytes();
    } finally {
      if (await snapshot.exists()) await snapshot.delete();
    }
  }

  /// Text cells starting with one of these are read as formulas by spreadsheets.
  static const formulaStarts = {'=', '+', '-', '@', '\t', '\r'};

  /// Whether [value] is some apostrophes (at least [minApostrophes]) followed by a
  /// formula character.
  static bool _isProtected(String value, int minApostrophes) {
    var i = 0;
    while (i < value.length && value[i] == "'") {
      i++;
    }
    return i >= minApostrophes &&
        i < value.length &&
        formulaStarts.contains(value[i]);
  }

  /// Neutralises CSV injection: a leading apostrophe turns the cell into text. A text
  /// that already starts with apostrophes before a formula character gets one more,
  /// so [csvTextCell] gives every text back exactly.
  static String _csvText(String value) =>
      _isProtected(value, 0) ? "'$value" : value;

  /// Reverses [_csvText]: drops exactly one apostrophe from a cell that starts with
  /// apostrophes before a formula character, and nothing else.
  static String csvTextCell(String cell) =>
      _isProtected(cell, 1) ? cell.substring(1) : cell;

  String createCsvFromTransactions(
    List<MoneyTransaction> data, {
    String format = 'csv',
    String fieldSeparator = ',',
    String listSeparator = '|',
  }) {
    final dateFormatter = DateFormat('yyyy-MM-dd HH:mm:ss');
    final processedData = <List<String?>>[
      // Header
      [
        'ID',
        'Amount',
        'Date',
        'Title',
        'Note',
        'Account',
        'Currency',
        'Category',
        'Subcategory',
        'Tags',
      ],
    ];

    for (final transaction in data) {
      final category = transaction.category;

      List<String> buildRow(double amount, Account account) => [
        // ID
        _csvText(transaction.id),
        // Amount
        amount.toStringAsFixed(2),
        // Date
        dateFormatter.format(transaction.date),
        // Title
        _csvText(transaction.title ?? ''),
        // Notes
        _csvText(transaction.notes ?? ''),
        // Account
        _csvText(account.name),
        // Currency
        _csvText(account.currencyId),
        // Category
        if (transaction.isTransfer)
          'TRANSFER'
        else if (transaction.isInvestment)
          'INVESTMENT'
        else
          _csvText(category?.parentCategory?.name ?? category?.name ?? ''),
        // Subcategory
        _csvText(category?.parentCategory != null ? category!.name : ''),
        // Tags
        _csvText(transaction.tags.map((e) => e.name).join(listSeparator)),
      ];

      if (transaction.isTransfer) {
        // One row per account, signed so each account's rows add up
        processedData.add(buildRow(-transaction.value, transaction.account));
        processedData.add(
          buildRow(
            transaction.valueInDestiny ?? transaction.value,
            transaction.receivingAccount!,
          ),
        );
      } else {
        processedData.add(buildRow(transaction.value, transaction.account));
      }
    }
    final csvData = Csv(fieldDelimiter: fieldSeparator).encode(processedData);
    return csvData;
  }

  Future<File> exportSpreadsheet(
    String exportPath,
    List<MoneyTransaction> data,
  ) async {
    final csvData = createCsvFromTransactions(data);

    final file = createAndReturnFile(
      exportPath: exportPath,
      fileName:
          "Transactions-${DateFormat('yyyyMMdd-Hms').format(DateTime.now())}.csv",
    );

    return file.writeAsString(csvData, mode: FileMode.writeOnly);
  }

  /// Seals the database and the receipt photos with [key] (AES-256-GCM, v3 format)
  /// into a new file in [exportPath]. The sealed bytes are written block by block.
  Future<File> exportEncryptedBackup(
    String exportPath,
    BackupKey key, {
    String? documentsDir,
  }) async {
    final now = DateTime.now();
    final zip = await buildBackupPackage(
      database: await getDbFileInBytes(),
      documentsDir:
          documentsDir ?? (await getApplicationDocumentsDirectory()).path,
      schemaVersion: db.schemaVersion,
      date: now,
    );

    final file = createAndReturnFile(
      exportPath: exportPath,
      fileName: 'finanzas-${DateFormat('yyyyMMdd-Hms').format(now)}.fia',
    );
    final sink = file.openWrite();
    try {
      await sink.addStream(encryptBackupStream(Stream.value(zip), key));
    } finally {
      await sink.close();
    }
    return file;
  }

  /// Lets the user pick a backup file and reads it. Returns null if none was selected.
  Future<Uint8List?> pickBackupBytes() async {
    final selectedFile = await pickAndReadSingleFile(
      type: Platform.isWindows ? FileType.custom : FileType.any,
      allowedExtensions: Platform.isWindows ? ['db', 'fia'] : null,
    );

    if (selectedFile == null) {
      return null;
    }

    if (await selectedFile.length() > kMaxBackupBytes) {
      throw const InvalidBackupException(
        InvalidBackupReason.corrupt,
        'the file is too large',
      );
    }

    return selectedFile.readAsBytes();
  }

  /// Restores any copy (v1 bare database, v2 package or v3 encrypted) in two phases;
  /// the app must restart afterwards. A v3 copy is opened with [password], or with the
  /// stored key when it was sealed with it. A v1 or v2 copy is not encrypted and is
  /// refused unless [unencryptedConfirmed]. Throws [InvalidBackupException] before
  /// touching anything.
  Future<void> restorePackage(
    Uint8List bytes, {
    String? password,
    BackupKeyStore? keyStore,
    bool unencryptedConfirmed = false,
  }) async {
    BackupKeyResolver? resolver;
    if (isEncryptedBackup(bytes)) {
      final stored = await (keyStore ?? SecureBackupKeyStore()).load();
      resolver = password != null
          ? resolverFromPassword(password)
          : stored != null
          ? resolverFromKey(stored)
          : null;
    } else if (!unencryptedConfirmed) {
      throw const InvalidBackupException(
        InvalidBackupReason.unencrypted,
        'the copy is not encrypted',
      );
    }
    await restoreInApp(bytes, resolver);
  }

  Future<File?> pickAndReadSingleFile({
    FileType type = FileType.any,
    List<String>? allowedExtensions,
  }) async {
    final result = await FilePicker.pickFiles(
      type: type,
      allowedExtensions: allowedExtensions,
      allowMultiple: false,
    );

    if (result == null) {
      return null;
    }

    return File(result.files.single.path!);
  }

  Future<List<List<String>>> processCsv(String csvData) async {
    return csv
        .decode(csvData)
        .map((row) => row.map((e) => e.toString()).toList())
        .toList();
  }
}
