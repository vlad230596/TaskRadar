import { createHash } from "node:crypto";
import sharp from "sharp";

/*
 * What happens to a picture between the upload and the disk (task editor,
 * design/task-editor-spec.md §10).
 *
 * 1. The type is read from the bytes, never from the client's Content-Type or
 *    file name: PNG, JPEG and WebP, nothing else. A file that only claims to be
 *    an image is a 415 before any decoder sees it.
 * 2. Metadata is removed, because a phone photo carries the place it was taken
 *    in its EXIF and the server has no business keeping that.
 *    - JPEG is re-encoded (sharp drops all metadata unless asked to keep it),
 *      with the EXIF orientation applied to the pixels first -- otherwise a
 *      portrait photo would come back lying on its side once the tag that
 *      said "rotate me" is gone.
 *    - PNG and WebP are NOT re-encoded: the phone has already chosen PNG for a
 *      screenshot with text precisely so that it stays sharp, and a second
 *      lossy WebP pass would only lose more. Their metadata lives in separate
 *      chunks, so those chunks are dropped and the image data is kept byte
 *      for byte.
 * 3. The image is decoded once to make the 512 px WebP thumbnail. That is also
 *    the proof that it *is* an image: a file with a valid signature and broken
 *    data fails here and is refused like any other non-image.
 *
 * Decoding is bounded by `maxPixels` (sharp's `limitInputPixels`), so a small
 * file that declares 100 000 x 100 000 pixels is refused instead of being
 * expanded into tens of gigabytes.
 */

export type ImageMime = "image/png" | "image/jpeg" | "image/webp";

/** The file extension each stored type gets. */
export const EXTENSION: Readonly<Record<ImageMime, string>> = {
  "image/png": "png",
  "image/jpeg": "jpg",
  "image/webp": "webp",
};

/** The thumbnail's longest side and quality (§10). */
export const THUMB_SIZE = 512;
export const THUMB_QUALITY = 75;

/** Quality the JPEG re-encode uses; the phone already sent q85 (§6). */
const JPEG_QUALITY = 90;

/** Default decode bound: a 100-megapixel photo still fits, a pixel bomb does not. */
export const DEFAULT_MAX_PIXELS = 100_000_000;

/** The bytes are not a picture this server stores. Becomes a 415. */
export class UnsupportedImageError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "UnsupportedImageError";
  }
}

const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

/** The type of an image from its first bytes, or null when it is none of the three. */
export function sniffImage(bytes: Buffer): ImageMime | null {
  if (bytes.length >= 8 && bytes.subarray(0, 8).equals(PNG_SIGNATURE)) return "image/png";
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
    return "image/jpeg";
  }
  if (
    bytes.length >= 12 &&
    bytes.toString("latin1", 0, 4) === "RIFF" &&
    bytes.toString("latin1", 8, 12) === "WEBP"
  ) {
    return "image/webp";
  }
  return null;
}

/**
 * PNG ancillary chunks that carry metadata rather than pixels: EXIF (which can
 * hold GPS), the three text chunks (author, software, comments -- anything)
 * and the modification time. Colour chunks (`iCCP`, `gAMA`, `sRGB`...) stay:
 * they change how the pixels look.
 */
const PNG_METADATA_CHUNKS = new Set(["eXIf", "tEXt", "zTXt", "iTXt", "tIME"]);

/** A PNG without its metadata chunks; the image data is untouched. */
export function stripPngMetadata(bytes: Buffer): Buffer {
  const kept: Buffer[] = [PNG_SIGNATURE];
  let offset = 8;
  let sawEnd = false;
  while (offset < bytes.length) {
    if (offset + 12 > bytes.length) throw new UnsupportedImageError("Truncated PNG chunk");
    const length = bytes.readUInt32BE(offset);
    const type = bytes.toString("latin1", offset + 4, offset + 8);
    const end = offset + 12 + length;
    if (end > bytes.length) throw new UnsupportedImageError("Truncated PNG chunk");
    if (!PNG_METADATA_CHUNKS.has(type)) kept.push(bytes.subarray(offset, end));
    offset = end;
    if (type === "IEND") {
      sawEnd = true;
      break;
    }
  }
  if (!sawEnd) throw new UnsupportedImageError("PNG has no IEND chunk");
  return Buffer.concat(kept);
}

/** VP8X flag bits that announce an EXIF and an XMP chunk. */
const VP8X_EXIF_FLAG = 0x08;
const VP8X_XMP_FLAG = 0x04;

/**
 * A WebP without its EXIF and XMP chunks. Only the extended format (`VP8X`)
 * can carry them; a simple WebP is returned as it is. The VP8X flags are
 * cleared to match, and the RIFF size rewritten.
 */
export function stripWebpMetadata(bytes: Buffer): Buffer {
  if (bytes.length < 20) throw new UnsupportedImageError("Truncated WebP");
  const chunks: Buffer[] = [];
  let offset = 12;
  let extended: Buffer | null = null;
  while (offset < bytes.length) {
    if (offset + 8 > bytes.length) throw new UnsupportedImageError("Truncated WebP chunk");
    const fourcc = bytes.toString("latin1", offset, offset + 4);
    const size = bytes.readUInt32LE(offset + 4);
    const end = offset + 8 + size + (size % 2);
    if (offset + 8 + size > bytes.length) throw new UnsupportedImageError("Truncated WebP chunk");
    const chunk = Buffer.from(bytes.subarray(offset, Math.min(end, bytes.length)));
    if (fourcc === "VP8X") {
      if (size < 1) throw new UnsupportedImageError("Malformed VP8X chunk");
      extended = chunk;
    }
    if (fourcc !== "EXIF" && fourcc !== "XMP ") chunks.push(chunk);
    offset = end;
  }
  if (extended !== null) {
    const flags = extended[8] ?? 0;
    extended[8] = flags & ~(VP8X_EXIF_FLAG | VP8X_XMP_FLAG);
  }
  const body = Buffer.concat(chunks);
  const header = Buffer.alloc(12);
  header.write("RIFF", 0, "latin1");
  header.writeUInt32LE(body.length + 4, 4);
  header.write("WEBP", 8, "latin1");
  return Buffer.concat([header, body]);
}

/** A picture ready to be stored. */
export interface PreparedImage {
  mime: ImageMime;
  /** The original as it will be stored: metadata stripped. */
  data: Buffer;
  /** WebP, longest side {@link THUMB_SIZE}. */
  thumb: Buffer;
  width: number;
  height: number;
  /** Hex SHA-256 of `data`. */
  sha256: string;
}

/**
 * Turns uploaded bytes into what is stored, or throws
 * {@link UnsupportedImageError}. See the note at the top of this file.
 */
export async function prepareImage(
  bytes: Buffer,
  maxPixels: number = DEFAULT_MAX_PIXELS,
): Promise<PreparedImage> {
  const mime = sniffImage(bytes);
  if (mime === null) throw new UnsupportedImageError("Only PNG, JPEG and WebP are accepted");

  const options = { limitInputPixels: maxPixels, failOn: "error" } as const;
  let data: Buffer;
  try {
    if (mime === "image/jpeg") {
      data = await sharp(bytes, options).rotate().jpeg({ quality: JPEG_QUALITY }).toBuffer();
    } else if (mime === "image/png") {
      data = stripPngMetadata(bytes);
    } else {
      data = stripWebpMetadata(bytes);
    }

    const meta = await sharp(data, options).metadata();
    const expectedFormat = { "image/png": "png", "image/jpeg": "jpeg", "image/webp": "webp" }[mime];
    if (meta.format !== expectedFormat || !meta.width || !meta.height) {
      throw new UnsupportedImageError("The image could not be read");
    }
    // `pageHeight` is the height of one frame of an animation; `height` is all of them.
    const height = meta.pageHeight ?? meta.height;

    const thumb = await sharp(data, options)
      .rotate()
      .resize({ width: THUMB_SIZE, height: THUMB_SIZE, fit: "inside", withoutEnlargement: true })
      .webp({ quality: THUMB_QUALITY })
      .toBuffer();

    return {
      mime,
      data,
      thumb,
      width: meta.width,
      height,
      sha256: createHash("sha256").update(data).digest("hex"),
    };
  } catch (error) {
    if (error instanceof UnsupportedImageError) throw error;
    // Anything sharp refuses -- corrupt data, too many pixels -- is a file this
    // server does not take, not a server fault.
    throw new UnsupportedImageError(
      `The image could not be read: ${error instanceof Error ? error.message : String(error)}`,
    );
  }
}
