# Router1 API Exposure Plan

Goal: expose Router1 API safely for the mobile app without exposing the local
service directly.

Current local API:

- Bind: `127.0.0.1:8081`
- Service: `router1-api.service`
- Auth: bearer token
- Public exposure: disabled

## Public Shape

Use only this public prefix:

```text
https://api.router1.tech/api/v1
```

Never expose `127.0.0.1:8081` directly to the internet.

## Nginx Template

Replace `api.router1.tech` with the real domain.

```nginx
limit_req_zone $binary_remote_addr zone=router1_api_rate:10m rate=5r/s;

log_format router1_api '$remote_addr - $remote_user [$time_local] '
                       '"$request" $status $body_bytes_sent '
                       '"$http_user_agent" "$request_time"';

server {
    listen 80;
    server_name api.router1.tech;

    location /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name api.router1.tech;

    ssl_certificate /etc/letsencrypt/live/api.router1.tech/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.router1.tech/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    access_log /var/log/nginx/router1-api-access.log router1_api;
    error_log /var/log/nginx/router1-api-error.log warn;

    client_max_body_size 256k;

    location /api/v1/ {
        limit_req zone=router1_api_rate burst=20 nodelay;

        limit_except GET POST {
            deny all;
        }

        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header Authorization $http_authorization;

        rewrite ^/api/v1(/.*)$ $1 break;
        proxy_pass http://127.0.0.1:8081;
    }

    location / {
        return 404;
    }
}
```

## TLS

Use Let's Encrypt after DNS is pointed to the API host:

```bash
apt-get install -y certbot python3-certbot-nginx
certbot --nginx -d api.router1.tech
nginx -t
systemctl reload nginx
```

## Security Rules

- API binds to `127.0.0.1` only.
- Public path is only `/api/v1`.
- Bearer token remains required by Router1 API.
- Nginx allows only `GET` and `POST`.
- Rate limit starts at `5r/s` per IP with burst `20`.
- Access and error logs are separate from the main site logs.
- Do not proxy `/logs` publicly until device tokens are per-user and scoped.

## App Endpoint

Set in `lib/main.dart`:

```dart
Router1Api(
  baseUrl: 'https://api.router1.tech/api/v1',
  token: 'issued-user-token',
)
```

## Open Items

- Decide final API domain.
- Issue per-user app tokens from existing bot/account system.
- Scope dangerous commands like restart to admin/test users first.
- Add token rotation and revocation before broad rollout.
