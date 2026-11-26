#!/usr/bin/env bash
# Optional: render the opening-story narration to OGG files with Piper (offline neural TTS),
# so the narrator sounds identical on Linux and Windows. Without these files the game falls
# back to the operating system's own text-to-speech voice.
#
#   1. Install Piper (https://github.com/rhasspy/piper) and download a voice, e.g. en_GB-alan-medium.
#   2. ./tools/make_narration.sh /path/to/piper /path/to/en_GB-alan-medium.onnx
#   3. Re-export the game (./build.sh).
set -euo pipefail
PIPER=${1:?path to piper binary}
VOICE=${2:?path to .onnx voice}
cd "$(dirname "$0")/.."
OUT=assets/voice
mkdir -p "$OUT"
python3 - "$OUT" <<'PY' | while IFS=$'\t' read -r idx text; do
import re, sys
src = open("scripts/story.gd", encoding="utf-8").read()
block = src[src.index("const SLIDES"):src.index("]\n]") + 3]
for i, (title, body) in enumerate(re.findall(r'\["(.*?)", "(.*?)"\]', block), 1):
    text = f"{title.capitalize()}. {body}".replace("₹25", "25 rupees")
    print(f"{i}\t{text}")
PY
	echo "$text" | "$PIPER" -m "$VOICE" -f "$OUT/story_$idx.wav"
	ffmpeg -loglevel error -y -i "$OUT/story_$idx.wav" -c:a libvorbis -q:a 5 "$OUT/story_$idx.ogg"
	rm "$OUT/story_$idx.wav"
	echo "wrote $OUT/story_$idx.ogg"
done
