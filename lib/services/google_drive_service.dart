// lib/services/google_drive_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/people/v1.dart' as people;
import 'package:http/http.dart' as http;

// Contact info for sharing UI
class ContactInfo {
  final String name;
  final String email;
  ContactInfo(this.name, this.email);
}

class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }
}

class GoogleDriveService {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      drive.DriveApi.driveScope,
      people.PeopleServiceApi.contactsReadonlyScope,
    ],
  );

  GoogleSignInAccount? _currentUser;
  drive.DriveApi? _driveApi;
  people.PeopleServiceApi? _peopleApi;

  String generateFileName(String appName, String listName) {
    final safeListName = listName.replaceAll(' ', '_');
    return '${appName}_$safeListName.json';
  }

  Future<bool> signIn() async {
    try {
      _currentUser = await _googleSignIn.signIn();

      if (_currentUser == null) {
        debugPrint('User cancelled AUTHZ');
        return false;
      }

      final headers = await _currentUser!.authHeaders;
      final authenticateClient = GoogleAuthClient(headers);

      _driveApi = drive.DriveApi(authenticateClient);
      _peopleApi = people.PeopleServiceApi(authenticateClient);

      return true;
    } catch (e) {
      debugPrint('AUTHZ error: $e');
      await signOut();
      return false;
    }
  }

  Future<bool> restoreSession() async {
    try {
      // Trying to sign in with previous session
      _currentUser = await _googleSignIn.signInSilently();

      if (_currentUser == null) {
        return false; // no saved session
      }

      // if found then initialize the connection
      final headers = await _currentUser!.authHeaders;
      final authenticateClient = GoogleAuthClient(headers);

      _driveApi = drive.DriveApi(authenticateClient);
      _peopleApi = people.PeopleServiceApi(authenticateClient);

      return true;
    } catch (e) {
      debugPrint('Failed silent sign-in: $e');
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.disconnect();
    } catch (e) {
      debugPrint('Logout error: $e');
    }
    _currentUser = null;
    _driveApi = null;
    _peopleApi = null;
  }

  GoogleSignInAccount? get currentUser => _currentUser;

  Future<String?> _getFileId(String targetFileName) async {
    if (_driveApi == null) return null;
    try {
      final fileList = await _driveApi!.files.list(
        q: "name = '$targetFileName' and trashed = false",
        spaces: 'drive',
      );
      if (fileList.files != null && fileList.files!.isNotEmpty) {
        return fileList.files!.first.id;
      }
    } catch (e) {
      debugPrint('Search file error: $e');
    }
    return null;
  }

  Future<bool> uploadJson(
    String targetFileName,
    Map<String, dynamic> jsonData,
  ) async {
    if (_driveApi == null) return false;
    try {
      final String jsonString = jsonEncode(jsonData);
      final List<int> bytes = utf8.encode(jsonString);
      final stream = Future.value(bytes).asStream();

      final media = drive.Media(stream, bytes.length);
      final fileId = await _getFileId(targetFileName);

      if (fileId == null) {
        var driveFile = drive.File()..name = targetFileName;
        await _driveApi!.files.create(driveFile, uploadMedia: media);
        debugPrint('File $targetFileName successfully created.');
      } else {
        var driveFile = drive.File();
        await _driveApi!.files.update(driveFile, fileId, uploadMedia: media);
        debugPrint('File $targetFileName successfully updated.');
      }
      return true;
    } catch (e) {
      debugPrint('File uploading error: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> downloadJson(String targetFileName) async {
    if (_driveApi == null) return null;
    try {
      final fileId = await _getFileId(targetFileName);
      if (fileId == null) return null;

      final response =
          await _driveApi!.files.get(
                fileId,
                downloadOptions: drive.DownloadOptions.fullMedia,
              )
              as drive.Media;

      final List<int> dataStore = [];
      await response.stream.forEach((data) {
        dataStore.addAll(data);
      });

      final jsonString = utf8.decode(dataStore);
      return jsonDecode(jsonString);
    } catch (e) {
      debugPrint('File downloading error: $e');
      return null;
    }
  }

  // --- Contacts and sharing ---
  Future<List<ContactInfo>> getContacts() async {
    if (_peopleApi == null) return [];
    try {
      final response = await _peopleApi!.people.connections.list(
        'people/me',
        personFields: 'emailAddresses,names',
        pageSize: 1000,
      );

      final List<ContactInfo> contacts = [];
      if (response.connections != null) {
        for (var person in response.connections!) {
          if (person.emailAddresses != null &&
              person.emailAddresses!.isNotEmpty) {
            final email = person.emailAddresses!.first.value!;
            final name = person.names?.first.displayName ?? email;
            contacts.add(ContactInfo(name, email));
          }
        }
      }
      return contacts;
    } catch (e) {
      debugPrint('Error: $e');
      return [];
    }
  }

  Future<bool> shareFileWithUser(
    String targetFileName,
    String emailAddress,
  ) async {
    if (_driveApi == null) return false;

    try {
      final fileId = await _getFileId(targetFileName);
      if (fileId == null) {
        debugPrint('Shared file wasn\'t found');
        return false;
      }

      final permission = drive.Permission(
        type: 'user',
        role: 'writer',
        emailAddress: emailAddress,
      );

      await _driveApi!.permissions.create(
        permission,
        fileId,
        sendNotificationEmail: false,
      );

      debugPrint('File was successfully shared with $emailAddress');
      return true;
    } catch (e) {
      debugPrint('File sharing error: $e');
      return false;
    }
  }
}
