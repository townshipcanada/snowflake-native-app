"""Upload Native App files to Snowflake stage."""
import getpass
import sys
import snowflake.connector
import os

ACCOUNT = os.environ.get("SNOWFLAKE_ACCOUNT", "")
USER = os.environ.get("SNOWFLAKE_USER", "")
ROLE = "ACCOUNTADMIN"

if not ACCOUNT or not USER:
    print("Error: SNOWFLAKE_ACCOUNT and SNOWFLAKE_USER environment variables must be set.")
    print("  export SNOWFLAKE_ACCOUNT='your-account-identifier'")
    print("  export SNOWFLAKE_USER='your-username'")
    sys.exit(1)

APP_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

password = getpass.getpass("Snowflake password: ")

conn = snowflake.connector.connect(
    account=ACCOUNT,
    user=USER,
    password=password,
    role=ROLE,
)

cur = conn.cursor()

try:
    print("Uploading manifest.yml...")
    cur.execute(
        f"PUT 'file://{APP_DIR}/manifest.yml' "
        "@township_canada_pkg.stage_content.app_stage/ "
        "OVERWRITE=TRUE AUTO_COMPRESS=FALSE"
    )
    print(f"  -> {cur.fetchone()}")

    print("Uploading setup_script.sql...")
    cur.execute(
        f"PUT 'file://{APP_DIR}/setup_script.sql' "
        "@township_canada_pkg.stage_content.app_stage/ "
        "OVERWRITE=TRUE AUTO_COMPRESS=FALSE"
    )
    print(f"  -> {cur.fetchone()}")

    print("Uploading streamlit/setup_wizard.py...")
    cur.execute(
        f"PUT 'file://{APP_DIR}/streamlit/setup_wizard.py' "
        "@township_canada_pkg.stage_content.app_stage/streamlit/ "
        "OVERWRITE=TRUE AUTO_COMPRESS=FALSE"
    )
    print(f"  -> {cur.fetchone()}")

    print("\nVerifying uploads...")
    cur.execute("LIST @township_canada_pkg.stage_content.app_stage")
    for row in cur.fetchall():
        print(f"  {row[0]} ({row[1]} bytes)")

    print("\nAll files uploaded successfully!")

except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)
finally:
    cur.close()
    conn.close()
