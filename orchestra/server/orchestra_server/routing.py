"""The route table: modules register handlers with @route on import."""

import re
from collections.abc import Callable

ROUTES: list[tuple[str, re.Pattern, Callable]] = []
STREAMED = object()  # a handler that wrote its own response returns this


def route(method: str, pattern: str):
    def register(handler: Callable) -> Callable:
        ROUTES.append((method, re.compile(f"^{pattern}$"), handler))
        return handler

    return register


class Request:
    def __init__(self, handler, params: dict, query: dict, body: dict):
        self.handler = handler
        self.params = params
        self.query = query
        self.body = body
