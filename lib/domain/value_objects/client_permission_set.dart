class ClientPermissionSet {
  const ClientPermissionSet({
    required this.canRead,
    required this.canUpdate,
    required this.canDelete,
  });

  factory ClientPermissionSet.fromJson(Map<String, dynamic> json) {
    return ClientPermissionSet(
      canRead: json['read'] as bool? ?? false,
      canUpdate: json['update'] as bool? ?? false,
      canDelete: json['delete'] as bool? ?? false,
    );
  }

  final bool canRead;
  final bool canUpdate;
  final bool canDelete;

  bool allows(SqlOperation operation) {
    return switch (operation) {
      SqlOperation.read => canRead,
      SqlOperation.update => canUpdate,
      SqlOperation.delete => canDelete,
    };
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'read': canRead,
      'update': canUpdate,
      'delete': canDelete,
    };
  }
}

enum SqlOperation {
  read,
  update,
  delete,
}
