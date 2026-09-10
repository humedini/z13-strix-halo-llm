# 02. Base install and the community setup script

## The starting point

The community install script for this hardware is [th3cavalry/strix-halo-linux-setup](https://github.com/th3cavalry/strix-halo-linux-setup) (previously `GZ302-Linux-Setup`). This build used v6.8.0, commit `4a05828`, from 2026-07-05. It is the right place to start and it did most of the work: hardware fixes, the z13ctl control layer, Ollama, llama.cpp and Open WebUI.

It is also a `curl | sudo bash` style installer that downloads library files at runtime, so the first thing done was to fetch the whole repository as a tarball, read all of it, and run it from disk. Everything below came from that reading and from watching it fail.

**On kernel 7.0 its hardware fixes section is almost entirely a no-op.** Its `kernel-compat.sh` gates every workaround on kernel versions below 6.17 or 6.19, and this machine is past all of them. That is expected and correct: the fixes exist for older kernels.

## The four bugs

Four genuine bugs were found in the LLM module (`modules/llm.sh`). All four are in `patches/llm.sh.patch`. The upstream project may have fixed some or all of them since; check before assuming.

### 1. Module filename mismatch aborts the whole installer

The main script calls `download_and_execute_module "gz302-gaming"`, `"gz302-llm"` and `"gz302-hypervisor"`. It looks for `modules/gz302-gaming.sh` locally and, failing that, downloads from `GITHUB_RAW_URL`. But the repository ships `modules/gaming.sh`, `llm.sh` and `hypervisor.sh`, and `GITHUB_RAW_URL` still points at the pre rename repository path where the `gz302-` names return 404.

The download produces an empty file, the function returns 1, and the main script runs under `set -euo pipefail`, so **the entire installer aborts at section 3**. Sections 4 and 5, which are the ones you wanted, never run.

Workaround: symlink `modules/gz302-llm.sh -> llm.sh` and the same for the other two, so the local lookup succeeds and no network fetch happens.

### 2. `get_rocm_version()` kills the script once ROCm is installed

```bash
get_rocm_version() {
    if command -v rocminfo &>/dev/null; then
        rocminfo 2>/dev/null | grep -oP 'ROCm Runtime Version: \K[0-9.]+' | head -1
```

Ubuntu's `rocminfo` never prints a `ROCm Runtime Version:` line. The grep exits 1 with no match, `pipefail` propagates that through the pipeline, and the caller's `version=$(get_rocm_version)` assignment dies under `set -e`.

This only triggers once `rocminfo` exists. Before that, `command -v rocminfo` fails and the function falls through to `echo "unknown"` with exit 0. So **installing ROCm is what exposes it**, which is a confusing thing to debug.

Patched with `|| true` guards and a `dpkg-query` fallback that returns the real version.

### 3. Wrong `HSA_OVERRIDE_GFX_VERSION`, in two places

The module gates "native gfx1151 support" on ROCm version 7.2 or newer. Ubuntu 26.04 ships 7.1.1, so the check fails and it writes:

```
export HSA_OVERRIDE_GFX_VERSION=11.0.0
```

That forces gfx1100 (discrete RDNA3) kernels onto gfx1151 hardware. It lands in both `/etc/profile.d/strix-halo-rocm.sh` **and** the Ollama systemd drop-in, so it affects the daemon and not just interactive shells.

Modern ROCm supports gfx1151 natively. `rocminfo` enumerates `amdgcn-amd-amdhsa--gfx1151` directly, and Ollama's own log shows it detecting `compute=gfx1151` with the override absent. The override is not merely unnecessary; it is wrong.

Patched so detection asks the runtime whether it enumerates a gfx1151 agent, rather than comparing version strings. Script `03-postfix.sh` also strips it from both files after the fact.

### 4. llama.cpp is not installable as shipped

The resolver reads `https://api.github.com/repos/ggerganov/llama.cpp/releases/latest`. That repository now redirects to `ggml-org/llama.cpp`, and its `releases/latest` returns a semver tag (`v0.4.0` at the time) carrying **no binary assets**. Prebuilt binaries only ship in the `bNNNN` build releases. The hardcoded fallback of `b8043` is thousands of builds stale.

Patched to list recent releases from `ggml-org/llama.cpp` and select the newest `bNNNN` tag, then verify the Vulkan x64 asset exists before downloading.

### Also: every installer call was fatal

All 21 backend and frontend install functions were invoked bare inside `case` branches. Under `set -euo pipefail`, one failed optional component aborted every component selected after it. Each call now carries `|| true`, so a failed llama.cpp download no longer prevents Ollama from installing.

## The security defaults, which you should change

The installer, as shipped, does two things you should be aware of on a portable machine:

- Sets `OLLAMA_HOST=0.0.0.0`, binding an **unauthenticated** inference API to every interface
- Deploys Open WebUI with `-p 3000:8080`, on every interface, where **the first visitor becomes the admin account**

On a desktop behind a home router that is merely untidy. On a tablet that joins café and hotel networks, it is an open API and an unclaimed admin panel exposed to whoever is on the same Wi-Fi.

This build moved both to loopback and published them over Tailscale only. See [remote access](09-remote-access.md). If you use the installer, do the same, and claim the Open WebUI admin account immediately.

## Prerequisites the installer assumes

`git` and `build-essential` are not installed on a fresh Ubuntu 26.04 desktop. The installer expects them. Script `01-prep.sh` installs those plus `mesa-utils`, `vulkan-tools` and `lm-sensors` for verification, and `rocminfo` from the archive.

Note that installing `rocminfo` is what triggers bug 2 above. Apply the patch first.

## What actually landed

After patching and running with `--no-fixes --no-z13ctl --no-tools` to resume past the abort:

- Section 1 (hardware fixes): no-ops on kernel 7.0, as expected
- Section 2 (command center): z13ctl 1.3.2, `pwrcfg`, tray config
- Section 3 (gaming): partial. `steam-installer` succeeded, then the module's second `apt-get install` failed. Steam and GameMode present; Lutris, MangoHUD and Wine not.
- Section 4 (AI): Ollama, llama.cpp Vulkan build, Open WebUI in Docker

## Running it yourself

```bash
curl -sL https://github.com/th3cavalry/strix-halo-linux-setup/archive/refs/heads/main.tar.gz -o shs.tar.gz
mkdir shs && tar xzf shs.tar.gz -C shs --strip-components=1
cd shs
# read it
patch -p0 < /path/to/patches/llm.sh.patch     # may need adjusting if upstream has moved
ln -sf gaming.sh modules/gz302-gaming.sh
ln -sf llm.sh modules/gz302-llm.sh
ln -sf hypervisor.sh modules/gz302-hypervisor.sh
sudo ./strix-halo-setup.sh
```

Say yes to sections 1, 2 and 4. Run the AI section before the gaming section; if gaming fails it aborts everything after it, and the AI stack is the part you actually want.
