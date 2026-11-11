import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/smart_tokens.dart';
import '../../theme/tokens.dart';
import 'editor_theme.dart';

/// What the server knows about a link (`GET /link-preview`, spec section 8):
/// the page's title and site name, either may be missing.
@immutable
class LinkPreview {
  const LinkPreview({required this.url, this.title, this.siteName});

  final String url;
  final String? title;
  final String? siteName;
}

/// Where link previews come from. WP2 provides the real one (the API call,
/// the in-memory cache and the `read_cache_store` copy) by overriding
/// [linkPreviewSourceProvider]; until then -- and offline -- a card shows the
/// domain, which is the spec's offline behaviour anyway.
abstract interface class LinkPreviewSource {
  /// The preview of [url], or null when there is none (no network, the page
  /// has no title, the server said 204).
  Future<LinkPreview?> fetch(String url);
}

/// The stand-in until WP2: never a preview.
class NoLinkPreviews implements LinkPreviewSource {
  const NoLinkPreviews();

  @override
  Future<LinkPreview?> fetch(String url) async => null;
}

/// The link-preview source the editor reads. Override it (WP2) with the
/// server-backed one.
final Provider<LinkPreviewSource> linkPreviewSourceProvider =
    Provider<LinkPreviewSource>((ref) => const NoLinkPreviews());

/// One link's preview, fetched once per editor visit.
final linkPreviewProvider = FutureProvider.autoDispose
    .family<LinkPreview?, String>(
      (ref, url) => ref.watch(linkPreviewSourceProvider).fetch(url),
    );

/// Opens a link in the browser. `url_launcher` arrives with WP0; until it
/// does, the default copies the address and says so -- a link the user can
/// paste is better than a tap that does nothing. Override
/// [linkOpenerProvider] with `launchUrl(uri, mode: externalApplication)`.
typedef LinkOpener = Future<void> Function(BuildContext context, String url);

Future<void> copyLinkToClipboard(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  await Clipboard.setData(ClipboardData(text: url));
  messenger
    ?..clearSnackBars()
    ..showSnackBar(const SnackBar(content: Text('Ссылка скопирована')));
}

final Provider<LinkOpener> linkOpenerProvider = Provider<LinkOpener>(
  (ref) => copyLinkToClipboard,
);

/// The domain of [url] without `www.`, for a card with no preview.
String linkDomain(String url) {
  final host = Uri.tryParse(url)?.host ?? '';
  if (host.isEmpty) return url;
  return host.startsWith('www.') ? host.substring(4) : host;
}

/// The cards under the description: one per distinct link of the title and
/// the description. Tap opens, long press copies.
class LinkCards extends StatelessWidget {
  const LinkCards({required this.links, super.key});

  final List<LinkSpan> links;

  @override
  Widget build(BuildContext context) {
    final seen = <String>{};
    final unique = <LinkSpan>[
      for (final link in links)
        if (seen.add(link.url)) link,
    ];
    if (unique.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final link in unique) ...<Widget>[
          _LinkCard(url: link.url),
          if (link != unique.last) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _LinkCard extends ConsumerWidget {
  const _LinkCard({required this.url});

  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = ref.watch(linkPreviewProvider(url)).value;
    final domain = linkDomain(url);
    final title = preview?.title?.trim();
    final hasTitle = title != null && title.isNotEmpty;

    return Material(
      color: EditorColors.well,
      borderRadius: BorderRadius.circular(Radii.row),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.row),
        onTap: () => ref.read(linkOpenerProvider)(context, url),
        onLongPress: () => copyLinkToClipboard(context, url),
        child: Container(
          constraints: const BoxConstraints(minHeight: Targets.minimum + 8),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: <Widget>[
              const Icon(Icons.link, size: 20, color: EditorColors.bright),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      hasTitle ? title : domain,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: EditorText.chip.copyWith(color: EditorColors.ink),
                    ),
                    if (hasTitle)
                      Text(
                        preview?.siteName ?? domain,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: EditorText.note,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
