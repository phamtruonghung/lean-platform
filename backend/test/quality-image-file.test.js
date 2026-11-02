/*
 * `image-file.js` — what a picture is, read from its own bytes (issue #418).
 *
 * No database and no HTTP: this is the arithmetic and the refusals, and every
 * case below is a case the door actually has to answer. The two that matter
 * most are the ones the card names as acceptance criteria — a file that is not
 * an image is refused, and one over the bound is refused with a sentence saying
 * what was sent — plus the one that makes the other two true: the size is read
 * from the header, never taken from the caller.
 *
 * The three pictures are built by hand rather than checked in as fixtures: a
 * header is what is being parsed, a 30-byte binary in the repository is a file
 * nobody can read, and a synthetic header lets the test state a 1600 px edge
 * exactly.
 */

const test = require('node:test');
const assert = require('node:assert');

const {
  MAX_IMAGE_BYTES,
  MAX_IMAGE_EDGE,
  MAX_CAPTION_LENGTH,
  readCaption,
  readImageFile
} = require('../src/modules/quality/image-file');

// An 8-byte PNG signature, the IHDR type, and the two 32-bit dimensions.
function png(width, height) {
  const buffer = Buffer.alloc(33);
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).copy(buffer, 0);
  buffer.writeUInt32BE(13, 8);
  buffer.write('IHDR', 12, 'ascii');
  buffer.writeUInt32BE(width, 16);
  buffer.writeUInt32BE(height, 20);
  return buffer;
}

// SOI, then a baseline SOF0 whose segment carries precision, height and width.
function jpeg(width, height) {
  const buffer = Buffer.alloc(25);
  buffer.writeUInt16BE(0xffd8, 0); // SOI
  buffer.writeUInt16BE(0xffc0, 2); // SOF0
  buffer.writeUInt16BE(17, 4); // segment length, this package's own bytes included
  buffer.writeUInt8(8, 6); // precision
  buffer.writeUInt16BE(height, 7);
  buffer.writeUInt16BE(width, 9);
  return buffer;
}

// A RIFF/WEBP container whose first chunk is VP8X: a flags byte, three reserved
// bytes, then the canvas size stored as (dimension - 1).
function webp(width, height) {
  const buffer = Buffer.alloc(40);
  buffer.write('RIFF', 0, 'ascii');
  buffer.writeUInt32LE(32, 4);
  buffer.write('WEBP', 8, 'ascii');
  buffer.write('VP8X', 12, 'ascii');
  buffer.writeUInt32LE(10, 16);
  buffer.writeUIntLE(width - 1, 24, 3);
  buffer.writeUIntLE(height - 1, 27, 3);
  return buffer;
}

test('a PNG, a JPEG and a WebP are read for their own size', () => {
  assert.deepStrictEqual(readImageFile(png(1600, 1200), 'image/png'), {
    contentType: 'image/png',
    width: 1600,
    height: 1200,
    bytes: 33
  });
  assert.deepStrictEqual(readImageFile(jpeg(1200, 1600), 'image/jpeg'), {
    contentType: 'image/jpeg',
    width: 1200,
    height: 1600,
    bytes: 25
  });
  assert.deepStrictEqual(readImageFile(webp(1024, 768), 'image/webp'), {
    contentType: 'image/webp',
    width: 1024,
    height: 768,
    bytes: 40
  });
});

test('a picture whose long edge is over 1600 is refused, naming the size', () => {
  assert.throws(
    () => readImageFile(png(MAX_IMAGE_EDGE + 1, 900), 'image/png'),
    (error) => {
      assert.strictEqual(error.status, 413);
      assert.match(error.message, /1601x900/);
      assert.match(error.message, /1600/);
      return true;
    }
  );
  // The edge is the *long* one, either way round.
  assert.throws(() => readImageFile(jpeg(900, MAX_IMAGE_EDGE + 1), 'image/jpeg'), /1601/);
  // And exactly at the bound is accepted.
  assert.strictEqual(readImageFile(png(MAX_IMAGE_EDGE, MAX_IMAGE_EDGE), 'image/png').width, 1600);
});

test('a body over 5 MiB is refused with its own byte count', () => {
  const oversized = Buffer.alloc(MAX_IMAGE_BYTES + 1);
  png(100, 100).copy(oversized, 0);
  assert.throws(
    () => readImageFile(oversized, 'image/png'),
    (error) => {
      assert.strictEqual(error.status, 413);
      assert.match(error.message, new RegExp(String(MAX_IMAGE_BYTES + 1)));
      return true;
    }
  );
});

test('a file that is not an image is refused, whatever type it claims', () => {
  assert.throws(
    () => readImageFile(Buffer.from('this is a text file, honestly', 'utf8'), 'image/png'),
    (error) => {
      assert.strictEqual(error.status, 400);
      assert.match(error.message, /not a JPEG, PNG or WebP/);
      return true;
    }
  );
  // A truncated PNG signature is not a PNG.
  assert.throws(() => readImageFile(png(10, 10).subarray(0, 12), 'image/png'), /not a JPEG/);
});

test('a declared type that disagrees with the bytes is refused, naming both', () => {
  assert.throws(
    () => readImageFile(jpeg(800, 600), 'image/png'),
    (error) => {
      assert.strictEqual(error.status, 400);
      assert.match(error.message, /image\/jpeg/);
      assert.match(error.message, /image\/png/);
      return true;
    }
  );
});

test('a request that is not one of the three types is refused with 415', () => {
  assert.throws(
    () => readImageFile(Buffer.from('hello'), 'text/plain'),
    (error) => {
      assert.strictEqual(error.status, 415);
      assert.match(error.message, /image\/jpeg, image\/png, image\/webp/);
      return true;
    }
  );
  // A picture sent with no type at all is the same mistake.
  assert.throws(() => readImageFile(png(10, 10), undefined), /415|image\/jpeg/);
});

test('an empty body is refused rather than stored as a zero-byte picture', () => {
  assert.throws(() => readImageFile(Buffer.alloc(0), 'image/png'), /the request body must be the picture/);
});

test('a caption is trimmed, kept or refused, and blank is no caption', () => {
  assert.strictEqual(readCaption(undefined), null);
  assert.strictEqual(readCaption('   '), null);
  assert.strictEqual(readCaption('  Burr on the flange  '), 'Burr on the flange');
  assert.throws(() => readCaption(42), /caption must be text/);
  assert.throws(
    () => readCaption('x'.repeat(MAX_CAPTION_LENGTH + 1)),
    new RegExp(String(MAX_CAPTION_LENGTH))
  );
  assert.strictEqual(readCaption('x'.repeat(MAX_CAPTION_LENGTH)).length, MAX_CAPTION_LENGTH);
});
