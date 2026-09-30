import 'dart:typed_data';

import 'package:dart_mappable/dart_mappable.dart';
import 'package:localsend_isolates/model/dto/file_dto.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

part 'sending_file.mapper.dart';

@MappableClass()
class SendingFile with SendingFileMappable {
  final FileDto file;
  final String? token;
  final Uint8List? thumbnail;
  final AssetEntity? asset; // for thumbnails
  final String? path; // android, iOS, desktop
  final List<int>? bytes; // web
  final String? errorMessage; // when failed; the live status is tracked in fileTransferProvider

  /// Byte offset the next upload of this file starts at, as reported by the
  /// receiver in the `resume` field of the prepare-upload response.
  ///
  /// `0` sends the whole file (断点续传: a greater value continues an
  /// interrupted transfer instead of restarting it).
  final int offset;

  const SendingFile({
    required this.file,
    required this.token,
    required this.thumbnail,
    required this.asset,
    required this.path,
    required this.bytes,
    required this.errorMessage,
    this.offset = 0,
  });

  /// Custom toString() to avoid printing the bytes.
  @override
  String toString() {
    return 'SendingFile(file: $file, token: $token, thumbnail: ${thumbnail != null ? thumbnail!.length : 'null'}, asset: $asset, path: $path, bytes: ${bytes != null ? bytes!.length : 'null'}, errorMessage: $errorMessage, offset: $offset)';
  }
}
