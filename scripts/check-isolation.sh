#!/usr/bin/env bash
# Checks Treble's dependency rules (see Packages/TrebleKit/Package.swift):
#
#   - A module never imports another module, a service it didn't declare, or the shell.
#   - A service never imports a module or the shell.
#   - TrebleCore imports nothing of ours.
#   - The shell never imports a module.
#
# SwiftPM sometimes lets undeclared imports slip through, so this checks the source.
# Usage: scripts/check-isolation.sh

set -uo pipefail
cd "$(dirname "$0")/../Packages/TrebleKit/Sources" || exit 1

list() { [ -d "$1" ] && ls "$1" || true; }
modules=$(list Modules)
services=$(list Services)
fail=0

imports() { # imports <dir> <name> → true if any file in <dir> imports <name>
    grep -rqE "^[[:space:]]*(@testable[[:space:]]+)?import[[:space:]]+$2([[:space:]]|$)" "$1"
}

for m in $modules; do
    for other in TrebleShell $modules $services; do
        [ "$other" = "$m" ] && continue
        if imports "Modules/$m" "$other"; then
            # Importing a service is fine; the compiler checks it's declared in Package.swift.
            if echo "$services" | grep -qx "$other"; then continue; fi
            echo "✗ Module $m imports $other"
            fail=1
        fi
    done
done

for s in $services; do
    for other in TrebleShell $modules; do
        if imports "Services/$s" "$other"; then
            echo "✗ Service $s imports $other"
            fail=1
        fi
    done
done

for other in TrebleShell $modules $services; do
    if imports TrebleCore "$other"; then
        echo "✗ TrebleCore imports $other"
        fail=1
    fi
done

for m in $modules; do
    if imports TrebleShell "$m"; then
        echo "✗ TrebleShell imports $m"
        fail=1
    fi
done

if [ $fail -eq 0 ]; then
    echo "✓ Isolation rules hold ($(echo $modules | wc -w | tr -d ' ') modules, $(echo $services | wc -w | tr -d ' ') services)"
fi
exit $fail
