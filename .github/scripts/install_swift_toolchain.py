import os
import re
import subprocess
import sys
import urllib.parse
from pathlib import Path


TARGET_KEYS = {
    "download": ["download", "file", "filename"],
    "download_dir": ["download_dir", "download_directory", "dir"],
    "download_url": ["download_url", "url"],
}


def strip_inline_comment(line: str) -> str:
    in_single = False
    in_double = False
    for index, char in enumerate(line):
        if char == "'" and not in_double:
            in_single = not in_single
        elif char == '"' and not in_single:
            in_double = not in_double
        elif char == "#" and not in_single and not in_double:
            return line[:index]
    return line


def print_debug(raw_text: str) -> None:
    sys.stderr.write("\nMetadata preview (first 120 lines):\n")
    for index, line in enumerate(raw_text.splitlines()[:120], start=1):
        sys.stderr.write(f"{index:03d}: {line}\n")
    sys.stderr.write("--- end preview ---\n")


def parse_metadata(path: Path) -> tuple[dict[str, str], str]:
    result: dict[str, str] = {}
    raw_text = path.read_text(encoding="utf-8")
    for raw_line in raw_text.splitlines():
        without_comment = strip_inline_comment(raw_line).rstrip()
        line = without_comment.strip()
        if not line:
            continue
        if line.startswith("#"):
            continue
        if line.startswith("-"):
            line = line.lstrip("- ")
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key not in result and value:
            result[key] = value
    return result, raw_text


def first_present(metadata: dict[str, str], aliases: list[str]) -> str | None:
    for key in aliases:
        value = metadata.get(key)
        if value:
            return value
    return None


def main(argv: list[str]) -> None:
    if len(argv) != 9:
        raise SystemExit("install_swift_toolchain.py expects 8 arguments")

    meta_path = Path(argv[1])
    runner_os, channel, platform = argv[2:5]
    swift_cache, clang_cache = argv[5:7]
    github_path, github_env = argv[7:9]

    metadata, raw_text = parse_metadata(meta_path)

    download = first_present(metadata, TARGET_KEYS["download"])
    if not download:
        match = re.search(r"^\s*(?:-\s*)?download:\s*(\S.*)$", raw_text, re.MULTILINE)
        if match:
            download = match.group(1).strip().strip('"').strip("'")
        if not download:
            platform_pattern = re.escape(platform)
            patterns = []
            if runner_os == "macOS":
                patterns.append(r"swift-[^\s'\"]+-osx\.pkg")
            else:
                patterns.append(rf"swift-[^\s'\"]+-{platform_pattern}\.tar\.gz")
            patterns.extend([
                r"swift-[^\s'\"]+\.pkg",
                r"swift-[^\s'\"]+\.tar\.gz",
            ])
            for candidate in patterns:
                match = re.search(candidate, raw_text)
                if match:
                    download = match.group(0)
                    break
        if not download:
            print_debug(raw_text)
            raise SystemExit("Failed to locate Swift snapshot download name")

    download_dir = first_present(metadata, TARGET_KEYS["download_dir"])
    if not download_dir:
        if runner_os == "macOS":
            base = download.removesuffix(".pkg")
            download_dir = base.removesuffix("-osx")
        else:
            base = download.removesuffix(".tar.gz")
            download_dir = base.removesuffix(f"-{platform}")

    if not download_dir:
        match = re.search(r"^\s*(?:-\s*)?(dir|download_dir|download_directory):\s*(\S.*)$", raw_text, re.MULTILINE)
        if match:
            download_dir = match.group(2).strip().strip('"').strip("'")
        if not download_dir:
            print_debug(raw_text)
            raise SystemExit("Failed to determine Swift snapshot directory")

    url = first_present(metadata, TARGET_KEYS["download_url"])
    if not url:
        match = re.search(r"^\s*(?:-\s*)?(download_url|url):\s*(\S.*)$", raw_text, re.MULTILINE)
        if match:
            url = match.group(2).strip().strip('"').strip("'")
        if not url:
            match = re.search(r"https://download\.swift\.org[^\s'\"]+", raw_text)
            if match:
                url = match.group(0)
        if not url:
            url = f"https://download.swift.org/{channel}/{platform}/{download_dir}/{download}"
    elif not urllib.parse.urlparse(url).scheme:
        url = f"https://download.swift.org{url}"

    print(f"Resolved Swift snapshot: {download} (dir: {download_dir})")

    os.makedirs(swift_cache, exist_ok=True)
    os.makedirs(clang_cache, exist_ok=True)

    if runner_os == "macOS":
        subprocess.run(["curl", "-sSL", url, "-o", "swift.pkg"], check=True)
        subprocess.run(["sudo", "installer", "-pkg", "swift.pkg", "-target", "/"], check=True)
        toolchain_id = download.removesuffix("-osx.pkg").removesuffix(".pkg")
        toolchain_path = f"/Library/Developer/Toolchains/{toolchain_id}.xctoolchain/usr/bin"
        with open(github_path, "a", encoding="utf-8") as handle:
            handle.write(f"{toolchain_path}\n")
        with open(github_env, "a", encoding="utf-8") as handle:
            handle.write("TOOLCHAINS=swift\n")
    else:
        subprocess.run(["curl", "-sSL", url, "-o", "swift.tar.gz"], check=True)
        subprocess.run(["tar", "-xzf", "swift.tar.gz"], check=True)
        snapshot_dir = download.removesuffix(".tar.gz")
        bin_path = os.path.join(os.getcwd(), snapshot_dir, "usr", "bin")
        lib_path = os.path.join(os.getcwd(), snapshot_dir, "usr", "lib")
        with open(github_path, "a", encoding="utf-8") as handle:
            handle.write(f"{bin_path}\n")
        ld_library_path = os.environ.get("LD_LIBRARY_PATH", "")
        if ld_library_path:
            value = f"LD_LIBRARY_PATH={lib_path}:{ld_library_path}\n"
        else:
            value = f"LD_LIBRARY_PATH={lib_path}\n"
        with open(github_env, "a", encoding="utf-8") as handle:
            handle.write(value)


if __name__ == "__main__":
    main(sys.argv)
