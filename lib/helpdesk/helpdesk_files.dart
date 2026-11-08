import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'helpdesk_api.dart';
import 'helpdesk_common.dart';

class HdPickedFile {
  const HdPickedFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

class HdPickResult {
  const HdPickResult(this.files, this.rejected);
  final List<HdPickedFile> files;
  final List<String> rejected;
}

/// Picks supporting documents/images. Files over 25 MB are rejected locally;
/// the backend still validates the real MIME bytes.
Future<HdPickResult> hdPickFiles({bool multiple = true}) async {
  final selected = await FilePicker.pickFiles(
    type: FileType.custom,
    allowMultiple: multiple,
    withData: true,
    allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf', 'docx', 'txt'],
  );
  final files = <HdPickedFile>[];
  final rejected = <String>[];
  for (final f in selected?.files ?? const <PlatformFile>[]) {
    final bytes = f.bytes;
    if (bytes == null) {
      rejected.add('${f.name} could not be read');
    } else if (bytes.length > helpDeskMaxFileBytes) {
      rejected.add('${f.name} is larger than 25 MB');
    } else {
      files.add(HdPickedFile(f.name, bytes));
    }
  }
  return HdPickResult(files, rejected);
}

/// Downloads through the authorized API into the temporary directory and opens it.
Future<void> hdOpenAttachment(HelpDeskApi api, String requestId, Map<String, dynamic> file) async {
  final bytes = await api.download(requestId, hdStr(file['id']));
  final dir = await getTemporaryDirectory();
  final safe = hdStr(file['name']).replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final path = '${dir.path}/helpdesk_${hdStr(file['id'])}_$safe';
  await File(path).writeAsBytes(bytes, flush: true);
  await OpenFilex.open(path);
}
