import importlib.util
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VALIDATOR_PATH = ROOT / "scripts" / "validate_kitty_remote_control.py"
SPEC = importlib.util.spec_from_file_location("kitty_remote_control", VALIDATOR_PATH)
assert SPEC and SPEC.loader
VALIDATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VALIDATOR)


def test_accepts_spaces_and_tabs_between_setting_and_value():
    for separator in (" ", "\t", " \t"):
        valid, _ = VALIDATOR.validate(f"allow_remote_control{separator}no\n")
        assert valid


def test_effective_setting_is_the_last_active_directive():
    assert VALIDATOR.validate("allow_remote_control no\nallow_remote_control yes\n")[0] is False
    assert VALIDATOR.validate("allow_remote_control yes\nallow_remote_control no\n")[0] is True


def test_ignores_comments_and_directives_with_a_similar_name():
    config = "# allow_remote_control yes\nallow_remote_controlled yes\nallow_remote_control\tno\n"
    assert VALIDATOR.values_in_order(config) == ["no"]
    assert VALIDATOR.validate(config)[0] is True


def test_rejects_missing_or_enabled_effective_setting():
    assert VALIDATOR.validate("# allow_remote_control no\n")[0] is False
    assert VALIDATOR.validate("allow_remote_control yes\n")[0] is False
