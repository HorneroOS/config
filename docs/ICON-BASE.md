# Icon-base recommendation

Evaluation of third-party icon-base candidates for HorneroOS, against
coverage, license, packaging (Arch official repos preferred) and fit with
the warm clay/sunset/earth brand direction. Evidence gathered 2026-09-13
via `pacman -Si` / `pacman -Ss` / `pacman -Fl` on Arch.

## Result

- **Dark flagship (`hornero-dark`): VERIFY `Papirus-Dark`.** Keep.
- **Light flagship (`hornero-light`): OVERTURN `Numix-Circle` → `Papirus`.**
  Implemented in this branch (`profiles/themes/hornero-light/theme.json`).
- **Pampa flagship (`pampa`): `Papirus-Dark`.** Same family, same single
  official package — no new dependency, no new verdict needed.

One icon family across all three flagships, every variant shipped by a
single official package, no new dependency.

## Evidence

| Candidate | Coverage | License | Packaging | Fit | Verdict |
|---|---|---|---|---|---|
| **Papirus / Papirus-Dark / Papirus-Light** | Largest of the set; actively maintained; per-app coverage far exceeds Numix-Circle | GPL-3.0 | `extra/papirus-icon-theme` (official, Felix Yan). One package ships all three variants (verified via `pacman -Fl`: `Papirus`, `Papirus-Dark`, `Papirus-Light` index.theme files) | Neutral rounded style; recolors cleanly against terracotta/sunset; Dark variant matches the night-adobe ramp | **ADOPT** (all three flagships) |
| Tela | Good coverage, many color variants | GPL-3.0-or-later | Split: only `tela-circle-icon-theme-*` in `extra`; base `tela-icon-theme` only in `chaotic-aur`. Depending on it pulls a third-party repo for the full set | Blue-leaning defaults; fights the warm ramp | Reject: weaker packaging story than Papirus |
| Colloid | Good coverage, modern | GPL-3.0 (upstream) | Only `chaotic-aur/colloid-icon-theme-git` (rolling `-git`, no official package) | Grey sight, cool; acceptable but not warm | Reject: no official-repo package |
| BeautyLine | Outlined, Candy/Sweet companion set | GPL | Only `chaotic-aur/beautyline`; designed for the Sweet theme | Neon candy aesthetic = the generic-cyberpunk direction the brand explicitly avoids | Reject: wrong direction + unofficial packaging |
| Numix-Circle (incumbent, light) | Dated, narrower app coverage than Papirus | GPL-3.0 (upstream) | Only `chaotic-aur/numix-circle-icon-theme-git` (rolling `-git`); **no official-repo package** — the flagship light theme depended on an unofficial repo | Circle imposed on every glyph clashes with the bird/sun-disc mark language | **Remove** from flagship light |

## Consequences

- `hornero-light/theme.json`: `iconTheme` is now `Papirus` (was
  `Numix-Circle`). No new package dependency: `papirus-icon-theme`
  already covers the dark flagship.
- Custom Hornero app/system icons ship as vector sources under
  `assets/brand/icons/` (installed to `.../hornero/brand/`); they layer
  over the Papirus base, they do not replace it.
- GTK themes are untouched by this decision (config-gtk worker owns
  `desktop/gtk-theme*`); the flagship `gtkTheme` values are out of scope.
