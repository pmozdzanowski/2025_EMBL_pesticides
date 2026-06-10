"""
Annotate drugs and pesticides with RefchemDB targets, based on standardized SMILES and inchikey.
"""

from pathlib import Path

import polars as pl


def main():
    support = 7
    output_dir = Path("../02_outputs")
    output_dir.mkdir(parents=True, exist_ok=True)

    # Add standardized inchikey to refchemdb
    refchemdb_ids = (
        pl.read_csv("../02_outputs/refchemdb/standardized_refchemdb.csv")
        .select(["InChIKey_standardized", "DTXSID"])
        .rename({"InChIKey_standardized": "INCHIKEY"})
    )

    refchemdb = pl.read_csv("../00_inputs/refchemdb/refchemdb.csv").rename({"dsstox_substance_id": "DTXSID"})

    refchemdb = refchemdb.join(refchemdb_ids, on="DTXSID").filter(pl.col("support") >= support)

    refchemdb_simple = refchemdb.select(["DTXSID", "target", "INCHIKEY"]).unique()

    # Process drugs and pesticides
    pesticides = (
        pl.read_csv("../02_outputs/standardized_pesticides.csv", infer_schema_length=10000)
        .select(["InChIKey_standardized", "Descriptive name", "CHEMBL_ID", "ChEBI", "Pesticide type"])
        .rename({"InChIKey_standardized": "INCHIKEY", "Descriptive name": "name"})
    )

    drugs = (
        pl.read_csv("../02_outputs/standardized_drugs.csv", infer_schema_length=10000)
        .select(["InChIKey_standardized", "Name", "Target"])
        .rename({"InChIKey_standardized": "INCHIKEY", "Name": "name", "Target": "orig_target_ann"})
    )

    # Annotate drugs
    joined = refchemdb_simple.join(drugs, on="INCHIKEY", how="inner")

    agg = joined.group_by("INCHIKEY").agg(
        [
            pl.col("target").unique().count().alias("target_count"),
            pl.col("target").unique().implode().str.join(", ").alias("targets"),
            pl.col("DTXSID").unique().implode().str.join(", ").alias("DTXSID"),
        ]
    )

    drugs_targets = drugs.join(agg, on="INCHIKEY", how="left")
    drugs_targets.write_csv(output_dir / "drugs_targets.csv")

    # Annotate pesticides
    joined = refchemdb_simple.join(pesticides, on="INCHIKEY", how="inner")

    agg = joined.group_by("INCHIKEY").agg(
        [
            pl.col("target").unique().count().alias("target_count"),
            pl.col("target").unique().implode().str.join(", ").alias("targets"),
            pl.col("DTXSID").unique().implode().str.join(", ").alias("DTXSID"),
        ]
    )

    pesticides_targets = pesticides.join(agg, on="INCHIKEY", how="left")
    pesticides_targets.write_csv(output_dir / "pesticides_targets.csv")


if __name__ == "__main__":
    main()
