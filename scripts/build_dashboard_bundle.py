#!/usr/bin/env python3
"""Build a small, static dashboard bundle from an HPC analysis directory."""

from __future__ import annotations

import argparse
import json
import re
import shlex
import shutil
from pathlib import Path


SCRIPT_RE = re.compile(r"^(\d+)(?:[-_ .]|$).*\.sh$", re.IGNORECASE)
SUPPORTED_OUTPUT = {".html", ".htm", ".png", ".jpg", ".jpeg", ".svg", ".csv", ".tsv"}
OUTPUT_FLAGS = {"-o", "--out", "--output", "--output-dir", "--outdir", "--outfile", "--report", "--html"}
FILE_EXTENSIONS = SUPPORTED_OUTPUT | {
    ".fastq", ".fq", ".bam", ".sam", ".fa", ".fasta", ".fna", ".txt", ".json", ".pdf", ".rds", ".biom", ".db"
}


def clean_token(token: str) -> str:
    return token.strip("'\";,\")")


def is_file_token(token: str) -> bool:
    return Path(clean_token(token)).suffix.lower() in FILE_EXTENSIONS


def parse_script(script: Path, project: Path) -> tuple[list[str], list[str]]:
    """Infer file arguments and output arguments from a shell script."""
    inputs: set[str] = set()
    outputs: set[str] = set()
    text = script.read_text(errors="replace")

    for raw_line in text.splitlines():
        line = re.sub(r"\s+#.*$", "", raw_line).strip()
        if not line or line.startswith("#"):
            continue

        for match in re.finditer(r"(?:>|>>|2>|2>>|<)\s*([^\s;&|]+)", line):
            path = clean_token(match.group(1))
            (inputs if "<" in match.group(0) else outputs).add(path)

        try:
            tokens = shlex.split(line.replace("\\\n", " "))
        except ValueError:
            tokens = line.split()

        for index, token in enumerate(tokens[1:], start=1):
            value = clean_token(token)
            previous = tokens[index - 1].lower() if index else ""
            flag, separator, attached = value.partition("=")
            if flag.lower() in OUTPUT_FLAGS and separator and attached:
                outputs.add(clean_token(attached))
            elif previous in OUTPUT_FLAGS:
                outputs.add(value)
            elif is_file_token(value) and not value.startswith("-"):
                inputs.add(value)

    inputs -= outputs
    return sorted(inputs), sorted(outputs)


def resolve_path(value: str, script: Path, project: Path) -> Path | None:
    value = clean_token(value).replace("\\", "/")
    if not value or value.startswith(("$", "-")):
        return None
    candidate = Path(value)
    candidates = [project / candidate, script.parent / candidate]
    for path in candidates:
        if path.exists():
            return path.resolve()
    return None


def output_files(script: Path, output_tokens: list[str], project: Path) -> set[Path]:
    found: set[Path] = set()
    for token in output_tokens:
        resolved = resolve_path(token, script, project)
        if not resolved:
            continue
        if resolved.is_file() and resolved.suffix.lower() in SUPPORTED_OUTPUT:
            found.add(resolved)
        elif resolved.is_dir():
            found.update(p for p in resolved.rglob("*") if p.is_file() and p.suffix.lower() in SUPPORTED_OUTPUT)
    return found


def display_name(script: Path) -> str:
    name = script.stem
    return re.sub(r"^\d+[-_ .]*", "", name).replace("_", " ").replace("-", " ").strip() or script.stem


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=Path, help="HPC analysis directory")
    parser.add_argument("--output", type=Path, default=Path("dashboard-data"), help="Bundle directory (default: dashboard-data)")
    parser.add_argument("--name", help="Dashboard project name (default: source directory name)")
    args = parser.parse_args()

    project = args.project.expanduser().resolve()
    output = args.output.expanduser().resolve()
    if not project.is_dir():
        parser.error(f"not a directory: {project}")
    if output == project or project in output.parents:
        parser.error("output directory must not be inside the source project directory")

    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)

    source_files = [p for p in project.rglob("*") if p.is_file()]
    scripts = sorted((p for p in source_files if SCRIPT_RE.match(p.name)), key=lambda p: (int(SCRIPT_RE.match(p.name).group(1)), str(p)))
    config = next((p for p in source_files if p.name.lower() == "config.tsv"), None)
    copied: set[str] = set()

    def copy_file(path: Path) -> str:
        relative = path.relative_to(project).as_posix()
        destination = output / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, destination)
        copied.add(relative)
        return relative

    config_relative = copy_file(config) if config else None
    steps = []
    for script in scripts:
        inputs, output_tokens = parse_script(script, project)
        script_relative = copy_file(script)
        result_files = output_files(script, output_tokens, project)
        relative_outputs = sorted(copy_file(path) for path in result_files)
        declared_outputs = sorted(set(output_tokens) | set(relative_outputs))
        steps.append({
            "number": int(SCRIPT_RE.match(script.name).group(1)),
            "name": display_name(script),
            "script": script_relative,
            "inputs": inputs,
            "outputs": declared_outputs,
            "copied_outputs": relative_outputs,
        })

    manifest = {
        "version": 1,
        "name": args.name or project.name,
        "config": config_relative,
        "steps": steps,
        "files": sorted(copied),
    }
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Built {output} from {project}")
    print(f"Included {len(steps)} steps and {len(copied)} files")
    for step in steps:
        print(f"  {step['number']:02d} {step['name']}: {len(step['inputs'])} inputs, {len(step['outputs'])} declared outputs, {len(step['copied_outputs'])} copied outputs")
    if not config:
        print("Warning: config.tsv was not found")


if __name__ == "__main__":
    main()
