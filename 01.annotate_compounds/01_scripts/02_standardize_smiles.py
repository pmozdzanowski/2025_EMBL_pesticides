"""
Standardizes SMILES structures for pesticides, drugs, and RefChemDB datasets and saves the results.
"""

from pathlib import Path

import pandas as pd
from standardize_smiles import StandardizeMolecule


def main():
    num_cpus = 8
    output_dir = Path("../02_outputs")
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "refchemdb").mkdir(parents=True, exist_ok=True)

    # Read in compound lists
    pesticides = pd.read_csv("../00_inputs/pesticides.csv")

    # Read in drugs
    drugs = pd.read_csv("../00_inputs/drugs.csv")
    drugs = drugs.drop(columns=["SMILES"])

    drug_smiles = pd.read_csv("../00_inputs/drugs_cas_to_smiles.csv")
    drug_smiles = drug_smiles[drug_smiles["SMILES"].notna() & (drug_smiles["SMILES"] != "")]

    drugs = drugs.merge(drug_smiles, on="CAS Number", how="inner")

    # Read in RefChemDB
    files = [
        "../02_outputs/refchemdb/output_comptoxdb/dtxsid_smiles_1.csv",
        "../02_outputs/refchemdb/output_comptoxdb/dtxsid_smiles_2.csv",
        "../02_outputs/refchemdb/output_comptoxdb/dtxsid_smiles_3.csv",
        "../02_outputs/refchemdb/output_comptoxdb/dtxsid_smiles_4.csv",
    ]

    # Read and concatenate
    refchemdb = [pd.read_csv(f) for f in files]
    refchemdb = pd.concat(refchemdb, ignore_index=True)

    # Standardize the smiles
    standardized_pesticides = StandardizeMolecule(input=pesticides, augment=True, num_cpu=num_cpus).run()
    standardized_pesticides.to_csv(output_dir / "standardized_pesticides.csv", index=False)

    standardized_drugs = StandardizeMolecule(input=drugs, augment=True, num_cpu=num_cpus).run()
    standardized_drugs.to_csv(output_dir / "standardized_drugs.csv", index=False)

    standardized_refchemdb = StandardizeMolecule(input=refchemdb, augment=True, num_cpu=num_cpus).run()
    standardized_refchemdb.to_csv(output_dir / "refchemdb/standardized_refchemdb.csv", index=False)


if __name__ == "__main__":
    main()
