import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/smart_tokens.dart';
import '../../providers/attachment_providers.dart';
import '../../theme/tokens.dart';
import 'editor_theme.dart';

/// Opens a link in the browser (spec section 5: `url_launcher`,
/// `LaunchMode.externalApplication`). A provider so a test can see the tap
/// without a platform channel. When nothing can open it, the address is
/// copied and said so -- a link the user can paste beats a dead tap.
typedef LinkOpener = Future<void> Function(BuildContext context, String url);

Future<void> copyLinkToClipboard(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  await Clipboard.setData(ClipboardData(text: url));
  messenger
    ?..clearSnackBars()
    ..showSnackBar(const SnackBar(content: Text('Ссылка скопирована')));
}

Future<void> openLinkExternally(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  var opened = false;
  if (uri != null) {
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
  }
  if (!opened && context.mounted) await copyLinkToClipboard(context, url);
}

final Provider<LinkOpener> linkOpenerProvider = Provider<LinkOpener>(
  (ref) => openLinkExternally,
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
