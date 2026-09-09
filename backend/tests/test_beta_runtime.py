import subprocess

import httpx
import pytest

import beta_runtime


@pytest.mark.parametrize('service,expected', [('modellyng-beta-gateway', True), ('unrelated', False)])
def test_health_tries_second_resolver_after_negative_dns_cache(monkeypatch, service, expected):
    url = 'https://beta.example.com'
    calls = []

    def get(target, **kwargs):
        calls.append(target)
        if target == url + '/health':
            raise httpx.ConnectError('DNS unavailable')
        if target == 'https://dns.google/resolve':
            return httpx.Response(200, json={'Status': 3})
        assert target == 'https://cloudflare-dns.com/dns-query'
        return httpx.Response(200, json={'Answer': [{'type': 1, 'data': '192.0.2.10'}]})

    def run(command, **kwargs):
        assert '--insecure' not in command and '-k' not in command
        assert 'beta.example.com:443:192.0.2.10' in command
        assert command[-1] == url + '/health'
        return subprocess.CompletedProcess(command, 0, '{"service":"' + service + '"}')

    monkeypatch.setattr(beta_runtime.httpx, 'get', get)
    monkeypatch.setattr(beta_runtime.shutil, 'which', lambda name: 'curl')
    monkeypatch.setattr(beta_runtime.subprocess, 'run', run)
    assert beta_runtime.public_health(url) is expected
    assert len(calls) == 3
