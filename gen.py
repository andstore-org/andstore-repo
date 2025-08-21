import os
import json
import hashlib
import tarfile
import io
import zstandard as zstd

REPO_URL = "https://raw.githubusercontent.com/andstore-org/andstore-repo/main/packages"

def sha256sum(file_path):
    h = hashlib.sha256()
    with open(file_path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()

def read_info_file(info_path):
    info = {}
    with open(info_path, "r") as f:
        for line in f:
            if "=" in line:
                k, v = line.strip().split("=", 1)
                info[k] = v
    return info

def list_tar_zst_contents(file_path):
    contents = []
    dctx = zstd.ZstdDecompressor()
    with open(file_path, "rb") as f:
        with dctx.stream_reader(f) as reader:
            with tarfile.open(fileobj=io.BytesIO(reader.read()), mode="r:") as tar:
                for member in tar.getmembers():
                    if not member.isdir():
                        contents.append(member.name)
    return contents

def generate_repo_json(packages_dir):
    repo = {"packages": {}}

    for package_name in os.listdir(packages_dir):
        package_path = os.path.join(packages_dir, package_name)
        if not os.path.isdir(package_path):
            continue

        info_file = os.path.join(package_path, "INFO")
        if not os.path.exists(info_file):
            continue

        info = read_info_file(info_file)

        package_entry = {
            "version": info.get("VERSION", ""),
            "min_api": info.get("MIN_API", ""),
            "dependencies": info.get("DEPENDENCIES", "").split() if info.get("DEPENDENCIES") else [],
            "conflicts": info.get("CONFLICTS", "").split() if info.get("CONFLICTS") else [],
            "architectures": {}
        }

        for arch in ["arm64-v8a", "armeabi-v7a", "x86", "x86_64", "riscv64"]:
            arch_path = os.path.join(package_path, arch)
            if not os.path.exists(arch_path):
                continue

            for file in os.listdir(arch_path):
                if file.endswith(".tar.zst"):
                    file_path = os.path.join(arch_path, file)
                    checksum = sha256sum(file_path)
                    contents = list_tar_zst_contents(file_path)
                    size_bytes = os.path.getsize(file_path)

                    package_entry["architectures"][arch] = {
                        "url": f"{REPO_URL}/{package_name}/{arch}/{file}",
                        "sha256": checksum,
                        "size": size_bytes,
                        "contents": contents
                    }

        repo["packages"][package_name] = package_entry

    return repo


if __name__ == "__main__":
    repo_json = generate_repo_json("packages")
    with open("repo.json", "w") as f:
        json.dump(repo_json, f, indent=4)
    print("repo.json generated successfully!")
