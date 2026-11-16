"""Download all available splits of the public campus placement dataset."""
from pathlib import Path
import pandas as pd
from datasets import load_dataset

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "data" / "raw"
RAW.mkdir(parents=True, exist_ok=True)


def main() -> None:
    dataset = load_dataset("Krooz/Campus_Recruitment_CSV")
    frames = []
    for split_name, split in dataset.items():
        frame = split.to_pandas()
        frame["SourceSplit"] = split_name
        frames.append(frame)
    if not frames:
        raise RuntimeError("No dataset splits were returned.")
    df = pd.concat(frames, ignore_index=True)
    if "PlacementStatus" not in df.columns:
        raise ValueError("Dataset does not include the expected PlacementStatus label.")
    output = RAW / "campus_placement.csv"
    df.to_csv(output, index=False)
    print(f"Saved {len(df):,} records across {len(frames)} splits to {output}")
    print("Columns:", ", ".join(df.columns))


if __name__ == "__main__":
    main()
