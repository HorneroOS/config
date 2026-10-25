# Studio application presets

Portable, opt-in application preset templates for HorneroOS Studio.
Application and workload IDs come from the canonical Hornero catalogue
(HorneroOS/hornero `editions/catalogue.yaml`); this repo ships only
preference templates, never package composition.

## Contract

- `desktop/studio-presets/presets.json` is the versioned index
  (`schemaVersion: 1`). Each preset names a catalogued application, a
  version, source/license notices, template files, and a materialization
  strategy.
- The only strategy in v1 is `create-if-absent`: a preset may create a
  new application config file, but it never overwrites, merges into, or
  deletes an existing user-owned one. If the target exists, the preset
  is skipped and reported, not forced.
- Templates install as data under `~/.config/hornero/studio-presets`.
  Applying one to an application is an explicit later step (user copy
  or a reviewed `horneroctl` flow); materialization alone changes no
  application state.
- Before applying, preview the template; to restore, delete the file
  the preset created. Nothing else is touched.

## Shipped presets

- **OBS Studio recording baseline** (`obs-studio/basic.ini`): a
  1080p30 profile that records to MKV. It contains no stream key, no
  account data, and no hardcoded bitrate or encoder choice — those
  stay with OBS defaults, your hardware, and your own accounts.

## Boundaries

- No device-specific audio settings from factory device names; those
  come only from explicit user calibration (see
  `docs/STUDIO-AUDIO.md`).
- No proprietary assets, plugin caches, licenses, project paths, or
  personal templates.
- Applications without a documented, stable upstream config format
  stay unconfigured on purpose; a missing preset is not a gap to fill
  with a guessed file.
- Sample projects are QA/docs fixtures with their own licenses; config
  references them, never copies or mutates them.
