# WordPress Infra (Deploy-Only, Image-Based)

Repo ini khusus infra/deployment untuk WordPress `Nginx + PHP-FPM`.
Image aplikasi WordPress dibangun di repo terpisah (theme/plugin repo), lalu repo ini hanya pull + deploy image tersebut.

## Struktur
- `infra/servers/prod.env`: env server production
- `infra/scripts/00_check.sh`: validasi env + SSH
- `infra/scripts/10_bootstrap.sh`: setup server fresh (docker + ufw + dirs)
- `infra/scripts/20_provision_app.sh`: kirim compose + nginx conf + template compose/wp-config
- `infra/scripts/30_deploy.sh`: deploy image tag ke server
- `infra/scripts/40_rollback.sh`: rollback ke image sebelumnya
- `infra/app/docker-compose.yml`: stack WordPress FPM + MariaDB + Nginx
- `infra/app/nginx/default.conf`: Nginx FastCGI config ke `wordpress:9000`
- `infra/app/env/compose.env.prod.template`: template env MariaDB/volume
- `infra/app/env/wp-config-sample.php.prod.template`: template config WordPress production

## Alur Pakai
1. Edit `infra/servers/prod.env`.
2. Jalankan awal:
   - `bash infra/scripts/00_check.sh infra/servers/prod.env`
   - `bash infra/scripts/10_bootstrap.sh infra/servers/prod.env`
   - `bash infra/scripts/20_provision_app.sh infra/servers/prod.env`
3. Deploy:
   - `bash infra/scripts/30_deploy.sh infra/servers/prod.env`
4. Rollback jika perlu:
   - `bash infra/scripts/40_rollback.sh infra/servers/prod.env`

## CI/CD
- Workflow: `.github/workflows/deploy-prod.yml`
- Trigger: push ke `main` (termasuk fast-forward merge ke `main`)
- Mode: deploy-only. Tidak build image di repo ini.
- Source image: `IMAGE_REGISTRY/IMAGE_NAME:IMAGE_TAG` dari `infra/servers/prod.env`.
- Manual override tag tersedia lewat `workflow_dispatch` input `image_tag`.

## Catatan Penting
- Image aplikasi harus kompatibel dengan WordPress FPM (`php-fpm`, port 9000).
- Deploy script akan recreate volume code `WORDPRESS_DATA_VOLUME` saat deploy/rollback agar kode dari image terbaru benar-benar terambil.
- Upload media tetap aman karena disimpan di volume terpisah `WORDPRESS_UPLOADS_VOLUME`.
- `shared/wp-config-sample.php` diprovision dari template deployment, lalu setiap deploy/rollback akan dicopy ke `/var/www/html/wp-config.php`.
