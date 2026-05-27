// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes
// Reason: Immutable value object compares by value for equality.

class ClientPermissionSet {
  const ClientPermissionSet({
    required this.canRead,
    required this.canUpdate,
    required this.canDelete,
    this.canDdl = false,
  });

  factory ClientPermissionSet.fromJson(Map<String, dynamic> json) {
    return ClientPermissionSet(
      canRead: json['read'] as bool? ?? false,
      canUpdate: json['update'] as bool? ?? false,
      canDelete: json['delete'] as bool? ?? false,
      canDdl: json['ddl'] as bool? ?? false,
    );
  }

  static const none = ClientPermissionSet(
    canRead: false,
    canUpdate: false,
    canDelete: false,
  );

  static const legacyScopedAccess = ClientPermissionSet(
    canRead: true,
    canUpdate: true,
    canDelete: true,
  );

  static const fullAccess = ClientPermissionSet(
    canRead: true,
    canUpdate: true,
    canDelete: true,
    canDdl: true,
  );

  final bool canRead;
  final bool canUpdate;
  final bool canDelete;
  final bool canDdl;

  bool get hasAnyPermission => canRead || canUpdate || canDelete || canDdl;

  bool get isFullAccess => canRead && canUpdate && canDelete && canDdl;

  bool allows(SqlOperation operation) {
    return switch (operation) {
      SqlOperation.read => canRead,
      SqlOperation.update => canUpdate,
      SqlOperation.delete => canDelete,
      SqlOperation.ddl => canDdl,
    };
  }

  ClientPermissionSet copyWith({
    bool? canRead,
    bool? canUpdate,
    bool? canDelete,
    bool? canDdl,
  }) {
    return ClientPermissionSet(
      canRead: canRead ?? this.canRead,
      canUpdate: canUpdate ?? this.canUpdate,
      canDelete: canDelete ?? this.canDelete,
      canDdl: canDdl ?? this.canDdl,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'read': canRead,
      'update': canUpdate,
      'delete': canDelete,
      'ddl': canDdl,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ClientPermissionSet &&
        other.canRead == canRead &&
        other.canUpdate == canUpdate &&
        other.canDelete == canDelete &&
        other.canDdl == canDdl;
  }

  @override
  int get hashCode => Object.hash(canRead, canUpdate, canDelete, canDdl);
}

enum SqlOperation {
  read,
  update,
  delete,
  ddl,
}
