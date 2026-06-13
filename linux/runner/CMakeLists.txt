 bool | Literal[0, 1] = 0,
        extra_preargs: list[str] | None = ...,
        extra_postargs: list[str] | None = ...,
        build_temp: str | None = ...,
        target_lang: str | None = ...,
    ) -> None: ...
    def link_executable(
        self,
        objects: list[str],
        output_progname: str,
        output_dir: str | None = ...,
        libraries: list[str] | None = ...,
        library_dirs: list[str] | None = ...,
        runtime_library_dirs: list[str] | None = ...,
        debug: bool | Literal[0, 1] = 0,
        extra_preargs: list[str] | None = ...,
        extra_postargs: list[str] | None = ...,
        target_lang: str | None = ...,
    ) -> None: ...
    def link_shared_lib(
        self,
        objects: list[str],
        output_libname: str,
        output_dir: str | None = ...,
        libraries: list[str] | None = ...,
        library_dirs: list[str] | None = ...,
        runtime_library_dirs: list[str] | None = ...,
        export_symbols: list[str]