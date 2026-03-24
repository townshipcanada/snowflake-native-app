# Township Canada — Databricks Delta Sharing

DLS grid boundary data published as a Delta Sharing dataset for Databricks users.

## Overview

This directory contains the configuration and documentation for publishing Township Canada's DLS (Dominion Land Survey) grid boundaries as a Delta Sharing dataset on Databricks Marketplace.

Delta Sharing is an open protocol for secure data sharing. By publishing DLS grid boundaries as a shared dataset, Databricks users can join their well, lease, or land data against survey grid polygons without any API calls.

## What's Included in the Dataset

| Table | Description | Geometry Type | Coverage |
|-------|-------------|---------------|----------|
| `dls_townships` | Township boundaries (6-mile × 6-mile grids) | Polygon | AB, SK, MB |
| `dls_sections` | Section boundaries (1-mile × 1-mile grids) | Polygon | AB, SK, MB |
| `dls_quarter_sections` | Quarter-section boundaries | Polygon | AB, SK, MB |

Each table includes:
- `township`, `range`, `meridian` (and `section`, `quarter` where applicable)
- `lld` — formatted legal land description string
- `geometry` — WKT polygon boundary
- `centroid_lat`, `centroid_lon` — center point coordinates
- `area_ha` — area in hectares

## Usage in Databricks

### 1. Access the Share

Once you have access to the Township Canada share (via Databricks Marketplace or direct sharing):

```python
# The shared tables appear as Unity Catalog tables
df = spark.table("township_canada.dls.dls_townships")
df.show()
```

### 2. Spatial Join with Your Data

```python
from pyspark.sql import functions as F
from mosaic import enable_mosaic
enable_mosaic(spark)

# Your wells data with lat/lon
wells = spark.table("my_catalog.my_schema.wells")

# DLS township boundaries
townships = spark.table("township_canada.dls.dls_townships")

# Point-in-polygon join to find which township each well is in
enriched = wells.join(
    townships,
    F.expr("ST_Contains(ST_GeomFromWKT(geometry), ST_Point(longitude, latitude))")
)
```

### 3. SQL Spatial Join

```sql
-- Find the legal land description for a coordinate
SELECT t.lld, t.township, t.range, t.meridian
FROM township_canada.dls.dls_townships t
WHERE ST_Contains(ST_GeomFromWKT(t.geometry), ST_Point(-114.0719, 51.0447));

-- Enrich a wells table with township info
SELECT w.well_id, w.latitude, w.longitude, t.lld AS township_lld
FROM my_wells w
JOIN township_canada.dls.dls_townships t
  ON ST_Contains(ST_GeomFromWKT(t.geometry), ST_Point(w.longitude, w.latitude));
```

## Delta Sharing Configuration

### Share Definition

The `share.yaml` file defines the tables and permissions for the Delta Sharing server:

```yaml
name: township_canada_dls
comment: "DLS grid boundaries for Western Canada (AB, SK, MB)"
tables:
  - name: dls_townships
    schema: dls
    comment: "Township boundaries (6mi × 6mi)"
  - name: dls_sections
    schema: dls
    comment: "Section boundaries (1mi × 1mi)"
  - name: dls_quarter_sections
    schema: dls
    comment: "Quarter-section boundaries"
```

### Publishing to Databricks Marketplace

1. Create a Unity Catalog share containing the DLS boundary tables
2. Register as a Databricks Marketplace provider
3. Create a listing with the share attached
4. Submit for review

See `share.yaml` for the share definition and `listing.json` for marketplace listing metadata.

## Environment Variables

| Variable | Description |
|----------|-------------|
| `DATABRICKS_HOST` | Databricks workspace URL |
| `DATABRICKS_TOKEN` | Personal access token with Unity Catalog permissions |
| `UNITY_CATALOG_NAME` | Catalog containing the DLS boundary tables |

## Related

- [Delta Sharing Protocol](https://delta.io/sharing/)
- [Databricks Marketplace Provider Guide](https://docs.databricks.com/en/marketplace/provider.html)
- Township Canada Snowflake Native App (see parent directory)
