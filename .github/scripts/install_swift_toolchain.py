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


def parse_metadata(path: Path) -> tuple[dict[str, str], str]:
    result: dict[str, str] = {}
    raw_text = path.read_text(encoding="utf-8")
    for raw_line in raw_text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
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
        match = re.search(r"^download:\s*(\S.*)$", raw_text, re.MULTILINE)
        if match:
            download = match.group(1).strip().strip('"').strip("'")
        if not download:
            match = re.search(r"swift-[\w-]+\.(pkg|tar\.gz)", raw_text)
            if match:
                download = match.group(0)
        if not download:
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
        match = re.search(r"^(dir|download_dir|download_directory):\s*(\S.*)$", raw_text, re.MULTILINE)
        if match:
            download_dir = match.group(2).strip().strip('"').strip("'")
        if not download_dir:
            raise SystemExit("Failed to determine Swift snapshot directory")

    url = first_present(metadata, TARGET_KEYS["download_url"])
    if not url:
        match = re.search(r"^(download_url|url):\s*(\S.*)$", raw_text, re.MULTILINE)
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
