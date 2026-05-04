# Compatibility shim for ESP-IDF v6: the built-in `json` component was removed
# and replaced with managed `espressif/cjson`. This shim resolves any third-party
# component that still does `REQUIRES "json"` by transitively re-exporting cjson.
idf_component_register(REQUIRES cjson)
