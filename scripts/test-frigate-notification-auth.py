import ast
import datetime
import logging
import sys
import types
import unittest
from pathlib import Path


source = ast.parse(Path(sys.argv[1]).read_text())
view = next(node for node in source.body if isinstance(node, ast.ClassDef) and node.name == "NotificationsProxyView")
method = next(node for node in view.body if isinstance(node, ast.FunctionDef) and node.name == "_permit_request")
module = ast.Module(body=[ast.ImportFrom(module="__future__", names=[ast.alias(name="annotations")], level=0), method], type_ignores=[])
namespace = {
    "CONF_NOTIFICATION_PROXY_ENABLE": "notification_proxy_enable",
    "CONF_NOTIFICATION_PROXY_EXPIRE_AFTER_SECONDS": "notification_proxy_expire_after_seconds",
    "KEY_AUTHENTICATED": "authenticated",
    "datetime": datetime,
    "_LOGGER": logging.getLogger(__name__),
}
exec(compile(ast.fix_missing_locations(module), "notification-auth", "exec"), namespace)
permit = namespace["_permit_request"]


class NotificationAuthTests(unittest.TestCase):
    def test_proxy_does_not_bypass_authentication(self):
        values = [keyword.value for node in ast.walk(view) if isinstance(node, ast.Call) for keyword in node.keywords if keyword.arg == "allow_unauthenticated"]
        self.assertEqual(len(values), 1)
        self.assertIs(values[0].value, False)

    def test_anonymous_requests_are_denied_even_without_expiration(self):
        for event in ["1791463818.200811-umj5h1", "invalid", "9999999999.1-new"]:
            self.assertFalse(permit(None, {"authenticated": False}, types.SimpleNamespace(options={}), event))

    def test_recent_events_are_not_public(self):
        event = f"{int(datetime.datetime.now(datetime.timezone.utc).timestamp())}.1-new"
        options = {"notification_proxy_expire_after_seconds": 3600}
        self.assertFalse(permit(None, {"authenticated": False}, types.SimpleNamespace(options=options), event))

    def test_authenticated_requests_remain_allowed(self):
        self.assertTrue(permit(None, {"authenticated": True}, types.SimpleNamespace(options={}), "1791463818.200811-umj5h1"))

    def test_disabled_proxy_remains_disabled(self):
        options = {"notification_proxy_enable": False}
        self.assertFalse(permit(None, {"authenticated": True}, types.SimpleNamespace(options=options), "1791463818.200811-umj5h1"))


unittest.main(argv=[sys.argv[0]])
