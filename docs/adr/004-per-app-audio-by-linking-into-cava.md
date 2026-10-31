# 004 — Per-app audio by linking apps straight into CAVA

**Status:** accepted (supersedes the null-sink approach used in the first version)

## Context

To visualise only some apps, the first version created a PipeWire null sink, linked the selected apps into it in parallel with the speakers, and pointed CAVA at the sink's monitor. It worked, but the sink showed up as an extra output device ("Visualizador") in Plasma's sound menu, which confused users.

CAVA 1.0's PipeWire input has no option to stay unconnected. Given a target that doesn't exist, WirePlumber falls back and links it to the **default microphone**. Testing showed that WirePlumber does not re-create links that someone else removed.

## Decision

- Start CAVA with `method=pipewire`, `virtual=1` (no recording indicator) and a target named `nowplaying-viz-capture` that doesn't exist; the target is also how we find CAVA's node.
- While CAVA runs, link the selected apps' output ports into its input ports and delete every other link into it, the fallback microphone link included.
- With no apps selected, use `source=auto`, the default output.
- Unload a null sink left over by older versions at startup.

## Consequences

- No virtual device in the sound menu.
- For a fraction of a second after CAVA starts, before the first sync, it may hear the microphone. The helper syncs links 0.3 s after starting CAVA, and then every second.
- PipeWire is required; plain PulseAudio is not supported.
- Verified with a test tone played without a speaker connection: bars reached 1000 with the tone selected and stayed at 0 without it.
