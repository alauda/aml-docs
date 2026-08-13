"""Copy files and directory prefixes to or from S3-compatible storage."""

from __future__ import annotations

import argparse
import os
import tempfile
from pathlib import Path, PurePosixPath
from urllib.parse import urlparse

import boto3
from botocore.config import Config


def s3_location(uri: str) -> tuple[str, str]:
    parsed = urlparse(uri)
    if parsed.scheme != "s3" or not parsed.netloc:
        raise ValueError(f"Expected an S3 URI, got {uri!r}")
    return parsed.netloc, parsed.path.lstrip("/")


def is_s3_uri(value: str) -> bool:
    return value.startswith("s3://")


def s3_client():
    endpoint = os.environ.get("AWS_S3_ENDPOINT")
    if not endpoint:
        raise RuntimeError("Set AWS_S3_ENDPOINT to the S3-compatible endpoint URL")
    session = boto3.Session(region_name=os.environ.get("AWS_DEFAULT_REGION", "us-east-1"))
    return session.client(
        "s3",
        endpoint_url=endpoint,
        config=Config(s3={"addressing_style": "path"}),
    )


def safe_destination(root: Path, relative_key: str) -> Path:
    relative_path = PurePosixPath(relative_key)
    if not relative_key or relative_path.is_absolute() or ".." in relative_path.parts:
        raise ValueError(f"Unsafe object key relative to S3 prefix: {relative_key!r}")
    root = root.resolve()
    destination = (root / Path(*relative_path.parts)).resolve()
    try:
        destination.relative_to(root)
    except ValueError as error:
        raise ValueError(f"Object key escapes destination directory: {relative_key!r}") from error
    return destination


def download_file(client, bucket: str, key: str, destination: Path):
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=destination.parent, delete=False) as temporary:
        temporary_path = Path(temporary.name)
    try:
        client.download_file(bucket, key, str(temporary_path))
        temporary_path.replace(destination)
    except BaseException:
        temporary_path.unlink(missing_ok=True)
        raise


def download_prefix(client, source: str, destination: Path):
    bucket, prefix = s3_location(source)
    prefix = prefix.rstrip("/") + "/"
    downloaded = 0
    for page in client.get_paginator("list_objects_v2").paginate(Bucket=bucket, Prefix=prefix):
        for item in page.get("Contents", []):
            key = item["Key"]
            relative_key = key.removeprefix(prefix)
            if not relative_key:
                continue
            target = safe_destination(destination, relative_key)
            print(f"download s3://{bucket}/{key} -> {target}")
            download_file(client, bucket, key, target)
            downloaded += 1
    if not downloaded:
        raise RuntimeError(f"No objects found under {source}")


def upload_prefix(client, source: Path, destination: str):
    bucket, prefix = s3_location(destination)
    prefix = prefix.rstrip("/")
    uploaded = 0
    for path in source.rglob("*"):
        if path.is_symlink():
            raise ValueError(f"Refusing to upload symbolic link: {path}")
        if not path.is_file():
            continue
        key = "/".join(part for part in (prefix, path.relative_to(source).as_posix()) if part)
        print(f"upload {path} -> s3://{bucket}/{key}")
        client.upload_file(str(path), bucket, key)
        uploaded += 1
    if not uploaded:
        raise RuntimeError(f"No regular files found under {source}")


def sync(source: str, destination: str):
    client = s3_client()
    if is_s3_uri(source) and not is_s3_uri(destination):
        download_prefix(client, source, Path(destination))
    elif not is_s3_uri(source) and is_s3_uri(destination):
        local_source = Path(source)
        if not local_source.is_dir():
            raise ValueError(f"sync source must be a directory: {local_source}")
        upload_prefix(client, local_source, destination)
    else:
        raise ValueError("sync requires one local directory and one S3 URI")


def copy_file(source: str, destination: str):
    client = s3_client()
    if is_s3_uri(source) and not is_s3_uri(destination):
        bucket, key = s3_location(source)
        download_file(client, bucket, key, Path(destination))
    elif not is_s3_uri(source) and is_s3_uri(destination):
        local_source = Path(source)
        if not local_source.is_file() or local_source.is_symlink():
            raise ValueError(f"copy source must be a regular file: {local_source}")
        bucket, key = s3_location(destination)
        if not key:
            raise ValueError("copy destination must include an object key")
        print(f"upload {local_source} -> s3://{bucket}/{key}")
        client.upload_file(str(local_source), bucket, key)
    else:
        raise ValueError("copy requires one local file and one S3 URI")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    for command in ("sync", "copy"):
        subparser = subparsers.add_parser(command)
        subparser.add_argument("source")
        subparser.add_argument("destination")
    args = parser.parse_args()
    if args.command == "sync":
        sync(args.source, args.destination)
    else:
        copy_file(args.source, args.destination)


if __name__ == "__main__":
    main()
