# Township Canada — DLS/NTS to GPS Conversion

Convert Canadian legal land descriptions to GPS coordinates directly in Snowflake SQL.

## Overview

Township Canada provides the **TOWNSHIP_CANADA_CONVERT** external function that transforms Dominion Land Survey (DLS) and National Topographic System (NTS) references into latitude/longitude coordinates — without leaving Snowflake.

Every Canadian energy, agriculture, and land company working in Western Canada references well sites, field locations, and parcels using legal land descriptions. This app lets you geocode those references at scale inside your existing Snowflake pipelines.

## What You Get

- **SQL function**: `SELECT TOWNSHIP_CANADA_CONVERT('NW-36-42-3-W5')` returns GPS coordinates
- **Batch processing**: Convert up to 100 rows per API call automatically
- **Format validation**: Built-in `VALIDATE_LLD()` function to check inputs before conversion
- **Setup wizard**: Interactive Streamlit UI that generates all required SQL and AWS configuration
- **CARTO-ready**: Geospatial enrichment examples for CARTO Analytics Toolbox, H3 binning, and spatial joins
- **Reference data**: Sample queries, supported formats, and pricing tiers included in the app

## Supported Formats

| Format | Example | Coverage |
|--------|---------|----------|
| DLS (dash) | `NW-36-42-3-W5` | AB, SK, MB |
| DLS (space) | `NE 7 102 19 W4` | AB, SK, MB |
| DLS (period) | `SE.1.23.4.W5` | AB, SK, MB |
| DLS (compact) | `SW1423W4` | AB, SK, MB |
| LSD | `01-36-42-03-W5` | AB, SK, MB |
| NTS | `083E/01` | BC |

## Example Queries

```sql
-- Single conversion
SELECT TOWNSHIP_CANADA_CONVERT('NW-36-42-3-W5') AS result;

-- Batch conversion from a table
SELECT
  lld_column,
  TOWNSHIP_CANADA_CONVERT(lld_column):latitude::FLOAT AS latitude,
  TOWNSHIP_CANADA_CONVERT(lld_column):longitude::FLOAT AS longitude
FROM your_table;

-- Validate before converting
SELECT lld_column
FROM your_table
WHERE CORE.VALIDATE_LLD(lld_column);

-- Create geospatial points for mapping
SELECT
  lld_column,
  ST_MAKEPOINT(
    TOWNSHIP_CANADA_CONVERT(lld_column):longitude::FLOAT,
    TOWNSHIP_CANADA_CONVERT(lld_column):latitude::FLOAT
  ) AS geom
FROM your_table;
```

## Architecture

The app guides you through a one-time setup:

1. **AWS Lambda** — A lightweight proxy function that forwards requests to the Township Canada Batch API
2. **API Gateway** — REST endpoint with IAM authorization that Snowflake calls
3. **API Integration** — Snowflake object that securely connects to your API Gateway
4. **External Function** — The `TOWNSHIP_CANADA_CONVERT` SQL function available to all users

The interactive setup wizard generates all required SQL and configuration — no manual coding needed.

## Prerequisites

- Snowflake account with ACCOUNTADMIN access
- AWS account (for API Gateway + Lambda proxy)
- Township Canada API key — [get a trial key](https://townshipcanada.com/api/try?ref=snowflake) or a [paid key](https://developer.townshipcanada.com)

## Use Cases

- **Oil & gas**: Geocode well sites, lease locations, and facility references for spatial analytics
- **Agriculture**: Convert legal land descriptions on crop insurance, soil, and lease records
- **Real estate**: Map rural property references to coordinates for valuation and planning
- **Government**: Enrich regulatory filings and permit data with precise locations
- **CARTO users**: Feed enriched coordinates into CARTO Builder for visualization, H3 binning, and spatial joins

## Pricing

| Tier | Monthly Rows | Price |
|------|-------------|-------|
| Build | 1,000 | $40/month |
| Scale | 10,000 | $200/month |
| Enterprise | 100,000 | $1,000/month |
| Custom | Unlimited | Contact sales |

## Support

- Documentation: [townshipcanada.com/guides/snowflake-external-function](https://townshipcanada.com/guides/snowflake-external-function)
- Email: support@townshipcanada.com
- Sales: sales@townshipcanada.com

Built by [Township Canada](https://townshipcanada.com) — trusted by Western Canadian professionals since 2017.
