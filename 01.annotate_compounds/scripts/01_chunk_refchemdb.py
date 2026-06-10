"""
Splits RefChemDB dataset into smaller CSV chunks based on dsstox_substance_id for downstream processing.
"""

import math

import polars as pl


def main():
    # Process RefChemDB
    refchemdb = pl.read_csv("../data/refchemdb/refchemdb.csv").select("dsstox_substance_id").unique()

    chunk_size = 10_000
    total_rows = refchemdb.height
    num_chunks = math.ceil(total_rows / chunk_size)

    for i in range(num_chunks):
        start = i * chunk_size
        end = min(start + chunk_size, total_rows)
        chunk = refchemdb.slice(start, end - start)
        chunk.write_csv(f"../data/refchemdb/input_comptoxdb/refchemdb_dtxsid_{i + 1}.csv")


if __name__ == "__main__":
    main()
