#!/bin/bash
# Module: WARP Native

manage_warp_native() {
    echo -e ""
    echo -e "${COLOR_GREEN}${LANG[WARP_NATIVE_MENU]}${COLOR_RESET}"
    echo -e ""
    echo -e "${COLOR_YELLOW}1. ${LANG[WARP_INSTALL]}${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}2. ${LANG[WARP_UNINSTALL]}${COLOR_RESET}"
    echo -e ""
    echo -e "${COLOR_YELLOW}3. ${LANG[WARP_ADD_CONFIG]}${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}4. ${LANG[WARP_DELETE_WARP_SETTINGS]}${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}5. ${LANG[WARP_FULL_ROUTE]}${COLOR_RESET}"
    echo -e ""
    echo -e "${COLOR_YELLOW}0. ${LANG[EXIT]}${COLOR_RESET}"
    echo -e ""
    reading "${LANG[WARP_PROMPT]}" WARP_OPTION

    case $WARP_OPTION in
        1)
            if ! grep -q "remnanode:" /opt/remnawave/docker-compose.yml 2>/dev/null && \
               ! grep -q "remnanode:" /opt/remnanode/docker-compose.yml 2>/dev/null; then
                echo -e "${COLOR_RED}${LANG[WARP_NO_NODE]}${COLOR_RESET}"
                sleep 2
                log_clear
                manage_warp_native
                return
            fi
            bash <(curl -fsSL https://raw.githubusercontent.com/distillium/warp-native/main/install.sh)
            local warp_install_status=$?
            if [ "$warp_install_status" -eq 0 ]; then
                ensure_warp_endpoint_connectivity
            fi
            sleep 2
            log_clear
            manage_warp_native
            ;;
        2)
            bash <(curl -fsSL https://raw.githubusercontent.com/distillium/warp-native/main/uninstall.sh)
            sleep 2
            log_clear
            manage_warp_native
            ;;
        3)
            manage_warp_add_config
            sleep 2
            log_clear
            manage_warp_native
            ;;
        4)
            manage_warp_delete_settings
            sleep 2
            log_clear
            manage_warp_native
            ;;
        5)
            manage_warp_full_route
            sleep 2
            log_clear
            manage_warp_native
            ;;
        0)
            echo -e "${COLOR_YELLOW}${LANG[EXIT]}${COLOR_RESET}"
            ;;
        *)
            echo -e "${COLOR_RED}${LANG[WARP_INVALID_CHOICE]}${COLOR_RESET}"
            sleep 2
            log_clear
            manage_warp_native
            ;;
    esac
}

cleanup_warp_config_json() {
    local config_json="$1"

    echo "$config_json" | jq '
        .outbounds = [(.outbounds // [])[] | select(.tag != "warp-out")]
        | (.routing //= {})
        | .routing.rules = [
            (.routing.rules // [])[]
            | select(
                (.outboundTag // "") != "warp-out"
                and (.balancerTag // "") != "warp-fallback"
                and (.ruleTag // "") != "warp-full-route"
            )
        ]
        | .routing.balancers = [(.routing.balancers // [])[] | select(.tag != "warp-fallback")]
        | if has("observatory") and (.observatory | type == "object") then
            .observatory.subjectSelector = [(.observatory.subjectSelector // [])[] | select(. != "warp-out")]
            | if ((.observatory.subjectSelector // []) | length) == 0 then
                del(.observatory)
              else
                .
              end
          else
            .
          end
    '
}

ensure_warp_endpoint_connectivity() {
    local warp_conf="/etc/wireguard/warp.conf"
    local warp_service="wg-quick@warp"
    local endpoint_line endpoint_host original_endpoint backup_file
    local -a candidate_ports=("2408" "500" "1701" "4500")

    if [ ! -f "$warp_conf" ]; then
        echo -e "${COLOR_YELLOW}${LANG[WARP_ENDPOINT_SKIP]}${COLOR_RESET}"
        return 0
    fi

    if ! command -v wg > /dev/null 2>&1 || ! command -v systemctl > /dev/null 2>&1; then
        echo -e "${COLOR_YELLOW}${LANG[WARP_ENDPOINT_SKIP]}${COLOR_RESET}"
        return 0
    fi

    endpoint_line=$(awk -F' = ' '/^Endpoint = / {print $2; exit}' "$warp_conf")
    endpoint_host="${endpoint_line%:*}"
    if [ -z "$endpoint_host" ] || [ "$endpoint_host" = "$endpoint_line" ]; then
        endpoint_host="engage.cloudflareclient.com"
    fi

    backup_file="${warp_conf}.bak.$(date +%Y%m%d-%H%M%S)"
    cp "$warp_conf" "$backup_file"

    echo -e "${COLOR_YELLOW}${LANG[WARP_ENDPOINT_CHECK]}${COLOR_RESET}"

    local selected_port=""
    local latest_handshake received_bytes
    for port in "${candidate_ports[@]}"; do
        printf "${COLOR_YELLOW}${LANG[WARP_ENDPOINT_TEST]}${COLOR_RESET}\n" "$port"
        sed -i -E "s|^Endpoint = .*$|Endpoint = ${endpoint_host}:${port}|" "$warp_conf"

        if ! systemctl restart "$warp_service" > /dev/null 2>&1; then
            printf "${COLOR_RED}${LANG[WARP_ENDPOINT_TEST_FAIL]}${COLOR_RESET}\n" "$port"
            continue
        fi

        sleep 12

        latest_handshake=$(wg show warp latest-handshakes 2>/dev/null | awk 'NR==1 {print $2}')
        received_bytes=$(wg show warp transfer 2>/dev/null | awk 'NR==1 {print $3}')

        if [ -n "$latest_handshake" ] && [ "$latest_handshake" != "0" ] && \
           [ -n "$received_bytes" ] && [ "$received_bytes" != "0" ]; then
            selected_port="$port"
            break
        fi
    done

    if [ -n "$selected_port" ]; then
        printf "${COLOR_GREEN}${LANG[WARP_ENDPOINT_SELECTED]}${COLOR_RESET}\n" "$selected_port"
        return 0
    fi

    cp "$backup_file" "$warp_conf"
    systemctl restart "$warp_service" > /dev/null 2>&1 || true
    echo -e "${COLOR_RED}${LANG[WARP_ENDPOINT_RESTORE]}${COLOR_RESET}"
    return 1
}

select_warp_node_profile() {
    local token="$1"
    local domain_url="${2:-127.0.0.1:3000}"
    local selection_prompt="${3:-${LANG[WARP_SELECT_CONFIG]}}"

    local nodes_response
    nodes_response=$(make_api_request "GET" "${domain_url}/api/nodes" "$token")
    if [ -z "$nodes_response" ] || ! echo "$nodes_response" | jq -e '.response | type == "array"' > /dev/null 2>&1; then
        echo -e "${COLOR_RED}${LANG[WARP_NO_PANEL_NODES]}: Invalid response${COLOR_RESET}" >&2
        return 1
    fi

    local nodes
    nodes=$(echo "$nodes_response" | jq -r '
        .response[]
        | select(.isDisabled != true)
        | select(.name and .configProfile.activeConfigProfileUuid and .configProfile.activeConfigProfileUuid != null)
        | [.name, (.address // "-"), .configProfile.activeConfigProfileUuid]
        | @tsv
    ' 2>/dev/null)
    if [ -z "$nodes" ]; then
        echo -e "${COLOR_RED}${LANG[WARP_NO_PANEL_NODES]}${COLOR_RESET}" >&2
        return 1
    fi

    echo -e ""
    echo -e "${COLOR_YELLOW}${selection_prompt}${COLOR_RESET}" >&2
    echo -e "" >&2

    local i=1
    declare -A profile_map
    while IFS=$'\t' read -r name address profile_uuid; do
        echo -e "${COLOR_YELLOW}$i. $name [$address]${COLOR_RESET}" >&2
        profile_map[$i]="$profile_uuid"
        ((i++))
    done <<< "$nodes"

    echo -e "" >&2
    echo -e "${COLOR_YELLOW}0. ${LANG[EXIT]}${COLOR_RESET}" >&2
    echo -e "" >&2

    local config_option
    reading "${LANG[WARP_PROMPT1]}" config_option

    if [ "$config_option" = "0" ]; then
        echo -e "${COLOR_YELLOW}${LANG[EXIT]}${COLOR_RESET}" >&2
        return 1
    fi

    if [ -z "${profile_map[$config_option]}" ]; then
        echo -e "${COLOR_RED}${LANG[WARP_INVALID_CHOICE2]}${COLOR_RESET}" >&2
        return 1
    fi

    echo "${profile_map[$config_option]}"
}

manage_warp_full_route() {
    load_api_module

    local domain_url="127.0.0.1:3000"

    echo -e ""
    echo -e "${COLOR_RED}${LANG[WARNING_LABEL]}${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}${LANG[WARP_CONFIRM_SERVER_PANEL]}${COLOR_RESET}"
    echo -e ""
    echo -e "${COLOR_GREEN}[?]${COLOR_RESET} ${COLOR_YELLOW}${LANG[CONFIRM_PROMPT]}${COLOR_RESET}"
    read confirm
    echo

    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${COLOR_YELLOW}${LANG[EXIT]}${COLOR_RESET}"
        return 0
    fi

    get_panel_token
    token=$(cat "$TOKEN_FILE")

    local selected_uuid
    selected_uuid=$(select_warp_node_profile "$token" "$domain_url" "${LANG[WARP_SELECT_CONFIG_FULL_ROUTE]}") || return 1

    local config_data
    config_data=$(make_api_request "GET" "${domain_url}/api/config-profiles/$selected_uuid" "$token")
    if [ -z "$config_data" ] || ! echo "$config_data" | jq -e '.' > /dev/null 2>&1; then
        echo -e "${COLOR_RED}${LANG[WARP_UPDATE_FAIL]}: Invalid response${COLOR_RESET}"
        return 1
    fi

    local config_json
    if echo "$config_data" | jq -e '.response.config' > /dev/null 2>&1; then
        config_json=$(echo "$config_data" | jq -r '.response.config')
    else
        config_json=$(echo "$config_data" | jq -r '.config // ""')
    fi

    if [ -z "$config_json" ] || [ "$config_json" = "null" ]; then
        echo -e "${COLOR_RED}${LANG[WARP_UPDATE_FAIL]}: No config found in response${COLOR_RESET}"
        return 1
    fi

    local inbound_tags
    inbound_tags=$(echo "$config_json" | jq -c '[.inbounds[]?.tag | select(type == "string" and length > 0)] | unique')
    if [ -z "$inbound_tags" ] || [ "$inbound_tags" = "[]" ]; then
        echo -e "${COLOR_RED}${LANG[WARP_NO_INBOUNDS]}${COLOR_RESET}"
        return 1
    fi

    config_json=$(cleanup_warp_config_json "$config_json")

    local warp_outbound='{
        "tag": "warp-out",
        "protocol": "freedom",
        "settings": {
            "domainStrategy": "UseIP"
        },
        "streamSettings": {
            "sockopt": {
                "interface": "warp",
                "tcpFastOpen": true
            }
        }
    }'

    config_json=$(echo "$config_json" | jq \
        --argjson warp_out "$warp_outbound" \
        --argjson inbound_tags "$inbound_tags" '
        (.outbounds //= [])
        | (.routing //= {})
        | (.routing.rules //= [])
        | (.routing.balancers //= [])
        | .outbounds += [$warp_out]
        | .routing.balancers += [
            {
                "tag": "warp-fallback",
                "selector": ["warp-out"],
                "fallbackTag": "DIRECT",
                "strategy": {
                    "type": "random"
                }
            }
        ]
        | .routing.rules += [
            {
                "type": "field",
                "inboundTag": $inbound_tags,
                "balancerTag": "warp-fallback",
                "ruleTag": "warp-full-route"
            }
        ]
        | (.observatory //= {})
        | (.observatory.subjectSelector //= [])
        | .observatory.subjectSelector |= (. + ["warp-out"] | unique)
        | .observatory.probeUrl = (.observatory.probeUrl // "https://connectivitycheck.gstatic.com/generate_204")
        | .observatory.probeInterval = (.observatory.probeInterval // "10s")
        | .observatory.enableConcurrency = (.observatory.enableConcurrency // false)
    ' 2>/dev/null)

    if [ -z "$config_json" ] || [ "$config_json" = "null" ]; then
        echo -e "${COLOR_RED}${LANG[WARP_UPDATE_FAIL]}: Failed to build full-route config${COLOR_RESET}"
        return 1
    fi

    local update_response
    update_response=$(make_api_request "PATCH" "${domain_url}/api/config-profiles" "$token" "{\"uuid\": \"$selected_uuid\", \"config\": $config_json}")
    if [ -z "$update_response" ] || ! echo "$update_response" | jq -e '.response.uuid' > /dev/null 2>&1; then
        echo -e "${COLOR_RED}${LANG[WARP_UPDATE_FAIL]}: Invalid response${COLOR_RESET}"
        return 1
    fi

    echo -e "${COLOR_GREEN}${LANG[WARP_FULL_ROUTE_SUCCESS]}${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}${LANG[WARP_FULL_ROUTE_NOTE]}${COLOR_RESET}"
}

manage_warp_add_config() {
    load_api_module

    local domain_url="127.0.0.1:3000"

    echo -e ""
    echo -e "${COLOR_RED}${LANG[WARNING_LABEL]}${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}${LANG[WARP_CONFIRM_SERVER_PANEL]}${COLOR_RESET}"
    echo -e ""
    echo -e "${COLOR_GREEN}[?]${COLOR_RESET} ${COLOR_YELLOW}${LANG[CONFIRM_PROMPT]}${COLOR_RESET}"
    read confirm
    echo

    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${COLOR_YELLOW}${LANG[EXIT]}${COLOR_RESET}"
        return 0
    fi

    get_panel_token
    token=$(cat "$TOKEN_FILE")

    local selected_uuid
    selected_uuid=$(select_warp_node_profile "$token" "$domain_url" "${LANG[WARP_SELECT_CONFIG]}") || return 1

    local config_data=$(make_api_request "GET" "${domain_url}/api/config-profiles/$selected_uuid" "$token")
    if [ -z "$config_data" ] || ! echo "$config_data" | jq -e '.' > /dev/null 2>&1; then
        echo -e "${COLOR_RED}${LANG[WARP_UPDATE_FAIL]}: Invalid response${COLOR_RESET}"
        return 1
    fi

    local config_json
    if echo "$config_data" | jq -e '.response.config' > /dev/null 2>&1; then
        config_json=$(echo "$config_data" | jq -r '.response.config')
    else
        config_json=$(echo "$config_data" | jq -r '.config // ""')
    fi

    if [ -z "$config_json" ] || [ "$config_json" == "null" ]; then
        echo -e "${COLOR_RED}${LANG[WARP_UPDATE_FAIL]}: No config found in response${COLOR_RESET}"
        return 1
    fi

    config_json=$(echo "$config_json" | jq '
        (.routing //= {})
        | (.routing.rules //= [])
        | .routing.rules = [.routing.rules[] | select((.ruleTag // "") != "warp-full-route" and (.balancerTag // "") != "warp-fallback")]
        | .routing.balancers = [(.routing.balancers // [])[] | select(.tag != "warp-fallback")]
        | if has("observatory") and (.observatory | type == "object") then
            .observatory.subjectSelector = [(.observatory.subjectSelector // [])[] | select(. != "warp-out")]
            | if ((.observatory.subjectSelector // []) | length) == 0 then
                del(.observatory)
              else
                .
              end
          else
            .
          end
    ' 2>/dev/null)

    config_json=$(echo "$config_json" | jq '(.outbounds //= [])' 2>/dev/null)

    if echo "$config_json" | jq -e '.outbounds[]? | select(.tag == "warp-out")' > /dev/null 2>&1; then
        echo -e "${COLOR_YELLOW}${LANG[WARP_WARNING]}${COLOR_RESET}"
    else
        local warp_outbound='{
            "tag": "warp-out",
            "protocol": "freedom",
            "settings": {
			    "domainStrategy": "UseIP"
			},
            "streamSettings": {
                "sockopt": {
                    "interface": "warp",
                    "tcpFastOpen": true
                }
            }
        }'
        config_json=$(echo "$config_json" | jq --argjson warp_out "$warp_outbound" '.outbounds += [$warp_out]' 2>/dev/null)
    fi

    if echo "$config_json" | jq -e '.routing.rules[]? | select(.outboundTag == "warp-out")' > /dev/null 2>&1; then
        echo -e "${COLOR_YELLOW}${LANG[WARP_WARNING2]}${COLOR_RESET}"
    else
        local warp_rule='{
            "type": "field",
            "domain": ["whoer.net", "browserleaks.com", "2ip.io", "2ip.ru"],
            "outboundTag": "warp-out"
        }'
        config_json=$(echo "$config_json" | jq --argjson warp_rule "$warp_rule" '.routing.rules += [$warp_rule]' 2>/dev/null)
    fi

    local update_response=$(make_api_request "PATCH" "${domain_url}/api/config-profiles" "$token" "{\"uuid\": \"$selected_uuid\", \"config\": $config_json}")
    if [ -z "$update_response" ] || ! echo "$update_response" | jq -e '.' > /dev/null 2>&1; then
        echo -e "${COLOR_RED}${LANG[WARP_UPDATE_FAIL]}: Invalid response${COLOR_RESET}"
        return 1
    fi

    echo -e "${COLOR_GREEN}${LANG[WARP_UPDATE_SUCCESS]}${COLOR_RESET}"
}

manage_warp_delete_settings() {
    load_api_module

    local domain_url="127.0.0.1:3000"

    echo -e ""
    echo -e "${COLOR_RED}${LANG[WARNING_LABEL]}${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}${LANG[WARP_CONFIRM_SERVER_PANEL]}${COLOR_RESET}"
    echo -e ""
    echo -e "${COLOR_GREEN}[?]${COLOR_RESET} ${COLOR_YELLOW}${LANG[CONFIRM_PROMPT]}${COLOR_RESET}"
    read confirm
    echo

    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${COLOR_YELLOW}${LANG[EXIT]}${COLOR_RESET}"
        return 0
    fi

    get_panel_token
    token=$(cat "$TOKEN_FILE")

    local selected_uuid
    selected_uuid=$(select_warp_node_profile "$token" "$domain_url" "${LANG[WARP_SELECT_CONFIG_DELETE]}") || return 1

    local config_data=$(make_api_request "GET" "${domain_url}/api/config-profiles/$selected_uuid" "$token")
    if [ -z "$config_data" ] || ! echo "$config_data" | jq -e '.' > /dev/null 2>&1; then
        echo -e "${COLOR_RED}${LANG[WARP_UPDATE_FAIL]}: Invalid response${COLOR_RESET}"
        return 1
    fi

    local config_json
    if echo "$config_data" | jq -e '.response.config' > /dev/null 2>&1; then
        config_json=$(echo "$config_data" | jq -r '.response.config')
    else
        config_json=$(echo "$config_data" | jq -r '.config // ""')
    fi

    if [ -z "$config_json" ] || [ "$config_json" == "null" ]; then
        echo -e "${COLOR_RED}${LANG[WARP_UPDATE_FAIL]}: No config found in response${COLOR_RESET}"
        return 1
    fi

    local has_warp_outbound has_warp_rule has_warp_full_route
    has_warp_outbound=$(echo "$config_json" | jq -e '.outbounds[]? | select(.tag == "warp-out")' > /dev/null 2>&1; echo $?)
    has_warp_rule=$(echo "$config_json" | jq -e '.routing.rules[]? | select(.outboundTag == "warp-out")' > /dev/null 2>&1; echo $?)
    has_warp_full_route=$(echo "$config_json" | jq -e '.routing.rules[]? | select((.balancerTag // "") == "warp-fallback" or (.ruleTag // "") == "warp-full-route")' > /dev/null 2>&1; echo $?)

    config_json=$(cleanup_warp_config_json "$config_json")

    if [ "$has_warp_outbound" -eq 0 ]; then
        echo -e "${COLOR_YELLOW}${LANG[WARP_REMOVED_WARP_SETTINGS1]}${COLOR_RESET}"
    else
        echo -e "${COLOR_YELLOW}${LANG[WARP_NO_WARP_SETTINGS1]}${COLOR_RESET}"
    fi

    if [ "$has_warp_rule" -eq 0 ]; then
        echo -e "${COLOR_YELLOW}${LANG[WARP_REMOVED_WARP_SETTINGS2]}${COLOR_RESET}"
    else
        echo -e "${COLOR_YELLOW}${LANG[WARP_NO_WARP_SETTINGS2]}${COLOR_RESET}"
    fi

    if [ "$has_warp_full_route" -eq 0 ]; then
        echo -e "${COLOR_YELLOW}${LANG[WARP_REMOVED_FULL_ROUTE]}${COLOR_RESET}"
    fi

    local update_response=$(make_api_request "PATCH" "${domain_url}/api/config-profiles" "$token" "{\"uuid\": \"$selected_uuid\", \"config\": $config_json}")
    if [ -z "$update_response" ] || ! echo "$update_response" | jq -e '.' > /dev/null 2>&1; then
        echo -e "${COLOR_RED}${LANG[WARP_UPDATE_FAIL]}: Invalid response${COLOR_RESET}"
        return 1
    fi

    echo -e "${COLOR_GREEN}${LANG[WARP_DELETE_SUCCESS]}${COLOR_RESET}"
}
