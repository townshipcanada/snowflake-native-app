"""
Township Canada — Snowflake Native App Setup Wizard

Interactive setup wizard for configuring the TOWNSHIP_CANADA_CONVERT external function
that converts Canadian legal land descriptions (DLS/NTS) to GPS coordinates.
"""

import streamlit as st
from snowflake.snowpark.context import get_active_session

session = get_active_session()

st.title("Township Canada")
st.caption("Legal Land Description to GPS Conversion")

tab_welcome, tab_try, tab_aws, tab_snowflake, tab_test, tab_reference = st.tabs([
    "Welcome",
    "Try Now",
    "AWS Setup",
    "Snowflake Setup",
    "Test",
    "Reference",
])

# =============================================================================
# Tab 1: Welcome
# =============================================================================
with tab_welcome:
    st.header("Welcome to Township Canada")
    st.write(
        "This app converts Canadian legal land descriptions (DLS and NTS formats) "
        "to GPS coordinates. It includes built-in tools you can use right away, "
        "plus an optional external API integration for live batch conversions."
    )

    st.subheader("Use Right Away — No Setup Required")
    st.markdown(
        """
        - **Validate** legal land descriptions against recognized DLS formats
        - **Parse** land descriptions into structured components (quarter, section, township, range, meridian)
        - **Standardize** any supported input format to standard dash-separated format
        - **Look up** GPS coordinates from 30 pre-computed sample conversions
        - **Browse** reference data for supported formats and sample queries
        """
    )

    st.subheader("Optional: Live API Conversion")
    st.markdown(
        """
        For live batch conversions of any legal land description, you can optionally
        configure the **TOWNSHIP_CANADA_CONVERT** external function. This connects
        to the Township Canada API through AWS for real-time GPS coordinate lookups.
        See the **AWS Setup** and **Snowflake Setup** tabs for configuration steps.
        """
    )

    st.subheader("Architecture")
    st.graphviz_chart("""
        digraph {
            rankdir=LR
            node [shape=box, style="rounded,filled", fontname="Helvetica", fontsize=11]
            edge [fontname="Helvetica", fontsize=9]

            subgraph cluster_snowflake {
                label="Snowflake (works immediately)"
                style="dashed"
                color="#29B5E8"
                fontcolor="#29B5E8"
                fontname="Helvetica"
                VL [label="VALIDATE_LLD\\nPARSE_LLD\\nSTANDARDIZE_LLD" fillcolor="#E8F4FD"]
                DM [label="DEMO.LOOKUP\\nSample Dataset" fillcolor="#E8F4FD"]
            }

            subgraph cluster_optional {
                label="Optional — Live API"
                style="dashed"
                color="#FF9900"
                fontcolor="#FF9900"
                fontname="Helvetica"
                EF [label="TOWNSHIP_CANADA_CONVERT\\nExternal Function" fillcolor="#FFF3E0"]
                AG [label="AWS API Gateway\\n+ Lambda Proxy" fillcolor="#FFF3E0"]
            }

            subgraph cluster_tc {
                label="Township Canada"
                style="dashed"
                color="#1a3d2e"
                fontcolor="#1a3d2e"
                fontname="Helvetica"
                API [label="Batch API\\n/batch/legal-location" fillcolor="#E8F5E9"]
            }

            EF -> AG [label="SQL rows"]
            AG -> API [label="POST"]
            API -> AG [label="GeoJSON" style=dashed]
            AG -> EF [label="coordinates" style=dashed]
        }
    """)

    version_result = session.sql("SELECT CORE.VERSION()").collect()
    st.caption(f"App version: {version_result[0][0]}")


# =============================================================================
# Tab 2: Try Now — Immediate utility, no setup required
# =============================================================================
with tab_try:
    st.header("Try Now")
    st.write("These tools work immediately — no API key or external setup required.")

    st.subheader("Validate a Legal Land Description")
    validate_input = st.text_input(
        "Enter a legal land description",
        value="NW-36-42-3-W5",
        key="try_validate_lld",
    )

    if st.button("Validate & Parse", key="btn_try_validate", type="primary"):
        col1, col2 = st.columns(2)
        with col1:
            with st.spinner("Validating..."):
                result = session.sql(
                    "SELECT CORE.VALIDATE_LLD(?)",
                    params=[validate_input]
                ).collect()
            is_valid = result[0][0]
            if is_valid:
                st.success(f"Valid DLS format")
            else:
                st.error(f"Not a recognized DLS format")

        with col2:
            with st.spinner("Parsing..."):
                result = session.sql(
                    "SELECT CORE.PARSE_LLD(?)",
                    params=[validate_input]
                ).collect()
            parsed = result[0][0]
            if parsed:
                st.json(parsed)
            else:
                st.info("Cannot parse — not a valid DLS format.")

    st.divider()

    st.subheader("Standardize Format")
    st.write("Convert any supported format to standard dash-separated notation.")

    std_input = st.text_input(
        "Enter a legal land description in any format",
        value="NE 7 102 19 W4",
        key="try_standardize_lld",
    )

    if st.button("Standardize", key="btn_try_standardize"):
        with st.spinner("Standardizing..."):
            result = session.sql(
                "SELECT CORE.STANDARDIZE_LLD(?)",
                params=[std_input]
            ).collect()
        standardized = result[0][0]
        if standardized:
            st.success(f"Standardized: **{standardized}**")
        else:
            st.error("Input does not match a recognized DLS format.")

    st.divider()

    st.subheader("Demo GPS Lookup")
    st.write(
        "Look up GPS coordinates from the built-in sample dataset of 30 "
        "pre-computed conversions."
    )

    demo_input = st.text_input(
        "Enter a legal land description",
        value="NW-36-42-3-W5",
        key="try_demo_lld",
    )

    if st.button("Look Up Coordinates", key="btn_try_demo", type="primary"):
        with st.spinner("Looking up..."):
            result = session.sql(
                "SELECT DEMO.LOOKUP(?)",
                params=[demo_input]
            ).collect()
        lookup = result[0][0]
        if lookup:
            st.success("Found in sample dataset!")
            st.json(lookup)
        else:
            st.warning(
                "This description is not in the sample dataset. "
                "Configure the external API (AWS Setup tab) for live conversions "
                "of any legal land description."
            )

    st.divider()

    st.subheader("Browse Sample Dataset")
    if st.button("Load Sample Data", key="btn_try_browse"):
        with st.spinner("Loading..."):
            df = session.sql("SELECT * FROM DEMO.SAMPLE_CONVERSIONS ORDER BY province, lld").collect()
        st.dataframe(df, use_container_width=True)


# =============================================================================
# Tab 3: AWS Setup
# =============================================================================
with tab_aws:
    st.header("AWS Setup")
    st.info(
        "This step is **optional**. The app provides validation, parsing, "
        "standardization, and demo lookups without any AWS setup. Configure "
        "AWS only if you need live batch conversions of any legal land description."
    )
    st.write(
        "To enable live conversions, you need an AWS Lambda function and "
        "API Gateway that proxy requests to the Township Canada Batch API."
    )

    # Lambda
    st.subheader("Step 1: Lambda Function")
    st.markdown(
        """
        Create a new Lambda function with:
        - **Runtime:** Python 3.12
        - **Handler:** `lambda_function.lambda_handler`
        - **Timeout:** 30 seconds
        - **Environment variable:** `TOWNSHIP_API_KEY` = your API key.
          Get a [trial key](https://townshipcanada.com/api/try?ref=snowflake) or a
          [paid key](https://developer.townshipcanada.com)
        """
    )

    if st.button("Show Lambda Code", key="btn_lambda"):
        with st.spinner("Loading Lambda code..."):
            result = session.sql("CALL CONFIG.GET_LAMBDA_CODE()").collect()
        st.code(result[0][0], language="python")

    # API Gateway
    st.subheader("Step 2: API Gateway")
    st.markdown(
        """
        1. Create a **REST API** in API Gateway
        2. Add a **POST** method at the root resource (`/`)
        3. Set integration type to **Lambda Function** and select your function
        4. Deploy to a stage (e.g., `prod`)
        5. Note the **Invoke URL** — you will need it in the Snowflake Setup tab
        """
    )
    st.warning(
        "Make sure the API Gateway has IAM authorization enabled, not open access."
    )

    # IAM
    st.subheader("Step 3: IAM Role and Policy")
    st.markdown(
        """
        Create an IAM role that Snowflake will assume to invoke your API Gateway.
        Attach an execution policy granting `execute-api:Invoke` permission.
        """
    )

    with st.expander("Generate IAM Execution Policy"):
        col1, col2 = st.columns(2)
        with col1:
            aws_account_id = st.text_input(
                "AWS Account ID", placeholder="123456789012", key="iam_account"
            )
        with col2:
            api_id = st.text_input(
                "API Gateway ID", placeholder="abc123def4", key="iam_api_id"
            )
        col3, col4 = st.columns(2)
        with col3:
            iam_region = st.text_input(
                "AWS Region", value="us-west-2", key="iam_region"
            )
        with col4:
            iam_stage = st.text_input(
                "API Stage", value="prod", key="iam_stage"
            )

        if st.button("Generate Policy", key="btn_iam_policy"):
            if aws_account_id and api_id:
                with st.spinner("Generating IAM policy..."):
                    result = session.sql(
                        "CALL CONFIG.GET_IAM_POLICY(?, ?, ?, ?)",
                        params=[aws_account_id, api_id, iam_region, iam_stage]
                    ).collect()
                st.code(result[0][0], language="json")
            else:
                st.error("Please provide both AWS Account ID and API Gateway ID.")


# =============================================================================
# Tab 4: Snowflake Setup
# =============================================================================
with tab_snowflake:
    st.header("Snowflake Setup")
    st.info(
        "This step is **optional**. Only needed if you want live batch conversions "
        "via the TOWNSHIP_CANADA_CONVERT external function."
    )
    st.write(
        "Enter your AWS details below to generate the SQL script that an "
        "**ACCOUNTADMIN** must run to create the API Integration and External Function."
    )

    st.warning(
        "The generated SQL must be run by an ACCOUNTADMIN because Native Apps "
        "cannot create API Integrations or External Functions directly."
    )

    col1, col2 = st.columns(2)
    with col1:
        api_gateway_url = st.text_input(
            "API Gateway Invoke URL",
            placeholder="https://abc123.execute-api.us-west-2.amazonaws.com/prod",
            key="sf_api_url",
        )
    with col2:
        iam_role_arn = st.text_input(
            "IAM Role ARN",
            placeholder="arn:aws:iam::123456789012:role/township-snowflake-role",
            key="sf_iam_role",
        )

    aws_region = st.text_input(
        "AWS Region", value="us-west-2", key="sf_region"
    )

    if st.button("Generate Setup SQL", type="primary", key="btn_generate_sql"):
        if api_gateway_url and iam_role_arn:
            with st.spinner("Generating setup SQL..."):
                result = session.sql(
                    "CALL CONFIG.CONFIGURE(?, ?, ?)",
                    params=[api_gateway_url, iam_role_arn, aws_region]
                ).collect()
            st.success("SQL generated. Copy the script below and run it as ACCOUNTADMIN.")
            st.code(result[0][0], language="sql")
        else:
            st.error("Please provide both the API Gateway URL and IAM Role ARN.")

    st.divider()

    st.subheader("After Running the Setup SQL")
    st.markdown(
        """
        After running `DESCRIBE INTEGRATION township_canada_integration`, you need to
        update the IAM trust policy with the Snowflake values. Use the tool below
        to generate the trust policy JSON.
        """
    )

    with st.expander("Generate Trust Policy"):
        col1, col2 = st.columns(2)
        with col1:
            sf_iam_user_arn = st.text_input(
                "API_AWS_IAM_USER_ARN (from DESCRIBE INTEGRATION)",
                placeholder="arn:aws:iam::...:user/...",
                key="sf_iam_user",
            )
        with col2:
            sf_external_id = st.text_input(
                "API_AWS_EXTERNAL_ID (from DESCRIBE INTEGRATION)",
                placeholder="ABC123_SFCRole=...",
                key="sf_ext_id",
            )

        if st.button("Generate Trust Policy", key="btn_trust_policy"):
            if sf_iam_user_arn and sf_external_id:
                with st.spinner("Generating trust policy..."):
                    result = session.sql(
                        "CALL CONFIG.GENERATE_TRUST_POLICY(?, ?)",
                        params=[sf_iam_user_arn, sf_external_id]
                    ).collect()
                st.code(result[0][0], language="json")
                st.info(
                    "Copy this JSON and paste it as the Trust Policy for your "
                    "IAM role in the AWS Console."
                )
            else:
                st.error("Please provide both values from DESCRIBE INTEGRATION.")


# =============================================================================
# Tab 5: Test
# =============================================================================
with tab_test:
    st.header("Test Your Setup")

    st.subheader("Validate Format")
    st.write("Check if a legal land description matches a recognized DLS format.")

    validate_input = st.text_input(
        "Legal Land Description",
        value="NW-36-42-3-W5",
        key="validate_lld",
    )

    if st.button("Validate", key="btn_validate"):
        with st.spinner("Validating format..."):
            result = session.sql(
                "SELECT CORE.VALIDATE_LLD(?)",
                params=[validate_input]
            ).collect()
        is_valid = result[0][0]
        if is_valid:
            st.success(f"'{validate_input}' is a valid DLS format.")
        else:
            st.error(
                f"'{validate_input}' does not match a recognized DLS format. "
                "Check the Reference tab for supported formats."
            )

    st.divider()

    st.subheader("Test External Function")
    st.write(
        "After completing the optional AWS and Snowflake setup, test the "
        "TOWNSHIP_CANADA_CONVERT external function. "
        "This calls the Township Canada API through your AWS proxy."
    )

    test_input = st.text_input(
        "Legal Land Description",
        value="NW-36-42-3-W5",
        key="test_lld",
    )

    if st.button("Convert", type="primary", key="btn_convert"):
        try:
            with st.spinner("Converting legal land description..."):
                result = session.sql(
                    "SELECT TOWNSHIP_CANADA_CONVERT(?) AS result",
                    params=[test_input]
                ).collect()
            st.success("Conversion successful!")
            st.json(result[0][0])
        except Exception as e:
            st.error(
                "The external function is not available. "
                "Please complete the AWS and Snowflake setup steps first, "
                "or use the Demo Lookup on the Try Now tab."
            )
            with st.expander("Error details"):
                st.code(str(e))

    st.divider()

    st.subheader("Health Check")
    if st.button("Run Health Check", key="btn_health"):
        try:
            with st.spinner("Running health check..."):
                result = session.sql("CALL CORE.HEALTH_CHECK()").collect()
            status = result[0][0]
            if status.startswith("OK"):
                st.success(status)
            else:
                st.warning(status)
        except Exception as e:
            st.error(f"Health check failed: {str(e)}")


# =============================================================================
# Tab 6: Reference
# =============================================================================
with tab_reference:
    st.header("Reference")

    st.subheader("Supported Input Formats")
    formats_df = session.sql("SELECT * FROM REFERENCE.SUPPORTED_FORMATS").collect()
    st.dataframe(formats_df, use_container_width=True)

    st.divider()

    st.subheader("Sample Queries — Works Immediately")
    queries = session.sql("SELECT * FROM REFERENCE.SAMPLE_QUERIES").collect()
    for row in queries:
        with st.expander(f"{row['NAME']} — {row['DESCRIPTION']}"):
            st.code(row["SQL_QUERY"], language="sql")

    st.divider()

    st.subheader("API Queries — Requires External Function Setup")
    st.caption("These queries require the TOWNSHIP_CANADA_CONVERT external function to be configured.")
    api_queries = session.sql("SELECT * FROM REFERENCE.API_SAMPLE_QUERIES").collect()
    for row in api_queries:
        with st.expander(f"{row['NAME']} — {row['DESCRIPTION']}"):
            st.code(row["SQL_QUERY"], language="sql")

    st.divider()

    st.subheader("Pricing")
    pricing_df = session.sql("SELECT * FROM REFERENCE.PRICING").collect()
    st.dataframe(pricing_df, use_container_width=True)

    st.divider()

    st.subheader("Setup Guide")
    st.caption("Configuration steps for the optional external API integration.")
    guide = session.sql(
        "SELECT * FROM REFERENCE.SETUP_GUIDE ORDER BY STEP_NUMBER"
    ).collect()
    for row in guide:
        with st.expander(f"Step {row['STEP_NUMBER']}: {row['TITLE']}"):
            st.write(row["DESCRIPTION"])
            if row["SQL_COMMAND"]:
                st.code(row["SQL_COMMAND"], language="sql")
