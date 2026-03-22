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
    return RpcError(
      code: json['code'] as int,
      message: json['message'] as String,
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

  @override
  String toString() {
    if (data == null) {
      return 'RpcError(code: $code, message: $message)';
    }
    return 'RpcError(code: $code, message: $message, data: $data)';
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

    return ProblemDetails(
      type: json['type'] as String,
      title: json['title'] as String,
      status: json['status'] as int,
      detail: json['detail'] as String?,
      instance: json['instance'] as String?,
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
