#!/bin/bash

get_mac_address_alpine() {
    adapter_name="$1"
    mac_address=$(ip link show "$adapter_name" | awk '/link\/ether/ {print $2}')
    echo "$mac_address"
}

get_mac_address_generic() {
    adapter_name="$1"
    mac_address=$(ip link show "$adapter_name" | awk '/ether/ {print $2}')
    echo "$mac_address"
}

get_mac_address_list() {
    adapters=$(ip link show | awk -F': ' '/^[0-9]+:/{print $2}')
    if [[ "$(uname -a)" == *"Alpine"* ]]; then
        # Loop through all adapters and mount a list adapter_name=mac_value
        for adapter in $adapters; do
            mac=$(get_mac_address_alpine "$adapter")
            echo "$adapter=$mac"
        done
    else
        # Loop through all adapters and mount a list adapter_name=mac_value
        for adapter in $adapters; do
            mac=$(get_mac_address_generic "$adapter")
            echo "$adapter=$mac"
        done
    fi
}

#get_mac_address_list
