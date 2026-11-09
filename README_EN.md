# HP LaserJet 1020 on macOS

Get the **HP LaserJet 1020 / 1020 Plus** printing on modern macOS — Apple Silicon and Intel.

Verified on macOS 26 with an M-series Mac.

```
PDF ──► Ghostscript ──► pbmraw ──► foo2zjs ──► ZJS ──► USB ──► printer
```

> [中文文档](README.md)

---

## Why this exists

The HP LaserJet 1020 is a **host-based (GDI) printer**:

- No resident firmware, no page description language, only a small RAM buffer
- All rendering happens on the host CPU
- **After every power cycle or USB re-plug, the host must upload the printer's runtime firmware into its RAM** before it can print anything

HP stopped shipping macOS drivers for it long ago. Apple's HP Printer Drivers package was last updated in 2015 and its installer refuses to run on recent macOS. Meanwhile, the firmware files circulating in blog posts and repos are mostly **the wrong build** — which is why you get a job that "completes successfully" while the printer sits there silently.

This project's main contribution is documenting that firmware trap clearly, plus shipping a pipeline that actually works.

---

## Quick start

```bash
git clone https://github.com/1745761934/hp1020-macos.git
cd hp1020-macos

./fetch-vendor.sh    # get Ghostscript + foo2zjs
./install.sh         # install to /usr/local

hp1020-print document.pdf
```

Make sure the printer is powered on and connected over USB first.

---

## The firmware is the whole problem

This is the part worth reading.

### The correct firmware

| Property | Value |
|---|---|
| File | `fw/sihp1020.dl` |
| Size | **128999** bytes |
| md5 | **`0cd1ac3a4f6cb7995e99deffff840927`** |
| Format | ACL/PJL |
| First bytes | `1b 25 2d 31 32 33 34 35 58` = `\x1b%-12345X@PJL ENTER LANGUAGE=ACL` |
| Reported version | **`FWVER:20080222`** |

### Three wrong formats that "succeed" but never work

| Mistake | Symptom |
|---|---|
| Sending a **bare ELF** (`\x7fELF`, e.g. Apple's `hp1020.acl`) | Printer accepts the bytes, returns success, even echoes a version — but the firmware **never executes**. Nothing prints. |
| Wrapping a bare ELF with `arm2hpdl`, producing a `\xbe\xef` ("beef") header | Same |
| Using an older `.dl` build (md5 `dea9e815` / 128431 B, or `86403c3b` / 126151 B) | Version echoes back, but rendering fails — blank pages |

### The `arm2hpdl` trap

`arm2hpdl` has **two completely different output paths** depending on the input's first bytes:

| Input starts with | `arm2hpdl` emits | Works on LJ 1020 |
|---|---|---|
| `\x7fELF` (bare ARM/Linux ELF) | `\xbe\xef` HP download header ("beef") | **No** |
| ASCII `20...` (HP *raw* image, e.g. `sihp1020.img`) | ACL/PJL envelope | **Yes** |
| `\xbe\xef` (already "beef") | passed through unchanged | **No** |

Feed it a bare ELF and upload the result, and the printer **accepts the bytes and reports success but never runs** — no FWVER, no output. This is the single most confusing failure mode for this model.

Do one of these instead:

- Use HPLIP's `hp_laserjet_1020.fw.gz` (already ACL/PJL, no conversion needed)
- Or fetch HP's raw image with `foo2zjs`'s `getweb`, then run `arm2hpdl` on *that*
- **Never hand-wrap a bare ELF**

### Inspect a firmware file

Don't judge by eye — the repo ships a format checker:

```bash
./scripts/hp1020-fwinspect fw/sihp1020.dl
```

```
  文件:   fw/sihp1020.dl
  大小:   128999 字节
  md5:    0cd1ac3a4f6cb7995e99deffff840927
  格式:   ACL/PJL
  FWVER:  20080822
  ELF:    ELF32 BE ARM(HP custom) EXEC @ offset 50
  判定:   ✓ GOOD
```

Scan a directory:

```bash
./scripts/hp1020-fwinspect --all ~/Downloads
```

Machine-readable:

```bash
./scripts/hp1020-fwinspect --json fw/sihp1020.dl
```

Exit codes: `0` good / `1` wrong format / `2` missing file.

Recognized formats:

| Marker | Meaning | Usable |
|---|---|---|
| `ACL/PJL` | wrapped with `@PJL ENTER LANGUAGE=ACL` | depends on build |
| `BARE_ELF` | raw ELF, no envelope | ✗ |
| `DATE+ELF` | date string then ELF (Apple's `.acl`) | ✗ |
| `BEEF` | `arm2hpdl` beef header | ✗ |
| `HP_RAW_IMAGE` | HP raw image, needs `arm2hpdl` | → |
| `ARM2HPDL_WRAPPED` | intermediate `arm2hpdl` wrapper | ✗ |

`hp1020-print` runs this check before pushing firmware and **refuses to send a wrong format** — a bad push can wedge the printer's USB controller and require a power cycle to recover.

### Version reference

| FWVER | Verdict |
|---|---|
| `20080222` | ✅ correct |
| `20050309` | ❌ old, renders blank |
| `20041129` | ❌ older |
| no FWVER | ❌ not loaded |

**A reported FWVER does not mean the firmware is running.** Only `20080222` is known-good.

---

## Usage

```bash
hp1020-print document.pdf          # auto-skips blank pages
hp1020-print document.pdf 1        # page 1 only
hp1020-print document.pdf 1-3      # pages 1-3
hp1020-print --status              # printer state
hp1020-print --firmware            # push firmware only
hp1020-print --pages document.pdf  # show which pages have content
hp1020-print --check               # verify dependencies
hp1020-print --inspect             # inspect firmware file format
```

`--pages` uses Ghostscript's bbox to detect ink extents, so trailing blank pages in scanned documents get skipped automatically.

---

## Technical details

### Pipeline parameters

```
gs -sDEVICE=pbmraw -r1200x600 -sPAPERSIZE=a4
foo2zjs -r1200x600 -p9 -P -z1 -L0
```

- `-r1200x600` — engine resolution (1200 dpi horizontal, 600 dpi vertical)
- `-p9` — A4 (use `-p1` for Letter)
- `-P` — emit PJL job header
- `-z1` — ZJS mode

### USB layer

`bin/hp1020_usb` is a small IOKit tool: uploads firmware, sends raw ZJS streams.

```bash
./bin/hp1020_usb --info            # device ID + firmware state
./bin/hp1020_usb fw/sihp1020.dl    # upload firmware
./bin/hp1020_usb --send job.zjs    # raw send
```

Implementation notes (learned the hard way):

- Enumerate `IOUSBHostInterface` services, then filter on registry `idVendor`/`idProduct`
- **You cannot** filter via an `IOServiceMatching` dictionary — parent properties do not propagate to interface nodes
- `GetPipeProperties` takes `UInt16*`; passing `UInt8*` causes a bus error
- `GetPipeProperties` returning `0xe00002cd` is normal; the interface still works
- `Got USB return aborted during read` is normal in the bare boot state

Rebuild:

```bash
clang -O2 -framework Foundation -framework IOKit -framework CoreFoundation \
      -o bin/hp1020_usb src/hp1020_usb.m
```

The shipped binary is universal (arm64 + x86_64).

---

## Troubleshooting

### Printer totally silent, no motor sound

Firmware isn't running. Check `--status` reports `FWVER:20080222`.

### Device vanished from USB

```bash
ioreg -p IOUSB -w0 | grep -i laserjet   # nothing
```

Kernel log shows:

```
IOUSBHostDevice::getDescriptorGated: standard request timed out after 5000ms
failed to get device descriptor
IOUSBHostPort::disconnect: persistent enumeration failures
```

**Cause**: wrong firmware format (especially a bare ELF) pushed the printer's USB controller into a bad state. The port is flagged for persistent enumeration failure and won't retry. Not recoverable in software.

**Fix**: **unplug the power cable** (not the USB cable), wait 60 s, plug power back in and let it self-test for 30 s, then reconnect USB. Rebooting macOS also works.

### Prints but the page is blank

Wrong firmware build, or wrong resolution. Verify the md5 and `-r1200x600`.

### `USBInterfaceOpen: 0xe00002c5 (device busy?)`

Something holds the device — usually a CUPS backend. `sudo killall -9 cupsd`, then retry.

---

## Relationship to CUPS

This project deliberately **bypasses the CUPS queue** and writes straight to USB.

Under CUPS, a filter racing firmware loading can wedge the USB channel (`device busy`), and the error gets buried in logs. Direct sending is far easier to reason about.

---

## Credits

- [foo2zjs](https://github.com/OpenPrinting/foo2zjs) — ZJS encoder (GPL v2)
- [Ghostscript](https://www.ghostscript.com/) — PDF/PS rendering (AGPL v3)
- [Orthodox2000/hp-laserjet-1020-linux](https://github.com/Orthodox2000/hp-laserjet-1020-linux) — authoritative writeup of the firmware format trap; the checksums here come from it
- [anxkhn/hp1020-driver-mac](https://github.com/anxkhn/hp1020-driver-mac) — packaging of Apple's official filter components

## License

Code is MIT. `fw/sihp1020.dl` is HP proprietary firmware, redistributed for interoperability.
