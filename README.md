# omarchy-on-cachyos

- **UPDATE August 2026**: Full support for **Omarchy 4.0 (Quattro)** with Quickshell, enhanced Hyprland integration, and dedicated installer `install-omarchy-v4-on-cachyos.sh`.
- **UPDATE May 2026**: Interactive version selection added to choose between Omarchy v4.x, v3.x, and Bleeding Edge (`main`).
- **UPDATE October 2025**: Initial support for Omarchy 3.0+.

## 1. Introduction

This project provides an automated, non-destructive installer for running Basecamp/DHH's **Omarchy** (including **Omarchy 4.0 Quattro**) on top of **CachyOS**. Omarchy provides an opinionated, productive desktop setup based on Hyprland and Quickshell, while CachyOS delivers a performance-optimized Arch Linux distribution with custom x86-64-v3/v4 packages and tuned kernels.

## 2. What This Project Does and Does Not Do

### Features:
1. **Interactive Version Selection**: Choose between the latest **Omarchy 4.x (Quattro)** releases, legacy **Omarchy 3.x**, or bleeding-edge `main` branch.
2. **CachyOS Preservation**:
   - Preserves CachyOS CPU microarchitecture optimizations (`[cachyos-v3]`, `[cachyos-v4]`) and package mirrors.
   - Preserves `tealdeer` (Rust-based `tldr` implementation) without package conflicts.
   - Preserves the Fish shell as the default interactive shell while providing proper environment hooks for `mise` and Omarchy.
   - Protects existing bootloader and Snapper snapshot configs from being overwritten.
3. **Hardware Acceleration & NVIDIA Support**:
   - Automatically detects NVIDIA GPU architecture (Turing+ with open modules & GSP vs Maxwell/Pascal with proprietary drivers).
   - Preserves native CachyOS `chwd` driver packages without destructive removals or fragile profile hacks.
   - Installs `nvidia-vaapi-driver` and `libva-utils` and injects optimal Wayland/Hyprland environment variables for hardware decoding.

### What This Script Does NOT Do:
1. Install CachyOS itself (CachyOS must already be installed).
2. Repartition, reformat, or re-encrypt your drives.
3. Overwrite or destroy your display manager (SDDM / GDM).

---

## 3. Project Structure

```
bin/
├── fetch-omarchy.sh               # Interactive version selector and repository cloner
├── install-omarchy-v4-on-cachyos.sh # Dedicated installer for Omarchy 4.0 (Quattro)
├── install-omarchy-on-cachyos.sh    # Unified launcher (auto-dispatches to v4 or v3)
└── nvidia.sh                      # Safe NVIDIA & Wayland hardware acceleration setup
```

---

## 4. Pre-Requisites

1. **Operating System**: A fresh or existing installation of **CachyOS**.
2. **File System**: BTRFS with Snapper is recommended for full snapshot integration.
3. **Shell**: Fish (default in CachyOS) or Bash.
4. **Desktop / Display Manager**: Minimal install or CachyOS Hyprland with SDDM.

---

## 5. Installation Instructions

```bash
# 1. Clone this repository
git clone https://github.com/jeanmartins7/omarchy-on-cachyos.git

# 2. Navigate to the bin directory
cd omarchy-on-cachyos/bin

# 3. Make the scripts executable
chmod +x *.sh

# 4. Run the installer (interactive version selection)
./install-omarchy-on-cachyos.sh
```

> **Direct Omarchy 4.0 Installation**:
> You can also run the v4 installer directly:
> ```bash
> ./install-omarchy-v4-on-cachyos.sh
> ```

---

## 6. Hardware Video Acceleration Tips (NVIDIA Users)

### Chromium / Brave / Electron:
1. Add the following to `~/.config/chromium-flags.conf`:
   ```text
   --enable-features=VaapiOnNvidiaGPUs
   ```
2. In Chromium, install the [enhanced-h264ify extension](https://chromewebstore.google.com/detail/enhanced-h264ify/omkfmpieigblcllmkgbflkikinpkodlk) and disable **VP8** and **AV1** codecs if your GPU does not support hardware decoding for them.

### Firefox:
1. Add the following overrides to your `user.js` or `about:config`:
   ```javascript
   user_pref("media.hardware-video-decoding.force-enabled", true);
   user_pref("media.hardware-video-encoding.force-enabled", true);
   user_pref("layers.acceleration.force-enabled", true);
   user_pref("webgl.force-enabled", true);
   user_pref("media.ffmpeg.vaapi.enabled", true);
   user_pref("widget.dmabuf.force-enabled", true);
   ```

---

## 7. Statement of Lack of Warranty

THIS SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

Use this script at your own risk. Always backup your system and important data before running installation scripts.

---

## 8. Contributing

1. Fork the Repository
2. Create a Feature Branch (`git checkout -b feature/omarchy-v4-improvements`)
3. Commit Your Changes (`git commit -m "Enhance Omarchy 4.0 support"`)
4. Push to the Branch (`git push origin feature/omarchy-v4-improvements`)
5. Open a Pull Request
