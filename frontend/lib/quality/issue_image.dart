/// A picture of a Quality issue, and one issue as the slide show draws it
/// (issue #419).
///
/// **Two record kinds, one shape.** A Non-conformance and a customer complaint
/// can each carry pictures and be on a Site's slide show, and the API files
/// them under the same two names — `nonconformance` and `complaint`
/// (`issue-images.js`'s own `ISSUE_KINDS`). [IssueKind] is the client's copy of
/// that closed set: which address segment a picture hangs off
/// (`nonconformances` / `complaints`), and what the Screen calls the record.
/// Keeping it in one place is what lets the images section, the toggle and the
/// slide show Screen be written once rather than twice with a `if (kind)` in
/// each.
///
/// **The bounds are the client's too.** The browser downscales to
/// [imageMaxEdge] before it uploads (the backend carries no image library, the
/// same division of labour `signature_png.dart` records in its own header), and
/// refuses over [imageMaxBytes] in the picker rather than sending a body the
/// server will refuse. The two constants mirror `image-file.js`'s own; a change
/// to one should prompt a look at the other.
library;

import 'package:flutter/foundation.dart';

import '../status_tone.dart';

/// The two records a picture can belong to, and the two the show plays.
abstract final class IssueKind {
  static const String nonconformance = 'nonconformance';
  static const String complaint = 'complaint';

  static const List<String> values = [nonconformance, complaint];

  /// The address segment a picture hangs off, and the register the record is
  /// read from: `/api/quality/nonconformances/:id/images`.
  static String path(String kind) =>
      kind == nonconformance ? 'nonconformances' : 'complaints';

  /// What the record is called wherever a person reads it (CONTEXT.md's own
  /// words for the two).
  static String label(String kind) =>
      kind == nonconformance ? 'Non-conformance' : 'Customer complaint';

  /// What the slide's own type chip says: short, because it sits beside a
  /// number on a wall.
  static String shortLabel(String kind) =>
      kind == nonconformance ? 'NC' : 'Complaint';

  static StatusTone tone(String kind) =>
      kind == nonconformance ? StatusTone.warning : StatusTone.info;
}

/// The longest edge a stored picture may have, in pixels. Mirrors
/// `backend/src/modules/quality/image-file.js`'s `MAX_IMAGE_EDGE`.
const int imageMaxEdge = 1600;

/// The most a picture may weigh, in bytes: 5 MiB. Mirrors `image-file.js`'s
/// `MAX_IMAGE_BYTES`.
const int imageMaxBytes = 5 * 1024 * 1024;

/// The caption's ceiling, in characters. Mirrors `image-file.js`'s
/// `MAX_CAPTION_LENGTH` and the table's own CHECK.
const int imageMaxCaptionLength = 280;

/// One stored picture, as the list and the show read it — metadata only, no
/// bytes. The bytes are fetched from the picture's own address so a register of
/// thumbnails does not carry six megabytes of JSON.
@immutable
class IssueImage {
  const IssueImage({
    required this.id,
    required this.contentType,
    required this.width,
    required this.height,
    required this.bytes,
    this.caption,
    this.createdAt,
  });

  factory IssueImage.fromJson(Map<String, dynamic> json) {
    final caption = (json['caption'] as String?)?.trim();
    return IssueImage(
      id: json['id'].toString(),
      contentType: json['contentType'] as String? ?? 'image/png',
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
      bytes: (json['bytes'] as num?)?.toInt() ?? 0,
      caption: caption == null || caption.isEmpty ? null : caption,
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.tryParse(json['createdAt'].toString()),
    );
  }

  final String id;
  final String contentType;
  final int width;
  final int height;
  final int bytes;
  final String? caption;
  final DateTime? createdAt;

  /// What a person reads under the picture when there is no caption.
  String get sizeLabel => '$width × $height px';
}

/// One issue on the wall: what the overlay says, and the pictures it cycles.
///
/// The server sends one entry per chosen issue with all of that issue's
/// pictures, oldest first; the Screen flattens the pair into slides so an issue
/// with three pictures is three consecutive slides rather than one and a
/// promise (see `slide-show.js`'s own note on why).
@immutable
class SlideIssue {
  const SlideIssue({
    required this.kind,
    required this.id,
    required this.number,
    required this.status,
    required this.severity,
    required this.occurredAt,
    required this.images,
    this.position,
    this.productName,
    this.orgUnitName,
    this.partyName,
  });

  factory SlideIssue.fromJson(Map<String, dynamic> json) => SlideIssue(
        kind: json['kind'] as String? ?? IssueKind.nonconformance,
        id: json['id'].toString(),
        number: json['number'] as String? ?? '',
        status: json['status'] as String? ?? '',
        severity: json['severity'] as String? ?? 'minor',
        occurredAt: DateTime.tryParse(json['occurredAt']?.toString() ?? '') ??
            DateTime.now().toUtc(),
        position: (json['position'] as num?)?.toInt(),
        productName: json['productName'] as String?,
        orgUnitName: json['orgUnitName'] as String?,
        partyName: json['partyName'] as String?,
        images: [
          for (final row in (json['images'] as List<dynamic>? ?? const []))
            IssueImage.fromJson(row as Map<String, dynamic>),
        ],
      );

  final String kind;
  final String id;
  final String number;
  final String status;
  final String severity;
  final DateTime occurredAt;
  final int? position;
  final String? productName;
  final String? orgUnitName;

  /// The Customer, for a complaint. Null for a Non-conformance, which belongs
  /// to the plant rather than to somebody outside it.
  final String? partyName;

  final List<IssueImage> images;

  /// Whether there is anything to put on the wall. A chosen issue with no
  /// picture is still chosen — the picker says so — but it is not a slide.
  bool get hasPicture => images.isNotEmpty;

  String get typeLabel => IssueKind.shortLabel(kind);

  /// "Customer · Product", or "Org unit · Product" for a Non-conformance —
  /// whichever two names a reader on the floor recognises fastest.
  String get subject {
    final who = partyName ?? orgUnitName;
    if (who == null && productName == null) return '';
    if (who == null) return productName!;
    if (productName == null) return who;
    return '$who · $productName';
  }
}

/// The answer to "put this issue on the show, or take it off"
/// (`PUT /api/quality/slide-show/:kind/:id`).
@immutable
class SlideChoice {
  const SlideChoice({required this.kind, required this.id, required this.inSlideShow, this.position});

  factory SlideChoice.fromJson(Map<String, dynamic> json) => SlideChoice(
        kind: json['kind'] as String? ?? IssueKind.nonconformance,
        id: json['id'].toString(),
        inSlideShow: json['inSlideShow'] == true,
        position: (json['position'] as num?)?.toInt(),
      );

  final String kind;
  final String id;
  final bool inSlideShow;
  final int? position;
}

/// How old an issue is, in the plant's own words: the overlay's last fact, and
/// the one that says whether the wall is showing this morning's problem or last
/// month's. Days for a day or more, hours under that, minutes under an hour.
String issueAgeLabel(DateTime occurredAt, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final difference = today.difference(occurredAt.toLocal());
  if (difference.isNegative) return 'just now';
  if (difference.inDays >= 1) {
    return difference.inDays == 1 ? '1 day old' : '${difference.inDays} days old';
  }
  if (difference.inHours >= 1) {
    return difference.inHours == 1 ? '1 hour old' : '${difference.inHours} hours old';
  }
  if (difference.inMinutes >= 1) {
    return difference.inMinutes == 1 ? '1 minute old' : '${difference.inMinutes} minutes old';
  }
  return 'just now';
}
