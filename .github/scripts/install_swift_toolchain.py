import os
import subprocess
import sys
import urllib.parse

try:
    import yaml
except ImportError:
    raise SystemExit("PyYAML is required but not available on the runner")


def first_present(data, keys):
    for key in keys:
        value = data.get(key)
        if value:
            return value
    return None


def main(argv):
    if len(argv) != 9:
        raise SystemExit("install_swift_toolchain.py expects 8 arguments")

    meta_path, runner_os, channel, platform, swift_cache, clang_cache, github_path, github_env = argv[1:9]

    with open(meta_path, "r", encoding="utf-8") as handle:
        meta = yaml.safe_load(handle)

    download = first_present(meta, ["download", "file", "filename"])
    if not download:
        raise SystemExit("Failed to locate Swift snapshot download name")

    download_dir = first_present(meta, ["download_dir", "download_directory", "dir"])
    if not download_dir:
        if runner_os == "macOS":
            base = download.removesuffix(".pkg")
            download_dir = base.removesuffix("-osx")
        else:
            base = download.removesuffix(".tar.gz")
            download_dir = base.removesuffix(f"-{platform}")

    if not download_dir:
        raise SystemExit("Failed to determine Swift snapshot directory")

    url = first_present(meta, ["download_url", "url"])
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
