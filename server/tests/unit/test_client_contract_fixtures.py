from pathlib import Path

from inknest_server.sync import SyncBootstrapResponse


def test_flutter_bootstrap_fixture_matches_the_fastapi_response_contract() -> None:
    fixture = (
        Path(__file__).parents[3]
        / "test"
        / "fixtures"
        / "api"
        / "v1"
        / "sync_bootstrap_response.json"
    )

    response = SyncBootstrapResponse.model_validate_json(fixture.read_text())

    assert response.counts.pages == 1
    assert response.counts.infinite_canvases == 1
    assert response.counts.assets == 1
    assert response.pages[0].coordinate_space_version == {"future": 2}
    assert (
        "objectKey" not in response.model_dump(mode="json", by_alias=True)["assets"][0]
    )
