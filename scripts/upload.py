"""Upload Native App files to Snowflake stage."""
import getpass
import snowflake.connector
import os

ACCOUNT = "ZMYQUJY-VSB14218"
USER = "MEPA1363"
ROLE = "ACCOUNTADMIN"

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
finally:
    cur.close()
    conn.close()
