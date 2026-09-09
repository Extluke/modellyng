"""Restricted ingress for a supervised beta on the operator's computer.

Bind to loopback and expose only this app through the HTTPS tunnel. Never expose
Supabase Kong/Studio, PostgreSQL, Redis, or the development API directly.
"""

import hashlib
import time
from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, Response
from redis.asyncio import Redis
from redis.exceptions import RedisError

from .config import get_settings
from .health import dependency_health
from .main import app as product_app

settings = get_settings()
AUTH_ROUTES = {
    ("GET", "health"), ("GET", "settings"), ("GET", "user"),
    ("POST", "signup"), ("POST", "token"), ("POST", "logout"),
}
RATE_SCRIPT = """
local n = redis.call('INCR', KEYS[1])
if n == 1 then redis.call('EXPIRE', KEYS[1], ARGV[1]) end
return n
"""


@asynccontextmanager
async def lifespan(app):
    app.state.redis = Redis.from_url(settings.redis_url, socket_timeout=3)
    app.state.http = httpx.AsyncClient(timeout=15, follow_redirects=False)
    try:
        await app.state.redis.ping()
        yield
    finally:
        await app.state.http.aclose()
        await app.state.redis.aclose()


app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None, lifespan=lifespan)


def token_key(token: str) -> str:
    return 'modellyng:beta:session:' + hashlib.sha256(token.encode()).hexdigest()


async def within_limit(request: Request, name: str, limit: int, seconds: int) -> bool:
    window = int(time.time()) // seconds
    count = await request.app.state.redis.eval(
        RATE_SCRIPT, 1, f'modellyng:beta:limit:{name}:{window}', seconds + 1,
    )
    return count <= limit


def denied(status: int, message: str) -> JSONResponse:
    return JSONResponse({'detail': message}, status_code=status,
                        headers={'Cache-Control': 'no-store'})


@app.middleware('http')
async def restrict_ingress(request: Request, call_next):
    path = request.url.path
    if path != '/health' and not path.startswith(('/api/v1/', '/auth/v1/')):
        return denied(404, 'Not found')
    if path.startswith('/auth/v1/') and (request.method, path[9:]) not in AUTH_ROUTES:
        return denied(404, 'Not found')
    try:
        # cloudflared overwrites this header; the gateway listens only on loopback.
        address = request.headers.get('cf-connecting-ip', 'local')
        identity = hashlib.sha256(address.encode()).hexdigest()[:32]
        if not await within_limit(request, f'http:{identity}', 180, 60):
            return denied(429, 'Terlalu banyak permintaan. Coba lagi dalam satu menit.')

        protected = path.startswith('/api/v1/') or path in ('/auth/v1/user', '/auth/v1/logout')
        if protected:
            authorization = request.headers.get('authorization', '')
            scheme, _, token = authorization.partition(' ')
            if scheme.lower() != 'bearer' or not token or not await request.app.state.redis.exists(token_key(token)):
                return denied(401, 'Silakan login melalui aplikasi beta ini.')
            # Only actual GoTrue-issued login tokens pass this extra ingress gate.
            # FastAPI and Supabase still independently validate JWT/owner/RLS.
            if request.method == 'POST':
                analysis = path.endswith(('/papers/upload', '/process', '/comparisons'))
                chat = path.endswith('/chat')
                if analysis or chat:
                    category, limit = ('analysis', 20) if analysis else ('chat', 50)
                    if not await within_limit(request, category, limit, 86400):
                        return denied(429, 'Kuota bersama beta hari ini habis. Coba lagi besok (reset UTC).')
        response = await call_next(request)
        response.headers['Cache-Control'] = 'no-store'
        response.headers['X-Content-Type-Options'] = 'nosniff'
        return response
    except RedisError:
        return denied(503, 'Antrean beta tidak tersedia. Coba lagi nanti.')


@app.get('/health')
async def health():
    dependencies = await dependency_health()
    if dependencies.status != 'ok':
        return denied(503, 'Layanan beta belum siap.')
    return {'status': 'ok', 'service': 'modellyng-beta-gateway'}


@app.api_route('/auth/v1/{operation}', methods=['GET', 'POST'])
async def auth_proxy(operation: str, request: Request):
    if (request.method, operation) not in AUTH_ROUTES:
        return denied(404, 'Not found')
    if request.method == 'POST' and operation in ('signup', 'token'):
        address = request.headers.get('cf-connecting-ip', 'local')
        identity = hashlib.sha256(address.encode()).hexdigest()[:32]
        if not await within_limit(request, f'auth:{identity}', 20, 60):
            return denied(429, 'Terlalu banyak percobaan login. Tunggu satu menit.')
    if operation == 'token' and request.query_params.get('grant_type') not in ('password', 'refresh_token'):
        return denied(400, 'Unsupported authentication flow')
    body = bytearray()
    async for chunk in request.stream():
        body.extend(chunk)
        if len(body) > 16 * 1024:
            return denied(413, 'Authentication request too large')
    headers = {'apikey': settings.supabase_anon_key, 'Content-Type': 'application/json'}
    if operation in ('user', 'logout'):
        headers['Authorization'] = request.headers['authorization']
    try:
        upstream = await request.app.state.http.request(
            request.method, f'{settings.supabase_url}/auth/v1/{operation}',
            params=request.query_params, headers=headers, content=bytes(body),
        )
    except httpx.HTTPError:
        return denied(503, 'Layanan login beta belum tersedia.')
    if upstream.is_success and operation in ('token', 'signup'):
        payload = upstream.json()
        if token := payload.get('access_token'):
            ttl = max(1, min(int(payload.get('expires_in', 3600)), 86400))
            await request.app.state.redis.set(token_key(token), '1', ex=ttl)
    if upstream.is_success and operation == 'logout':
        token = request.headers['authorization'].split(' ', 1)[1]
        await request.app.state.redis.delete(token_key(token))
    return Response(upstream.content, status_code=upstream.status_code,
                    media_type='application/json', headers={'Cache-Control': 'no-store'})


app.mount('/', product_app)
