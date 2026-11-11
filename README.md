# Chapterize

Drop a `.srt` subtitles file on the window (or the Dock icon, or File › Open…) and get a YouTube chapter list back:

```
Contents:

00:00 - ALL the KVMs
01:59 - Caution
02:33 - PiKVM
```

Videos an hour or longer get `00:00:00`-style timestamps. YouTube's rules are enforced: first chapter at 0:00, chapters in order, each at least 10 seconds long. The app warns you if it ends up with fewer than 3 chapters.

## Build

Requires macOS 26 and Xcode 26 (or its Command Line Tools). No Xcode project.

```sh
./build.sh            # -> build/Chapterize.app
./build.sh --run      # build and launch
./build.sh --install  # build and copy to /Applications
```

## Models

**Automatic** (the default) uses Apple Intelligence if it's on, and falls back to Ollama if it isn't. You can pick one in Settings (⌘,).

| | Apple Intelligence | Ollama + `qwen3:8b` |
|---|---|---|
| Setup | none (already on the Mac) | `brew install ollama && ollama pull qwen3:8b` |
| RAM | managed by macOS | ~5 GB model + ~2 GB for 16K context |
| Context | 4K tokens: transcript is split into ~1,300-word parts, then a polish pass merges them | whole ~30 min transcript in one pass |
| Titles | decent | noticeably better |

Any Ollama model works. The Settings window lists the ones you've already pulled. `gemma3:4b` is lighter and faster if you have less memory to spare. The Ollama server URL is configurable, so you can point it at another machine.

**OpenAI-compatible server:** point Chapterize at anything that speaks `/v1/chat/completions` (vLLM, llama.cpp, LM Studio, MLX, OpenAI). Set the base URL (e.g. `http://turnstone.local:8000/v1`), an optional API key, and the model (Refresh lists what the server has). Set *Context* to the server's max context length so long transcripts are only split when they need to be. `<think>` blocks are stripped from replies.

## Tuning

- **Settings › Title style examples:** a few of your real chapter titles, so the model picks up your voice. The defaults are 30 titles from 2025 videos; Reset in Settings restores them.
- **CLI for prompt iteration:** batch-run a folder of SRTs. If a same-named `.txt` sits next to an `.srt`, it gets printed alongside for comparison.

  ```sh
  swift run chapterize-cli ~/Videos/*.srt
  swift run chapterize-cli --ollama qwen3:8b "IP KVMs.srt"
  OPENAI_API_KEY=… CONTEXT_TOKENS=32768 swift run chapterize-cli --openai http://turnstone.local:8000/v1 my-model *.srt
  ```

- **Seed the style examples from past videos:** `scripts/extract-chapters.py <folder> --sample 30` pulls chapter titles from every `.md` file's `## YouTube Description` section and prints a random mix (at most 2 per video) to paste into Settings. Leave off `--sample` to list every title. Keep it to about 30 titles for Apple Intelligence; larger-context models can take more.
- The prompts are in `Sources/ChapterCore/Prompts.swift`.

## How it works

1. Parse the SRT, then merge cues into sentence-aligned segments of 5–15 seconds. Each segment start is a timestamp the model can pick.
2. Send the transcript to the model as `[MM:SS] text` lines (in parts if it's too long for the model's context window). The model replies with `MM:SS - Title` lines.
3. Snap each returned timestamp to the nearest real segment start, so the model can't invent timestamps.
4. If the transcript was split into parts, run one more pass to dedupe chapters and make the titles consistent.
5. Apply YouTube's rules and render the list.

## Icon

`Resources/AppIcon.svg` is the source. After editing it, regenerate the iconset:

```sh
for s in 16 32 128 256 512; do
  rsvg-convert -w $s -h $s Resources/AppIcon.svg -o Resources/AppIcon.iconset/icon_${s}x${s}.png
  rsvg-convert -w $((s*2)) -h $((s*2)) Resources/AppIcon.svg -o Resources/AppIcon.iconset/icon_${s}x${s}@2x.png
done
```

(`brew install librsvg` for `rsvg-convert`.)

## AI Disclosure

This project was built with heavy assistance from Claude Opus in 2026.
