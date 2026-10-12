-- DBA only, offline maintenance. Never executed by discovery or the MCP.
-- Review the target database first. Existing identity must NOT be overwritten.
CREATE TABLE "DBA"."se7e_source_identity" (
  singleton INTEGER NOT NULL PRIMARY KEY CHECK (singleton = 1),
  version INTEGER NOT NULL CHECK (version = 1),
  database_uuid CHAR(36) NOT NULL UNIQUE
);
INSERT INTO "DBA"."se7e_source_identity" VALUES (1, 1, LOWER(CONVERT(VARCHAR(36), NEWID())));
CREATE TRIGGER "se7e_source_identity_frozen" BEFORE INSERT, UPDATE, DELETE
ON "DBA"."se7e_source_identity"
FOR EACH ROW
BEGIN
  DECLARE identity_frozen EXCEPTION FOR SQLSTATE '99001';
  SIGNAL identity_frozen;
END;
COMMIT;
-- Grant SELECT on DBA.se7e_source_identity only to the agent's technical principal.
-- Do not grant DBA, ALTER, DROP, INSERT, UPDATE or DELETE for this table.
-- A clone used as a DIFFERENT source needs an offline DBA re-enrollment with a NEW UUID.
