"""Errors a route raises; the app turns them into JSON responses."""


class HttpError(Exception):
    def __init__(self, status: int, payload: dict):
        super().__init__(payload.get("error", status))
        self.status = status
        self.payload = payload


class BadRequest(HttpError):
    def __init__(self, message: str):
        super().__init__(400, {"error": message})


class Forbidden(HttpError):
    def __init__(self, message: str):
        super().__init__(403, {"error": message})


class NotFound(HttpError):
    def __init__(self, message: str = "no such route"):
        super().__init__(404, {"error": message})


class MethodNotAllowed(HttpError):
    def __init__(self, message: str = "method not allowed"):
        super().__init__(405, {"error": message})
