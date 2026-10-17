# Amar Hisab — prototype status

Last updated: 2026-10-17
Branch: `web-prototype`
Pull request: https://github.com/scmsohel/amar-hisab/pull/1
Main branch: unchanged; this prototype has not been merged or deployed.

## Working in the browser (demo data only)
- Responsive Bengali finance dashboard, charts, light/dark mode.
- Add, edit, delete, search and filter income/expense/transfer transactions.
- Transfer between demo wallets with source-balance validation.
- Wallet balances and expense category chart update from demo transactions.
- CSV export includes transfer source and destination.
- Transactions, dark mode and sidebar preference persist in this browser's localStorage.

## Not production-ready
- No backend/API or PostgreSQL connection.
- Demo baseline amounts are sample figures; localStorage data is not shared across browsers/devices and is not a safe financial database.
- Dashboard navigation pages other than Dashboard and Transactions are placeholders.
- No authentication, multi-user access, backup/restore or production test suite.

## Proxmox preview packaging
A Dockerfile, nginx config and isolated Compose file are included for a preview container.
Once these files are built and deployed on a reachable Proxmox VM/LXC, the preview is expected at:
`http://<PROXMOX_HOST_IP>:8088`

On the target that has Docker Compose and access to this branch, run from the repository directory:
`git pull origin web-prototype`
`docker compose -f docker-compose.preview.yml up -d --build`

Check status:
`docker compose -f docker-compose.preview.yml ps`
`docker compose -f docker-compose.preview.yml logs --tail=100 amar-hisab-web`

This config uses host port 8088 by default. If that port is already occupied, set `AMAR_HISAB_PORT` to an unused port before starting. Do not merge to main or replace the existing backend as part of this preview.

## Next
1. CI checks both the TypeScript/Vite build and the Docker image.
2. Deploy this isolated preview to the intended Proxmox VM/LXC.
3. Review the UI in a browser.
4. Only after UI review, plan API/database integration and production deployment.
