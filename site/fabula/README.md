# Fabula site

Standalone landing page for `https://fabula.router1.tech/`.

Production layout:

- document root: `/var/www/fabula`;
- `index.html`: this directory;
- `assets/hanged_man.webp`: `assets/fabula/tarot/hanged_man.webp` from the app repository;
- Nginx template: `nginx.conf`;
- downloads are routed through `/api/fabula/download/{platform}` so every click is recorded and the admin notification is sent before the static installer is returned.

DNS must contain an `A` record for `fabula.router1.tech` pointing to the Router1 web server. Issue the TLS certificate only after the record resolves publicly.
