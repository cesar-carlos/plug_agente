class EnvelopeModel {
  final int v;
  final String type;
  final String requestId;
  final String agentId;
  final DateTime timestamp;
  final String cmp;
  final String contentType;
  final List<Map<String, dynamic>> payloadBytes;

  const EnvelopeModel({
    required this.v,
    required this.type,
    required this.requestId,
    required this.agentId,
    required this.timestamp,
    required this.cmp,
    required this.contentType,
    required this.payloadBytes,
  });

  factory EnvelopeModel.fromJson(Map<String, dynamic> json) {
    return EnvelopeModel(
      v: json['v'] as int,
      type: json['type'] as String,
      requestId: json['requestId'] as String,
      agentId: json['agentId'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      cmp: json['cmp'] as String? ?? 'none',
      contentType: json['contentType'] as String? ?? 'json',
      payloadBytes: (json['payloadBytes'] as List<dynamic>).cast<Map<String, dynamic>>(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'v': v,
      'type': type,
      'requestId': requestId,
      'agentId': agentId,
      'timestamp': timestamp.toIso8601String(),
      'cmp': cmp,
      'contentType': contentType,
      'payloadBytes': payloadBytes,
    };
  }
}
