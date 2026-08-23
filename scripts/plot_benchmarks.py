#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
from statistics import mean, stdev

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt


LABELS = ("zdiff", "GNU diff", "GNU diff --minimal")
CASES = {
    "large-few-changes": (0, "Large files, few changes"),
    "completely-different": (1, "Completely different files"),
    "scattered-changes": (2, "Scattered changes"),
    "common-prefix-suffix": (3, "Long common prefix and suffix"),
    "many-small-files": (4, "Many small files"),
}


def result_dir(path: Path) -> Path:
    if list(path.glob("*.json")):
        return path
    candidates = [p for p in path.iterdir() if p.is_dir() and list(p.glob("*.json"))]
    if not candidates:
        raise ValueError(f"no hyperfine JSON files under {path}")
    return max(candidates, key=lambda p: p.stat().st_mtime)


def load(path: Path) -> list[tuple[str, dict[str, dict[str, list[float]]]]]:
    cases = []
    files = sorted(
        (file for file in path.glob("*.json") if not file.stem.endswith(("-memory", "-minimal-memory"))),
        key=lambda file: CASES.get(file.stem, (len(CASES),))[0],
    )
    for file in files:
        raw = json.loads(file.read_text())
        results = {item["command"]: item for item in raw.get("results", [])}
        for label, suffix in (("GNU diff", "memory"), ("GNU diff --minimal", "minimal-memory")):
            memory_file = file.with_name(f"{file.stem}-{suffix}.json")
            if memory_file.exists():
                memory_results = json.loads(memory_file.read_text()).get("results", [])
                if len(memory_results) == 1 and memory_results[0].get("command") == label:
                    results[label]["memory_usage_byte"] = memory_results[0].get("memory_usage_byte")
        if set(results) != set(LABELS) or any(
            not result.get(metric) or min(result[metric]) <= 0
            for result in results.values()
            for metric in ("times", "memory_usage_byte")
        ):
            raise ValueError(f"{file} must contain positive time and memory runs for {', '.join(LABELS)}")
        cases.append((CASES.get(file.stem, (0, file.stem.replace("-", " ")))[1], results))
    if not cases:
        raise ValueError(f"no hyperfine JSON files in {path}")
    return cases


def plot(cases: list[tuple[str, dict[str, dict[str, list[float]]]]], output: Path) -> None:
    colors = ("#2563eb", "#dc2626", "#f59e0b")
    fig, grid = plt.subplots(len(cases), 2, figsize=(14, len(cases) * 2.4), squeeze=False, layout="constrained")
    fig.suptitle("zdiff vs GNU diff", fontsize=16)

    for (time_axis, memory_axis), (name, results) in zip(grid, cases, strict=True):
        times = [mean(results[label]["times"]) * 1000 for label in LABELS]
        time_errors = [stdev(results[label]["times"]) * 1000 if len(results[label]["times"]) > 1 else 0 for label in LABELS]
        first, second = sorted(range(len(times)), key=times.__getitem__)[:2]
        combined_error = 2 * (
            time_errors[first] ** 2 / len(results[LABELS[first]]["times"])
            + time_errors[second] ** 2 / len(results[LABELS[second]]["times"])
        ) ** 0.5
        verdict = (
            f"No clear winner: {LABELS[first]} / {LABELS[second]}"
            if times[second] - times[first] <= combined_error
            else f"Fastest: {LABELS[first]}"
        )

        for axis, values, errors, unit, title in (
            (time_axis, times, time_errors, "ms", f"{name}  |  {verdict}"),
            (
                memory_axis,
                [mean(results[label]["memory_usage_byte"]) / 1024**2 for label in LABELS],
                [stdev(results[label]["memory_usage_byte"]) / 1024**2 if len(results[label]["memory_usage_byte"]) > 1 else 0 for label in LABELS],
                "MiB",
                "Hyperfine-reported peak memory",
            ),
        ):
            axis.barh(LABELS, values, xerr=errors, color=colors, alpha=0.8, capsize=4)
            axis.invert_yaxis()
            axis.set_xlim(0, max(value + error for value, error in zip(values, errors, strict=True)) * 1.4)
            axis.grid(axis="x", alpha=0.2)
            axis.set_title(title, loc="left")
            for row, (value, error) in enumerate(zip(values, errors, strict=True)):
                axis.text(value + error + max(values) * 0.02, row, f"{value:.1f} ± {error:.1f} {unit}", va="center")

    grid[-1, 0].set_xlabel("Mean runtime, lower is better")
    grid[-1, 1].set_xlabel("Peak memory, lower is better")
    output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output, dpi=180)
    plt.close(fig)


def main() -> None:
    parser = argparse.ArgumentParser(description="Plot hyperfine results for zdiff and GNU diff")
    parser.add_argument("results", nargs="?", type=Path, default=Path("benchmark-results"))
    parser.add_argument("-o", "--output", type=Path)
    args = parser.parse_args()
    directory = result_dir(args.results)
    output = args.output or directory / "comparison.png"
    plot(load(directory), output)
    print(output)


if __name__ == "__main__":
    main()
