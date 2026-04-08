# MariaDB continuous integration setup

This launch corresponding server in GitHub action.

other related project : https://github.com/mariadb-corporation/connector-ci-build-matrix

## MaxScale Support

This action now supports deploying MaxScale as a proxy in front of MariaDB Enterprise for testing.

### Usage

To enable MaxScale in your CI workflow, add the `maxscale-tag` input parameter:

```yaml
- uses: mariadb-corporation/connector-ci-setup@main
  with:
    db-type: enterprise
    db-tag: '11.4'
    maxscale-tag: '25.01'  # Enable MaxScale
    test-db-password: ${{ secrets.DB_PASSWORD }}
    test-db-database: testdb
    registry-user: ${{ secrets.ENTERPRISE_USER }}
    registry-password: ${{ secrets.ENTERPRISE_TOKEN }}
    os: ubuntu-latest
```

### Environment Variables

When MaxScale is enabled, the following environment variables are automatically set:

- `TEST_MXS_PORT`: MaxScale non-SSL port (default: 4006)
- `TEST_MXS_SSL_PORT`: MaxScale SSL port (default: 4009)

### Requirements

- MaxScale requires MariaDB Enterprise
- Registry credentials must be provided (`registry-user` and `registry-password`)
- MaxScale will automatically configure SSL using the same certificates as MariaDB

### Architecture

When MaxScale is enabled:
1. MariaDB Enterprise server is deployed on port 3306
2. MaxScale is deployed as a proxy
3. MaxScale listens on:
   - Port 4006 for non-SSL connections
   - Port 4009 for SSL connections
   - Port 8989 for REST API
4. Tests can connect through MaxScale instead of directly to MariaDB

### Example Test Connection

```javascript
// Connect through MaxScale (non-SSL)
const conn = await mariadb.createConnection({
  host: 'mariadb.example.com',
  port: process.env.TEST_MXS_PORT || 4006,
  user: 'root',
  password: process.env.TEST_DB_PASSWORD
});

// Connect through MaxScale (SSL)
const connSSL = await mariadb.createConnection({
  host: 'mariadb.example.com',
  port: process.env.TEST_MXS_SSL_PORT || 4009,
  user: 'root',
  password: process.env.TEST_DB_PASSWORD,
  ssl: true
});
```
