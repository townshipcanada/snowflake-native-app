# Deploying a New Version

Steps to submit an updated version of the Township Canada Native App to the Snowflake Marketplace.

## Prerequisites

- [Snowflake CLI](https://docs.snowflake.com/en/developer-guide/snowflake-cli/index) (`snow`) installed and configured
- `ACCOUNTADMIN` role on account `ZMYQUJY-VSB14218`

## 1. Upload updated files to the stage

From the project root directory:

```bash
snow stage copy setup_script.sql @township_canada_pkg.stage_content.app_stage/ --overwrite
```

If you also changed the Streamlit UI or manifest:

```bash
snow stage copy manifest.yml @township_canada_pkg.stage_content.app_stage/ --overwrite
snow stage copy streamlit/setup_wizard.py @township_canada_pkg.stage_content.app_stage/streamlit/ --overwrite
```

## 2. Register a new version

```sql
ALTER APPLICATION PACKAGE township_canada_pkg
  REGISTER VERSION v1_3
  USING '@township_canada_pkg.stage_content.app_stage';
```

> Increment the version number each time (v1_2, v1_3, v1_4, etc.). Check existing versions with `SHOW VERSIONS IN APPLICATION PACKAGE township_canada_pkg;`

## 3. Wait for security scan approval

```sql
SHOW VERSIONS IN APPLICATION PACKAGE township_canada_pkg;
SELECT "version", "patch", "review_status"
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
WHERE "version" = 'V1_3';
```

Re-run until `review_status` shows `APPROVED`. Usually takes 1-5 minutes.

## 4. Update the release channel

If the DEFAULT channel already has 2 versions, drop the oldest first:

```sql
-- Check what's on the channel
SHOW VERSIONS IN APPLICATION PACKAGE township_canada_pkg;

-- Drop old version if needed (keep the previous one as rollback)
ALTER APPLICATION PACKAGE township_canada_pkg
  MODIFY RELEASE CHANNEL DEFAULT
  DROP VERSION v1_1;

-- Add the new version
ALTER APPLICATION PACKAGE township_canada_pkg
  MODIFY RELEASE CHANNEL DEFAULT
  ADD VERSION v1_3;

-- Set it as the default
ALTER APPLICATION PACKAGE township_canada_pkg
  MODIFY RELEASE CHANNEL DEFAULT
  SET DEFAULT RELEASE DIRECTIVE
  VERSION = v1_3
  PATCH = 0;
```

## 5. Test locally

```sql
DROP APPLICATION IF EXISTS township_canada_app;
CREATE APPLICATION township_canada_app
  FROM APPLICATION PACKAGE township_canada_pkg;

-- Core functions
SELECT township_canada_app.core.version();
SELECT township_canada_app.core.validate_lld('NW-36-42-3-W5');
SELECT township_canada_app.core.validate_lld('083E/01');
SELECT township_canada_app.core.parse_lld('NW-36-42-3-W5');
SELECT township_canada_app.core.standardize_lld('NE 7 102 19 W4');

-- Demo
SELECT township_canada_app.demo.lookup('NE-1-25-1-W5');
SELECT COUNT(*) FROM township_canada_app.demo.sample_conversions;

-- References
SELECT * FROM township_canada_app.reference.supported_formats;
SELECT * FROM township_canada_app.reference.sample_queries;
```

## 6. Verify Marketplace listing updates

Go to **Snowsight > Provider Studio > Listings** and confirm the listing reflects the new version. Consumers on the DEFAULT release channel will receive the update automatically.

## Version history

| Version | Date       | Changes |
|---------|------------|---------|
| v1_0    | 2026-03-12 | Initial submission |
| v1_1    | 2026-03-27 | Remove config DDL and pricing from consumer-facing content |
| v1_2    | 2026-04-01 | Fix LOOKUP NULL bug, add NTS validation, 100 samples |
