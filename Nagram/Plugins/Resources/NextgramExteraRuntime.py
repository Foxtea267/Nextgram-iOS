"""Nextgram's source-level extera compatibility surface, not a Python sandbox."""

import ast
import json
import logging
import os
import re
import sys
from enum import Enum
from types import ModuleType, SimpleNamespace


class HookStrategy(Enum):
    DEFAULT = "default"
    CANCEL = "cancel"
    MODIFY = "modify"
    MODIFY_FINAL = "modify_final"


class HookResult:
    def __init__(self, strategy=HookStrategy.DEFAULT, params=None):
        self.strategy = strategy
        self.params = params


class MenuItemType(Enum):
    MESSAGE_CONTEXT_MENU = "message_context_menu"
    DRAWER_MENU = "drawer_menu"
    MAIN_MENU = "main_menu"
    CHAT_ACTION_MENU = "chat_action_menu"
    PROFILE_ACTION_MENU = "profile_action_menu"


class MenuItemData:
    def __init__(self, menu_type, text, on_click, item_id=None, icon=None,
                 subtext=None, condition=None, priority=0):
        self.menu_type = menu_type
        self.text = text
        self.on_click = on_click
        self.item_id = item_id
        self.condition = condition
        self.priority = priority


class BasePlugin:
    def on_plugin_load(self):
        pass

    def on_plugin_unload(self):
        pass

    def create_settings(self):
        return []

    def get_setting(self, key, default=None):
        return self._settings.get(key, default)

    def set_setting(self, key, value, reload_settings=False):
        settings = dict(self._settings, **{key: value})
        temporary = self._settings_path + ".tmp"
        with open(temporary, "w", encoding="utf-8") as file:
            json.dump(settings, file, allow_nan=False)
        os.replace(temporary, self._settings_path)
        self._settings = settings

    def add_on_send_message_hook(self, priority=0):
        if not callable(getattr(self, "on_send_message_hook", None)):
            raise ValueError("Define on_send_message_hook before registering it.")
        self._send_priority = int(priority)

    def add_menu_item(self, item):
        if item.menu_type is not MenuItemType.MESSAGE_CONTEXT_MENU or item.condition:
            raise NotImplementedError("Only unconditional MESSAGE_CONTEXT_MENU items are supported on iOS.")
        if not isinstance(item.text, str) or not item.text.strip() or not callable(item.on_click):
            raise ValueError("A message menu item requires a title and callback.")
        item_id = item.item_id or str(self._next_menu_id)
        if not isinstance(item_id, str) or item_id in self._menus:
            raise ValueError("A menu item ID must be a unique string.")
        self._next_menu_id += 1
        self._menus[item_id] = item
        return item_id

    def remove_menu_item(self, item_id):
        self._menus.pop(item_id, None)

    def add_hook(self, *args, **kwargs):
        raise NotImplementedError("Request and update hooks are not supported by Nextgram.")

    def hook_method(self, *args, **kwargs):
        raise NotImplementedError("Android/Xposed hooks cannot run in Nextgram for iOS.")


class _Row:
    def __init__(self, text, key=None, default=None, subtext=None, icon=None,
                 on_change=None, **options):
        if options:
            raise NotImplementedError("Unsupported settings options: " + ", ".join(sorted(options)))
        self.text = text
        self.key = key
        self.default = default
        self.subtext = subtext
        self.on_change = on_change


class Header(_Row):
    pass


class Text(_Row):
    pass


class Input(_Row):
    pass


class Switch(_Row):
    pass


def _module(name, *exports):
    module = ModuleType(name)
    module.__dict__.update((item.__name__, item) for item in exports)
    sys.modules[name] = module
    return module


_module("base_plugin", BasePlugin, HookResult, HookStrategy, MenuItemData, MenuItemType)
ui = _module("ui")
ui.__path__ = []
ui.settings = _module("ui.settings", Header, Text, Input, Switch)


class _AndroidImports:
    def find_spec(self, fullname, path=None, target=None):
        if fullname.split(".")[0] in {
            "android", "android_utils", "java", "jnius", "org", "com", "de",
            "hook_utils", "client_utils", "extera_utils", "file_utils",
        }:
            raise ImportError(f"{fullname} is not supported by Nextgram's iOS plugin SDK.")
        return None


sys.meta_path.insert(0, _AndroidImports())
_enabled = {}
_metadata_keys = {"__id__", "__name__", "__description__", "__version__", "__author__", "__requirements__"}


class _MenuMessage(SimpleNamespace):
    def getId(self):
        return self.id


def _inspect(source):
    if len(source.encode("utf-8")) > 2 * 1024 * 1024:
        raise ValueError("Plugin source exceeds 2 MB.")
    tree = ast.parse(source, filename="<extera plugin>")
    values = {}
    for statement in tree.body:
        if not isinstance(statement, (ast.Assign, ast.AnnAssign)):
            continue
        targets = statement.targets if isinstance(statement, ast.Assign) else [statement.target]
        for target in targets:
            if isinstance(target, ast.Name) and target.id in _metadata_keys:
                values[target.id] = ast.literal_eval(statement.value)
    identifier = values.get("__id__")
    if not isinstance(identifier, str) or not re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]{1,31}", identifier):
        raise ValueError("Invalid plugin __id__: use 2–32 letters, digits, underscores or hyphens.")
    name = values.get("__name__")
    if not isinstance(name, str) or not name.strip() or len(name) > 200:
        raise ValueError("Plugin __name__ must be a non-empty string up to 200 characters.")
    if values.get("__requirements__"):
        raise NotImplementedError("Installing Python packages is not supported by Nextgram.")
    metadata = {"id": identifier, "name": name}
    for source_key, key in (("__description__", "description"), ("__version__", "version"), ("__author__", "author")):
        value = values.get(source_key, "")
        if not isinstance(value, str):
            raise ValueError(f"{source_key} must be a string.")
        metadata[key] = value[:1000]
    return metadata, tree


def _enable(source, identifier, settings_path):
    metadata, tree = _inspect(source)
    if metadata["id"] != identifier or identifier in _enabled:
        raise ValueError("Unexpected or already enabled plugin ID.")
    module_name = "nextgram_plugin_" + identifier
    module = ModuleType(module_name)
    sys.modules[module_name] = module
    try:
        exec(compile(tree, identifier + ".plugin", "exec"), module.__dict__)
        # The extera metadata assignment to __name__ changes the module name
        # seen by Python class definitions. Identify source-defined classes.
        definitions = {node.name for node in tree.body if isinstance(node, ast.ClassDef)}
        classes = [
            value for name, value in vars(module).items()
            if name in definitions and isinstance(value, type)
            and value is not BasePlugin and issubclass(value, BasePlugin)
        ]
        if len(classes) != 1:
            raise ValueError("A plugin must define exactly one BasePlugin subclass.")
        plugin = classes[0]()
        plugin.logger = logging.getLogger(module_name)
        plugin._settings_path = settings_path
        try:
            with open(settings_path, encoding="utf-8") as file:
                plugin._settings = json.load(file)
        except FileNotFoundError:
            plugin._settings = {}
        plugin._send_priority = None
        plugin._next_menu_id = 0
        plugin._menus = {}
        plugin.on_plugin_load()
        _enabled[identifier] = plugin
    except BaseException:
        sys.modules.pop(module_name, None)
        raise


def _settings(plugin):
    rows = []
    keys = set()
    for row in plugin.create_settings():
        if type(row) not in {Header, Text, Input, Switch} or not isinstance(row.text, str):
            raise NotImplementedError("Supported settings rows: Header, Text, Input and Switch.")
        value = None
        if isinstance(row, (Input, Switch)):
            if not isinstance(row.key, str) or not row.key or row.key in keys:
                raise ValueError("Editable settings rows must have a unique non-empty key.")
            keys.add(row.key)
            expected = bool if isinstance(row, Switch) else str
            default = expected() if row.default is None else row.default
            value = plugin.get_setting(row.key, default)
            if not isinstance(value, expected):
                raise ValueError(f"Invalid setting value for {row.key}.")
        rows.append({"kind": type(row).__name__, "text": row.text, "key": row.key,
                     "subtext": row.subtext, "value": value})
    return rows


def _send(account, dialog_id, messages):
    plugins = sorted(
        ((identifier, plugin) for identifier, plugin in _enabled.items() if plugin._send_priority is not None),
        key=lambda item: (-item[1]._send_priority, item[0]),
    )
    output = []
    for message in messages:
        if message is not None:
            for identifier, plugin in plugins:
                try:
                    params = SimpleNamespace(message=message, peer=dialog_id)
                    result = plugin.on_send_message_hook(account, params)
                    if not isinstance(result, HookResult) or not isinstance(result.strategy, HookStrategy):
                        raise TypeError("Expected HookResult with a HookStrategy.")
                    if result.strategy is HookStrategy.CANCEL:
                        message = None
                        break
                    if result.strategy in {HookStrategy.MODIFY, HookStrategy.MODIFY_FINAL}:
                        message = getattr(result.params, "message", None)
                        if not isinstance(message, str) or not message.strip() or len(message.encode("utf-16-le")) > 8192:
                            raise ValueError("Modified text must be non-empty and at most 4096 UTF-16 units.")
                    if result.strategy is HookStrategy.MODIFY_FINAL:
                        break
                except BaseException as error:
                    raise RuntimeError(f"{identifier}: {type(error).__name__}: {error}") from error
        output.append(message)
    return output


def _run(request):
    operation = request["operation"]
    identifier = request.get("id")
    if operation == "inspect":
        return _inspect(request["source"])[0]
    if operation == "enable":
        _enable(request["source"], identifier, request["settingsPath"])
    elif operation == "disable":
        plugin = _enabled.pop(identifier)
        try:
            plugin.on_plugin_unload()
        finally:
            sys.modules.pop("nextgram_plugin_" + identifier, None)
    elif operation == "settings":
        return _settings(_enabled[identifier])
    elif operation == "setSetting":
        plugin = _enabled[identifier]
        row = next(
            (row for row in plugin.create_settings() if isinstance(row, (Input, Switch)) and row.key == request["key"]),
            None,
        )
        if row is None or not isinstance(request["value"], bool if isinstance(row, Switch) else str):
            raise ValueError("Unknown setting or incorrect value type.")
        plugin.set_setting(row.key, request["value"])
        if row.on_change is not None:
            row.on_change(request["value"])
    elif operation == "invoke":
        context = request["context"]
        if "message" in context:
            context["message"] = _MenuMessage(**context["message"])
        _enabled[identifier]._menus[request["itemId"]].on_click(context)
    elif operation == "send":
        return _send(request["account"], request["dialogId"], request["messages"])
    else:
        raise ValueError(f"Unknown plugin operation: {operation}")
    return None


def dispatch_json(payload):
    error_message = None
    try:
        result = _run(json.loads(payload))
    except BaseException as error:
        result = None
        error_message = f"{type(error).__name__}: {error}"[:1000]
    try:
        return json.dumps({
            "result": result,
            "error": error_message,
            "enabled": list(_enabled),
            "hasSendHook": any(plugin._send_priority is not None for plugin in _enabled.values()),
            "menus": [
                {"pluginId": identifier, "id": item_id, "title": item.text, "priority": item.priority}
                for identifier, plugin in _enabled.items() for item_id, item in plugin._menus.items()
            ],
        }, allow_nan=False)
    except BaseException as error:
        return json.dumps({"error": f"{type(error).__name__}: {error}"[:1000]})
