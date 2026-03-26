-- =============================================================================
-- Township Canada — Snowflake Native App Setup Script
-- Converts Canadian legal land descriptions (DLS/NTS) to GPS coordinates
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Schema: CORE — Main application functionality
-- -----------------------------------------------------------------------------
CREATE APPLICATION ROLE IF NOT EXISTS APP_PUBLIC;

CREATE SCHEMA IF NOT EXISTS CORE;
GRANT USAGE ON SCHEMA CORE TO APPLICATION ROLE APP_PUBLIC;

-- Version function
CREATE OR REPLACE FUNCTION CORE.VERSION()
  RETURNS VARCHAR
  LANGUAGE SQL
  COMMENT = 'Returns the current version of the Township Canada Native App.'
AS
$$
  '1.0.0'
$$;

GRANT USAGE ON FUNCTION CORE.VERSION() TO APPLICATION ROLE APP_PUBLIC;

-- Validate legal land description format
-- NOTE: Currently validates DLS (Dominion Land Survey) format only.
-- NTS (National Topographic System) format validation is not yet implemented.
-- NTS descriptions (e.g., '083E/01') are accepted by the conversion API but
-- will not pass this validation check. Use this function to pre-filter DLS inputs.
CREATE OR REPLACE FUNCTION CORE.VALIDATE_LLD(lld VARCHAR)
  RETURNS BOOLEAN
  LANGUAGE SQL
  COMMENT = 'Validates whether a string matches a recognized DLS legal land description format. Does NOT validate NTS format — NTS descriptions are accepted by the API but will return FALSE from this function. Supports separators: dash, space, period, or no separator between DLS components.'
AS
$$
  RLIKE(lld, '^((NW|NE|SW|SE|N|S|E|W)|[0-9]{1,2})[ .\\-]?[0-9]{1,2}[ .\\-]?[0-9]{1,3}[ .\\-]?[0-9]{1,2}[ .\\-]?W[ .\\-]?[4-6]$', 'i')
$$;

GRANT USAGE ON FUNCTION CORE.VALIDATE_LLD(VARCHAR) TO APPLICATION ROLE APP_PUBLIC;

-- Standardize legal land description to dash-separated format
CREATE OR REPLACE FUNCTION CORE.STANDARDIZE_LLD(lld VARCHAR)
  RETURNS VARCHAR
  LANGUAGE SQL
  COMMENT = 'Normalizes a DLS legal land description to standard dash-separated format (e.g., NW-36-42-3-W5). Accepts space, period, dash, or no-separator inputs. Returns NULL if the input does not match a recognized DLS format.'
AS
$$
  CASE
    WHEN CORE.VALIDATE_LLD(lld) THEN
      UPPER(
        REGEXP_REPLACE(
          REGEXP_REPLACE(TRIM(lld), '[ .]+', '-'),
          '([A-Za-z])([0-9])', '\\1-\\2'
        )
      )
    ELSE NULL
  END
$$;

GRANT USAGE ON FUNCTION CORE.STANDARDIZE_LLD(VARCHAR) TO APPLICATION ROLE APP_PUBLIC;

-- Parse legal land description into structured components
CREATE OR REPLACE FUNCTION CORE.PARSE_LLD(lld VARCHAR)
  RETURNS OBJECT
  LANGUAGE SQL
  COMMENT = 'Parses a DLS legal land description into its structured components: quarter (or LSD), section, township, range, and meridian. Returns an OBJECT with named fields. Returns NULL if input is not a valid DLS format.'
AS
$$
  CASE
    WHEN CORE.VALIDATE_LLD(lld) THEN
      OBJECT_CONSTRUCT(
        'quarter', REGEXP_SUBSTR(CORE.STANDARDIZE_LLD(lld), '^([A-Z]+|[0-9]{1,2})', 1, 1, 'i', 1),
        'section', REGEXP_SUBSTR(CORE.STANDARDIZE_LLD(lld), '^[^-]+-([0-9]+)', 1, 1, 'i', 1)::INT,
        'township', REGEXP_SUBSTR(CORE.STANDARDIZE_LLD(lld), '^[^-]+-[0-9]+-([0-9]+)', 1, 1, 'i', 1)::INT,
        'range', REGEXP_SUBSTR(CORE.STANDARDIZE_LLD(lld), '^[^-]+-[0-9]+-[0-9]+-([0-9]+)', 1, 1, 'i', 1)::INT,
        'meridian', REGEXP_SUBSTR(CORE.STANDARDIZE_LLD(lld), '(W[4-6])$', 1, 1, 'i', 1),
        'standardized', CORE.STANDARDIZE_LLD(lld)
      )
    ELSE NULL
  END
$$;

GRANT USAGE ON FUNCTION CORE.PARSE_LLD(VARCHAR) TO APPLICATION ROLE APP_PUBLIC;

-- Health check procedure
CREATE OR REPLACE PROCEDURE CORE.HEALTH_CHECK()
  RETURNS VARCHAR
  LANGUAGE SQL
  COMMENT = 'Verifies that the TOWNSHIP_CANADA_CONVERT external function exists and is callable by running a test conversion.'
AS
$$
DECLARE
  result VARCHAR;
BEGIN
  BEGIN
    SELECT TOWNSHIP_CANADA_CONVERT('NW-36-42-3-W5') INTO result;
    RETURN 'OK: External function is working. Test result: ' || result;
  EXCEPTION
    WHEN OTHER THEN
      RETURN 'ERROR: External function TOWNSHIP_CANADA_CONVERT is not available. ' ||
             'Please complete the setup steps in the Setup Wizard or run the SQL from REFERENCE.SETUP_GUIDE. ' ||
             'Details: ' || SQLERRM;
  END;
END;
$$;

GRANT USAGE ON PROCEDURE CORE.HEALTH_CHECK() TO APPLICATION ROLE APP_PUBLIC;

-- -----------------------------------------------------------------------------
-- Schema: CONFIG — Configuration procedures
-- -----------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS CONFIG;
GRANT USAGE ON SCHEMA CONFIG TO APPLICATION ROLE APP_PUBLIC;

-- Reference registration callback for API Integration
CREATE OR REPLACE PROCEDURE CONFIG.REGISTER_API_INTEGRATION(ref_name VARCHAR)
  RETURNS VARCHAR
  LANGUAGE SQL
  COMMENT = 'Callback procedure for registering the API Integration reference. Called automatically by Snowflake when the consumer configures the reference.'
AS
$$
BEGIN
  -- Store the reference name for later use
  CREATE TABLE IF NOT EXISTS CONFIG.APP_STATE (
    key VARCHAR,
    value VARCHAR,
    updated_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
  );
  MERGE INTO CONFIG.APP_STATE AS target
    USING (SELECT 'api_integration_ref' AS key, ref_name AS value) AS source
    ON target.key = source.key
    WHEN MATCHED THEN UPDATE SET value = source.value, updated_at = CURRENT_TIMESTAMP()
    WHEN NOT MATCHED THEN INSERT (key, value) VALUES (source.key, source.value);
  RETURN 'API Integration reference registered successfully: ' || ref_name;
END;
$$;

GRANT USAGE ON PROCEDURE CONFIG.REGISTER_API_INTEGRATION(VARCHAR) TO APPLICATION ROLE APP_PUBLIC;

-- Generate complete setup SQL for the admin
CREATE OR REPLACE PROCEDURE CONFIG.CONFIGURE(
  api_gateway_url VARCHAR,
  iam_role_arn VARCHAR,
  aws_region VARCHAR DEFAULT 'us-west-2'
)
  RETURNS VARCHAR
  LANGUAGE SQL
  COMMENT = 'Generates the complete SQL script an ACCOUNTADMIN must run to create the API Integration and External Function for Township Canada. Accepts the API Gateway URL, IAM Role ARN, and AWS region.'
AS
$$
DECLARE
  setup_sql VARCHAR;
BEGIN
  setup_sql := '-- =============================================================================\n' ||
               '-- Township Canada — External Function Setup\n' ||
               '-- Run this script as ACCOUNTADMIN\n' ||
               '-- =============================================================================\n\n' ||

               '-- Step 1: Create the API Integration\n' ||
               'CREATE OR REPLACE API INTEGRATION township_canada_integration\n' ||
               '  API_PROVIDER = aws_api_gateway\n' ||
               '  API_AWS_ROLE_ARN = ''' || iam_role_arn || '''\n' ||
               '  API_ALLOWED_PREFIXES = (''' || api_gateway_url || ''')\n' ||
               '  ENABLED = true;\n\n' ||

               '-- Step 2: Get the Snowflake IAM user ARN and External ID\n' ||
               '-- You need these values to configure the IAM trust policy in AWS.\n' ||
               'DESCRIBE INTEGRATION township_canada_integration;\n' ||
               '-- Look for API_AWS_IAM_USER_ARN and API_AWS_EXTERNAL_ID in the output.\n\n' ||

               '-- Step 3: Update the IAM Role trust policy in AWS Console\n' ||
               '-- Replace <API_AWS_IAM_USER_ARN> and <API_AWS_EXTERNAL_ID> with values from Step 2:\n' ||
               '-- {\n' ||
               '--   "Version": "2012-10-17",\n' ||
               '--   "Statement": [\n' ||
               '--     {\n' ||
               '--       "Effect": "Allow",\n' ||
               '--       "Principal": {\n' ||
               '--         "AWS": "<API_AWS_IAM_USER_ARN>"\n' ||
               '--       },\n' ||
               '--       "Action": "sts:AssumeRole",\n' ||
               '--       "Condition": {\n' ||
               '--         "StringEquals": {\n' ||
               '--           "sts:ExternalId": "<API_AWS_EXTERNAL_ID>"\n' ||
               '--         }\n' ||
               '--       }\n' ||
               '--     }\n' ||
               '--   ]\n' ||
               '-- }\n\n' ||

               '-- Step 4: Create the External Function\n' ||
               'CREATE OR REPLACE EXTERNAL FUNCTION TOWNSHIP_CANADA_CONVERT(lld VARCHAR)\n' ||
               '  RETURNS VARIANT\n' ||
               '  API_INTEGRATION = township_canada_integration\n' ||
               '  MAX_BATCH_ROWS = 100\n' ||
               '  HEADERS = (''Content-Type'' = ''application/json'')\n' ||
               '  AS ''' || api_gateway_url || ''';\n\n' ||

               '-- Step 5: Grant access\n' ||
               'GRANT USAGE ON FUNCTION TOWNSHIP_CANADA_CONVERT(VARCHAR) TO PUBLIC;\n\n' ||

               '-- Step 6: Test it!\n' ||
               'SELECT TOWNSHIP_CANADA_CONVERT(''NW-36-42-3-W5'') AS result;\n';

  RETURN setup_sql;
END;
$$;

GRANT USAGE ON PROCEDURE CONFIG.CONFIGURE(VARCHAR, VARCHAR, VARCHAR) TO APPLICATION ROLE APP_PUBLIC;

-- Return the Lambda proxy function code
CREATE OR REPLACE PROCEDURE CONFIG.GET_LAMBDA_CODE()
  RETURNS VARCHAR
  LANGUAGE SQL
  COMMENT = 'Returns the complete Python code for the AWS Lambda function that proxies requests from Snowflake to the Township Canada Batch API.'
AS
$$
BEGIN
  RETURN 'import json\n' ||
         'import os\n' ||
         'import urllib.request\n' ||
         'import urllib.error\n\n' ||
         'TOWNSHIP_API_KEY = os.environ["TOWNSHIP_API_KEY"]\n' ||
         'TOWNSHIP_API_URL = "https://townshipcanada.com/api/batch/legal-location"\n\n' ||
         'def lambda_handler(event, context):\n' ||
         '    rows = event.get("data", [])\n' ||
         '    llds = [row[1] for row in rows]\n\n' ||
         '    req = urllib.request.Request(\n' ||
         '        TOWNSHIP_API_URL,\n' ||
         '        data=json.dumps(llds).encode("utf-8"),\n' ||
         '        headers={\n' ||
         '            "X-API-Key": TOWNSHIP_API_KEY,\n' ||
         '            "Content-Type": "application/json"\n' ||
         '        },\n' ||
         '        method="POST"\n' ||
         '    )\n\n' ||
         '    try:\n' ||
         '        with urllib.request.urlopen(req, timeout=25) as resp:\n' ||
         '            result = json.loads(resp.read().decode("utf-8"))\n' ||
         '    except urllib.error.HTTPError as e:\n' ||
         '        return {\n' ||
         '            "statusCode": e.code,\n' ||
         '            "body": json.dumps({\n' ||
         '                "error": f"Township Canada API returned {e.code}: {e.reason}"\n' ||
         '            })\n' ||
         '        }\n' ||
         '    except urllib.error.URLError as e:\n' ||
         '        return {\n' ||
         '            "statusCode": 502,\n' ||
         '            "body": json.dumps({\n' ||
         '                "error": f"Failed to connect to Township Canada API: {e.reason}"\n' ||
         '            })\n' ||
         '        }\n' ||
         '    except Exception as e:\n' ||
         '        return {\n' ||
         '            "statusCode": 500,\n' ||
         '            "body": json.dumps({\n' ||
         '                "error": f"Unexpected error calling Township Canada API: {str(e)}"\n' ||
         '            })\n' ||
         '        }\n\n' ||
         '    coords_map = {}\n' ||
         '    for fc in result:\n' ||
         '        for feature in fc.get("features", []):\n' ||
         '            props = feature.get("properties", {})\n' ||
         '            geom = feature.get("geometry", {})\n' ||
         '            if props.get("shape") == "centroid" and geom.get("type") == "Point":\n' ||
         '                lld = props.get("legal_location", "")\n' ||
         '                lon, lat = geom["coordinates"]\n' ||
         '                coords_map[lld] = {"latitude": lat, "longitude": lon}\n\n' ||
         '    output_rows = []\n' ||
         '    for row in rows:\n' ||
         '        row_number = row[0]\n' ||
         '        lld = row[1]\n' ||
         '        coord = coords_map.get(lld)\n' ||
         '        if coord:\n' ||
         '            output_rows.append([row_number, json.dumps(coord)])\n' ||
         '        else:\n' ||
         '            output_rows.append([row_number, None])\n\n' ||
         '    return {"data": output_rows}\n';
END;
$$;

GRANT USAGE ON PROCEDURE CONFIG.GET_LAMBDA_CODE() TO APPLICATION ROLE APP_PUBLIC;

-- Generate IAM execution policy for the Lambda role
CREATE OR REPLACE PROCEDURE CONFIG.GET_IAM_POLICY(
  aws_account_id VARCHAR,
  api_id VARCHAR,
  region VARCHAR DEFAULT 'us-west-2',
  stage VARCHAR DEFAULT 'prod'
)
  RETURNS VARCHAR
  LANGUAGE SQL
  COMMENT = 'Generates the IAM execution policy JSON for the API Gateway. The policy grants invoke access to the specified API Gateway resource.'
AS
$$
DECLARE
  policy VARCHAR;
BEGIN
  policy := '{\n' ||
            '  "Version": "2012-10-17",\n' ||
            '  "Statement": [\n' ||
            '    {\n' ||
            '      "Effect": "Allow",\n' ||
            '      "Action": "execute-api:Invoke",\n' ||
            '      "Resource": "arn:aws:execute-api:' || region || ':' || aws_account_id || ':' || api_id || '/' || stage || '/POST/*"\n' ||
            '    }\n' ||
            '  ]\n' ||
            '}';
  RETURN policy;
END;
$$;

GRANT USAGE ON PROCEDURE CONFIG.GET_IAM_POLICY(VARCHAR, VARCHAR, VARCHAR, VARCHAR) TO APPLICATION ROLE APP_PUBLIC;

-- Generate IAM trust policy for Snowflake access
CREATE OR REPLACE PROCEDURE CONFIG.GENERATE_TRUST_POLICY(
  snowflake_iam_user_arn VARCHAR,
  external_id VARCHAR
)
  RETURNS VARCHAR
  LANGUAGE SQL
  COMMENT = 'Generates the IAM trust policy JSON that allows Snowflake to assume the IAM role. Use the values from DESCRIBE INTEGRATION output.'
AS
$$
DECLARE
  policy VARCHAR;
BEGIN
  policy := '{\n' ||
            '  "Version": "2012-10-17",\n' ||
            '  "Statement": [\n' ||
            '    {\n' ||
            '      "Effect": "Allow",\n' ||
            '      "Principal": {\n' ||
            '        "AWS": "' || snowflake_iam_user_arn || '"\n' ||
            '      },\n' ||
            '      "Action": "sts:AssumeRole",\n' ||
            '      "Condition": {\n' ||
            '        "StringEquals": {\n' ||
            '          "sts:ExternalId": "' || external_id || '"\n' ||
            '        }\n' ||
            '      }\n' ||
            '    }\n' ||
            '  ]\n' ||
            '}';
  RETURN policy;
END;
$$;

GRANT USAGE ON PROCEDURE CONFIG.GENERATE_TRUST_POLICY(VARCHAR, VARCHAR) TO APPLICATION ROLE APP_PUBLIC;

-- -----------------------------------------------------------------------------
-- Schema: REFERENCE — Documentation and sample data
-- -----------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS REFERENCE;
GRANT USAGE ON SCHEMA REFERENCE TO APPLICATION ROLE APP_PUBLIC;

-- Setup guide as queryable rows
CREATE OR REPLACE VIEW REFERENCE.SETUP_GUIDE
  COMMENT = 'Step-by-step setup instructions for configuring the Township Canada External Function in Snowflake.'
AS
SELECT column1 AS step_number,
       column2 AS title,
       column3 AS description,
       column4 AS sql_command
FROM (VALUES
  (1, 'Deploy Lambda Function',
   'Create an AWS Lambda function that proxies requests from Snowflake to the Township Canada Batch API. Use Python 3.12 runtime. Set the TOWNSHIP_API_KEY environment variable with your API key from developer.townshipcanada.com.',
   'CALL CONFIG.GET_LAMBDA_CODE();'),

  (2, 'Create API Gateway',
   'Create a REST API in AWS API Gateway. Add a POST method that integrates with your Lambda function. Deploy to a stage (e.g., "prod"). Note the Invoke URL.',
   NULL),

  (3, 'Create IAM Role',
   'Create an IAM role with the API Gateway execution policy. The role will be assumed by Snowflake to invoke the API Gateway endpoint.',
   'CALL CONFIG.GET_IAM_POLICY(''<aws_account_id>'', ''<api_id>'');'),

  (4, 'Generate Setup SQL',
   'Provide your API Gateway URL, IAM Role ARN, and AWS region to generate the Snowflake SQL commands. An ACCOUNTADMIN must run the generated script.',
   'CALL CONFIG.CONFIGURE(''https://<api-id>.execute-api.<region>.amazonaws.com/prod'', ''arn:aws:iam::<account>:role/<role-name>'');'),

  (5, 'Configure Trust Policy',
   'After running the DESCRIBE INTEGRATION command from Step 4, update the IAM role trust policy with the Snowflake IAM user ARN and external ID.',
   'CALL CONFIG.GENERATE_TRUST_POLICY(''<API_AWS_IAM_USER_ARN>'', ''<API_AWS_EXTERNAL_ID>'');'),

  (6, 'Test the Function',
   'Run a test query to verify the external function is working correctly.',
   'SELECT TOWNSHIP_CANADA_CONVERT(''NW-36-42-3-W5'') AS result;'),

  (7, 'Validate Your Data',
   'Use the built-in VALIDATE_LLD function to check your legal land descriptions before sending them to the API.',
   'SELECT CORE.VALIDATE_LLD(''NW-36-42-3-W5'');')
);

GRANT SELECT ON VIEW REFERENCE.SETUP_GUIDE TO APPLICATION ROLE APP_PUBLIC;

-- Sample queries — only includes queries that work immediately after install
CREATE OR REPLACE VIEW REFERENCE.SAMPLE_QUERIES
  COMMENT = 'Ready-to-run SQL examples that work immediately after installing the app. No external API configuration required.'
AS
SELECT column1 AS name,
       column2 AS description,
       column3 AS sql_query
FROM (VALUES
  ('Validate a Land Description',
   'Check if a legal land description matches a recognized DLS format.',
   'SELECT CORE.VALIDATE_LLD(''NW-36-42-3-W5'') AS is_valid;'),

  ('Parse Land Description',
   'Break down a legal land description into its structured components (quarter, section, township, range, meridian).',
   'SELECT CORE.PARSE_LLD(''NW-36-42-3-W5'') AS parsed;'),

  ('Standardize Format',
   'Normalize a legal land description from any supported format to standard dash-separated format.',
   'SELECT CORE.STANDARDIZE_LLD(''NE 7 102 19 W4'') AS standardized;'),

  ('Demo Lookup',
   'Look up GPS coordinates from the built-in sample dataset of 100 pre-computed conversions.',
   'SELECT DEMO.LOOKUP(''NW-36-42-3-W5'') AS coordinates;'),

  ('Browse Sample Data',
   'Explore the full sample dataset of pre-computed legal land description conversions.',
   'SELECT * FROM DEMO.SAMPLE_CONVERSIONS;'),

  ('Validate Your Data',
   'Check which of your legal land descriptions are valid DLS format before conversion.',
   'SELECT lld_column, CORE.VALIDATE_LLD(lld_column) AS is_valid, CORE.STANDARDIZE_LLD(lld_column) AS standardized FROM your_table;'),

  ('Parse and Analyze',
   'Parse your land descriptions and extract individual components for analysis.',
   'SELECT lld_column, CORE.PARSE_LLD(lld_column):township::INT AS township, CORE.PARSE_LLD(lld_column):range::INT AS range_num, CORE.PARSE_LLD(lld_column):meridian::VARCHAR AS meridian FROM your_table WHERE CORE.VALIDATE_LLD(lld_column);')
);

-- API-dependent sample queries — require external function setup
CREATE OR REPLACE VIEW REFERENCE.API_SAMPLE_QUERIES
  COMMENT = 'SQL examples that require the TOWNSHIP_CANADA_CONVERT external function to be configured. See the Setup Wizard or REFERENCE.SETUP_GUIDE for configuration instructions.'
AS
SELECT column1 AS name,
       column2 AS description,
       column3 AS sql_query
FROM (VALUES
  ('Single Conversion',
   'Convert a single legal land description to GPS coordinates via the API.',
   'SELECT TOWNSHIP_CANADA_CONVERT(''NW-36-42-3-W5'') AS result;'),

  ('Batch Conversion',
   'Convert multiple legal land descriptions from a table column.',
   'SELECT lld_column, TOWNSHIP_CANADA_CONVERT(lld_column) AS coordinates FROM your_table;'),

  ('Filter Valid Records',
   'Convert only valid legal land descriptions from a table.',
   'SELECT lld_column, TOWNSHIP_CANADA_CONVERT(lld_column) AS coordinates FROM your_table WHERE CORE.VALIDATE_LLD(lld_column);'),

  ('Extract Latitude/Longitude',
   'Extract latitude and longitude as separate float columns from the conversion result.',
   'SELECT lld_column, TOWNSHIP_CANADA_CONVERT(lld_column):latitude::FLOAT AS latitude, TOWNSHIP_CANADA_CONVERT(lld_column):longitude::FLOAT AS longitude FROM your_table;'),

  ('Convert with Metadata',
   'Join conversion results with your existing data for enrichment.',
   'SELECT t.well_id, t.lld, TOWNSHIP_CANADA_CONVERT(t.lld) AS geo_result FROM wells_table t WHERE CORE.VALIDATE_LLD(t.lld) LIMIT 100;'),

  ('Health Check',
   'Verify the external function is properly configured and working.',
   'CALL CORE.HEALTH_CHECK();')
);

GRANT SELECT ON VIEW REFERENCE.API_SAMPLE_QUERIES TO APPLICATION ROLE APP_PUBLIC;

GRANT SELECT ON VIEW REFERENCE.SAMPLE_QUERIES TO APPLICATION ROLE APP_PUBLIC;

-- Supported input formats
CREATE OR REPLACE VIEW REFERENCE.SUPPORTED_FORMATS
  COMMENT = 'Reference of supported legal land description input formats for the Township Canada conversion API.'
AS
SELECT column1 AS format_name,
       column2 AS example,
       column3 AS description
FROM (VALUES
  ('DLS — Dash Separated',
   'NW-36-42-3-W5',
   'Quarter-Section-Township-Range-WMeridian with dash separators. Most common format.'),

  ('DLS — Space Separated',
   'NE 7 102 19 W4',
   'Quarter Section Township Range WMeridian with space separators.'),

  ('DLS — Period Separated',
   'SE.1.23.4.W5',
   'Quarter.Section.Township.Range.WMeridian with period separators.'),

  ('DLS — No Separator',
   'SW1423W4',
   'Compact format with no separators between numeric components.'),

  ('DLS — Half Section',
   'N-36-42-3-W5',
   'Half-section notation using N, S, E, or W as the quarter indicator.'),

  ('LSD — Legal Subdivision',
   '01-36-42-03-W5',
   'Legal Subdivision format with two-digit LSD prefix instead of quarter section.'),

  ('NTS — National Topographic System',
   '083E/01',
   'NTS map sheet reference for areas covered by the National Topographic System.')
);

GRANT SELECT ON VIEW REFERENCE.SUPPORTED_FORMATS TO APPLICATION ROLE APP_PUBLIC;

-- Pricing information
CREATE OR REPLACE VIEW REFERENCE.PRICING
  COMMENT = 'Township Canada API pricing tiers and conversion limits.'
AS
SELECT column1 AS tier,
       column2 AS monthly_rows,
       column3 AS price,
       column4 AS description
FROM (VALUES
  ('Build', '1,000', '$40/month', 'Up to 1,000 row conversions per month. Ideal for evaluation and small projects.'),
  ('Scale', '10,000', '$200/month', 'Up to 10,000 row conversions per month. Recommended for regular Snowflake workloads.'),
  ('Enterprise', '100,000', '$1,000/month', 'Up to 100,000 row conversions per month with priority support and SLA guarantees.'),
  ('Custom', 'Unlimited', 'Contact sales', 'Unlimited conversions with dedicated support and custom integrations. Contact sales@townshipcanada.com.')
);

GRANT SELECT ON VIEW REFERENCE.PRICING TO APPLICATION ROLE APP_PUBLIC;

-- -----------------------------------------------------------------------------
-- Schema: DEMO — Built-in sample data for immediate utility
-- Provides pre-computed conversions so consumers can explore the app
-- without configuring external API access.
-- -----------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS DEMO;
GRANT USAGE ON SCHEMA DEMO TO APPLICATION ROLE APP_PUBLIC;

-- Sample dataset of pre-computed legal land description conversions
CREATE OR REPLACE VIEW DEMO.SAMPLE_CONVERSIONS
  COMMENT = 'Pre-computed GPS coordinate conversions for common Alberta and Saskatchewan legal land descriptions. Use this data to explore the output format, test your workflows, and evaluate the app before configuring the external API.'
AS
SELECT column1 AS lld,
       column2 AS latitude,
       column3 AS longitude,
       column4 AS province,
       column5 AS description
FROM (VALUES
  -- Calgary region
  ('NE-1-25-1-W5',   51.2047, -114.0719, 'AB', 'Near Calgary, Alberta'),
  ('SE-15-24-1-W5',  51.1749, -114.0522, 'AB', 'Central Calgary area'),
  ('SW-36-23-1-W5',  51.1457, -114.0110, 'AB', 'Southeast Calgary area'),
  ('NW-22-24-1-W5',  51.1900, -114.0800, 'AB', 'Northwest Calgary area'),
  ('NE-6-24-1-W5',   51.1600, -114.1200, 'AB', 'West Calgary area'),
  ('SE-31-24-29-W4', 51.2100, -113.9200, 'AB', 'East Calgary area'),
  ('SW-14-23-4-W5',  51.1000, -114.4900, 'AB', 'Near Cochrane, Alberta'),
  ('NE-36-17-27-W4', 50.7222, -113.5400, 'AB', 'Near Okotoks, Alberta'),
  ('NW-3-24-2-W5',   51.1500, -114.1700, 'AB', 'Near Signal Hill, Calgary'),
  ('SE-11-25-2-W5',  51.2300, -114.1900, 'AB', 'Near Bowness, Calgary'),
  -- Edmonton region
  ('NW-1-51-25-W4',  53.5461, -113.4938, 'AB', 'Near Edmonton, Alberta'),
  ('NE-12-50-25-W4', 53.5016, -113.4390, 'AB', 'East Edmonton area'),
  ('SE-10-48-26-W4', 53.3261, -113.5400, 'AB', 'Near Leduc, Alberta'),
  ('NE-14-47-26-W4', 53.2400, -113.5200, 'AB', 'Near Beaumont, Alberta'),
  ('NE-22-55-20-W4', 53.9200, -112.5600, 'AB', 'Near Westlock, Alberta'),
  ('SW-7-52-24-W4',  53.6100, -113.3100, 'AB', 'Near Sherwood Park, Alberta'),
  ('NW-18-53-24-W4', 53.7000, -113.3500, 'AB', 'Near Fort Saskatchewan, Alberta'),
  ('SE-22-51-25-W4', 53.5700, -113.4600, 'AB', 'Near Mill Woods, Edmonton'),
  ('NE-33-52-25-W4', 53.6800, -113.5100, 'AB', 'Near St. Albert, Alberta'),
  ('SW-5-50-24-W4',  53.4300, -113.2800, 'AB', 'Near Ardrossan, Alberta'),
  -- Central Alberta
  ('NW-36-42-3-W5',  52.3206, -114.3356, 'AB', 'Near Eckville, Alberta'),
  ('SW-8-36-21-W4',  51.7278, -112.8100, 'AB', 'Near Red Deer, Alberta'),
  ('NW-26-39-27-W4', 52.0361, -113.5983, 'AB', 'Near Ponoka, Alberta'),
  ('NW-8-42-1-W5',   52.2800, -114.0600, 'AB', 'Near Sylvan Lake, Alberta'),
  ('NE-5-33-3-W5',   51.4800, -114.3200, 'AB', 'Near Sundre, Alberta'),
  ('SE-1-36-7-W5',   51.7278, -114.8900, 'AB', 'Near Rocky Mountain House, Alberta'),
  ('NW-16-45-3-W5',  53.1100, -114.3600, 'AB', 'Near Drayton Valley, Alberta'),
  ('SW-33-28-20-W4', 51.5400, -112.7000, 'AB', 'Near Drumheller, Alberta'),
  ('SE-3-29-23-W4',  51.5600, -113.2100, 'AB', 'Near Three Hills, Alberta'),
  ('NW-19-38-27-W4', 51.9600, -113.6400, 'AB', 'Near Lacombe, Alberta'),
  ('SE-14-40-1-W5',  52.1200, -114.0700, 'AB', 'Near Innisfail, Alberta'),
  ('NE-27-37-28-W4', 51.9100, -113.7500, 'AB', 'Near Blackfalds, Alberta'),
  ('SW-2-44-2-W5',   52.9600, -114.2000, 'AB', 'Near Nordegg, Alberta'),
  ('NE-16-35-27-W4', 51.6600, -113.6100, 'AB', 'Near Trochu, Alberta'),
  -- Southern Alberta
  ('SE-22-9-4-W4',   49.8144, -110.4667, 'AB', 'Near Medicine Hat, Alberta'),
  ('NE-3-10-20-W4',  49.8364, -112.6800, 'AB', 'Near Lethbridge, Alberta'),
  ('SE-9-16-2-W5',   50.5933, -114.2200, 'AB', 'Near High River, Alberta'),
  ('NE-15-17-19-W4', 50.6200, -112.5200, 'AB', 'Near Vulcan, Alberta'),
  ('SW-20-12-6-W4',  49.9700, -110.7100, 'AB', 'Near Redcliff, Alberta'),
  ('NW-14-8-12-W4',  49.7100, -111.5200, 'AB', 'Near Taber, Alberta'),
  ('SE-28-7-22-W4',  49.6800, -112.8700, 'AB', 'Near Coaldale, Alberta'),
  ('NE-9-11-14-W4',  49.9100, -111.7800, 'AB', 'Near Vauxhall, Alberta'),
  ('SW-17-9-13-W4',  49.7800, -111.6800, 'AB', 'Near Bow Island, Alberta'),
  ('NW-6-13-24-W4',  50.0600, -113.2500, 'AB', 'Near Claresholm, Alberta'),
  ('SE-22-15-1-W5',  50.3800, -114.0600, 'AB', 'Near Nanton, Alberta'),
  ('NE-11-10-22-W4', 49.8500, -112.9800, 'AB', 'Near Picture Butte, Alberta'),
  -- Northern Alberta
  ('SE-30-62-17-W4', 54.6074, -112.3892, 'AB', 'Near Athabasca, Alberta'),
  ('NW-5-72-25-W4',  55.4780, -113.4700, 'AB', 'Near Slave Lake, Alberta'),
  ('NE-7-102-19-W4', 58.2217, -112.5600, 'AB', 'Near Fort McMurray, Alberta'),
  ('NW-20-83-18-W4', 56.4300, -112.1700, 'AB', 'Near Fort McMurray region'),
  ('SW-11-60-6-W4',  54.4200, -110.7600, 'AB', 'Near Bonnyville, Alberta'),
  ('NE-18-66-22-W4', 55.0100, -113.0200, 'AB', 'Near Athabasca, Alberta'),
  ('SE-5-58-10-W4',  54.2500, -111.2700, 'AB', 'Near Elk Point, Alberta'),
  ('NW-30-75-7-W4',  55.7500, -110.8800, 'AB', 'Near Cold Lake, Alberta'),
  ('SW-14-68-10-W5', 55.1800, -115.2800, 'AB', 'Near Grande Prairie, Alberta'),
  ('NE-21-71-6-W6',  55.4100, -118.7300, 'AB', 'Near Dawson Creek region'),
  ('SE-8-82-19-W4',  56.3500, -112.5400, 'AB', 'Near Fort McMurray south'),
  ('NW-33-77-4-W4',  55.9400, -110.4100, 'AB', 'Near Lac La Biche, Alberta'),
  ('NE-6-65-18-W4',  54.8900, -112.3600, 'AB', 'Near Athabasca region'),
  ('SW-22-59-4-W5',  54.3600, -114.4800, 'AB', 'Near Whitecourt, Alberta'),
  -- Saskatchewan
  ('NW-1-18-16-W4',  50.7822, -111.9300, 'SK', 'Near Maple Creek, Saskatchewan'),
  ('NW-22-36-4-W4',  51.7278, -110.3900, 'SK', 'Near Swift Current, Saskatchewan'),
  ('SE-15-17-3-W3',  50.6100, -106.3100, 'SK', 'Near Moose Jaw, Saskatchewan'),
  ('NE-20-36-20-W2', 51.7500, -104.6400, 'SK', 'Near Regina, Saskatchewan'),
  ('SW-8-36-5-W3',   51.7000, -106.5900, 'SK', 'Near Saskatoon region'),
  ('NW-11-48-23-W3', 52.7700, -108.9200, 'SK', 'Near North Battleford, Saskatchewan'),
  ('SE-29-45-15-W2', 52.5000, -104.1300, 'SK', 'Near Prince Albert, Saskatchewan'),
  ('NE-3-25-4-W3',   51.2200, -106.4200, 'SK', 'Near Moose Jaw north'),
  ('SW-16-18-17-W3', 50.6500, -107.5800, 'SK', 'Near Swift Current east'),
  ('NW-27-35-23-W2', 51.6800, -104.9700, 'SK', 'Near Lumsden, Saskatchewan'),
  ('SE-10-42-6-W3',  52.2200, -106.6500, 'SK', 'Near Saskatoon south'),
  ('NE-14-49-16-W3', 52.8500, -107.6100, 'SK', 'Near Shellbrook, Saskatchewan'),
  ('SW-33-20-1-W3',  50.8800, -106.0100, 'SK', 'Near Davidson, Saskatchewan'),
  ('NW-7-36-19-W2',  51.6900, -104.4100, 'SK', 'Near Regina north'),
  ('SE-21-53-3-W3',  53.2600, -106.2800, 'SK', 'Near Nipawin, Saskatchewan'),
  -- Western Alberta foothills/mountains
  ('NW-10-26-5-W5',  51.3100, -114.6100, 'AB', 'Near Bragg Creek, Alberta'),
  ('SE-3-30-10-W5',  51.5200, -115.2800, 'AB', 'Near Banff, Alberta'),
  ('NE-22-51-1-W6',  53.5900, -118.0500, 'AB', 'Near Hinton, Alberta'),
  ('SW-15-48-12-W5', 53.3400, -115.5600, 'AB', 'Near Edson, Alberta'),
  ('NW-36-43-7-W5',  52.9700, -114.8900, 'AB', 'Near Nordegg region'),
  ('SE-18-34-8-W5',  51.6100, -115.0600, 'AB', 'Near Sundre west'),
  ('NE-1-27-6-W5',   51.3600, -114.7300, 'AB', 'Near Turner Valley, Alberta'),
  ('SW-30-40-7-W5',  52.1500, -114.9500, 'AB', 'Near Caroline, Alberta'),
  -- Peace River / Grande Prairie region
  ('NW-15-72-6-W6',  55.4500, -118.7000, 'AB', 'Near Grande Prairie, Alberta'),
  ('SE-8-71-10-W6',  55.3500, -119.3200, 'AB', 'Near Beaverlodge, Alberta'),
  ('NE-25-78-20-W5', 55.9800, -116.6800, 'AB', 'Near Peace River, Alberta'),
  ('SW-12-83-24-W5', 56.3900, -117.2500, 'AB', 'Near Manning, Alberta'),
  ('NW-33-85-14-W6', 56.6200, -119.8300, 'AB', 'Near Fairview, Alberta'),
  -- Oil sands region
  ('SE-15-89-10-W4', 56.9200, -111.2500, 'AB', 'Near Fort McMurray east'),
  ('NE-4-91-12-W4',  57.0800, -111.5000, 'AB', 'Near Fort McMurray northeast'),
  ('SW-21-95-8-W4',  57.4500, -110.9600, 'AB', 'Near Fort Chipewyan region'),
  ('NW-16-88-9-W4',  56.8400, -111.1200, 'AB', 'Near Fort McMurray south area'),
  -- British Columbia Peace block (W6 meridian)
  ('SE-10-79-15-W6', 56.0700, -119.9500, 'AB', 'Near Rycroft, Alberta'),
  ('NE-18-76-13-W6', 55.8100, -119.6400, 'AB', 'Near Sexsmith, Alberta'),
  -- Lloydminster / border region
  ('SW-25-49-1-W4',  52.8200, -110.0100, 'AB', 'Near Lloydminster, Alberta'),
  ('NW-14-50-27-W3', 52.9000, -109.4700, 'SK', 'Near Lloydminster, Saskatchewan'),
  ('SE-6-33-1-W4',   51.4600, -110.0500, 'AB', 'Near Provost, Alberta'),
  ('NE-20-44-4-W4',  52.9400, -110.4000, 'AB', 'Near Wainwright, Alberta')
);

GRANT SELECT ON VIEW DEMO.SAMPLE_CONVERSIONS TO APPLICATION ROLE APP_PUBLIC;

-- Look up a legal land description from the built-in sample dataset
CREATE OR REPLACE FUNCTION DEMO.LOOKUP(lld VARCHAR)
  RETURNS OBJECT
  LANGUAGE SQL
  COMMENT = 'Looks up a legal land description in the built-in sample dataset and returns pre-computed GPS coordinates. Works immediately without any external API configuration. Returns NULL if the description is not in the sample dataset.'
AS
$$
  (SELECT OBJECT_CONSTRUCT(
      'latitude', d.latitude,
      'longitude', d.longitude,
      'province', d.province,
      'description', d.description,
      'source', 'demo_dataset'
    )
   FROM DEMO.SAMPLE_CONVERSIONS d
   WHERE d.lld = CORE.STANDARDIZE_LLD(lld)
   LIMIT 1)
$$;

GRANT USAGE ON FUNCTION DEMO.LOOKUP(VARCHAR) TO APPLICATION ROLE APP_PUBLIC;
