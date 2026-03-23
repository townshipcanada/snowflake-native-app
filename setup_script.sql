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
         'TRIAL_API_URL = "https://townshipcanada.com/api/integrations/trial/batch/legal-location"\n' ||
         'PAID_API_URL = "https://developer.townshipcanada.com/batch/legal-location"\n' ||
         'TOWNSHIP_API_URL = TRIAL_API_URL if TOWNSHIP_API_KEY.startswith("tc_trial_") else PAID_API_URL\n\n' ||
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
   'Create an AWS Lambda function that proxies requests from Snowflake to the Township Canada Batch API. Use Python 3.12 runtime. Set the TOWNSHIP_API_KEY environment variable with your API key (trial or paid). Get a trial key at townshipcanada.com/api/try?ref=snowflake or a paid key at developer.townshipcanada.com.',
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

-- Sample queries
CREATE OR REPLACE VIEW REFERENCE.SAMPLE_QUERIES
  COMMENT = 'Ready-to-run SQL examples demonstrating common use cases for the Township Canada External Function.'
AS
SELECT column1 AS name,
       column2 AS description,
       column3 AS sql_query
FROM (VALUES
  ('Single Conversion',
   'Convert a single legal land description to GPS coordinates.',
   'SELECT TOWNSHIP_CANADA_CONVERT(''NW-36-42-3-W5'') AS result;'),

  ('Batch Conversion',
   'Convert multiple legal land descriptions from a table column.',
   'SELECT lld_column, TOWNSHIP_CANADA_CONVERT(lld_column) AS coordinates FROM your_table;'),

  ('Validate Before Convert',
   'Validate legal land descriptions before calling the API to avoid errors.',
   'SELECT lld_column, CORE.VALIDATE_LLD(lld_column) AS is_valid FROM your_table;'),

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
