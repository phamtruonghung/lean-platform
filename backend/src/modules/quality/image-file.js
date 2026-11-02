/*
 * What a picture of a Quality issue is, read from its own bytes (issue #419).
 *
 * The backend carries no image library, on purpose (ADR-0052's own comment on
 * `signature_png.dart`: the client does the pixel work so the server never has
 * to). It cannot re-encode a picture — so it does the next best thing, which is
 * the thing that actually matters: **it never trusts the caller about what was
 * uploaded.** The format is sniffed from the magic bytes, the width and height
 * are read from the file's own header, and a body whose declared
 * `Content-Type` disagrees with its contents is refused rather than stored.
 *
 * That is what makes the bounds real. The client downscales to a 1600 px long
 * edge before it uploads (a phone photo is 4000-odd px wide and a slide cannot
 * use it), but a caller who skips that step — a script, a future client, a
 * hand-made request — is refused here, with a sentence naming the size it
 * actually sent. The database states the same ceilings again in
 * `1803300000000_quality-issue-images-and-slide-show.js`, so the invariant is
 * true of the table and not only of this door.
 *
 * Three formats, the three a browser can display without a plugin and a phone
 * camera produces: JPEG, PNG and WebP. Each header parse is written from the
 * format's own definition rather than from a library, because a dependency for
 * eight bytes of arithmetic is a worse trade than eighty lines of arithmetic
 * with a test beside it (`test/quality-image-file.test.js`).
 */

// The most a picture may weigh: 5 MiB. Mirrored by the table's CHECK and by
// `quality_image_options.dart`'s own constant on the client.
const MAX_IMAGE_BYTES = 5242880;

// The longest edge a stored picture may have, in pixels. Mirrored by the
// table's CHECK and by the client's downscale target.
const MAX_IMAGE_EDGE = 1600;

// The caption's ceiling, in characters. Mirrored by the table's CHECK.
const MAX_CAPTION_LENGTH = 280;

const CONTENT_TYPES = ['image/jpeg', 'image/png', 'image/webp'];

function refuse(status, message) {
  const error = new Error(message);
  error.status = status;
  return error;
}

function readUInt32BE(buffer, offset) {
  return buffer.readUInt32BE(offset);
}

// PNG: an 8-byte signature, then the IHDR chunk, whose width and height are the
// first two 32-bit big-endian fields after its own 4-byte type.
function readPngSize(buffer) {
  const signature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  if (buffer.length < 24 || !buffer.subarray(0, 8).equals(signature)) return null;
  if (buffer.subarray(12, 16).toString('ascii') !== 'IHDR') return null;
  return { width: readUInt32BE(buffer, 16), height: readUInt32BE(buffer, 20) };
}

// The JPEG frame headers that carry the picture's own size: every SOFn except
// the four that mean something else (DHT C4, JPG C8, DAC CC).
function isStartOfFrame(marker) {
  return marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc;
}

// JPEG: walk the marker segments from SOI until a start-of-frame, then read the
// height and width the frame carries. Entropy-coded data cannot appear before
// the frame header in a file a decoder would accept, so reaching SOS first
// means there is no size to read.
function readJpegSize(buffer) {
  if (buffer.length < 4 || buffer[0] !== 0xff || buffer[1] !== 0xd8) return null;
  let offset = 2;
  while (offset + 4 <= buffer.length) {
    if (buffer[offset] !== 0xff) return null;
    let marker = buffer[offset + 1];
    // Fill bytes: any number of 0xFF may precede a marker.
    while (marker === 0xff && offset + 2 < buffer.length) {
      offset += 1;
      marker = buffer[offset + 1];
    }
    offset += 2;
    if (marker === 0xd8 || marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) continue;
    if (marker === 0xd9 || marker === 0xda) return null;
    if (offset + 2 > buffer.length) return null;
    const length = buffer.readUInt16BE(offset);
    if (length < 2 || offset + length > buffer.length) return null;
    if (isStartOfFrame(marker)) {
      if (length < 7) return null;
      return { height: buffer.readUInt16BE(offset + 3), width: buffer.readUInt16BE(offset + 5) };
    }
    offset += length;
  }
  return null;
}

// WebP: a RIFF container whose first chunk is one of three bitstreams, each
// carrying the canvas size differently. `VP8 ` is lossy (14-bit dimensions
// after a fixed 3-byte frame tag and its start code), `VP8L` is lossless
// (14-bit width-1 and height-1 packed into one 32-bit word) and `VP8X` is the
// extended container (24-bit width-1 and height-1 after a flags byte).
function readWebpSize(buffer) {
  if (buffer.length < 30) return null;
  if (buffer.subarray(0, 4).toString('ascii') !== 'RIFF') return null;
  if (buffer.subarray(8, 12).toString('ascii') !== 'WEBP') return null;
  const chunk = buffer.subarray(12, 16).toString('ascii');
  if (chunk === 'VP8 ') {
    return {
      width: buffer.readUInt16LE(26) & 0x3fff,
      height: buffer.readUInt16LE(28) & 0x3fff
    };
  }
  if (chunk === 'VP8L') {
    if (buffer[20] !== 0x2f) return null;
    const bits = buffer.readUInt32LE(21);
    return { width: (bits & 0x3fff) + 1, height: ((bits >> 14) & 0x3fff) + 1 };
  }
  if (chunk === 'VP8X') {
    return {
      width: buffer.readUIntLE(24, 3) + 1,
      height: buffer.readUIntLE(27, 3) + 1
    };
  }
  return null;
}

/**
 * The format, width and height of an uploaded picture, read from its own bytes.
 *
 * [declaredType] is the `Content-Type` the caller sent. It is checked against
 * the sniffed format rather than believed: a JPEG sent as `image/png` is a
 * caller's mistake worth a sentence, and storing it under the wrong label would
 * make every later read serve it with a type the browser then refuses to draw.
 *
 * Throws a 415 for a body whose type is not one of the three, a 400 for a file
 * whose bytes are not the format it claims, too large, or too big an edge.
 */
function readImageFile(buffer, declaredType) {
  if (!CONTENT_TYPES.includes(declaredType)) {
    throw refuse(415, `an image must be sent as one of ${CONTENT_TYPES.join(', ')}`);
  }
  if (!Buffer.isBuffer(buffer) || buffer.length === 0) {
    throw refuse(400, 'the request body must be the picture itself, sent as image/jpeg, image/png or image/webp');
  }
  if (buffer.length > MAX_IMAGE_BYTES) {
    throw refuse(413, `that picture is ${buffer.length} bytes; the most a slide can hold is ${MAX_IMAGE_BYTES}`);
  }

  const png = readPngSize(buffer);
  const jpeg = png ? null : readJpegSize(buffer);
  const webp = png || jpeg ? null : readWebpSize(buffer);
  const size = png ?? jpeg ?? webp;
  if (!size) {
    throw refuse(400, 'that file is not a JPEG, PNG or WebP picture this Platform can read');
  }

  const contentType = png ? 'image/png' : jpeg ? 'image/jpeg' : 'image/webp';
  if (contentType !== declaredType) {
    throw refuse(400, `that picture is a ${contentType}, not the ${declaredType} it was sent as`);
  }
  if (!Number.isInteger(size.width) || !Number.isInteger(size.height) || size.width < 1 || size.height < 1) {
    throw refuse(400, 'that picture has no readable size');
  }
  if (size.width > MAX_IMAGE_EDGE || size.height > MAX_IMAGE_EDGE) {
    throw refuse(
      413,
      `that picture is ${size.width}x${size.height}; the longest edge a slide shows is ${MAX_IMAGE_EDGE} px`
    );
  }

  return { contentType, width: size.width, height: size.height, bytes: buffer.length };
}

/** The caption as the plant wrote it, or null for none. */
function readCaption(value) {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string') throw refuse(400, 'caption must be text');
  const caption = value.trim();
  if (caption === '') return null;
  if (caption.length > MAX_CAPTION_LENGTH) {
    throw refuse(400, `a caption is at most ${MAX_CAPTION_LENGTH} characters`);
  }
  return caption;
}

module.exports = {
  CONTENT_TYPES,
  MAX_IMAGE_BYTES,
  MAX_IMAGE_EDGE,
  MAX_CAPTION_LENGTH,
  readImageFile,
  readCaption
};
