import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// What the server could learn about a link (`GET /link-preview`,
/// `design/task-editor-spec.md` §10): the page's `og:title` or `<title>`,
/// and the site's name. Either may be missing.
@immutable
class LinkPreview {
  const LinkPreview({required this.url, this.title, this.siteName});

  factory LinkPreview.fromJson(Map<String, dynamic> json) => LinkPreview(
    url: json['url'] as String,
    title: json['title'] as String?,
    siteName: json['siteName'] as String?,
  );

  final String url;
  final String? title;
  final String? siteName;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'url': url,
    'title': title,
    'siteName': siteName,
  };

  @override
  bool operator ==(Object other) =>
      other is LinkPreview &&
      other.url == url &&
      other.title == title &&
      other.siteName == siteName;

  @override
  int get hashCode => Object.hash(url, title, siteName);

  @override
  String toString() => 'LinkPreview($url, $title, $siteName)';
}

/// `GET /link-preview?url=…`. The server fetches the page (SSRF-guarded,
/// 5 s, 512 KB, cached 30 days) so the phone never talks to a stranger's site.
class LinkPreviewApi {
  const LinkPreviewApi(this._client);

  final ApiClient _client;

  /// The preview, or null when the server has none (204: not http(s), a
  /// private address, a timeout, no title).
  Future<LinkPreview?> fetch(String url) async {
    // `dynamic`: a 204 arrives as null or as an empty string, depending on
    // the headers it came with.
    final json = await _client.get<dynamic>(
      '/link-preview',
      queryParameters: <String, dynamic>{'url': url},
    );
    if (json is! Map) return null;
    final preview = LinkPreview.fromJson(Map<String, dynamic>.from(json));
    if (preview.title == null && preview.siteName == null) return null;
    return preview;
  }
}
