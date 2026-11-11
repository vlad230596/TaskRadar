import 'api_client.dart';

/// A personal token for coding agents, as the list shows it
/// (`backend/src/routes/agentTokens.ts`). Never the token itself: that is
/// only in [CreatedAgentToken], once.
class AgentToken {
  const AgentToken({
    required this.id,
    required this.name,
    required this.prefix,
    required this.createdAt,
    required this.lastUsedAt,
  });

  factory AgentToken.fromJson(Map<String, dynamic> json) => AgentToken(
    id: json['id'] as String,
    name: json['name'] as String?,
    prefix: json['prefix'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    lastUsedAt: switch (json['lastUsedAt']) {
      final String at => DateTime.parse(at),
      _ => null,
    },
  );

  final String id;
  final String? name;

  /// The first characters of the token, to tell tokens apart.
  final String prefix;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
}

/// The answer to creating a token: the row, and the token in plain text --
/// the only time the server ever sends it.
class CreatedAgentToken {
  const CreatedAgentToken({required this.info, required this.token});

  final AgentToken info;
  final String token;
}

/// `/agent-tokens`: list, create, revoke. Behind the ordinary session.
class AgentTokenApi {
  AgentTokenApi(this._client);

  final ApiClient _client;

  Future<List<AgentToken>> list() async {
    final rows = await _client.get<List<dynamic>>('/agent-tokens');
    return <AgentToken>[
      for (final row in rows)
        AgentToken.fromJson((row as Map).cast<String, dynamic>()),
    ];
  }

  Future<CreatedAgentToken> create({String? name}) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/agent-tokens',
      body: <String, dynamic>{
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      },
    );
    return CreatedAgentToken(
      info: AgentToken.fromJson(json),
      token: json['token'] as String,
    );
  }

  Future<void> revoke(String id) =>
      _client.delete<void>('/agent-tokens/${Uri.encodeComponent(id)}');
}
