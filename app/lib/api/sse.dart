import 'dart:async';
import 'dart:convert';

/// One Server-Sent Event: its `event:` name and its `data:` lines, joined.
class SseEvent {
  const SseEvent(this.event, this.data);

  /// `message` when the server named none, as the spec says.
  final String event;
  final String data;

  @override
  bool operator ==(Object other) =>
      other is SseEvent && other.event == event && other.data == data;

  @override
  int get hashCode => Object.hash(event, data);

  @override
  String toString() => 'SseEvent($event, $data)';
}

/// Turns a response body into the events in it, as the bytes arrive.
///
/// The subset of the spec the backend speaks (`backend/src/lib/eventStream.ts`)
/// and a little more, so a proxy's reformatting cannot break it: `event:` and
/// `data:` fields, several `data:` lines joined with `\n`, `:` comments
/// ignored, `\r\n` as well as `\n`, and a chunk boundary anywhere -- in the
/// middle of a line, or of a UTF-8 sequence. `id:` and `retry:` are dropped:
/// nothing here reconnects.
///
/// An event is dispatched at the blank line that ends it. One cut off by the
/// end of the stream is dropped, as a browser would drop it -- half an event is
/// not an event.
///
/// Built from transformers rather than an `async*` loop on purpose: cancelling
/// the result has to reach the response body at once, and an `async*`
/// generator parked in `await for` was seen not to -- a cancelled "Разобрать"
/// kept its connection open.
Stream<SseEvent> parseSse(Stream<List<int>> bytes) {
  String? event;
  final data = <String>[];

  return bytes
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .transform(
        StreamTransformer<String, SseEvent>.fromHandlers(
          handleData: (line, sink) {
            if (line.isEmpty) {
              if (data.isNotEmpty) {
                sink.add(SseEvent(event ?? 'message', data.join('\n')));
              }
              event = null;
              data.clear();
              return;
            }
            if (line.startsWith(':')) return;

            final colon = line.indexOf(':');
            final field = colon < 0 ? line : line.substring(0, colon);
            var value = colon < 0 ? '' : line.substring(colon + 1);
            if (value.startsWith(' ')) value = value.substring(1);

            switch (field) {
              case 'event':
                event = value;
              case 'data':
                data.add(value);
            }
          },
        ),
      );
}
