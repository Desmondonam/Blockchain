import json

from minichain.__main__ import main


def test_demo_save_and_verify_round_trip(tmp_path, capsys):
    path = tmp_path / "chain.json"
    assert main(["demo", "--out", str(path)]) == 0
    assert main(["verify", str(path)]) == 0
    assert "VALID" in capsys.readouterr().out


def test_verify_detects_edited_file(tmp_path, capsys):
    path = tmp_path / "chain.json"
    main(["demo", "--out", str(path)])
    data = json.loads(path.read_text())
    data["blocks"][1]["transactions"][0]["amount"] = 1  # tamper
    path.write_text(json.dumps(data))

    assert main(["verify", str(path)]) == 1
    assert "TAMPERED" in capsys.readouterr().out
