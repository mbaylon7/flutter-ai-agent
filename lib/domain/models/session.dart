/// A conversation in the OpenClaw gateway.
///
/// The stable identifier is [key] (e.g. `"agent:main:main"`). It is what
/// `chat.send`, `chat.history`, etc. expect as `sessionKey`.
class Session {
  const Session({
    required this.key,
    required this.title,
    required this.updatedAt,
    required this.kind,
    required this.pinned,
    this.lastPreview,
    this.totalTokens,
    this.estimatedCostUsd,
  });

  /// Stable session identifier (gateway calls this `key`). Used as `sessionKey`.
  final String key;

  /// User-facing title (gateway: `displayName`).
  final String title;

  /// Last update timestamp.
  final DateTime updatedAt;

  /// "direct", "cron", etc. — used to distinguish system vs user sessions.
  final String kind;

  /// Local-only flag — gateway doesn't store it.
  final bool pinned;

  final String? lastPreview;
  final int? totalTokens;
  final double? estimatedCostUsd;

  factory Session.fromJson(Map<String, dynamic> j) => Session(
        key: j['key'] as String,
        title:
            (j['label'] as String?) ?? (j['displayName'] as String?) ?? 'Untitled',
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (j['updatedAt'] as num?)?.toInt() ?? 0,
        ),
        kind: (j['kind'] as String?) ?? 'direct',
        pinned: false, // local-only; merged from cache
        totalTokens: (j['totalTokens'] as num?)?.toInt(),
        estimatedCostUsd: (j['estimatedCostUsd'] as num?)?.toDouble(),
      );

  Session copyWith({
    String? key,
    String? title,
    DateTime? updatedAt,
    String? kind,
    bool? pinned,
    String? lastPreview,
    int? totalTokens,
    double? estimatedCostUsd,
  }) =>
      Session(
        key: key ?? this.key,
        title: title ?? this.title,
        updatedAt: updatedAt ?? this.updatedAt,
        kind: kind ?? this.kind,
        pinned: pinned ?? this.pinned,
        lastPreview: lastPreview ?? this.lastPreview,
        totalTokens: totalTokens ?? this.totalTokens,
        estimatedCostUsd: estimatedCostUsd ?? this.estimatedCostUsd,
      );
}
