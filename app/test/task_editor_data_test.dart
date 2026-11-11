import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/api/api_exception.dart';
import 'package:taskradar/api/attachment_api.dart';
import 'package:taskradar/api/link_preview_api.dart';
import 'package:taskradar/api/patch_field.dart';
import 'package:taskradar/api/project_api.dart';
import 'package:taskradar/api/task_wire.dart';
import 'package:taskradar/models/board_project.dart';
import 'package:taskradar/models/checklist_item.dart';
import 'package:taskradar/models/task.dart';
import 'package:taskradar/models/task_attachment.dart';
import 'package:taskradar/models/task_location.dart';
import 'package:taskradar/models/task_status.dart';
import 'package:taskradar/storage/outbox_store.dart';

import 'support/fake_backend.dart';
import 'support/fake_project_backend.dart';

/// The task editor's data (WP2, `design/task-editor-spec.md` §10): the new
/// task fields on the wire, the attachment and link-preview API, and the
/// outbox file format that carries them.
void main() {
  final png = Uint8List.fromList(<int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3, 4, //
  ]);

  Map<String, dynamic> taskJson({Map<String, dynamic> extra = const {}}) =>
      <String, dynamic>{
        'id': 't1',
        'projectId': 'p1',
        'title': 'Собрать шкаф',
        'description': null,
        'status': 'pending',
        'position': 1000,
        'remindAt': null,
        'createdAt': '2026-11-11T10:00:00.000Z',
        'updatedAt': '2026-11-11T10:00:00.000Z',
        'isCurrent': true,
        ...extra,
      };

  group('the task model', () {
    test('reads checklist, place and pictures, and round-trips through '
        'JSON text', () {
      final task = Task.fromJson(
        taskJson(
          extra: <String, dynamic>{
            'checklist': <dynamic>[
              <String, dynamic>{
                'id': 'item0001',
                'text': 'Шурупы',
                'done': true,
              },
              <String, dynamic>{
                'id': 'item0002',
                'text': 'Петли',
                'done': false,
              },
            ],
            'location': <String, dynamic>{
              'lat': 55.75,
              'lng': 37,
              'radius': 300,
              'label': 'Дом',
            },
            'attachments': <dynamic>[
              <String, dynamic>{
                'id': 'a' * 32,
                'mime': 'image/png',
                'width': 640,
                'height': 480,
                'sizeBytes': 1234,
                'createdAt': '2026-11-11T10:05:00.000Z',
              },
            ],
          },
        ),
      );

      expect(task.checklist, const <ChecklistItem>[
        ChecklistItem(id: 'item0001', text: 'Шурупы', done: true),
        ChecklistItem(id: 'item0002', text: 'Петли'),
      ]);
      expect(
        task.location,
        const TaskLocation(lat: 55.75, lng: 37, radius: 300, label: 'Дом'),
      );
      expect(task.attachments.single.sizeBytes, 1234);

      // Through text, as the board snapshot and an outbox `row` go.
      final back = Task.fromJson(
        jsonDecode(jsonEncode(task.toJson())) as Map<String, dynamic>,
      );
      expect(back, task);
      // And straight from the map, nested values as maps (explicitToJson).
      expect(Task.fromJson(task.toJson()), task);
    });

    test('a row without the new keys -- an older server, an old snapshot, '
        'the raw row of /focus -- reads as none', () {
      final task = Task.fromJson(
        taskJson(
          extra: <String, dynamic>{
            'locLat': 55.0,
            'locLng': 37.0,
            'locRadius': 200,
            'locLabel': 'Место',
          },
        ),
      );
      expect(task.checklist, isNull);
      expect(task.location, isNull);
      expect(task.attachments, isEmpty);
    });

    test('the board snapshot keeps them', () {
      final row = BoardProject.fromJson(<String, dynamic>{
        'id': 'p1',
        'name': 'Дом',
        'scopeId': 's',
        'archivedAt': null,
        'createdAt': '2026-11-11T10:00:00.000Z',
        'updatedAt': '2026-11-11T10:00:00.000Z',
        'tasks': <dynamic>[
          taskJson(
            extra: <String, dynamic>{
              'checklist': <dynamic>[
                <String, dynamic>{'id': 'item0001', 'text': 'x', 'done': false},
              ],
              'location': <String, dynamic>{
                'lat': 1.5,
                'lng': 2.5,
                'radius': 100,
                'label': 'Место',
              },
            },
          ),
        ],
      });
      final back = BoardProject.fromJson(
        jsonDecode(jsonEncode(row.toJson())) as Map<String, dynamic>,
      );
      expect(back, row);
      expect(back.tasks.single.location!.label, 'Место');
    });

    test('checklist ids are fresh, inside the server\'s 8..40', () {
      final ids = <String>{for (var i = 0; i < 50; i++) ChecklistItem.newId()};
      expect(ids, hasLength(50));
      expect(ids.every((id) => id.length >= 8 && id.length <= 40), isTrue);
      expect(
        ChecklistItem.progressOf(const <ChecklistItem>[
          ChecklistItem(id: 'item0001', text: 'a', done: true),
          ChecklistItem(id: 'item0002', text: 'b'),
        ]),
        '1/2',
      );
    });
  });

  group('TaskWire', () {
    test('an empty checklist goes out as null, a place without a label '
        'without the key', () {
      expect(TaskWire.checklist(const <ChecklistItem>[]), isNull);
      expect(TaskWire.checklist(null), isNull);
      expect(
        TaskWire.location(const TaskLocation(lat: 1, lng: 2)),
        <String, Object?>{'lat': 1.0, 'lng': 2.0, 'radius': 200},
      );
      expect(TaskWire.checklistFrom(const <Object?>[]), isNull);
      expect(TaskWire.locationFrom(null), isNull);
    });
  });

  group('ProjectApi with the editor\'s fields', () {
    late FakeBackend backend;
    late FakeProjectBackend server;
    late ProjectApi api;
    late String projectId;

    setUp(() {
      backend = FakeBackend();
      server = FakeProjectBackend(backend);
      api = ProjectApi(backend.client);
      projectId = server.addProject(name: 'Дом');
    });

    test('a create carries checklist, place and status', () async {
      final task = await api.createTask(
        projectId: projectId,
        title: 'Собрать шкаф',
        status: TaskStatus.blocked,
        checklist: const <ChecklistItem>[
          ChecklistItem(id: 'item0001', text: 'Шурупы'),
        ],
        location: const TaskLocation(lat: 55.7, lng: 37.6, label: 'Дом'),
        createKey: 'create-key-1',
      );

      final body = backend.lastRequest.data as Map<String, dynamic>;
      expect(body['checklist'], <dynamic>[
        <String, dynamic>{'id': 'item0001', 'text': 'Шурупы', 'done': false},
      ]);
      expect(body['location'], <String, dynamic>{
        'lat': 55.7,
        'lng': 37.6,
        'radius': 200,
        'label': 'Дом',
      });
      expect(body['status'], 'blocked');
      expect(task.checklist!.single.text, 'Шурупы');
      expect(task.location!.label, 'Дом');
      expect(task.attachments, isEmpty);
    });

    test('an empty checklist and no place are not sent at all', () async {
      await api.createTask(
        projectId: projectId,
        title: 'Пусто',
        checklist: const <ChecklistItem>[],
      );
      final body = backend.lastRequest.data as Map<String, dynamic>;
      expect(body.containsKey('checklist'), isFalse);
      expect(body.containsKey('location'), isFalse);
    });

    test('a PATCH sets, clears and leaves the two fields', () async {
      final taskId = server.addTask(projectId: projectId, title: 'Шкаф');

      await api.updateTask(
        taskId,
        checklist: const PatchField<List<ChecklistItem>>.to(<ChecklistItem>[
          ChecklistItem(id: 'item0001', text: 'Петли', done: true),
        ]),
        location: const PatchField<TaskLocation>.to(
          TaskLocation(lat: 1, lng: 2, radius: 500),
        ),
      );
      expect(server.patches.last.body['checklist'], <dynamic>[
        <String, dynamic>{'id': 'item0001', 'text': 'Петли', 'done': true},
      ]);
      expect(server.patches.last.body['location'], <String, dynamic>{
        'lat': 1.0,
        'lng': 2.0,
        'radius': 500,
      });

      final cleared = await api.updateTask(
        taskId,
        checklist: const PatchField<List<ChecklistItem>>.to(<ChecklistItem>[]),
        location: const PatchField<TaskLocation>.clear(),
      );
      final body = server.patches.last.body;
      expect(body.containsKey('checklist'), isTrue);
      expect(body['checklist'], isNull);
      expect(body['location'], isNull);
      expect(cleared.checklist, isNull);
      expect(cleared.location, isNull);

      await api.updateTask(taskId, title: 'Шкаф-купе');
      expect(server.patches.last.body.containsKey('checklist'), isFalse);
      expect(server.patches.last.body.containsKey('location'), isFalse);
    });
  });

  group('AttachmentApi', () {
    late FakeBackend backend;
    late FakeProjectBackend server;
    late AttachmentApi api;
    late String taskId;

    setUp(() {
      backend = FakeBackend();
      server = FakeProjectBackend(backend);
      api = AttachmentApi(backend.client);
      final projectId = server.addProject(name: 'Дом');
      taskId = server.addTask(projectId: projectId, title: 'Шкаф');
    });

    test(
      'uploads multipart, uploadKey before the file, with progress',
      () async {
        final progress = <double>[];
        final saved = await api.upload(
          taskId,
          uploadKey: 'upload-key-1',
          bytes: png,
          mime: 'image/png',
          onSendProgress: (sent, total) => progress.add(sent / total),
        );

        expect(saved.mime, 'image/png');
        expect(saved.sizeBytes, png.length);
        expect(server.attachmentBytes[saved.id], png);
        expect(server.uploads.single.uploadKey, 'upload-key-1');
        expect(server.uploads.single.filename, 'upload-key-1.png');
        expect(
          backend.lastRequest.headers['content-type'] as String,
          startsWith('multipart/form-data'),
        );
        expect(backend.lastRequest.headers['Authorization'], isNull);
        expect(progress, isNotEmpty);
      },
    );

    test('a replay of the same uploadKey gets the same attachment', () async {
      final first = await api.upload(
        taskId,
        uploadKey: 'upload-key-1',
        bytes: png,
        mime: 'image/png',
      );
      final again = await api.upload(
        taskId,
        uploadKey: 'upload-key-1',
        bytes: png,
        mime: 'image/png',
      );
      expect(again, first);
      expect(server.tasks.single['attachments'], hasLength(1));
    });

    test('the server\'s refusals arrive as their status codes', () async {
      for (var i = 0; i < FakeProjectBackend.maxAttachmentsPerTask; i++) {
        server.addAttachment(taskId: taskId);
      }
      await expectLater(
        api.upload(
          taskId,
          uploadKey: 'k-31-abc',
          bytes: png,
          mime: 'image/png',
        ),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 409)),
      );
      await expectLater(
        api.upload(
          'missing',
          uploadKey: 'k-missing',
          bytes: png,
          mime: 'image/png',
        ),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 404)),
      );
    });

    test(
      'fetches the picture and its thumbnail as bytes, deletes it',
      () async {
        final id = server.addAttachment(
          taskId: taskId,
          bytes: Uint8List.fromList(<int>[1, 2, 3]),
        );

        expect(await api.fetchBytes(id), <int>[1, 2, 3]);
        expect(backend.lastRequest.path, '/attachments/$id');
        expect(await api.fetchBytes(id, thumb: true), <int>[3, 2, 1]);
        expect(backend.lastRequest.path, '/attachments/$id/thumb');

        await api.delete(id);
        expect(server.attachmentBytes, isEmpty);
        await expectLater(
          api.fetchBytes(id),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'status', 404)
                .having((e) => e.message, 'message', 'Attachment not found'),
          ),
        );
      },
    );

    test('knows the three types by their bytes', () {
      expect(sniffImageMime(png), 'image/png');
      expect(
        sniffImageMime(Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xE0])),
        'image/jpeg',
      );
      expect(
        sniffImageMime(
          Uint8List.fromList(<int>[
            ...ascii.encode('RIFF'),
            0, 0, 0, 0, //
            ...ascii.encode('WEBP'),
          ]),
        ),
        'image/webp',
      );
      expect(
        sniffImageMime(Uint8List.fromList(ascii.encode('GIF89a'))),
        isNull,
      );
      expect(extensionForMime('image/jpeg'), 'jpg');
    });
  });

  group('LinkPreviewApi', () {
    test('a preview, or null for a 204', () async {
      final backend = FakeBackend();
      final server = FakeProjectBackend(backend);
      server.linkPreviews['https://example.com/a'] = <String, dynamic>{
        'url': 'https://example.com/a',
        'title': 'Пример',
        'siteName': 'Example',
      };
      final api = LinkPreviewApi(backend.client);

      expect(
        await api.fetch('https://example.com/a'),
        const LinkPreview(
          url: 'https://example.com/a',
          title: 'Пример',
          siteName: 'Example',
        ),
      );
      expect(
        backend.lastRequest.queryParameters['url'],
        'https://example.com/a',
      );
      expect(await api.fetch('https://example.com/none'), isNull);
    });
  });

  group('the outbox file', () {
    test('a version-1 file is read as it is', () {
      final raw = jsonEncode(<String, dynamic>{
        'version': 1,
        'entries': <dynamic>[
          <String, dynamic>{
            'key': 'k1',
            'kind': 'createTask',
            'projectId': 'p',
            'title': 'Старое',
            'body': <String, dynamic>{'title': 'Старое'},
            'expected': <String, dynamic>{},
            'state': 'waiting',
            'createdAt': '2026-11-01T10:00:00.000Z',
            'conflictFields': <dynamic>[],
          },
        ],
      });
      final entry = OutboxStore.decode(raw).single;
      expect(entry.kind, OutboxKind.createTask);
      expect(entry.waited, isFalse);
      expect(
        (jsonDecode(OutboxStore.encode(<OutboxEntry>[entry]))
            as Map)['version'],
        OutboxStore.schemaVersion,
      );
    });

    test('a picture entry round-trips', () {
      final entry = OutboxEntry(
        key: 'upload1',
        kind: OutboxKind.uploadAttachment,
        projectId: 'p',
        taskId: 'local:outbox:create1',
        title: 'Шкаф',
        body: const <String, Object?>{
          'uploadKey': 'upload1',
          'mime': 'image/png',
          'localPath': '/x/outbox_files/upload1.png',
        },
        createdAt: DateTime.utc(2026, 11, 11),
        waited: true,
      );
      final back = OutboxStore.decode(
        OutboxStore.encode(<OutboxEntry>[entry]),
      ).single;
      expect(back.toJson(), entry.toJson());
      expect(back.uploadKey, 'upload1');
      expect(back.localPath, '/x/outbox_files/upload1.png');
      expect(back.pendingAttachmentId, 'local:upload:upload1');
      expect(back.waited, isTrue);
    });
  });

  test('TaskAttachment reads the server\'s metadata', () {
    final attachment = TaskWire.attachmentFrom(<String, dynamic>{
      'id': 'b' * 32,
      'mime': 'image/webp',
      'width': 512,
      'height': 256,
      'sizeBytes': 10,
      'createdAt': '2026-11-11T10:00:00.000Z',
    });
    expect(
      attachment,
      TaskAttachment(
        id: 'b' * 32,
        mime: 'image/webp',
        width: 512,
        height: 256,
        sizeBytes: 10,
        createdAt: '2026-11-11T10:00:00.000Z',
      ),
    );
  });
}
