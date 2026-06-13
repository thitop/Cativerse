ook: Callable[[dict[Any, Any]], Any] | None = ...,
    parse_float: Callable[[str], Any] | None = ...,
    parse_int: Callable[[str], Any] | None = ...,
    parse_constant: Callable[[str], Any] | None = ...,
    object_pairs_hook: Callable[[list[tuple[Any, Any]]], Any] | None = ...,
    use_decimal: bool = ...,
    allow_nan: bool = ...,
) -> Any: ...
@overload
def load(
    fp: IO[str],
    encoding: str | None = ...,
    *,
    cls: type[JSONDecoder],
    object_hook: Callable[[dict[Any, Any]], Any] | None = ...,
    parse_float: Callable[[str], Any] | None = ...,
    parse_int: Callable[[str], Any] | None = ...,
    parse_constant: Callable[[str], Any] | None = ...,
    object_pairs_hook: Callable[[list[tuple[Any, Any]]], Any] | None = ...,
    use_decimal: bool = ...,
    allow_nan: bool = ...,
    **kw: Any,
) -> Any: ...
@overload
def load(
    fp: IO[str],
    encoding: str | None = ...,
    cls: type[JSONDecoder] | None = ...,
    object_h