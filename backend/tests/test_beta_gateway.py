import httpx
import pytest
from fastapi.testclient import TestClient

from app import beta_gateway as gateway


class MemoryRedis:
    def __init__(self):
        self.data = {}

    async def ping(self):
        return True

    async def aclose(self):
        pass

    async def eval(self, script, count, key, ttl):
        self.data[key] = self.data.get(key, 0) + 1
        return self.data[key]

    async def set(self, key, value, ex):
        self.data[key] = value

    async def exists(self, key):
        return key in self.data

    async def delete(self, key):
        self.data.pop(key, None)


@pytest.fixture
def client(monkeypatch):
    redis = MemoryRedis()
    monkeypatch.setattr(gateway.Redis, 'from_url', lambda *a, **kw: redis)
    with TestClient(gateway.app) as client:
        yield client


def test_gateway_does_not_expose_supabase_admin_storage_or_docs(client):
    for path in ('/', '/docs', '/openapi.json', '/health/dependencies',
                 '/rest/v1/papers', '/storage/v1/object', '/auth/v1/admin/users',
                 '/auth/v1/../admin/users', '/auth/v1/recover'):
        assert client.get(path).status_code == 404


def test_gateway_rejects_tokens_not_issued_through_beta_login(client):
    for path in ('/api/v1/projects', '/auth/v1/user', '/auth/v1/logout'):
        response = client.get(path, headers={'Authorization': 'Bearer forged-token'})
        assert response.status_code == 401 or response.status_code == 404


def test_auth_proxy_uses_fixed_origin_and_server_anon_key(client):
    async def send(method, url, **kwargs):
        assert url == f'{gateway.settings.supabase_url}/auth/v1/token'
        assert kwargs['headers']['apikey'] == gateway.settings.supabase_anon_key
        assert 'Authorization' not in kwargs['headers']
        return httpx.Response(200, json={'access_token': 'issued-test-token', 'expires_in': 3600})

    gateway.app.state.http.request = send
    response = client.post('/auth/v1/token?grant_type=password', json={},
                           headers={'apikey': 'attacker-key', 'Authorization': 'Bearer attacker'})
    assert response.status_code == 200
    assert gateway.token_key('issued-test-token') in gateway.app.state.redis.data
    assert response.headers['cache-control'] == 'no-store'


def test_auth_payload_is_bounded_and_unknown_grants_rejected(client):
    assert client.post('/auth/v1/token?grant_type=implicit').status_code == 400
    assert client.post('/auth/v1/signup', content=b'x' * 16385).status_code == 413


def test_beta_ai_quota_blocks_before_product_execution(client):
    gateway.app.state.redis.data[gateway.token_key('issued-test-token')] = '1'
    import time
    window = int(time.time()) // 86400
    gateway.app.state.redis.data[f'modellyng:beta:limit:analysis:{window}'] = 20
    response = client.post('/api/v1/projects/test/papers/upload',
                           headers={'Authorization': 'Bearer issued-test-token'})
    assert response.status_code == 429


def test_logout_revokes_gateway_session(client):
    gateway.app.state.redis.data[gateway.token_key('issued-test-token')] = '1'

    async def send(*args, **kwargs):
        return httpx.Response(204)

    gateway.app.state.http.request = send
    response = client.post('/auth/v1/logout', headers={'Authorization': 'Bearer issued-test-token'})
    assert response.status_code == 204
    assert gateway.token_key('issued-test-token') not in gateway.app.state.redis.data
