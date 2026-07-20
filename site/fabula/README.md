# Fabula site

Standalone landing page for `https://router1.tech/fabula/`.

Production layout:

- primary document root: `/var/www/html/fabula`;
- mirror for the future subdomain: `/var/www/fabula`;
- `index.html`: this directory;
- `assets/strength.webp`: `assets/fabula/tarot/strength.webp` from the app repository;
- Nginx template: `nginx.conf`;
- downloads use stable branded URLs under `/fabula/android/` and `/fabula/windows/`.

DNS must contain an `A` record for `fabula.router1.tech` pointing to the Router1 web server. Issue the TLS certificate only after the record resolves publicly.
