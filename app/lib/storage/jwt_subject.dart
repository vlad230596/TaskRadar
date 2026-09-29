import 'dart:convert';

/// The `sub` claim of a JWT -- the id of the user the token was issued to -- or
/// null when it cannot be read.
///
/// No signature check, on purpose: the server is the only party that can verify
/// the token, and this value is used for one local decision only ("is this the
/// same person whose data is cached on this device?"). A forged `sub` could at
/// worst make the device keep or drop its *own* cache; it never reaches the
/// server. Anything malformed (not three segments, bad base64, not JSON, no
/// string `sub`) reads as null, which callers treat as "unknown person".
String? jwtSubject(String token) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return null;

    // JWT segments are base64url *without* padding; `base64Url.decode` insists
    // on it, so normalize restores it first.
    final payload = utf8.decode(
      base64Url.decode(base64Url.normalize(parts[1])),
    );
    final decoded = jsonDecode(payload);
    if (decoded is! Map<String, dynamic>) return null;

    final sub = decoded['sub'];
    return (sub is String && sub.isNotEmpty) ? sub : null;
  } catch (_) {
    return null;
  }
}
