# SQL Anywhere Connection

## Connection String Format

SQL Anywhere ODBC expects **HOST** as `host:port` (combined), not separate parameters. This matches the format used by `dbping` and `dbisql`.

### Format

```
DRIVER={SQL Anywhere 16};UID=user;PWD=password;DBN=database;HOST=host:port
```

### Parameters

| Parameter | Description                                                  |
| --------- | ------------------------------------------------------------ |
| DRIVER    | ODBC driver name (e.g. `SQL Anywhere 16`, `SQL Anywhere 17`) |
| UID       | Username                                                     |
| PWD       | Password                                                     |
| DBN       | Database name                                                |
| HOST      | `hostname:port` or `ip:port`                                 |

### Example

```
DRIVER={SQL Anywhere 16};UID=dba;PWD=sql;DBN=VL;HOST=localhost:2650
```

## Common Ports

- **2638** – SQL Anywhere default port
- **2650** – Common alternative

## Troubleshooting

### "Database server not found" (08001, -100)

- Verify the server is running
- Confirm host and port (use `Host=host:port` format)
- Check firewall allows the port
- Ensure 64-bit ODBC driver for 64-bit app (Plug Agente)

### Testing via CMD

Use the scripts in `tool/`:

- `tool/test_db_cmd.bat` – connectivity test (dbping)
- `tool/test_select1_cmd.bat` – run `SELECT 1` (dbisql)

Edit the variables at the top of each script to match your environment.
