/// JSON-RPC 2.0 Error object.
///
/// Represents an error in a JSON-RPC response.
class RpcError {
  const RpcError({
    required this.code,
    required this.message,
    this.data,
  });

  factory RpcError.fromJson(Map<String, dynamic> json) {
    final rawCode = json['code'];
    final rawMessage = json['message'];

    final int code;
    if (rawCode is int) {
      code = rawCode;
    } else if (rawCode is num) {
      code = rawCode.toInt();
    } else {
      throw FormatException('RpcError.code must be an integer, got ${rawCode.runtimeType}');
    }

    if (rawMessage is! String) {
      throw FormatException('RpcError.message must be a string, got ${rawMessage.runtimeType}');
    }

    return RpcError(
      code: code,
      message: rawMessage,
      data: json['data'],
    );
  }

  /// Error code. Must be an integer.
  final int code;

  /// Short error description.
  final String message;

  /// Additional error information (optional).
  /// Can contain Problem Details (RFC 9457) style data.
  final dynamic data;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'code': code,
      'message': message,
    };

    if (data != null) {
      json['data'] = data;
    }

    return json;
  }
}

/// Problem Details style error data (RFC 9457 inspired).
class ProblemDetails {
  const ProblemDetails({
    required this.type,
    required this.title,
    required this.status,
    this.detail,
    this.instance,
    this.extensions = const {},
  });

  factory ProblemDetails.fromJson(Map<String, dynamic> json) {
    final standardKeys = {'type', 'title', 'status', 'detail', 'instance'};
    final extensions = <String, dynamic>{};

    for (final entry in json.entries) {
      if (!standardKeys.contains(entry.key)) {
        extensions[entry.key] = entry.value;
      }
    }

    final rawStatus = json['status'];
    final int status;
    if (rawStatus is int) {
      status = rawStatus;
    } else if (rawStatus is num) {
      status = rawStatus.toInt();
    } else {
      throw FormatException('ProblemDetails.status must be an integer, got ${rawStatus.runtimeType}');
    }

    return ProblemDetails(
      type: json['type'] is String ? json['type'] as String : '',
      title: json['title'] is String ? json['title'] as String : '',
      status: status,
      detail: json['detail'] is String ? json['detail'] as String : null,
      instance: json['instance'] is String ? json['instance'] as String : null,
      extensions: extensions,
    );
  }

  /// URI identifying the problem type.
  final String type;

  /// Short, human-readable summary.
  final String title;

  /// HTTP-style status code (for semantic mapping).
  final int status;

  /// Human-readable explanation specific to this occurrence.
  final String? detail;

  /// URI identifying the specific occurrence.
  final String? instance;

  /// Problem-specific extension fields.
  final Map<String, dynamic> extensions;

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'title': title,
      'status': status,
      if (detail != null) 'detail': detail,
      if (instance != null) 'instance': instance,
      ...extensions,
    };
  }
}
