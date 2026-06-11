#!/usr/bin/env python3

import argparse
from pathlib import Path

import numpy as np
import pandas as pd
from rdkit import Chem, DataStructs
from rdkit.Chem import rdFingerprintGenerator

MODULE_DIR = Path(__file__).resolve().parents[1]
OUTPUT_DIR = MODULE_DIR / "02_outputs"
FINGERPRINT_DIR = OUTPUT_DIR / "Morgan_fingerprints"


INPUTS = {
    "pesticides": OUTPUT_DIR / "standardized_pesticides.csv",
    "drugs": OUTPUT_DIR / "standardized_drugs.csv",
    "refchemdb": OUTPUT_DIR / "refchemdb/standardized_refchemdb.csv",
}


SMILES_COLUMNS = [
    "SMILES_standardized",
    "standardized_smiles",
    "Standardized_SMILES",
    "standardized_SMILES",
    "Canonical_SMILES_standardized",
    "canonical_smiles",
    "SMILES",
    "smiles",
]

ID_COLUMNS = [
    "DTXSID",
    "dsstox_substance_id",
    "INCHIKEY",
    "InChIKey_standardized",
    "InChIKey",
    "CHEMBL_ID",
    "ChEBI",
    "CAS Number",
    "CASRN",
    "Name",
    "name",
    "Descriptive name",
    "Pesticide type",
]


def find_column(df: pd.DataFrame, candidates: list[str], label: str) -> str:
    for col in candidates:
        if col in df.columns:
            return col

    raise ValueError(f"No {label} column found. Tried: {candidates}. Available columns: {list(df.columns)}")


def fingerprint_from_smiles(smiles: str, generator, n_bits: int) -> np.ndarray | None:
    if pd.isna(smiles) or str(smiles).strip() == "":
        return None

    mol = Chem.MolFromSmiles(str(smiles))

    if mol is None:
        return None

    fp = generator.GetFingerprint(mol)
    arr = np.zeros((n_bits,), dtype=np.uint8)
    DataStructs.ConvertToNumpyArray(fp, arr)

    return arr


def save_table(df: pd.DataFrame, path_stem: Path, output_format: str) -> None:
    if output_format in {"parquet", "both"}:
        df.to_parquet(path_stem.with_suffix(".parquet"), index=False)

    if output_format in {"csv", "both"}:
        df.to_csv(path_stem.with_suffix(".csv"), index=False)


def process_group(name: str, input_path: Path, radius: int, n_bits: int, output_format: str) -> None:
    print(f"\nProcessing {name}")
    print(f"Input: {input_path}")

    df = pd.read_csv(input_path, low_memory=False)
    smiles_col = find_column(df, SMILES_COLUMNS, "SMILES")

    keep_cols = [col for col in ID_COLUMNS if col in df.columns]
    if smiles_col not in keep_cols:
        keep_cols = [smiles_col] + keep_cols

    meta = df[keep_cols].copy()
    meta = meta.rename(columns={smiles_col: "standardized_smiles"})

    generator = rdFingerprintGenerator.GetMorganGenerator(
        radius=radius,
        fpSize=n_bits,
    )

    fps = []
    valid = []

    for smiles in meta["standardized_smiles"]:
        fp = fingerprint_from_smiles(smiles, generator, n_bits)
        fps.append(fp)
        valid.append(fp is not None)

    meta["valid_mol"] = valid

    invalid = meta.loc[~meta["valid_mol"]].copy()
    valid_meta = meta.loc[meta["valid_mol"]].reset_index(drop=True)
    valid_fps = [fp for fp in fps if fp is not None]

    fp_df = pd.DataFrame(
        np.vstack(valid_fps),
        columns=[f"morgan_{i}" for i in range(n_bits)],
    )

    result = pd.concat([valid_meta, fp_df], axis=1)

    output_stem = FINGERPRINT_DIR / f"{name}_fingerprints"
    save_table(result, output_stem, output_format)

    if len(invalid) > 0:
        invalid.to_csv(FINGERPRINT_DIR / f"{name}_invalid_smiles.csv", index=False)

    print(f"SMILES column: {smiles_col}")
    print(f"Valid molecules: {len(result)}")
    print(f"Invalid molecules: {len(invalid)}")
    print(f"Output: {output_stem}.{output_format if output_format != 'both' else 'parquet/csv'}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--radius", type=int, default=2)
    parser.add_argument("--n-bits", type=int, default=2048)
    parser.add_argument(
        "--format",
        choices=["parquet", "csv", "both"],
        default="parquet",
    )
    args = parser.parse_args()

    FINGERPRINT_DIR.mkdir(parents=True, exist_ok=True)

    for name, input_path in INPUTS.items():
        if not input_path.exists():
            raise FileNotFoundError(f"Input file not found: {input_path}")

        process_group(
            name=name,
            input_path=input_path,
            radius=args.radius,
            n_bits=args.n_bits,
            output_format=args.format,
        )


if __name__ == "__main__":
    main()
