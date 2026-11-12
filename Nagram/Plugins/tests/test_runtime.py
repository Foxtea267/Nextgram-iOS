import json
import runpy
import sys
import tempfile
import unittest
from pathlib import Path


RUNTIME = Path(__file__).resolve().parents[1] / "Resources" / "NextgramExteraRuntime.py"

SOURCE = '''
from typing import List
from base_plugin import BasePlugin, HookResult, HookStrategy, MenuItemData, MenuItemType
from ui.settings import Header, Text, Input, Switch

__id__ = "test_greeter"
__name__ = "Test Greeter"

class Greeter(BasePlugin):
    def on_plugin_load(self):
        self.add_on_send_message_hook(priority=10)
        self.add_menu_item(MenuItemData(MenuItemType.MESSAGE_CONTEXT_MENU, "Remember text", self.remember))

    def remember(self, context):
        self.set_setting("prefix", f"{context['message'].getId()}:{context['message'].messageText}")

    def create_settings(self) -> List:
        return [Header(text="Settings"), Input(key="prefix", text="Prefix", default="Hi"),
                Switch(key="active", text="Active", default=True), Text(text="Example")]

    def on_send_message_hook(self, account, params):
        if params.message == "/stop":
            return HookResult(HookStrategy.CANCEL)
        if params.message.startswith("/greet ") and self.get_setting("active", True):
            params.message = self.get_setting("prefix", "Hi") + " " + params.message[7:]
            return HookResult(HookStrategy.MODIFY_FINAL, params)
        return HookResult()
'''


class ExteraRuntimeTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        import_path = list(sys.meta_path)
        self.addCleanup(lambda: sys.meta_path.__setitem__(slice(None), import_path))
        self.dispatch = runpy.run_path(str(RUNTIME))["dispatch_json"]

    def request(self, operation, **args):
        return json.loads(self.dispatch(json.dumps(dict(operation=operation, **args))))

    def enable(self, source=SOURCE, identifier="test_greeter"):
        return self.request(
            "enable", source=source, id=identifier,
            settingsPath=str(Path(self.directory.name) / (identifier + ".json")),
        )

    def send(self, *texts):
        return self.request("send", messages=texts, account=20, dialogId=42)

    def test_inspect_does_not_execute(self):
        source = 'raise RuntimeError("must not run")\n' + SOURCE
        response = self.request("inspect", source=source)
        self.assertIsNone(response["error"])
        self.assertEqual(response["result"]["id"], "test_greeter")
        self.assertEqual(response["enabled"], [])
        self.assertIn("must not run", self.enable(source)["error"])

    def test_settings_menu_send_and_unload(self):
        response = self.enable()
        self.assertIsNone(response["error"])
        self.assertTrue(response["hasSendHook"])
        self.assertEqual(response["menus"][0]["title"], "Remember text")
        self.assertEqual(self.send("/greet 张三", "/stop", None, "plain")["result"], ["Hi 张三", None, None, "plain"])
        settings = self.request("settings", id="test_greeter")["result"]
        self.assertEqual([row["kind"] for row in settings], ["Header", "Input", "Switch", "Text"])
        self.assertIsNone(self.request("setSetting", id="test_greeter", key="prefix", value="Welcome")["error"])
        self.assertEqual(self.send("/greet test")["result"], ["Welcome test"])
        self.assertIsNone(self.request(
            "invoke", id="test_greeter", itemId="0",
            context={"message": {"id": 42, "messageText": "菜单"}},
        )["error"])
        self.assertEqual(self.send("/greet test")["result"], ["42:菜单 test"])
        response = self.request("disable", id="test_greeter")
        self.assertFalse(response["hasSendHook"])
        self.assertEqual(response["menus"], [])
        self.assertEqual(self.send("/greet test")["result"], ["/greet test"])
        self.assertIsNone(self.enable()["error"])
        self.assertEqual(self.send("/greet test")["result"], ["42:菜单 test"])

    def test_unsupported_android_and_invalid_metadata(self):
        response = self.enable("from java import jclass\n" + SOURCE)
        self.assertIn("not supported by Nextgram", response["error"])
        self.assertEqual(response["enabled"], [])
        self.assertIn("Invalid plugin __id__", self.request("inspect", source=SOURCE.replace("test_greeter", "../unsafe"))["error"])
        self.assertIn("Installing Python packages", self.request("inspect", source=SOURCE + '\n__requirements__ = ["example"]')["error"])

    def test_hook_error_does_not_return_original_message(self):
        response = self.enable(SOURCE.replace('if params.message == "/stop":', 'raise RuntimeError("hook failed")\n        if params.message == "/stop":'))
        self.assertIsNone(response["error"])
        response = self.send("text")
        self.assertIsNone(response["result"])
        self.assertIn("test_greeter: RuntimeError: hook failed", response["error"])


if __name__ == "__main__":
    unittest.main()
