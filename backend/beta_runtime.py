"""Start a supervised, zero-rental-cost beta on this computer.

Run with backend/.venv/Scripts/python.exe backend/beta_runtime.py from the repo.
The generated client config contains only public URLs and the anonymous key.
"""

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import tomllib

import httpx
from redis import Redis

from app.config import get_settings

ROOT = Path(__file__).resolve().parents[1]
STATE = ROOT / '.tool-state' / 'beta'


def public_health(url):
    """Verify TLS using the real hostname, with public DNS if local DNS is stale."""
    try:
        response = httpx.get(url + '/health', timeout=5)
        if response.status_code == 200:
            return response.json().get('service') == 'modellyng-beta-gateway'
    except (httpx.HTTPError, ValueError):
        pass
    # Only diagnostic/build preflight uses this fallback. The APK uses normal DNS.
    host = httpx.URL(url).host
    curl = shutil.which('curl.exe' if os.name == 'nt' else 'curl')
    if not curl:
        return False
    for resolver in ('https://dns.google/resolve', 'https://cloudflare-dns.com/dns-query'):
        try:
            answer = httpx.get(resolver, params={'name': host, 'type': 'A'},
                               headers={'Accept': 'application/dns-json'}, timeout=5).json()
            address = next(row['data'] for row in answer.get('Answer', []) if row['type'] == 1)
            result = subprocess.run([curl, '--silent', '--show-error', '--fail',
                '--max-time', '10', '--resolve', f'{host}:443:{address}', url + '/health'],
                capture_output=True, text=True, timeout=15)
            if result.returncode == 0 and json.loads(result.stdout).get('service') == 'modellyng-beta-gateway':
                return True
        except (httpx.HTTPError, ValueError, StopIteration, subprocess.SubprocessError):
            continue
    return False


def start():
    STATE.mkdir(parents=True, exist_ok=True)
    config = tomllib.loads((ROOT / 'supabase/config.toml').read_text(encoding='utf-8'))
    local_supabase = f"http://127.0.0.1:{config['api']['port']}"
    settings = get_settings()
    httpx.get(f'{local_supabase}/auth/v1/health', headers={
        'apikey': settings.supabase_anon_key,
    }, timeout=10).raise_for_status()
    redis = Redis.from_url(settings.redis_url, socket_timeout=5)
    redis.ping()
    redis.close()
    if not settings.gemini_api_key or not settings.supabase_service_role_key:
        raise RuntimeError('Configure backend credentials privately in backend/.env first.')
    for port in (8000, 8001):
        import socket
        with socket.socket() as sock:
            if sock.connect_ex(('127.0.0.1', port)) == 0:
                raise RuntimeError(f'Port {port} is already in use. Reuse or stop the existing beta first.')
    tunnel = shutil.which('cloudflared')
    if not tunnel:
        raise RuntimeError('cloudflared is required.')
    environment = dict(os.environ, MODELLYNG_SUPABASE_URL=local_supabase)
    children = []

    def launch(name, command):
        with (STATE / f'{name}.log').open('w', encoding='utf-8') as log:
            child = subprocess.Popen(command, cwd=ROOT / 'backend', env=environment,
                                     stdout=log, stderr=subprocess.STDOUT,
                                     creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
        children.append((name, child))

    try:
        launch('worker', [sys.executable, '-m', 'celery', '-A', 'app.celery_app:celery_app',
                          'worker', '--pool=solo', '--concurrency=1', '--loglevel=WARNING'])
        launch('api', [sys.executable, '-m', 'uvicorn', 'app.main:app',
                       '--host', '127.0.0.1', '--port', '8000', '--no-access-log'])
        launch('gateway', [sys.executable, '-m', 'uvicorn', 'app.beta_gateway:app',
                           '--host', '127.0.0.1', '--port', '8001', '--no-access-log'])
        for _ in range(60):
            if any(child.poll() is not None for _, child in children):
                raise RuntimeError('A beta process exited; inspect the private runtime logs.')
            try:
                health = httpx.get('http://127.0.0.1:8001/health', timeout=3)
                if health.status_code == 200:
                    break
            except httpx.HTTPError:
                pass
            time.sleep(1)
        else:
            raise RuntimeError('Beta gateway did not become healthy.')
        launch('tunnel', [tunnel, 'tunnel', '--no-autoupdate', '--url',
                          'http://127.0.0.1:8001', '--protocol', 'http2'])
        public_url = None
        deadline = time.monotonic() + 180
        while time.monotonic() < deadline:
            log = (STATE / 'tunnel.log').read_text(encoding='utf-8', errors='replace')
            match = re.search(r'https://[a-z0-9-]+\.trycloudflare\.com', log)
            if match:
                public_url = match.group(0)
                if public_health(public_url):
                    break
            time.sleep(1)
        else:
            raise RuntimeError('Public HTTPS tunnel did not become reachable.')
        client = {'BETA_BUILD': 'true', 'API_BASE_URL': public_url,
                  'SUPABASE_URL': public_url,
                  'SUPABASE_PUBLISHABLE_KEY': settings.supabase_anon_key}
        (STATE / 'client.json').write_text(json.dumps(client, indent=2), encoding='utf-8')
        (STATE / 'runtime.json').write_text(json.dumps({
            'public_url': public_url, 'started_at': time.time(),
            'processes': {name: child.pid for name, child in children},
        }, indent=2), encoding='utf-8')
        print(f'Beta HTTPS ready: {public_url}')
        print('Public build config: .tool-state/beta/client.json')
        print('Keep this computer, Docker, worker, gateway and tunnel running.')
    except Exception:
        for _, child in reversed(children):
            if child.poll() is None:
                child.terminate()
        raise


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == 'check':
        sys.exit(0 if public_health(sys.argv[2]) else 1)
    else:
        start()
