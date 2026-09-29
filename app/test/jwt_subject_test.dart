import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/storage/jwt_subject.dart';

import 'support/fixtures.dart';

void main() {
  String segment(String text) =>
      base64Url.encode(utf8.encode(text)).replaceAll('=', '');

  test('reads the sub claim from an unpadded base64url payload', () {
    expect(jwtSubject(fakeJwt('owner')), 'owner');
    expect(jwtSubject(fakeJwt('usr_ж-42')), 'usr_ж-42');
  });

  test('no sub, or a sub that is not a non-empty string, is null', () {
    expect(jwtSubject(fakeJwt(null)), isNull);
    expect(jwtSubject('a.${segment('{"sub":42}')}.c'), isNull);
    expect(jwtSubject('a.${segment('{"sub":""}')}.c'), isNull);
  });

  test('anything malformed is null rather than a throw', () {
    expect(jwtSubject(''), isNull);
    expect(jwtSubject('not-a-jwt'), isNull);
    expect(jwtSubject('a.b'), isNull);
    expect(jwtSubject('a.!!!.c'), isNull);
    expect(jwtSubject('a.${segment('not json')}.c'), isNull);
    expect(jwtSubject('a.${segment('[1,2]')}.c'), isNull);
  });
}
