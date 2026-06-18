set quiet := true
set shell := ['bash', '-euo', 'pipefail', '-c']

talosconfig := justfile_dir() + "/clusterconfig/talosconfig"
talconfig   := justfile_dir() + "/talconfig.yaml"

[private]
default:
    just --list --justfile {{ source_file() }}

[doc('Reset all nodes to maintenance mode (destructive — wipes STATE, EPHEMERAL, and Ceph OSD disks)')]
reset-cluster:
    task talos:reset

[doc('Reset a single node back to maintenance mode')]
reset-node node:
    gum confirm "Reset node {{ node }}? This wipes STATE + EPHEMERAL." || exit 0
    talosctl reset --nodes "{{ node }}" --graceful=false --reboot \
        --system-labels-to-wipe STATE --system-labels-to-wipe EPHEMERAL

[doc('Reboot a single node')]
reboot-node node:
    gum confirm "Reboot node {{ node }}?" || exit 0
    talosctl reboot --nodes "{{ node }}"

[doc('Power off a single node')]
shutdown-node node:
    gum confirm "Shut down node {{ node }}?" || exit 0
    talosctl shutdown --nodes "{{ node }}"

[doc('Upgrade Talos on a single node — reads image from talenv.yaml')]
upgrade-node node:
    task talos:upgrade-node IP="{{ node }}"

[doc('Check cluster health')]
health:
    talosctl health

[doc('Show node overview: role, IP, Talos version, Kubernetes version')]
nodes:
    #!/usr/bin/env bash
    set -uo pipefail
    NODE_COUNT=$(yq '.nodes | length' "{{ talconfig }}")
    {
        echo "NODE,ROLE,IP,TALOS,KUBERNETES"
        for i in $(seq 0 $((NODE_COUNT - 1))); do
            HOSTNAME=$(yq ".nodes[${i}].hostname" "{{ talconfig }}")
            IP=$(yq ".nodes[${i}].ipAddress" "{{ talconfig }}")
            IS_CP=$(yq ".nodes[${i}].controlPlane" "{{ talconfig }}")
            ROLE=$([[ "${IS_CP}" == "true" ]] && echo "CP" || echo "worker")

            VER=$(talosctl --talosconfig "{{ talosconfig }}" version \
                    --nodes "${IP}" -o json 2>/dev/null) || VER=""
            if [ -z "${VER}" ]; then
                echo "${HOSTNAME},${ROLE},${IP},offline,offline"
            else
                TALOS=$(printf '%s' "${VER}" | jq -r '.server.messages[0].version.tag // "?"')
                K8S=$(printf '%s' "${VER}" | jq -r '.server.messages[0].kubernetesVersion // "?"')
                echo "${HOSTNAME},${ROLE},${IP},${TALOS},${K8S}"
            fi
        done
    } | gum table --print -s ","

[doc('Show disk inventory for all nodes')]
disks:
    #!/usr/bin/env bash
    set -uo pipefail
    NODE_COUNT=$(yq '.nodes | length' "{{ talconfig }}")
    {
        echo "NODE,DEVICE,MODEL,SERIAL,SIZE,TYPE"
        for i in $(seq 0 $((NODE_COUNT - 1))); do
            HOSTNAME=$(yq ".nodes[${i}].hostname" "{{ talconfig }}")
            IP=$(yq ".nodes[${i}].ipAddress" "{{ talconfig }}")

            DISKS=$(talosctl --talosconfig "{{ talosconfig }}" get disks \
                     --nodes "${IP}" -o json 2>/dev/null) || DISKS=""
            if [ -z "${DISKS}" ]; then
                echo "${HOSTNAME},-,-,-,-,offline"
                continue
            fi

            printf '%s\n' "${DISKS}" | jq -r --arg host "${HOSTNAME}" '
                select(.spec.model != null) | [
                  $host,
                  ("/dev/" + .metadata.id),
                  (.spec.model | gsub("^\\s+|\\s+$"; "")),
                  (.spec.serial // "—"),
                  (.spec.size |
                    if   . >= 1099511627776 then ((. / 1099511627776 | floor | tostring) + " TB")
                    elif . >= 1073741824    then ((. / 1073741824    | floor | tostring) + " GB")
                    else                         ((. / 1048576        | floor | tostring) + " MB")
                    end),
                  (.spec.type // "" | ltrimstr("DISK_TYPE_") | ascii_downcase)
                ] | join(",")
            ' 2>/dev/null || true
        done
    } | gum table --print -s ","
