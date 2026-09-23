# Local Development Setup

## Prerequisites

- Docker + Docker Compose
- Python 3.12+
- Node.js 22+ with pnpm
- just (task runner): `cargo install just` or `sudo pacman -S just`

## Quick start

1. Clone the repo with submodules:
   ```bash
   git clone --recursive <repo-url>
   cd kaleem
   ```

2. Run the setup command:
   ```bash
   just setup
   ```

3. Start all services:
   ```bash
   just dev
   ```

4. Verify:
   - Backend API: http://localhost:8000/health/live/
   - Django admin: http://localhost:8000/admin/
   - Dashboard: http://localhost:5173
   - Marketing: http://localhost:4321
   - Mailpit: http://localhost:8025

## Test users

After running `just seed` (available from Phase A):
- Admin: admin@kaleem.test / admin123
- Teacher 1: teacher1@kaleem.test / test123
- Student 1-5: student{1-5}@kaleem.test / test123
- Parent 1-3: parent{1-3}@kaleem.test / test123
