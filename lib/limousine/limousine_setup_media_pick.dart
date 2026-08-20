// Shared limousine-setup picker read path. Cover and optional logo use the
// same ImagePicker + uploadPublicPartnerMedia pipeline. Never persist a
// local or content:// URI as a durable override.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image_picker/image_picker.dart';

import 'limousine_hero_contract.dart';
import 'limousine_profile_identity.dart';

enum LimousineSetupMediaKind { cover, logo }

class LimousineSetupMediaTarget {
  const LimousineSetupMediaTarget({
    required this.kind,
    required this.mediaType,
    required this.maxBytes,
    required this.minWidth,
    required this.minHeight,
    required this.maxEdge,
    required this.maxWidth,
    required this.filenameStem,
  });

  final LimousineSetupMediaKind kind;
  final String mediaType;
  final int maxBytes;
  final int minWidth;
  final int minHeight;
  final int maxEdge;
  final int maxWidth;
  final String filenameStem;
}

class LimousineImagePixelSize {
  const LimousineImagePixelSize(this.width, this.height);

  final int width;
  final int height;
}

class LimousineSetupPickedImage {
  const LimousineSetupPickedImage({
    required this.path,
    required this.name,
    this.bytes,
  });

  final String path;
  final String name;
  final Uint8List? bytes;

  bool get hasBytes => bytes != null && bytes!.isNotEmpty;
}

class LimousineNormalizedUpload {
  const LimousineNormalizedUpload({
    required this.bytes,
    required this.filename,
    required this.contentType,
  });

  final Uint8List bytes;
  final String filename;
  final String contentType;
}

class LimousinePickedMediaException implements Exception {
  const LimousinePickedMediaException(this.code);
  final String code;

  bool get isUnsupportedFormat => code == 'unsupported-image-format';
  bool get isEmptyBytes => code == 'empty-image-bytes';
  bool get isContentUriUnread => code == 'content-uri-unread';
  bool get isTooLarge => code == 'image-too-large';
  bool get isTooSmall => code == 'image-too-small';
  bool get isUploadNotDurable => code == 'upload-not-durable';

  @override
  String toString() => 'LimousinePickedMediaException($code)';
}

/// Survives State recreation after Android Photo Picker returns.
LimousineSetupMediaKind? limousineSetupPendingMediaKind;

LimousineSetupMediaTarget limousineSetupMediaTarget(
  LimousineSetupMediaKind kind,
) {
  switch (kind) {
    case LimousineSetupMediaKind.cover:
      return const LimousineSetupMediaTarget(
        kind: LimousineSetupMediaKind.cover,
        mediaType: kLimousineProfileCoverMediaType,
        maxBytes: 8 * 1024 * 1024,
        minWidth: 1,
        minHeight: 1,
        maxEdge: 8000,
        maxWidth: 1600,
        filenameStem: 'limousine-cover',
      );
    case LimousineSetupMediaKind.logo:
      return const LimousineSetupMediaTarget(
        kind: LimousineSetupMediaKind.logo,
        mediaType: kLimousineProfileLogoMediaType,
        maxBytes: 4 * 1024 * 1024,
        minWidth: 1,
        minHeight: 1,
        maxEdge: 4000,
        maxWidth: 900,
        filenameStem: 'limousine-logo',
      );
  }
}

bool limousinePickedPathIsContentUri(String path) {
  return path.trim().toLowerCase().startsWith('content://');
}

bool limousineHeroRefIsDurable(String value) {
  return value.trim().toLowerCase().startsWith('https://');
}

String limousineDetectImageMime(Uint8List bytes) {
  final len = bytes.length;
  if (len >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (len >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0D &&
      bytes[5] == 0x0A &&
      bytes[6] == 0x1A &&
      bytes[7] == 0x0A) {
    return 'image/png';
  }
  if (len >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'image/webp';
  }
  return '';
}

bool limousinePngHasAlpha(Uint8List bytes) {
  if (limousineDetectImageMime(bytes) != 'image/png' || bytes.length < 26) {
    return false;
  }
  // IHDR color type: 4 = greyscale+alpha, 6 = truecolor+alpha.
  final colorType = bytes[25];
  return colorType == 4 || colorType == 6;
}

LimousineImagePixelSize? limousineImagePixelSize(Uint8List bytes) {
  final mime = limousineDetectImageMime(bytes);
  if (mime == 'image/png') return _pngPixelSize(bytes);
  if (mime == 'image/jpeg') return _jpegPixelSize(bytes);
  if (mime == 'image/webp') return _webpPixelSize(bytes);
  return null;
}

void limousineValidateSetupMedia(
  Uint8List? bytes, {
  required LimousineSetupMediaTarget target,
}) {
  if (bytes == null || bytes.isEmpty) {
    throw const LimousinePickedMediaException('empty-image-bytes');
  }
  if (bytes.length > target.maxBytes) {
    throw const LimousinePickedMediaException('image-too-large');
  }
  final mime = limousineDetectImageMime(bytes);
  if (mime.isEmpty) {
    throw const LimousinePickedMediaException('unsupported-image-format');
  }
  final size = limousineImagePixelSize(bytes);
  if (size == null) return;
  if (size.width < target.minWidth || size.height < target.minHeight) {
    throw const LimousinePickedMediaException('image-too-small');
  }
  if (size.width > target.maxEdge || size.height > target.maxEdge) {
    throw const LimousinePickedMediaException('image-too-large');
  }
}

Future<Uint8List> limousineReadXFileBytes(XFile picked) async {
  try {
    final fromPicker = await picked.readAsBytes();
    if (fromPicker.isNotEmpty) return fromPicker;
  } catch (_) {}
  throw LimousinePickedMediaException(
    limousinePickedPathIsContentUri(picked.path)
        ? 'content-uri-unread'
        : 'empty-image-bytes',
  );
}

Future<XFile?> limousineRecoverLostPickedImage(ImagePicker picker) async {
  try {
    final lost = await picker.retrieveLostData();
    if (lost.isEmpty) return null;
    if (lost.file != null) return lost.file;
    final files = lost.files;
    if (files != null && files.isNotEmpty) return files.first;
  } catch (_) {}
  return null;
}

Future<LimousineSetupPickedImage?> limousinePickGalleryImage({
  required ImagePicker picker,
}) async {
  XFile? picked;
  try {
    picked = await picker.pickImage(
      source: ImageSource.gallery,
      requestFullMetadata: false,
    );
  } catch (_) {
    picked = null;
  }
  picked ??= await limousineRecoverLostPickedImage(picker);
  if (picked == null) return null;
  final bytes = await limousineReadXFileBytes(picked);
  return LimousineSetupPickedImage(
    path: picked.path,
    name: picked.name,
    bytes: bytes,
  );
}

Future<LimousineNormalizedUpload> limousinePreparePickedImageUpload(
  LimousineSetupPickedImage picked, {
  LimousineSetupMediaTarget? target,
  int maxWidth = 1600,
  String filenameStem = 'limousine-cover',
}) async {
  final resolved =
      target ??
      limousineSetupMediaTarget(
        LimousineSetupMediaKind.cover,
      ).copyWith(maxWidth: maxWidth, filenameStem: filenameStem);
  final raw = picked.bytes;
  if (resolved.maxWidth <= 0) {
    throw const LimousinePickedMediaException('empty-image-bytes');
  }
  if (raw == null || raw.isEmpty) {
    if (limousinePickedPathIsContentUri(picked.path)) {
      throw const LimousinePickedMediaException('content-uri-unread');
    }
    throw const LimousinePickedMediaException('empty-image-bytes');
  }
  limousineValidateSetupMedia(raw, target: resolved);
  final mime = limousineDetectImageMime(raw);
  // Keep original bytes so PNG/WebP alpha survives. Flutter Image widgets
  // honor JPEG EXIF orientation at display time; do not re-encode here.
  return LimousineNormalizedUpload(
    bytes: raw,
    filename: limousineSetupFilenameForMime(
      rawName: picked.name,
      mime: mime,
      stem: resolved.filenameStem,
    ),
    contentType: mime,
  );
}

String limousineSetupFilenameForMime({
  required String rawName,
  required String mime,
  required String stem,
}) {
  final name = rawName.trim();
  if (mime == 'image/png') {
    return name.toLowerCase().endsWith('.png') ? name : '$stem.png';
  }
  if (mime == 'image/webp') {
    return name.toLowerCase().endsWith('.webp') ? name : '$stem.webp';
  }
  if (name.toLowerCase().endsWith('.jpg') ||
      name.toLowerCase().endsWith('.jpeg')) {
    return name;
  }
  return '$stem.jpg';
}

/// Decodes via Flutter's codec so EXIF orientation is applied, then resizes.
/// Not used on the upload path: widget tests hang on instantiateImageCodec,
/// and re-encoding would flatten PNG/WebP transparency.
Future<Uint8List> limousineBakeOrientedImage(
  Uint8List bytes, {
  int maxWidth = 1600,
}) async {
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: maxWidth > 0 ? maxWidth : null,
  );
  try {
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null || png.lengthInBytes <= 0) {
        return bytes;
      }
      return png.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

extension LimousineSetupMediaTargetCopy on LimousineSetupMediaTarget {
  LimousineSetupMediaTarget copyWith({int? maxWidth, String? filenameStem}) {
    return LimousineSetupMediaTarget(
      kind: kind,
      mediaType: mediaType,
      maxBytes: maxBytes,
      minWidth: minWidth,
      minHeight: minHeight,
      maxEdge: maxEdge,
      maxWidth: maxWidth ?? this.maxWidth,
      filenameStem: filenameStem ?? this.filenameStem,
    );
  }
}

LimousineImagePixelSize? _pngPixelSize(Uint8List bytes) {
  if (bytes.length < 24) return null;
  final width =
      (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
  final height =
      (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
  if (width <= 0 || height <= 0) return null;
  return LimousineImagePixelSize(width, height);
}

LimousineImagePixelSize? _jpegPixelSize(Uint8List bytes) {
  var i = 2;
  while (i + 8 < bytes.length) {
    if (bytes[i] != 0xFF) {
      i += 1;
      continue;
    }
    final marker = bytes[i + 1];
    if (marker == 0xD8 ||
        marker == 0x01 ||
        (marker >= 0xD0 && marker <= 0xD9)) {
      i += 2;
      continue;
    }
    if (i + 3 >= bytes.length) return null;
    final length = (bytes[i + 2] << 8) | bytes[i + 3];
    final isSof =
        (marker >= 0xC0 && marker <= 0xC3) ||
        (marker >= 0xC5 && marker <= 0xC7) ||
        (marker >= 0xC9 && marker <= 0xCB) ||
        (marker >= 0xCD && marker <= 0xCF);
    if (isSof) {
      final height = (bytes[i + 5] << 8) | bytes[i + 6];
      final width = (bytes[i + 7] << 8) | bytes[i + 8];
      if (width <= 0 || height <= 0) return null;
      return LimousineImagePixelSize(width, height);
    }
    if (length < 2) return null;
    i += 2 + length;
  }
  return null;
}

LimousineImagePixelSize? _webpPixelSize(Uint8List bytes) {
  if (bytes.length < 30) return null;
  final tag = String.fromCharCodes(bytes.sublist(12, 16));
  if (tag.startsWith('VP8X')) {
    final width = 1 + (bytes[24] | (bytes[25] << 8) | (bytes[26] << 16));
    final height = 1 + (bytes[27] | (bytes[28] << 8) | (bytes[29] << 16));
    return LimousineImagePixelSize(width, height);
  }
  if (tag.startsWith('VP8L') && bytes.length >= 25) {
    final bits =
        bytes[21] | (bytes[22] << 8) | (bytes[23] << 16) | (bytes[24] << 24);
    return LimousineImagePixelSize(
      (bits & 0x3FFF) + 1,
      ((bits >> 14) & 0x3FFF) + 1,
    );
  }
  if (tag.startsWith('VP8 ')) {
    final width = bytes[26] | ((bytes[27] & 0x3F) << 8);
    final height = bytes[28] | ((bytes[29] & 0x3F) << 8);
    if (width <= 0 || height <= 0) return null;
    return LimousineImagePixelSize(width, height);
  }
  return null;
}
