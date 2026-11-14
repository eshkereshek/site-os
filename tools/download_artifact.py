import os
import shutil
import subprocess
import sys
import time
import urllib.request
import zipfile


def get_gh_token():
    try:
        out = subprocess.check_output(["gh", "auth", "token"], text=True)
        return out.strip()
    except Exception as e:
        print(f"Error getting gh token: {e}")
        return None


def get_artifact_download_url(token, artifact_id):
    url = f"https://api.github.com/repos/eshkereshek/site-os/actions/artifacts/{artifact_id}/zip"
    req = urllib.request.Request(
        url,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "User-Agent": "SiteOS-Downloader",
        },
    )
    # We do NOT follow redirects automatically to capture the signed Location header
    class NoRedirectHandler(urllib.request.HTTPRedirectHandler):
        def http_error_302(self, req, fp, code, msg, headers):
            return headers

    opener = urllib.request.build_opener(NoRedirectHandler)
    try:
        resp = opener.open(req)
        loc = resp.get("Location") or resp.get("location")
        if loc:
            return loc
    except Exception as e:
        print(f"Error getting redirect: {e}")
    return None


def download_with_resume(url, target_zip_path, max_retries=20):
    for attempt in range(1, max_retries + 1):
        existing_size = (
            os.path.getsize(target_zip_path) if os.path.exists(target_zip_path) else 0
        )
        print(
            f"Attempt {attempt}/{max_retries}: Starting from {existing_size / (1024*1024):.1f} MB..."
        )

        headers = {
            "User-Agent": "SiteOS-Downloader",
        }
        if existing_size > 0:
            headers["Range"] = f"bytes={existing_size}-"

        req = urllib.request.Request(url, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                mode = "ab" if existing_size > 0 else "wb"
                # Check if server accepted range
                code = resp.getcode()
                if existing_size > 0 and code != 206:
                    print("Server did not accept Range request, restarting download from 0.")
                    mode = "wb"
                    existing_size = 0

                content_len = resp.headers.get("Content-Length")
                total_expected = (
                    int(content_len) + existing_size if content_len else None
                )

                with open(target_zip_path, mode) as f:
                    downloaded = existing_size
                    last_print = time.time()
                    while True:
                        chunk = resp.read(1024 * 1024)  # 1MB chunk
                        if not chunk:
                            break
                        f.write(chunk)
                        downloaded += len(chunk)
                        if time.time() - last_print > 3:
                            last_print = time.time()
                            if total_expected:
                                pct = (downloaded / total_expected) * 100
                                print(
                                    f"Progress: {downloaded / (1024*1024):.1f} /"
                                    f" {total_expected / (1024*1024):.1f} MB ({pct:.1f}%)"
                                )
                            else:
                                print(f"Downloaded: {downloaded / (1024*1024):.1f} MB")

                print(
                    f"Download finished successfully! Total size: {os.path.getsize(target_zip_path)} bytes."
                )
                return True

        except Exception as e:
            print(f"Attempt {attempt} encountered error: {e}")
            time.sleep(3)

    return False


def main():
    token = get_gh_token()
    if not token:
        print("No gh token found!")
        sys.exit(1)

    artifact_id = "14107944593"
    print(f"Fetching download URL for artifact {artifact_id}...")
    direct_url = get_artifact_download_url(token, artifact_id)
    if not direct_url:
        print("Failed to get direct download URL!")
        sys.exit(1)

    out_dir = r"D:\RansomOS\out\siteos-iso"
    os.makedirs(out_dir, exist_ok=True)
    zip_path = r"D:\RansomOS\out\siteos-iso-temp.zip"

    ok = download_with_resume(direct_url, zip_path)
    if not ok:
        print("Download failed after maximum retries.")
        sys.exit(1)

    print(f"Extracting {zip_path} to {out_dir}...")
    with zipfile.ZipFile(zip_path, "r") as zf:
        zf.extractall(out_dir)

    try:
        os.remove(zip_path)
    except Exception:
        pass

    iso_src = os.path.join(out_dir, "SITEOS.iso")
    downloads_dir = os.path.expanduser(r"~\Downloads")
    if os.path.exists(iso_src) and os.path.isdir(downloads_dir):
        dest_iso = os.path.join(downloads_dir, "SITEOS.iso")
        print(f"Copying {iso_src} to {dest_iso}...")
        shutil.copy2(iso_src, dest_iso)

    print("ALL DONE SUCCESSFULLY!")


if __name__ == "__main__":
    main()
