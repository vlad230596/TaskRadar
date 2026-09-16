/// JSON fixtures shaped exactly like the backend's responses.
///
/// Hand-written from `backend/src/routes/board.ts` + the Prisma models rather
/// than captured from a running server, because the point of the model tests is
/// to pin the *contract*: if the server ever stops sending `isCurrent`, or
/// starts omitting `tasks` for an empty project, a test here should be the thing
/// that notices.
library;

/// One project with three tasks: a done one, the current one, and a blocked one
/// carrying a reminder date. Task order is `position` ascending, as the server
/// guarantees.
Map<String, dynamic> projectWithTasksJson() => <String, dynamic>{
  'id': 'prj_1',
  'name': 'TaskRadar',
  'archivedAt': null,
  'createdAt': '2026-08-01T09:15:00.000Z',
  'updatedAt': '2026-09-10T18:00:00.000Z',
  'tasks': <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'tsk_1',
      'projectId': 'prj_1',
      'title': 'Свести бэкенд и клиент',
      'description': null,
      'status': 'done',
      'position': 1000,
      'remindAt': null,
      'createdAt': '2026-08-01T09:16:00.000Z',
      'updatedAt': '2026-08-02T10:00:00.000Z',
      'isCurrent': false,
    },
    <String, dynamic>{
      'id': 'tsk_2',
      'projectId': 'prj_1',
      'title': 'Каркас Flutter',
      'description': 'F0',
      'status': 'pending',
      'position': 2000,
      'remindAt': null,
      'createdAt': '2026-08-01T09:17:00.000Z',
      'updatedAt': '2026-08-02T10:00:00.000Z',
      'isCurrent': true,
    },
    <String, dynamic>{
      'id': 'tsk_3',
      'projectId': 'prj_1',
      'title': 'Жду кабель',
      'description': null,
      'status': 'blocked',
      'position': 3000,
      // UTC midnight of a calendar date -- the shape the reminder logic depends
      // on. See the comment on Project about why this stays a string.
      'remindAt': '2026-09-18T00:00:00.000Z',
      'createdAt': '2026-08-01T09:18:00.000Z',
      'updatedAt': '2026-08-02T10:00:00.000Z',
      'isCurrent': false,
    },
  ],
};

/// A project with no tasks at all. The server sends `"tasks": []`, not a missing
/// key -- this fixture exists to keep that distinction tested.
Map<String, dynamic> emptyProjectJson() => <String, dynamic>{
  'id': 'prj_2',
  'name': 'Пустой',
  'archivedAt': null,
  'createdAt': '2026-08-05T12:00:00.000Z',
  'updatedAt': '2026-08-05T12:00:00.000Z',
  'tasks': <Map<String, dynamic>>[],
};

/// The whole `GET /board?archived=false` body: a bare array, projects in
/// `createdAt` ascending order.
List<dynamic> boardJson() => <dynamic>[projectWithTasksJson(), emptyProjectJson()];

// --- builders -------------------------------------------------------------
//
// The fixtures above are the *reference* shapes and are deliberately verbose.
// The builders below exist for tests that vary one thing (a status, a reminder
// date, how many tasks are done) and should not have to restate the other nine
// fields to do it.

/// One task row, in exactly the shape the server sends.
Map<String, dynamic> taskJson({
  required String id,
  String projectId = 'prj_1',
  String title = 'Задача',
  String? description,
  String status = 'pending',
  int position = 1000,
  String? remindAt,
  bool isCurrent = false,
  String createdAt = '2026-08-01T09:00:00.000Z',
  String updatedAt = '2026-08-01T09:00:00.000Z',
}) => <String, dynamic>{
  'id': id,
  'projectId': projectId,
  'title': title,
  'description': description,
  'status': status,
  'position': position,
  'remindAt': remindAt,
  'createdAt': createdAt,
  'updatedAt': updatedAt,
  'isCurrent': isCurrent,
};

/// One board row: a project plus its tasks.
Map<String, dynamic> boardProjectJson({
  required String id,
  required String name,
  List<Map<String, dynamic>> tasks = const <Map<String, dynamic>>[],
  String? archivedAt,
  String createdAt = '2026-08-01T09:00:00.000Z',
  String updatedAt = '2026-08-01T09:00:00.000Z',
}) => <String, dynamic>{
  'id': id,
  'name': name,
  'archivedAt': archivedAt,
  'createdAt': createdAt,
  'updatedAt': updatedAt,
  'tasks': tasks,
};

/// `POST /auth/login` 200 body.
Map<String, dynamic> loginOkJson({String token = 'jwt.token.value'}) =>
    <String, dynamic>{
      'ok': true,
      'token': token,
      // Seconds, 30 days -- see LoginResult.expiresIn.
      'expiresIn': 2592000,
    };

/// The backend's 401 body. Identical shape for a wrong password and for a dead
/// session; only the message differs.
Map<String, dynamic> unauthorizedJson({String message = 'Unauthorized'}) =>
    <String, dynamic>{'error': 'Unauthorized', 'message': message};
