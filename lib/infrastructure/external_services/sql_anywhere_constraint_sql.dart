/// Evidence from public SQL Anywhere 16 catalogs. Internal not_enforced is never authority.
abstract final class SqlAnywhereConstraintSql {
  static const _supported =
      "COALESCE(PROPERTY('ProductName'),'')='SQL Anywhere' AND COALESCE(PROPERTY('ProductVersion'),'') LIKE '16.%'";
  static String _backed(String table, String physical, String constraint, String kind) =>
      "$table.table_type_str='BASE' AND $physical.phys_index_id IS NOT NULL AND $constraint.constraint_type='$kind' AND NOT EXISTS(SELECT 1 FROM SYS.SYSPROXYTAB proxy WHERE proxy.table_object_id=$table.object_id)";

  static String query(String kind) {
    if (kind == 'foreign') {
      final child = _backed('t', 'ph', 'ct', 'F');
      const parent =
          "p.table_type_str='BASE' AND pp.phys_index_id IS NOT NULL AND pcst.constraint_type IN ('P','U') AND pi.[unique]=2 AND NOT EXISTS(SELECT 1 FROM SYS.SYSPROXYTAB proxy WHERE proxy.table_object_id=p.object_id)";
      final status =
          "CASE WHEN NOT ($_supported) THEN 'unknown' WHEN CASE WHEN $child AND $parent THEN 1 ELSE 0 END=0 THEN 'unknown' WHEN LOWER(CONNECTION_PROPERTY('fire_triggers'))='off' OR LOCATE(LOWER(PROPERTY('CommandLine')),'-gf')>0 THEN 'disabled' WHEN COALESCE(LOWER(CONNECTION_PROPERTY('fire_triggers')),'')<>'on' OR COALESCE(TRIM(PROPERTY('CommandLine')),'')='' OR LOCATE(PROPERTY('CommandLine'),'@')>0 THEN 'unknown' ELSE 'enabled' END";
      return 'SELECT u.user_name AS fktable_schem,t.table_name AS fktable_name,c.column_name AS fkcolumn_name,pu.user_name AS pktable_schem,p.table_name AS pktable_name,pc.column_name AS pkcolumn_name,ic.sequence+1 AS key_seq,i.index_name AS fk_name,$status AS constraint_status FROM SYS.SYSFKEY f JOIN SYS.SYSTAB t ON t.table_id=f.foreign_table_id JOIN SYS.SYSUSER u ON u.user_id=t.creator JOIN SYS.SYSTAB p ON p.table_id=f.primary_table_id JOIN SYS.SYSUSER pu ON pu.user_id=p.creator JOIN SYS.SYSIDX i ON i.table_id=f.foreign_table_id AND i.index_id=f.foreign_index_id JOIN SYS.SYSIDXCOL ic ON ic.table_id=i.table_id AND ic.index_id=i.index_id JOIN SYS.SYSTABCOL c ON c.table_id=t.table_id AND c.column_id=ic.column_id JOIN SYS.SYSTABCOL pc ON pc.table_id=p.table_id AND pc.column_id=ic.primary_column_id LEFT JOIN SYS.SYSPHYSIDX ph ON ph.table_id=i.table_id AND ph.phys_index_id=i.phys_index_id LEFT JOIN SYS.SYSCONSTRAINT ct ON ct.ref_object_id=i.object_id AND ct.table_object_id=t.object_id LEFT JOIN SYS.SYSIDX pi ON pi.table_id=f.primary_table_id AND pi.index_id=f.primary_index_id LEFT JOIN SYS.SYSPHYSIDX pp ON pp.table_id=pi.table_id AND pp.phys_index_id=pi.phys_index_id LEFT JOIN SYS.SYSCONSTRAINT pcst ON pcst.ref_object_id=pi.object_id AND pcst.table_object_id=p.object_id WHERE u.user_name=:schema AND t.table_name=:table ORDER BY i.index_name,ic.sequence';
    }
    if (kind != 'primary' && kind != 'unique') throw ArgumentError('Unsupported constraint kind');
    final proof = _backed('t', 'ph', 'ct', kind == 'primary' ? 'P' : 'U');
    final category = kind == 'primary' ? 'i.index_category=1' : 'i.index_category=3 AND i.[unique]=2';
    final status = "CASE WHEN $_supported AND $proof AND i.[unique]=2 THEN 'enabled' ELSE 'unknown' END";
    return 'SELECT u.user_name AS table_schem,t.table_name,c.column_name,ic.sequence+1 AS key_seq,i.index_name AS pk_name,$status AS constraint_status FROM SYS.SYSTAB t JOIN SYS.SYSUSER u ON u.user_id=t.creator JOIN SYS.SYSIDX i ON i.table_id=t.table_id JOIN SYS.SYSIDXCOL ic ON ic.table_id=i.table_id AND ic.index_id=i.index_id JOIN SYS.SYSTABCOL c ON c.table_id=t.table_id AND c.column_id=ic.column_id LEFT JOIN SYS.SYSPHYSIDX ph ON ph.table_id=i.table_id AND ph.phys_index_id=i.phys_index_id LEFT JOIN SYS.SYSCONSTRAINT ct ON ct.ref_object_id=i.object_id AND ct.table_object_id=t.object_id WHERE $category AND u.user_name=:schema AND t.table_name=:table ORDER BY i.index_name,ic.sequence';
  }
}
