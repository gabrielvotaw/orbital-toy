"""Generates audio/space_ambient.ogg: a seamless ambient loop synthesized with ffmpeg.

Run from the project folder: python tools/make_music.py   (needs ffmpeg on PATH)

The loop stays seamless because every oscillator frequency is rounded to a whole number of cycles
per loop, every pattern repeats exactly once per loop, and the track is rendered twice with only the
second pass kept, so echo tails from the end of the loop are already present at its start.
"""

import subprocess
from pathlib import Path

LOOP_SECONDS = 96
CHORD_SECONDS = 24
FADE_SECONDS = 8
BELL_SECONDS = 6
SAMPLE_RATE = 44100
VOLUME = 0.1

CHORDS = [
    [146.83, 220.00, 329.63, 349.23],  # D minor (add 9)
    [116.54, 174.61, 293.66, 440.00],  # B-flat major 7
    [174.61, 261.63, 329.63, 440.00],  # F major 7
    [98.00, 146.83, 261.63, 392.00],   # G sus / C
]
DRONE = 73.42
# One slot per BELL_SECONDS; 0 means silence. D minor pentatonic.
BELLS = [587.33, 0, 880.00, 0, 0, 698.46, 0, 0, 1046.50, 0, 783.99, 0, 0, 0, 1174.66, 0]


def loopable(frequency: float) -> float:
    return round(frequency * LOOP_SECONDS) / LOOP_SECONDS


def sine(frequency: float) -> str:
    return f"sin(2*PI*{loopable(frequency):.6f}*t)"


def chord_envelope(index: int) -> str:
    start = index * CHORD_SECONDS
    x = f"mod(t-{start}+{LOOP_SECONDS},{LOOP_SECONDS})"
    rise = f"(0.5-0.5*cos(PI*clip({x}/{FADE_SECONDS},0,1)))"
    fall = f"(0.5+0.5*cos(PI*clip(({x}-{CHORD_SECONDS})/{FADE_SECONDS},0,1)))"
    return f"{rise}*{fall}"


def pad(detune: float) -> str:
    chords = []
    for index, notes in enumerate(CHORDS):
        voices = [f"({sine(f)}+0.8*{sine(f * detune)}+0.15*{sine(2 * f)})" for f in notes]
        chords.append(f"{chord_envelope(index)}*({'+'.join(voices)})")
    return "+".join(chords)


def bells() -> str:
    x = f"mod(t,{BELL_SECONDS})"
    slot = f"mod(floor(t/{BELL_SECONDS}),{len(BELLS)})"
    frequency = "0"
    for index in reversed(range(len(BELLS))):
        frequency = f"if(eq({slot},{index}),{BELLS[index]},{frequency})"
    tone = f"(sin(2*PI*{frequency}*{x})+0.25*sin(2*PI*2.76*{frequency}*{x}))"
    return f"gt({frequency},0)*(1-exp(-30*{x}))*exp(-1.1*{x})*{tone}"


def channel(detune: float, bell_level: float) -> str:
    drone = f"0.5*(0.75+0.25*{sine(1 / 48)})*{sine(DRONE)}"
    return f"{VOLUME}*({pad(detune)}+{drone}+{bell_level}*{bells()})"


def main() -> None:
    output = Path("audio/space_ambient.ogg")
    output.parent.mkdir(exist_ok=True)
    expression = f"{channel(1.003, 1.6)}|{channel(0.997, 1.2)}"
    graph = (
        f"aevalsrc='{expression}':s={SAMPLE_RATE}:d={2 * LOOP_SECONDS},"
        "lowpass=f=5000,"
        "aecho=0.8:0.6:700|1300|2100:0.3|0.22|0.15,"
        f"atrim=start={LOOP_SECONDS}:end={2 * LOOP_SECONDS},asetpts=PTS-STARTPTS"
    )
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-f", "lavfi", "-i", graph,
         "-c:a", "libvorbis", "-q:a", "4", str(output)],
        check=True,
    )
    print(f"wrote {output}")


if __name__ == "__main__":
    main()
