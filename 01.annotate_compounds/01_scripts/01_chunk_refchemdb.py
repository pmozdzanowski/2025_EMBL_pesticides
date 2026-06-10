"""
Splits RefChemDB dataset into smaller CSV chunks based on dsstox_substance_id for downstream processing.
"""

import math
from pathlib import Path

import polars as pl

MODULE_DIR = Path(__file__).resolve().parents[1]


def main():
    # Process RefChemDB
    refchemdb = pl.read_csv(MODULE_DIR / "00_inputs/refchemdb/refchemdb.csv").select("dsstox_substance_id").unique()
    output_dir = MODULE_DIR / "02_outputs/refchemdb/input_comptoxdb"
    output_dir.mkdir(parents=True, exist_ok=True)

    chunk_size = 10_000
    total_rows = refchemdb.height
    num_chunks = math.ceil(total_rows / chunk_size)

    for i in range(num_chunks):
        start = i * chunk_size
        end = min(start + chunk_size, total_rows)
        chunk = refchemdb.slice(start, end - start)
        chunk.write_csv(output_dir / f"refchemdb_dtxsid_{i + 1}.csv")


if __name__ == "__main__":
    main()
