// Real Google account and Drive access (google_sign_in 7.x + googleapis). T002.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:monekin/features_ia/google/backup_package.dart';
import 'package:monekin/features_ia/google/drive_gateway.dart';

const kDriveScope = 'https://www.googleapis.com/auth/drive.appdata';

/// Web OAuth client id, required by google_sign_in 7 on Android. See docs/google-oauth.md.
const _serverClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

class RealGoogleAccountGateway implements GoogleAccountGateway {
  RealGoogleAccountGateway({String? serverClientId, bool? requiresClientId})
    : _clientId = serverClientId ?? _serverClientId,
      _requiresClientId = requiresClientId ?? Platform.isAndroid;

  final String _clientId;

  /// Android refuses to start without the web client id.
  final bool _requiresClientId;

  GoogleSignInAccount? _account;
  Future<void>? _initialized;

  /// Starts the plugin, or throws [GoogleNotConfiguredException] when the build lacks
  /// the client id, instead of leaking the plugin's raw configuration error.
  Future<void> _init() async {
    if (_requiresClientId && _clientId.isEmpty) {
      throw const GoogleNotConfiguredException();
    }
    return _initialized ??= GoogleSignIn.instance
        .initialize(serverClientId: _clientId.isEmpty ? null : _clientId)
        .catchError((Object e) {
          _initialized = null;
          if (e is GoogleSignInException &&
              e.code == GoogleSignInExceptionCode.clientConfigurationError) {
            throw const GoogleNotConfiguredException();
          }
          throw e;
        });
  }

  @override
  Future<String?> silentEmail() async {
    await _init();
    _account ??= await GoogleSignIn.instance.attemptLightweightAuthentication();
    return _account?.email;
  }

  @override
  Future<String?> signIn() async {
    await _init();
    try {
      _account = await GoogleSignIn.instance.authenticate(
        scopeHint: const [kDriveScope],
      );
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
    return _account?.email;
  }

  @override
  Future<void> signOut() async {
    await _init();
    _account = null;
    await GoogleSignIn.instance.signOut();
  }

  @override
  Future<void> disconnect() async {
    await _init();
    _account = null;
    await GoogleSignIn.instance.disconnect();
  }

  @override
  Future<DriveGateway?> openDrive({required bool interactive}) async {
    if (await silentEmail() == null) return null;
    final client = _account!.authorizationClient;
    final authorization = interactive
        ? await client.authorizeScopes(const [kDriveScope])
        : await client.authorizationForScopes(const [kDriveScope]);
    if (authorization == null) return null;
    return _GoogleDriveGateway(
      authorization.authClient(scopes: const [kDriveScope]),
    );
  }
}

class _GoogleDriveGateway implements DriveGateway {
  _GoogleDriveGateway(http.Client client) : _api = drive.DriveApi(client);

  final drive.DriveApi _api;

  @override
  Future<List<DriveBackupFile>> list() async {
    final files = <DriveBackupFile>[];
    String? pageToken;
    do {
      final page = await _api.files.list(
        spaces: 'appDataFolder',
        $fields: 'nextPageToken, files(id, name, createdTime)',
        pageSize: 100,
        pageToken: pageToken,
      );
      for (final f in page.files ?? const <drive.File>[]) {
        if (f.id == null || f.name == null) continue;
        files.add(
          DriveBackupFile(
            id: f.id!,
            name: f.name!,
            created: f.createdTime ?? DateTime.fromMillisecondsSinceEpoch(0),
          ),
        );
      }
      pageToken = page.nextPageToken;
    } while (pageToken != null);
    return files;
  }

  @override
  Future<DriveBackupFile> upload(String name, Uint8List bytes) async {
    final created = await _api.files.create(
      drive.File(name: name, parents: ['appDataFolder']),
      uploadMedia: drive.Media(Stream.value(bytes), bytes.length),
      $fields: 'id, name, createdTime',
    );
    return DriveBackupFile(
      id: created.id!,
      name: created.name ?? name,
      created: created.createdTime ?? DateTime.now(),
    );
  }

  @override
  Future<Uint8List> download(String id) async {
    final media =
        await _api.files.get(
              id,
              downloadOptions: drive.DownloadOptions.fullMedia,
            )
            as drive.Media;
    if ((media.length ?? 0) > kMaxBackupBytes) {
      throw const InvalidBackupException(
        InvalidBackupReason.corrupt,
        'the copy is too large',
      );
    }
    return collectCapped(media.stream);
  }

  @override
  Future<void> delete(String id) => _api.files.delete(id);
}
