"""Macro Wheel Command Runtime support module.

Source of truth for this file lives here, in `menu/tools/python/`, and is
copied into `resources/python/command_runtime/` by `fetch-python-runtimes.ps1`.
It is not kept inside the runtime tree because that tree is deleted and
re-extracted whenever the runtimes are re-fetched.

This module is part of Macro Wheel's application-owned Command Runtime. It is
locked: users cannot change it, install into it, or point the Menu at a
replacement interpreter (spec section 13.2.1, rules 25-26).

Built-in commands use it only when they genuinely need the DaVinci Resolve
scripting API. Ordinary keystroke-based commands are performed natively in C++
and never spawn this interpreter, so the common case stays fast.

User-authored scripts do NOT import this module. They are run by the separate
Script Runtime and talk to Resolve directly (spec 13.2.10, rule 21).
"""

from __future__ import annotations

import importlib
import os
import sys
from typing import Any, Optional

__all__ = [
    "resolve_scriptapp",
    "current_page",
    "call_resolve",
    "send_keys",
]


def _install_resolve_paths() -> None:
    """Puts the Resolve scripting paths on sys.path.

    The Menu sets RESOLVE_SCRIPT_API and RESOLVE_SCRIPT_LIB from the
    configuration before launching this interpreter.
    """
    for variable in ("RESOLVE_SCRIPT_API", "RESOLVE_SCRIPT_LIB"):
        path = os.environ.get(variable)
        if path and path not in sys.path:
            sys.path.insert(0, path)


def resolve_scriptapp(application: str = "Resolve") -> Optional[Any]:
    """Returns a connected Resolve handle, or None when unavailable.

    Never raises: a missing or broken Resolve install is a normal state that
    the Menu reports through its connection indicator.
    """
    _install_resolve_paths()
    try:
        module = importlib.import_module("DaVinciResolveScript")
    except Exception:
        return None

    try:
        return module.scriptapp(application)
    except Exception:
        return None


def current_page() -> Optional[str]:
    """Returns the active Resolve page in lowercase, or None.

    This is the only sanctioned source of the active page (spec section 7,
    rule 4). Nothing infers the page from shortcuts, mouse movement, or the UI.
    """
    app = resolve_scriptapp()
    if app is None:
        return None
    try:
        page = app.GetCurrentPage()
    except Exception:
        return None
    return page.lower() if isinstance(page, str) and page else None


def call_resolve(method_name: str, *args: Any, **kwargs: Any) -> Any:
    """Invokes a method on the Resolve handle.

    Used by built-in commands whose behaviour is fixed by Macro Wheel and
    cannot be expressed as a keystroke sequence. Returns None when Resolve is
    unavailable rather than propagating an exception into the Menu.
    """
    app = resolve_scriptapp()
    if app is None:
        return None
    method = getattr(app, method_name, None)
    if method is None:
        return None
    try:
        return method(*args, **kwargs)
    except Exception:
        return None


def send_keys(sequence: str) -> bool:
    """Keystroke fallback for built-in commands.

    The Menu performs keystrokes natively and normally does not call this. It
    exists so a built-in command invoked through the Command Runtime behaves
    identically rather than silently doing nothing.

    Returns True when the sequence was dispatched.
    """
    try:
        if sys.platform.startswith("win"):
            import ctypes

            keybd_event = ctypes.windll.user32.keybd_event
            vk = ctypes.windll.user32.VkKeyScanW(ord(sequence[0].upper())) & 0xFF
            keybd_event(vk, 0, 0, 0)
            keybd_event(vk, 0, 2, 0)
            return True
        # macOS and Linux injection is handled natively by the Menu.
        return False
    except Exception:
        return False


if __name__ == "__main__":
    # Smoke-test entry point: `python macro_wheel_commands.py`.
    page = current_page()
    if page is None:
        print("ERROR: Resolve is not reachable.")
        sys.exit(1)
    print(page)