#!/usr/bin/env python3
from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


@dataclass(frozen=True)
class FileCoverage:
    path: str
    lines_found: int
    lines_hit: int
    uncovered_lines: tuple[int, ...]

    @property
    def lines_missed(self) -> int:
        return self.lines_found - self.lines_hit

    @property
    def coverage_percent(self) -> float:
        if self.lines_found == 0:
            return 100.0
        return (self.lines_hit / self.lines_found) * 100.0


def _parse_lcov(content: str) -> list[FileCoverage]:
    records: list[FileCoverage] = []

    for block in content.split("end_of_record"):
        block = block.strip()
        if not block:
            continue

        path: str | None = None
        lines_found: int | None = None
        lines_hit: int | None = None
        uncovered: list[int] = []

        for raw_line in block.splitlines():
            line = raw_line.strip()
            if line.startswith("SF:"):
                path = line[3:]
            elif line.startswith("LF:"):
                lines_found = int(line[3:])
            elif line.startswith("LH:"):
                lines_hit = int(line[3:])
            elif line.startswith("DA:"):
                # DA:<line number>,<execution count>[,<checksum>]
                payload = line[3:]
                parts = payload.split(",")
                if len(parts) >= 2:
                    line_no = int(parts[0])
                    hit_count = int(parts[1])
                    if hit_count == 0:
                        uncovered.append(line_no)

        if path is None or lines_found is None or lines_hit is None:
            continue

        records.append(
            FileCoverage(
                path=path,
                lines_found=lines_found,
                lines_hit=lines_hit,
                uncovered_lines=tuple(sorted(uncovered)),
            )
        )

    return records


def _filter_records(
    records: Iterable[FileCoverage],
    include_patterns: list[str],
) -> list[FileCoverage]:
    if not include_patterns:
        return list(records)

    lowered = [pattern.lower() for pattern in include_patterns]
    return [
        record
        for record in records
        if any(pattern in record.path.lower() for pattern in lowered)
    ]


def _sort_records(records: list[FileCoverage], sort_by: str) -> list[FileCoverage]:
    if sort_by == "coverage":
        return sorted(
            records,
            key=lambda record: (
                record.coverage_percent,
                -record.lines_missed,
                record.path,
            ),
        )
    if sort_by == "missed":
        return sorted(
            records,
            key=lambda record: (
                -record.lines_missed,
                record.coverage_percent,
                record.path,
            ),
        )
    if sort_by == "lines":
        return sorted(
            records,
            key=lambda record: (
                -record.lines_found,
                record.coverage_percent,
                record.path,
            ),
        )
    return sorted(records, key=lambda record: record.path)


def _print_summary(records: list[FileCoverage], top: int, show_uncovered: bool) -> None:
    total_found = sum(record.lines_found for record in records)
    total_hit = sum(record.lines_hit for record in records)
    total_missed = total_found - total_hit
    overall = (total_hit / total_found * 100.0) if total_found else 100.0

    print(
        f"Overall: {total_hit}/{total_found} lines = {overall:.2f}% (missed {total_missed})"
    )

    if not records:
        print("No files matched the selected filters.")
        return

    print()
    print(f"Showing top {min(top, len(records))} files:")
    print("%cover   hit/found   missed   file")

    for record in records[:top]:
        print(
            f"{record.coverage_percent:6.2f}%   "
            f"{record.lines_hit:>4}/{record.lines_found:<4}   "
            f"{record.lines_missed:>5}   "
            f"{record.path}"
        )

        if show_uncovered and record.uncovered_lines:
            sample = ", ".join(str(line) for line in record.uncovered_lines[:50])
            suffix = " ..." if len(record.uncovered_lines) > 50 else ""
            print(f"         uncovered lines: {sample}{suffix}")


def _build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Parse an LCOV file and print overall/per-file coverage summary.",
    )
    parser.add_argument(
        "--input",
        default="coverage/lcov.info",
        help="Path to LCOV file (default: coverage/lcov.info)",
    )
    parser.add_argument(
        "--top",
        type=int,
        default=25,
        help="Number of files to display (default: 25)",
    )
    parser.add_argument(
        "--sort",
        choices=("coverage", "missed", "lines", "path"),
        default="coverage",
        help="Sort mode for file rows (default: coverage)",
    )
    parser.add_argument(
        "--include",
        action="append",
        default=[],
        help="Case-insensitive substring filter; can be provided multiple times",
    )
    parser.add_argument(
        "--show-uncovered",
        action="store_true",
        help="Also print uncovered line numbers for shown files",
    )
    return parser


def main() -> int:
    parser = _build_arg_parser()
    args = parser.parse_args()

    lcov_path = Path(args.input)
    if not lcov_path.exists():
        print(f"LCOV file not found: {lcov_path}")
        return 1

    records = _parse_lcov(lcov_path.read_text(encoding="utf-8"))
    records = _filter_records(records, args.include)
    records = _sort_records(records, args.sort)

    _print_summary(records, max(args.top, 0), args.show_uncovered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
