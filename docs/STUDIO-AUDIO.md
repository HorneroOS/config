# Studio audio policy

Portable PipeWire/WirePlumber policy for HorneroOS Studio. The mode
semantics are owned by the Hornero catalogue contract
(`studioAudioModes` in HorneroOS/hornero `editions/catalogue.yaml`); this
repo only ships the portable configuration values. Package selection stays
in Hornero, service/CLI lifecycle stays in `horneroctl`, and measured
support claims stay with HorneroOS/qa.

## Modes

| Mode | Shipped as | Behaviour |
|---|---|---|
| Balanced | `desktop/pipewire/pipewire.conf.d/10-hornero-studio-balanced.conf` (installed by default) | No rate or quantum override. PipeWire follows the device and WirePlumber policy. |
| Low Latency | `desktop/studio-audio/low-latency.conf` (template, opt-in) | Proposes a 128-frame quantum at 48 kHz (min 64, max 256) for interfaces that can sustain it. |
| Advanced | `desktop/studio-audio/advanced.conf` (template, opt-in) | Per-interface calibration. Ships no fixed values on purpose. |

## Proposal vs measured support

The Low Latency numbers are **proposals**, not measured per-device support.
Quantum is a scheduling period, not physical round-trip latency; only a
physical loopback fixture measures real latency, and QA owns every support
claim. A device that underruns at 128 frames should stay on Balanced.

## Applying and restoring

- Balanced is active wherever the `pipewire` config module is installed.
- To try Low Latency, copy the template to
  `~/.config/pipewire/pipewire.conf.d/50-hornero-studio-low-latency.conf`
  and restart the user PipeWire/WirePlumber services.
- To restore, delete the copied file and restart the same services. No
  other user configuration is touched, and existing personal PipeWire or
  WirePlumber configuration is never overwritten by these profiles.

## Boundaries

- No machine-specific device names, no personal project templates, no
  plugin caches, licenses, or credentials.
- No realtime privilege changes, RT kernel, IRQ, CPU governor, GPU, or
  I/O scheduler tuning. The Hornero mode contract forbids them.
- WirePlumber remains the session/policy manager; the legacy
  `pipewire-media-session` is not configured anywhere.
