-- =============================================================================
-- Township Canada — Full Setup (0 → 100)
--
-- Prerequisites:
--   • Role with CREATE APPLICATION PACKAGE / CREATE APPLICATION privileges
--   • A warehouse available (e.g. COMPUTE_WH)
--   • manifest.yml, setup_script.sql, and streamlit/setup_wizard.py already
--     uploaded to @township_canada_pkg.stage_content.app_stage
--     (use PUT or snowflake-cli to upload them before running this script)
-- =============================================================================

-- 1. Create the application package
CREATE APPLICATION PACKAGE IF NOT EXISTS township_canada_pkg
  COMMENT = 'Township Canada — Legal Land Description to GPS Conversion';

-- 2. Create the schema and stage for app artifacts
USE APPLICATION PACKAGE township_canada_pkg;
CREATE SCHEMA IF NOT EXISTS stage_content;
CREATE OR REPLACE STAGE township_canada_pkg.stage_content.app_stage
  DIRECTORY = (ENABLE = TRUE);

-- ─── Upload files to the stage ───────────────────────────────────────────────
-- Run these from SnowSQL / snowflake-cli BEFORE continuing:
--
--   PUT file://manifest.yml          @township_canada_pkg.stage_content.app_stage/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
--   PUT file://setup_script.sql      @township_canada_pkg.stage_content.app_stage/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
--   PUT file://streamlit/setup_wizard.py @township_canada_pkg.stage_content.app_stage/streamlit/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
-- ─────────────────────────────────────────────────────────────────────────────

-- 3. Register the version (release channels are enabled, so use REGISTER)
ALTER APPLICATION PACKAGE township_canada_pkg
  REGISTER VERSION v1_0
  USING '@township_canada_pkg.stage_content.app_stage';

-- 4. Add the version to the DEFAULT release channel
ALTER APPLICATION PACKAGE township_canada_pkg
  MODIFY RELEASE CHANNEL DEFAULT
  ADD VERSION v1_0;

-- 5. Set the release directive on the DEFAULT channel
ALTER APPLICATION PACKAGE township_canada_pkg
  MODIFY RELEASE CHANNEL DEFAULT
  SET DEFAULT RELEASE DIRECTIVE
  VERSION = v1_0
  PATCH = 0;

-- 6. (Optional) Add to ALPHA channel for testing in your own account
-- ALTER APPLICATION PACKAGE township_canada_pkg
--   MODIFY RELEASE CHANNEL ALPHA
--   ADD ACCOUNTS = (<org>.<account>);
-- ALTER APPLICATION PACKAGE township_canada_pkg
--   MODIFY RELEASE CHANNEL ALPHA
--   ADD VERSION v1_0;
-- ALTER APPLICATION PACKAGE township_canada_pkg
--   MODIFY RELEASE CHANNEL ALPHA
--   SET DEFAULT RELEASE DIRECTIVE
--   VERSION = v1_0
--   PATCH = 0;

-- 7. Install the application (test)
CREATE APPLICATION IF NOT EXISTS township_canada_app
  FROM APPLICATION PACKAGE township_canada_pkg;

-- 8. Verify immediate functionality (all work without external API setup)
SELECT township_canada_app.core.version();
SELECT township_canada_app.core.validate_lld('NW-36-42-3-W5');
SELECT township_canada_app.core.parse_lld('NW-36-42-3-W5');
SELECT township_canada_app.core.standardize_lld('NE 7 102 19 W4');
SELECT township_canada_app.demo.lookup('NW-36-42-3-W5');
SELECT * FROM township_canada_app.demo.sample_conversions LIMIT 5;

-- =============================================================================
-- Publish to Marketplace
-- =============================================================================

-- 9. Set distribution to EXTERNAL (triggers automated security scan)
ALTER APPLICATION PACKAGE township_canada_pkg
  SET DISTRIBUTION = 'EXTERNAL';

-- 10. Check security scan status (review_status → APPROVED before proceeding)
SHOW VERSIONS IN APPLICATION PACKAGE township_canada_pkg;

-- 11. Add a README to the stage (required for Marketplace listings)
--   PUT file://readme.md @township_canada_pkg.stage_content.app_stage/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

-- After scan passes, go to Marketplace → Provider Studio → Create Listing
-- to create the listing, submit for approval, and publish.

-- =============================================================================
-- Teardown (uncomment to clean up)
-- =============================================================================
-- DROP APPLICATION IF EXISTS township_canada_app;
-- ALTER APPLICATION PACKAGE township_canada_pkg DEREGISTER VERSION v1_0;
-- DROP APPLICATION PACKAGE IF EXISTS township_canada_pkg;
