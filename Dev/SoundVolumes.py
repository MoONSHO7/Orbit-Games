"""Build bundled 10–100% playback variants; --check validates them without writing.

Requires FFmpeg with libvorbis and ffprobe on PATH. Rebuilds are deterministic
with the same FFmpeg/libvorbis build; originals are never overwritten.
"""

import argparse
from array import array
import hashlib
import json
import math
from pathlib import Path
import shutil
import subprocess
import sys
from typing import NamedTuple


ROOT = Path(__file__).resolve().parents[1]
SOUNDS = ROOT / "Assets" / "Sounds"
OUTPUT = SOUNDS / "Playback"
CLIPS = ("dominating", "ownage", "rampage", "wicked-sick", "holyshit", "godlike")
LEVELS = range(10, 101, 10)
VORBIS_QUALITY = "3"
MAX_GAIN_ERROR = 0.04
MAX_DURATION_ERROR = 0.010
FADE_SECONDS = 0.120
PAD_SECONDS = 0.180
END_WINDOW_SECONDS = 0.001
MAX_END_PEAK_DB = -45
MAX_END_PEAK = 10 ** (MAX_END_PEAK_DB / 20)
FADE_END_WINDOW_SECONDS = 0.005
MAX_FADE_END_PEAK_DB = -60
MAX_FADE_END_PEAK = 10 ** (MAX_FADE_END_PEAK_DB / 20)
FFMPEG = ("ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-xerror")


class Audio(NamedTuple):
    rate: int
    channels: int
    frames: int
    rms: float
    end_peak: float
    fade_end_peak: float
    codec: str
    tags: dict

    @property
    def duration(self):
        return self.frames / self.rate


def run(*args):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise RuntimeError(result.stderr.decode("utf-8", errors="replace").strip())
    return result.stdout


def measure(path, fade_end_frame=None):
    probe = json.loads(run(
        "ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries",
        "stream=codec_name,sample_rate,channels:stream_tags:format_tags", "-of", "json", str(path),
    ))
    stream = probe["streams"][0]
    samples = array("f")
    samples.frombytes(run(
        *FFMPEG, "-flags:a", "+bitexact", "-i", str(path), "-map", "0:a:0",
        "-f", "f32le", "-c:a", "pcm_f32le", "-",
    ))
    if sys.byteorder != "little":
        samples.byteswap()
    rate, channels = int(stream["sample_rate"]), int(stream["channels"])
    if not samples or len(samples) % channels:
        raise RuntimeError(f"Missing or incomplete decoded audio: {path}")
    rms = math.sqrt(math.fsum(sample * sample for sample in samples) / len(samples))
    if not math.isfinite(rms) or rms == 0:
        raise RuntimeError(f"Silent or invalid decoded audio: {path}")
    end_sample_count = max(channels, math.ceil(rate * END_WINDOW_SECONDS) * channels)
    end_peak = max(abs(sample) for sample in samples[-end_sample_count:])
    fade_end_peak = 0
    if fade_end_frame is not None:
        fade_end_sample = min(len(samples), fade_end_frame * channels)
        fade_window_samples = max(channels, math.ceil(rate * FADE_END_WINDOW_SECONDS) * channels)
        fade_start_sample = max(0, fade_end_sample - fade_window_samples)
        fade_end_peak = max(abs(sample) for sample in samples[fade_start_sample:fade_end_sample])
    tags = probe.get("format", {}).get("tags", {}) | stream.get("tags", {})
    return Audio(
        rate,
        channels,
        len(samples) // channels,
        rms,
        end_peak,
        fade_end_peak,
        stream["codec_name"],
        tags,
    )


def encode(source, target, level, duration):
    fade_start = max(0, duration - FADE_SECONDS)
    run(
        *FFMPEG, "-flags:a", "+bitexact", "-i", str(source), "-map", "0:a:0",
        "-vn", "-sn", "-dn", "-map_metadata", "-1", "-map_metadata:s:a", "-1",
        "-map_chapters", "-1", "-af",
        f"volume={level / 100:.1f}:precision=double,"
        f"afade=t=out:st={fade_start:.9f}:d={FADE_SECONDS:.3f},apad=pad_dur={PAD_SECONDS:.3f}",
        "-c:a", "libvorbis", "-q:a", VORBIS_QUALITY, "-flags:a", "+bitexact",
        "-fflags", "+bitexact", "-serial_offset", "0", "-metadata:s:a:0", "encoder=",
        "-y", str(target),
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Check all 60 variants without rebuilding")
    args = parser.parse_args()
    for tool in ("ffmpeg", "ffprobe"):
        if not shutil.which(tool):
            parser.error(f"{tool} is required on PATH")
    if OUTPUT.resolve() != OUTPUT:
        raise RuntimeError(f"Output directory must not redirect elsewhere: {OUTPUT}")
    sources = [SOUNDS / f"{clip}.mp3" for clip in CLIPS]
    original_hashes = {path: hashlib.sha256(path.read_bytes()).hexdigest() for path in sources}
    originals = {source: measure(source) for source in sources}
    for source, original in originals.items():
        if original.codec != "mp3":
            raise RuntimeError(f"Expected an original MP3: {source}")
        if original.end_peak > MAX_END_PEAK:
            end_peak_db = 20 * math.log10(original.end_peak)
            raise RuntimeError(
                f"Abrupt audio endpoint: {source.name}: final {END_WINDOW_SECONDS * 1000:g}ms "
                f"peak is {end_peak_db:.2f} dBFS (maximum {MAX_END_PEAK_DB} dBFS)"
            )
    targets = [(source, level, OUTPUT / f"{source.stem}-{level}.ogg")
               for source in sources for level in LEVELS]
    for _, _, target in targets:
        if target.resolve().parent != OUTPUT or target.is_symlink():
            raise RuntimeError(f"Output must stay inside {OUTPUT}: {target}")
        if target.exists() and any(target.samefile(source) for source in sources):
            raise RuntimeError(f"Output must not alias an original: {target}")
    if not args.check:
        OUTPUT.mkdir(exist_ok=True)
        for source, level, target in targets:
            encode(source, target, level, originals[source].duration)

    size, maximum_gain_error, maximum_duration_error = 0, 0.0, 0.0
    for source in sources:
        original = originals[source]
        reference = measure(OUTPUT / f"{source.stem}-100.ogg", original.frames)
        reference_duration_error = abs(reference.duration - original.duration - PAD_SECONDS)
        if reference_duration_error > MAX_DURATION_ERROR:
            raise RuntimeError(
                f"Playback duration mismatch: {source.stem}-100.ogg: error={reference_duration_error:.6f}s"
            )
        ratios = []
        for _, level, target in (entry for entry in targets if entry[0] == source):
            audio = measure(target, original.frames)
            if audio.codec != "vorbis" or audio.tags or (audio.rate, audio.channels) != (original.rate, original.channels):
                raise RuntimeError(f"Unexpected codec, metadata, rate or channels: {target}")
            ratio = audio.rms / reference.rms
            gain_error = abs(ratio / (level / 100) - 1)
            duration_error = abs(audio.duration - reference.duration)
            if audio.end_peak > MAX_END_PEAK:
                raise RuntimeError(f"Abrupt playback endpoint: {target.name}")
            if audio.fade_end_peak > MAX_FADE_END_PEAK:
                fade_peak_db = 20 * math.log10(audio.fade_end_peak)
                raise RuntimeError(
                    f"Abrupt playback fade: {target.name}: final {FADE_END_WINDOW_SECONDS * 1000:g}ms "
                    f"before padding peaks at {fade_peak_db:.2f} dBFS (maximum {MAX_FADE_END_PEAK_DB} dBFS)"
                )
            if gain_error > MAX_GAIN_ERROR or duration_error > MAX_DURATION_ERROR:
                raise RuntimeError(
                    f"Audio mismatch: {target.name}: gain={ratio:.6f}, duration error={duration_error:.6f}s"
                )
            maximum_gain_error = max(maximum_gain_error, gain_error)
            maximum_duration_error = max(maximum_duration_error, duration_error)
            size += target.stat().st_size
            ratios.append(f"{level}%={ratio:.4f}")
        print(
            f"{source.stem}: {original.duration:.6f}s source + {PAD_SECONDS:.3f}s tail, "
            f"{original.rate} Hz, {original.channels} channel(s); " + ", ".join(ratios)
        )

    for source, expected in original_hashes.items():
        if hashlib.sha256(source.read_bytes()).hexdigest() != expected:
            raise RuntimeError(f"Original changed during validation: {source}")
    print(f"Checked {len(targets)} variants: {size:,} bytes; maximum relative RMS error {maximum_gain_error:.2%}; "
          f"maximum duration error {maximum_duration_error * 1000:.3f} ms. All six originals unchanged.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError) as error:
        raise SystemExit(str(error)) from error
