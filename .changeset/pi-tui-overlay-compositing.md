---
"@moonshot-ai/pi-tui": patch
---

Fix overlay compositing on lines narrower than the terminal width (keep the line's right-edge corner intact) and avoid full-screen redraws when an overlay appears.
