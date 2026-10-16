#!/bin/sh
# shellcheck shell=sh
# Entry-point dispatcher for runtimes that may or may not give the image
# ownership of PID 1.
#
# Normal Docker / Podman path: this script is PID 1, so we delegate to
# s6-overlay's /init exactly as before and keep the full supervision tree.
#
# Wrapped-runtime path (Fly Machines, `docker run --init`, some Nomad/K8s
# setups): the platform's own init is already PID 1 and execs the image
# entrypoint as a child. s6-overlay aborts there with "can only run as pid 1",
# so we run the stage2 bootstrap directly and then exec the main wrapper
# without /init.

set -e

# cont-init runs before s6 launches the container CMD, so it cannot discover
# `gateway run` by inspecting /proc: main-wrapper.sh does not exist yet. Carry
# that declared command through s6 in a root-private /run marker.  Do not use
# an environment declaration: /init deliberately scrubs the dispatcher env.
# Discard an ambient declaration first, then derive the marker only from this
# invocation.  Ask the canonical Python argv classifier rather than maintaining
# a second shell parser: optional top-level values (notably `-c gateway`) must
# retain exactly the same meaning at PID 1 as they do in the CLI.
unset HERMES_CONTAINER_GATEWAY_RUN
_hermes_gateway_marker=/run/hermes/container-gateway-run

if [ "$$" -eq 1 ]; then
    _hermes_classifier_status=0
    if /opt/hermes/.venv/bin/python -c '
try:
    import os
    import sys
    from hermes_cli._parser import command_argv

    command = command_argv(sys.argv[1:])
    no_supervise = "--no-supervise" in sys.argv[1:] or os.environ.get(
        "HERMES_GATEWAY_NO_SUPERVISE", ""
    ).lower() in ("1", "true", "yes")
except Exception:
    # Exit 1 means a valid command without gateway-run intent.  Never let an
    # import/startup/classifier failure impersonate that normal continuation.
    sys.exit(70)

sys.exit(0 if command[:2] == ["gateway", "run"] and not no_supervise else 1)
' "$@"; then
        _hermes_classifier_status=0
    else
        _hermes_classifier_status=$?
    fi

    case "$_hermes_classifier_status" in
        0) ;;
        1) _hermes_classifier_status= ;;
        *)
            echo "[hermes] ERROR: gateway intent classifier failed (exit $_hermes_classifier_status)" >&2
            exit "$_hermes_classifier_status"
            ;;
    esac

    if [ -n "$_hermes_classifier_status" ]; then
        (
        if [ -e "$_hermes_gateway_marker" ] || [ -L "$_hermes_gateway_marker" ]; then
            [ -f "$_hermes_gateway_marker" ] && [ ! -L "$_hermes_gateway_marker" ] && \
                [ "$(stat -c '%u:%g:%a' "$_hermes_gateway_marker")" = "0:0:600" ] || {
                echo "[hermes] ERROR: invalid pre-init gateway marker: $_hermes_gateway_marker" >&2; exit 1; }
            rm -f "$_hermes_gateway_marker"
        fi
        mkdir -p /run/hermes
        [ -d /run/hermes ] && [ ! -L /run/hermes ] || {
            echo "[hermes] ERROR: invalid pre-init marker directory: /run/hermes" >&2; exit 1; }
        chown root:root /run/hermes && chmod 0700 /run/hermes
        [ "$(stat -c '%u:%g:%a' /run/hermes)" = "0:0:700" ] || {
            echo "[hermes] ERROR: cannot secure pre-init marker directory" >&2; exit 1; }
        (umask 077; : > "$_hermes_gateway_marker")
        [ -f "$_hermes_gateway_marker" ] && [ ! -L "$_hermes_gateway_marker" ] && \
            [ "$(stat -c '%u:%g:%a' "$_hermes_gateway_marker")" = "0:0:600" ] || {
            echo "[hermes] ERROR: cannot record explicit gateway run intent" >&2; exit 1; }
        )
    fi
    exec /init /opt/hermes/docker/main-wrapper.sh "$@"
fi

echo "[hermes] WARNING: container entrypoint is not PID 1; skipping s6-overlay /init and falling back to direct bootstrap. Supervised services are unavailable in this runtime, but the requested command will still run." >&2
# /init normally seeds PATH with s6's helpers; the non-PID-1 fallback skips it.
export PATH="/command:/package/admin/s6/command:${PATH}"
/opt/hermes/docker/stage2-hook.sh
exec /opt/hermes/docker/main-wrapper.sh "$@"
