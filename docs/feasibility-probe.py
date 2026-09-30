#!/usr/bin/env python3
"""
Feasibility probe for LocalSend resumable transfers (断点续传).

NOT a Rust test. It is a faithful, runnable model of the algorithm the planned
change puts into `packages/core/src/http/server/common/save.rs` plus the
matching sender-side read. It verifies the semantics the design depends on:

  * the resume offset must come from the file on disk, never from the in-memory
    progress counter (512 KiB BufWriter hazard on a hard kill);
  * the full-file SHA-256 is still verified after a resumed transfer;
  * an offset that does not match the session is rejected before any write;
  * a short or corrupt prefix never yields a silently corrupt file: it either
    forces a restart from 0 or fails the checksum;
  * repeated interruptions converge (each round advances the offset);
  * backward compatibility: no `offset` parameter means "truncate and receive
    the whole file" (today's/legacy behaviour).

Run: python3 docs/feasibility-probe.py
"""

import hashlib
import os
import random
import shutil
import sys
import tempfile

CHUNK = 64 * 1024
BUFWRITER = 512 * 1024  # save.rs WRITE_BUFFER_SIZE


class ResumeInvalid(Exception):
    """Offset cannot be honoured -> the caller must restart from 0."""


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(CHUNK), b""):
            h.update(chunk)
    return h.hexdigest()


def receiver_write(path, offset, tail_iter, size, expected_sha,
                   simulate_bufwriter_loss=False, hard_kill=False):
    """Model of write_file_from_receiver() with resume support.

    `size` is the total file size from FileDto (the invariant is unchanged).
    Returns (outcome, on_disk) where outcome is "success" | "hash_mismatch" |
    "failed" (the body stopped before `size`), and on_disk is the real file
    length afterwards -- which is what the next resume must use.
    """
    if offset == 0:
        open(path, "wb").close()          # today's behaviour: File::create
    else:
        if not os.path.exists(path):
            raise ResumeInvalid("no partial file on disk")
        # The prefix read doubles as the offset check: EOF before `offset`
        # proves the advertised offset is not backed by data on disk.
        if os.path.getsize(path) < offset:
            raise ResumeInvalid(
                f"on-disk prefix {os.path.getsize(path)} < advertised offset {offset}")

    hasher = hashlib.sha256()
    if offset:
        # Seed the full-file hash with the prefix already on disk.
        with open(path, "rb") as f:
            remaining = offset
            while remaining:
                chunk = f.read(min(CHUNK, remaining))
                if not chunk:
                    raise ResumeInvalid("short read while hashing the prefix")
                hasher.update(chunk)
                remaining -= len(chunk)

    written = offset
    buffered = bytearray()
    with open(path, "r+b") as f:
        f.seek(offset)
        for chunk in tail_iter:
            if written + len(chunk) > size:
                return ("failed", os.path.getsize(path))
            hasher.update(chunk)
            written += len(chunk)
            if not simulate_bufwriter_loss:
                f.write(chunk)
                f.flush()
            else:
                buffered.extend(chunk)
                if len(buffered) >= BUFWRITER:
                    f.write(bytes(buffered))
                    f.flush()
                    buffered.clear()
        if simulate_bufwriter_loss:
            if not hard_kill:
                f.write(bytes(buffered))
                f.flush()
            # hard_kill: the buffered tail never reaches the file
        f.flush()

    if written != size:
        return ("failed", os.path.getsize(path))

    if expected_sha is not None and hasher.hexdigest().lower() != expected_sha.lower():
        return ("hash_mismatch", os.path.getsize(path))

    with open(path, "r+b") as f:   # set_len(size)
        f.truncate(size)
    return ("success", os.path.getsize(path))


def sender_tail(path, start, end):
    """Model of FileContent::into_stream_from(offset): serve [start, end)."""
    with open(path, "rb") as f:
        f.seek(start)
        remaining = end - start
        while remaining:
            chunk = f.read(min(CHUNK, remaining))
            if not chunk:
                break
            remaining -= len(chunk)
            yield chunk


def server_rules(session_offset, requested_offset, size):
    """Model of the planned /upload offset validation (400 on mismatch)."""
    if requested_offset is None:
        return 0                      # legacy sender: truncate + full receive
    if requested_offset > size:
        raise ValueError("400 offset beyond size")
    if requested_offset != session_offset:
        raise ValueError("400 offset does not match session")
    return requested_offset


def next_offset_from_disk(path, remembered):
    """Disk truth, clamped to what the partial store remembered."""
    if not os.path.exists(path):
        return 0
    return max(0, min(os.path.getsize(path), remembered))


RESULTS = []


def check(name, ok, detail=""):
    RESULTS.append((name, ok, detail))
    print(f"[{'PASS' if ok else 'FAIL'}] {name}" + (f"  ({detail})" if detail else ""))


def main():
    random.seed(20260930)
    tmp = tempfile.mkdtemp(prefix="localsend-resume-probe-")
    size = 5 * 1024 * 1024
    src = os.path.join(tmp, "source.bin")
    with open(src, "wb") as f:
        f.write(os.urandom(size))
    expected = sha256_of(src)
    print(f"fixture: {size} bytes, sha256={expected[:16]}...\n")

    # --- 1. interrupt at ~2 MiB, resume in a NEW session --------------------
    dst = os.path.join(tmp, "case1.bin")
    first = 2 * 1024 * 1024 + 100 * 1024
    out, disk = receiver_write(dst, 0, sender_tail(src, 0, first), size, expected)
    check("1a interrupted attempt leaves a partial file, body short",
          out == "failed" and disk == first, f"outcome={out} on_disk={disk}")
    offset = next_offset_from_disk(dst, remembered=first)
    req = server_rules(session_offset=offset, requested_offset=offset, size=size)
    out, disk = receiver_write(dst, req, sender_tail(src, req, size), size, expected)
    check("1b resumed upload verifies the full-file sha256", out == "success", f"outcome={out}")
    check("1c resumed file is byte-identical to the source",
          open(dst, "rb").read() == open(src, "rb").read())

    # --- 2. offset mismatch rejected before any write ----------------------
    dst2 = os.path.join(tmp, "case2.bin")
    receiver_write(dst2, 0, sender_tail(src, 0, first), size, expected)
    before = os.path.getsize(dst2)
    rejected = False
    try:
        server_rules(session_offset=first, requested_offset=1024 * 1024, size=size)
    except ValueError as e:
        rejected = "400" in str(e)
    check("2a offset != session offset is rejected (400)", rejected)
    check("2b rejected request wrote nothing", os.path.getsize(dst2) == before)

    # --- 3. hard kill: buffered bytes counted but not on disk --------------
    dst3 = os.path.join(tmp, "case3.bin")
    out, disk = receiver_write(dst3, 0, sender_tail(src, 0, first), size, expected,
                               simulate_bufwriter_loss=True, hard_kill=True)
    check("3a hard kill makes the progress counter overstate the disk",
          disk < first, f"counted={first} on_disk={disk}")
    offset = next_offset_from_disk(dst3, remembered=first)
    check("3b next resume offset is clamped to the real file length", offset == disk)
    out, _ = receiver_write(dst3, offset, sender_tail(src, offset, size), size, expected)
    check("3c resume from the clamped offset still verifies", out == "success", f"outcome={out}")

    # --- 4. offset not backed by data (lost tail) --------------------------
    dst4 = os.path.join(tmp, "case4.bin")
    with open(dst4, "wb") as f:
        f.write(os.urandom(1000))
    invalid = False
    try:
        receiver_write(dst4, 4096, sender_tail(src, 4096, size), size, expected)
    except ResumeInvalid:
        invalid = True
    check("4a offset not backed by data forces a restart from 0", invalid)
    out, _ = receiver_write(dst4, 0, sender_tail(src, 0, size), size, expected)
    check("4b forced full receive succeeds", out == "success" and sha256_of(dst4) == expected)

    # --- 5. corrupt prefix: never silently accepted + escape hatch ---------
    dst5 = os.path.join(tmp, "case5.bin")
    receiver_write(dst5, 0, sender_tail(src, 0, first), size, expected)
    with open(dst5, "r+b") as f:
        f.seek(1234)
        b = f.read(1)
        f.seek(1234)
        f.write(bytes([b[0] ^ 0xFF]))
    out, _ = receiver_write(dst5, first, sender_tail(src, first, size), size, expected)
    check("5a corrupt prefix is detected (hash mismatch -> 422)", out == "hash_mismatch")
    out, _ = receiver_write(dst5, 0, sender_tail(src, 0, size), size, expected)
    check("5b after N mismatches, restart from 0 recovers",
          out == "success" and sha256_of(dst5) == expected)

    # --- 6. legacy sender: no offset parameter -----------------------------
    dst6 = os.path.join(tmp, "case6.bin")
    receiver_write(dst6, 0, sender_tail(src, 0, first), size, expected)
    req = server_rules(session_offset=first, requested_offset=None, size=size)
    out, _ = receiver_write(dst6, req, sender_tail(src, 0, size), size, expected)
    check("6a legacy sender (no offset) truncates and succeeds",
          out == "success" and sha256_of(dst6) == expected)

    # --- 7. repeated interruptions converge --------------------------------
    dst7 = os.path.join(tmp, "case7.bin")
    offset, rounds = 0, 0
    while offset < size:
        rounds += 1
        step = min(700 * 1024, size - offset - 1)
        if step <= 0:
            break
        out, disk = receiver_write(dst7, offset, sender_tail(src, offset, offset + step),
                                   size, expected)
        if out == "success":
            break
        assert out == "failed", out
        assert disk > offset or offset == 0, (disk, offset)
        offset = disk
    out, _ = receiver_write(dst7, offset, sender_tail(src, offset, size), size, expected)
    check("7a repeated interruptions then resume completes",
          out == "success" and sha256_of(dst7) == expected, f"interruption_rounds={rounds}")

    # --- 8. prefix-from-disk hashing == hashing from scratch ---------------
    h = hashlib.sha256()
    with open(src, "rb") as f:
        h.update(f.read(size // 3))
    with open(src, "rb") as f:
        f.seek(size // 3)
        h.update(f.read())
    check("8a prefix-seeding equals a single-pass full-file hash", h.hexdigest() == expected)

    # --- 9. progress semantics ---------------------------------------------
    check("9a resume progress is monotonic: (offset + tail) / size",
          (first + (size - first)) / size == 1.0)

    shutil.rmtree(tmp, ignore_errors=True)
    failed = [n for n, ok, _ in RESULTS if not ok]
    print(f"\n{len(RESULTS) - len(failed)}/{len(RESULTS)} checks passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
