import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart' as ssh;

import '../../../core/errors/app_error.dart';
import '../domain/remote_entry.dart';
import '../domain/remote_path.dart';

/// An opened upload target: write the local bytes with progress,
/// abort an in-flight write, close when done.
final class UploadHandle {
  const UploadHandle({
    required this.write,
    required this.abort,
    required this.close,
  });

  final Future<void> Function(
    Stream<List<int>> data,
    void Function(int bytesSent) onProgress,
  )
  write;
  final Future<void> Function() abort;
  final Future<void> Function() close;
}

/// A started download: the byte stream, the total size when the
/// server reported one, and a close hook for cancellation.
final class DownloadHandle {
  const DownloadHandle({
    required this.stream,
    required this.totalBytes,
    required this.close,
  });

  final Stream<List<int>> stream;
  final int? totalBytes;
  final Future<void> Function() close;
}

/// The facts about a remote path that the file editor needs for
/// conflict detection (Edit File spec section 4): if size or
/// modification time changed since the file was loaded, someone
/// else touched it and a save must not silently overwrite.
final class RemoteFileStat {
  const RemoteFileStat({this.size, this.modifiedAt, this.isDirectory = false});

  final int? size;
  final DateTime? modifiedAt;
  final bool isDirectory;

  /// True when both stats describe the same remote state. A null
  /// field on either side counts as "unknown" and never proves a
  /// change on its own — both sides must report it and differ.
  bool sameAs(RemoteFileStat other) {
    if (size != null && other.size != null && size != other.size) {
      return false;
    }
    if (modifiedAt != null &&
        other.modifiedAt != null &&
        modifiedAt != other.modifiedAt) {
      return false;
    }
    return true;
  }
}

/// SFTP-backed remote file operations used by the Remote Explorer
/// (ARCHITECTURE: remote file service; ADR-003 SFTP for file ops —
/// never shell string interpolation).
abstract interface class RemoteFileService {
  /// Stats [path] (following links). Throws a typed [AppError].
  Future<RemoteFileStat> stat(String path);

  /// Reads the whole file at [path] into memory, refusing files
  /// larger than [maxBytes] with an [AppError] so callers (the
  /// file editor) never buffer unbounded remote content.
  Future<Uint8List> readBytes(String path, {required int maxBytes});

  /// Writes [bytes] to [path], creating or truncating it.
  Future<void> writeBytes(String path, List<int> bytes);

  /// Lists a directory. Throws a typed [AppError] on failure; the
  /// caller keeps its previous path in that case.
  Future<List<RemoteEntry>> list(String path);

  /// Canonical absolute path for [path] (resolving `.`/`..` and
  /// symlinks server-side when supported).
  Future<String> canonicalize(String path);

  /// The user's home directory as the server reports it.
  Future<String> homeDirectory();

  /// Whether anything exists at [path] (links not followed).
  Future<bool> exists(String path);

  /// Renames [from] to [to] (same directory moves are the UI's use
  /// case, but the operation itself is a plain SFTP rename).
  Future<void> rename(String from, String to);

  /// Deletes a file or symlink.
  Future<void> deleteFile(String path);

  /// Deletes a directory and everything inside it.
  Future<void> deleteRecursively(String path);

  /// Opens [path] for downloading. Throws a typed [AppError].
  Future<DownloadHandle> openDownload(String path);

  /// Creates a directory. Throws a typed [AppError] (for example
  /// when it already exists or permission is denied).
  Future<void> createDirectory(String path);

  /// Opens [path] for uploading, creating or truncating it.
  Future<UploadHandle> openUpload(String path);
}

final class DartSshRemoteFileService implements RemoteFileService {
  DartSshRemoteFileService(this._sftp);

  final ssh.SftpClient _sftp;

  @override
  Future<RemoteFileStat> stat(String path) async {
    try {
      final attr = await _sftp.stat(path);
      return RemoteFileStat(
        size: attr.size,
        modifiedAt: attr.modifyTime == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                attr.modifyTime! * 1000,
                isUtc: true,
              ),
        isDirectory: attr.isDirectory,
      );
    } catch (e) {
      throw mapSftpError(e, path);
    }
  }

  @override
  Future<Uint8List> readBytes(String path, {required int maxBytes}) async {
    final handle = await openDownload(path);
    final total = handle.totalBytes;
    if (total != null && total > maxBytes) {
      await handle.close();
      throw AppError(
        category: AppErrorCategory.unsupportedCapability,
        userMessage:
            'File is too large to open here '
            '(${(total / (1024 * 1024)).toStringAsFixed(1)} MB). '
            'Download it instead.',
      );
    }
    try {
      final builder = BytesBuilder(copy: false);
      await for (final chunk in handle.stream) {
        builder.add(chunk);
        if (builder.length > maxBytes) {
          throw AppError(
            category: AppErrorCategory.unsupportedCapability,
            userMessage: 'File is too large to open here. Download it instead.',
          );
        }
      }
      return builder.takeBytes();
    } finally {
      await handle.close();
    }
  }

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    final handle = await openUpload(path);
    try {
      await handle.write(Stream.value(bytes), (_) {});
      await handle.close();
    } catch (e) {
      await handle.abort();
      throw mapSftpError(e, path);
    }
  }

  @override
  Future<List<RemoteEntry>> list(String path) async {
    try {
      final names = await _sftp.listdir(path);
      final entries = <RemoteEntry>[];
      for (final item in names) {
        final name = item.filename;
        if (name == '.' || name == '..' || name.isEmpty) continue;
        final attr = item.attr;
        final kind = attr.isDirectory
            ? RemoteEntryKind.directory
            : attr.isSymbolicLink
            ? RemoteEntryKind.symlink
            : attr.isFile
            ? RemoteEntryKind.file
            : RemoteEntryKind.other;
        var targetIsDirectory = false;
        String? linkTarget;
        if (kind == RemoteEntryKind.symlink) {
          final entryPath = RemotePath.join(path, name);
          try {
            linkTarget = await _sftp.readlink(entryPath);
          } catch (_) {
            linkTarget = null;
          }
          try {
            final targetStat = await _sftp.stat(entryPath);
            targetIsDirectory = targetStat.isDirectory;
          } catch (_) {
            targetIsDirectory = false;
          }
        }
        entries.add(
          RemoteEntry(
            name: name,
            path: RemotePath.join(path, name),
            kind: kind,
            size: attr.size,
            modifiedAt: attr.modifyTime == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(
                    attr.modifyTime! * 1000,
                    isUtc: true,
                  ),
            permissions: _permissionsText(attr),
            linkTarget: linkTarget,
            targetIsDirectory: targetIsDirectory,
            uid: attr.userID,
            gid: attr.groupID,
            modeValue: attr.mode?.value,
          ),
        );
      }
      return entries;
    } catch (e) {
      throw mapSftpError(e, path);
    }
  }

  @override
  Future<String> canonicalize(String path) async {
    try {
      return RemotePath.normalize(await _sftp.absolute(path));
    } catch (_) {
      return RemotePath.normalize(path);
    }
  }

  @override
  Future<bool> exists(String path) async {
    try {
      await _sftp.stat(path, followLink: false);
      return true;
    } on ssh.SftpStatusError catch (e) {
      if (e.code == 2) return false; // SSH_FX_NO_SUCH_FILE
      rethrow;
    }
  }

  @override
  Future<void> rename(String from, String to) async {
    try {
      await _sftp.rename(from, to);
    } catch (e) {
      throw mapSftpError(e, from);
    }
  }

  @override
  Future<void> deleteFile(String path) async {
    try {
      await _sftp.remove(path);
    } catch (e) {
      throw mapSftpError(e, path);
    }
  }

  @override
  Future<void> deleteRecursively(String path) async {
    try {
      await _deleteRecursively(path);
    } catch (e) {
      throw mapSftpError(e, path);
    }
  }

  Future<void> _deleteRecursively(String path) async {
    final attrs = await _sftp.stat(path, followLink: false);
    if (attrs.isSymbolicLink || !attrs.isDirectory) {
      await _sftp.remove(path);
      return;
    }
    final children = await _sftp.listdir(path);
    for (final child in children) {
      if (child.filename == '.' || child.filename == '..') continue;
      await _deleteRecursively(RemotePath.join(path, child.filename));
    }
    await _sftp.rmdir(path);
  }

  @override
  Future<DownloadHandle> openDownload(String path) async {
    try {
      final attrs = await _sftp.stat(path);
      final file = await _sftp.open(path, mode: ssh.SftpFileOpenMode.read);
      return DownloadHandle(
        stream: file.read(),
        totalBytes: attrs.size,
        close: file.close,
      );
    } catch (e) {
      throw mapSftpError(e, path);
    }
  }

  @override
  Future<void> createDirectory(String path) async {
    try {
      await _sftp.mkdir(path);
    } catch (e) {
      throw mapSftpError(e, path);
    }
  }

  @override
  Future<UploadHandle> openUpload(String path) async {
    try {
      final file = await _sftp.open(
        path,
        mode:
            ssh.SftpFileOpenMode.write |
            ssh.SftpFileOpenMode.create |
            ssh.SftpFileOpenMode.truncate,
      );
      ssh.SftpFileWriter? writer;
      return UploadHandle(
        write: (data, onProgress) async {
          writer = file.write(
            data.map((chunk) => Uint8List.fromList(chunk)),
            onProgress: onProgress,
          );
          await writer!.done;
        },
        abort: () async {
          try {
            await writer?.abort();
          } catch (_) {}
          try {
            await file.close();
          } catch (_) {}
        },
        close: file.close,
      );
    } catch (e) {
      throw mapSftpError(e, path);
    }
  }

  @override
  Future<String> homeDirectory() async {
    try {
      return RemotePath.normalize(await _sftp.absolute('.'));
    } catch (e) {
      throw mapSftpError(e, '.');
    }
  }

  String? _permissionsText(ssh.SftpFileAttrs attr) {
    final mode = attr.mode;
    if (mode == null) return null;
    String tri(bool r, bool w, bool x) =>
        '${r ? 'r' : '-'}${w ? 'w' : '-'}${x ? 'x' : '-'}';
    return tri(mode.userRead, mode.userWrite, mode.userExecute) +
        tri(mode.groupRead, mode.groupWrite, mode.groupExecute) +
        tri(mode.otherRead, mode.otherWrite, mode.otherExecute);
  }
}

/// Maps SFTP failures to typed, user-facing errors. Status codes
/// follow the SFTP protocol (draft-ietf-secsh-filexfer).
AppError mapSftpError(Object error, String path) {
  if (error is AppError) return error;
  if (error is ssh.SftpStatusError) {
    switch (error.code) {
      case 2: // SSH_FX_NO_SUCH_FILE
        return AppError(
          category: AppErrorCategory.remotePathMissing,
          userMessage: 'No such directory: $path',
        );
      case 3: // SSH_FX_PERMISSION_DENIED
        return AppError(
          category: AppErrorCategory.permissionDenied,
          userMessage: 'Permission denied: $path.',
        );
      default:
        return AppError(
          category: AppErrorCategory.unknown,
          userMessage: 'Remote operation failed at $path.',
          diagnostic: 'SFTP status ${error.code}: ${error.message}',
        );
    }
  }
  return AppError(
    category: AppErrorCategory.unknown,
    userMessage: 'Remote operation failed at $path.',
    diagnostic: error.runtimeType.toString(),
  );
}
