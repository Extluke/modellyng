from types import SimpleNamespace

import pytest

from app import gemini_json, project_synthesis, research_flow


class FakeGeminiModels:
    """Pengganti client.models Gemini: tiap panggilan memakai hasil berikutnya."""

    def __init__(self, outcomes):
        self.outcomes = list(outcomes)
        self.calls: list[str] = []
        self.prompts: list[str] = []
        self.configs: list[object] = []

    def generate_content(self, *, model, contents, config):
        self.calls.append(model)
        self.prompts.append(contents)
        self.configs.append(config)
        outcome = self.outcomes.pop(0)
        if isinstance(outcome, Exception):
            raise outcome
        return SimpleNamespace(text=outcome)


@pytest.fixture
def fake_gemini(monkeypatch):
    """Pasang Gemini palsu dengan model utama "primary" dan cadangan "backup"."""

    def install(outcomes, *, max_input_chars: int = 50_000) -> FakeGeminiModels:
        models = FakeGeminiModels(outcomes)
        settings = SimpleNamespace(
            gemini_api_key="key",
            gemini_model="primary",
            gemini_fallback_model="backup",
            gemini_max_input_chars=max_input_chars,
        )
        for module in (gemini_json, research_flow, project_synthesis):
            monkeypatch.setattr(module, "get_settings", lambda: settings)
        monkeypatch.setattr(
            gemini_json.genai, "Client", lambda **_: SimpleNamespace(models=models)
        )
        return models

    return install
