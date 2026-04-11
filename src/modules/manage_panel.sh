#!/bin/bash
# Module: Manage Panel

ensure_manage_panel_api_loaded() {
    if declare -F get_panel_token > /dev/null 2>&1 && declare -F make_api_request > /dev/null 2>&1; then
        return 0
    fi

    if declare -F load_api_module > /dev/null 2>&1; then
        load_api_module
    fi

    declare -F get_panel_token > /dev/null 2>&1 && declare -F make_api_request > /dev/null 2>&1
}

show_manage_panel_menu() {
    echo -e ""
    echo -e "${COLOR_GREEN}${LANG[MENU_3]}${COLOR_RESET}"
    echo -e ""
    echo -e "${COLOR_YELLOW}1. ${LANG[START_PANEL_NODE]}${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}2. ${LANG[STOP_PANEL_NODE]}${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}3. ${LANG[UPDATE_PANEL_NODE]}${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}4. ${LANG[VIEW_LOGS]}${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}5. ${LANG[REMNAWAVE_CLI]}${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}6. ${LANG[ACCESS_PANEL]}${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}7. ${LANG[CASCADE_SETUP]}${COLOR_RESET}"
    echo -e ""
    echo -e "${COLOR_YELLOW}0. ${LANG[EXIT]}${COLOR_RESET}"
    echo -e ""
    reading "${LANG[MANAGE_PANEL_NODE_PROMPT]}" SUB_OPTION

    case $SUB_OPTION in
        1)
            start_panel_node
            sleep 2
            log_clear
            show_manage_panel_menu
            ;;
        2)
            stop_panel_node
            sleep 2
            log_clear
            show_manage_panel_menu
            ;;
        3)
            update_panel_node
            sleep 2
            log_clear
            show_manage_panel_menu
            ;;
        4)
            view_logs
            sleep 2
            log_clear
            show_manage_panel_menu
            ;;
        5)
            run_remnawave_cli
            sleep 2
            log_clear
            show_manage_panel_menu
            ;;
        6)
            manage_panel_access
            sleep 2
            log_clear
            show_manage_panel_menu
            ;;
        7)
            setup_two_node_cascade
            sleep 2
            log_clear
            show_manage_panel_menu
            ;;
        0)
            remnawave_reverse
            ;;
        *)
            echo -e "${COLOR_YELLOW}${LANG[MANAGE_PANEL_NODE_INVALID_CHOICE]}${COLOR_RESET}"
            sleep 1
            show_manage_panel_menu
            ;;
    esac
}

run_remnawave_cli() {
    if ! docker ps --format '{{.Names}}' | grep -q '^remnawave$'; then
        echo -e "${COLOR_YELLOW}${LANG[CONTAINER_NOT_RUNNING]}${COLOR_RESET}"
        return 1
    fi

    exec 3>&1 4>&2
    exec > /dev/tty 2>&1

    echo -e "${COLOR_YELLOW}${LANG[RUNNING_CLI]}${COLOR_RESET}"
    if docker exec -it -e TERM=xterm-256color remnawave remnawave; then
        echo -e "${COLOR_GREEN}${LANG[CLI_SUCCESS]}${COLOR_RESET}"
    else
        echo -e "${COLOR_RED}${LANG[CLI_FAILED]}${COLOR_RESET}"
        exec 1>&3 2>&4
        return 1
    fi

    exec 1>&3 2>&4
}

start_panel_node() {
    local dir=""
    if [ -d "/opt/remnawave" ]; then
        dir="/opt/remnawave"
    elif [ -d "/opt/remnanode" ]; then
        dir="/opt/remnanode"
    else
        echo -e "${COLOR_RED}${LANG[DIR_NOT_FOUND]}${COLOR_RESET}"
        exit 1
    fi

    cd "$dir" || { echo -e "${COLOR_RED}${LANG[CHANGE_DIR_FAILED]} $dir${COLOR_RESET}"; exit 1; }

    if docker ps -q --filter "ancestor=remnawave/backend:latest" | grep -q . || docker ps -q --filter "ancestor=remnawave/node:latest" | grep -q . || docker ps -q --filter "ancestor=remnawave/backend:2" | grep -q .; then
        echo -e "${COLOR_GREEN}${LANG[PANEL_RUNNING]}${COLOR_RESET}"
    else
        echo -e "${COLOR_YELLOW}${LANG[STARTING_PANEL_NODE]}...${COLOR_RESET}"
        sleep 1
        docker compose up -d > /dev/null 2>&1 &
        spinner $! "${LANG[WAITING]}"
        echo -e "${COLOR_GREEN}${LANG[PANEL_RUN]}${COLOR_RESET}"
    fi
}

stop_panel_node() {
    local dir=""
    if [ -d "/opt/remnawave" ]; then
        dir="/opt/remnawave"
    elif [ -d "/opt/remnanode" ]; then
        dir="/opt/remnanode"
    else
        echo -e "${COLOR_RED}${LANG[DIR_NOT_FOUND]}${COLOR_RESET}"
        exit 1
    fi

    cd "$dir" || { echo -e "${COLOR_RED}${LANG[CHANGE_DIR_FAILED]} $dir${COLOR_RESET}"; exit 1; }
    if ! docker ps -q --filter "ancestor=remnawave/backend:latest" | grep -q . && ! docker ps -q --filter "ancestor=remnawave/node:latest" | grep -q . && ! docker ps -q --filter "ancestor=remnawave/backend:2" | grep -q .; then
        echo -e "${COLOR_GREEN}${LANG[PANEL_STOPPED]}${COLOR_RESET}"
    else
        echo -e "${COLOR_YELLOW}${LANG[STOPPING_REMNAWAVE]}...${COLOR_RESET}"
        sleep 1
        docker compose down > /dev/null 2>&1 &
        spinner $! "${LANG[WAITING]}"
        echo -e "${COLOR_GREEN}${LANG[PANEL_STOP]}${COLOR_RESET}"
    fi
}

update_panel_node() {
    local dir=""
    if [ -d "/opt/remnawave" ]; then
        dir="/opt/remnawave"
    elif [ -d "/opt/remnanode" ]; then
        dir="/opt/remnanode"
    else
        echo -e "${COLOR_RED}${LANG[DIR_NOT_FOUND]}${COLOR_RESET}"
        exit 1
    fi

    cd "$dir" || { echo -e "${COLOR_RED}${LANG[CHANGE_DIR_FAILED]} $dir${COLOR_RESET}"; exit 1; }
    echo -e "${COLOR_YELLOW}${LANG[UPDATING]}${COLOR_RESET}"
    sleep 1

    images_before=$(docker compose config --images | sort -u)
    if [ -n "$images_before" ]; then
        before=$(echo "$images_before" | xargs -I {} docker images -q {} | sort -u)
    else
        before=""
    fi

    tmpfile=$(mktemp)
    docker compose pull > "$tmpfile" 2>&1 &
    spinner $! "${LANG[WAITING]}"
    pull_output=$(cat "$tmpfile")
    rm -f "$tmpfile"

    images_after=$(docker compose config --images | sort -u)
    if [ -n "$images_after" ]; then
        after=$(echo "$images_after" | xargs -I {} docker images -q {} | sort -u)
    else
        after=""
    fi

    if [ "$before" != "$after" ] || echo "$pull_output" | grep -q "Pull complete"; then
        echo -e ""
	echo -e "${COLOR_YELLOW}${LANG[IMAGES_DETECTED]}${COLOR_RESET}"
        docker compose down > /dev/null 2>&1 &
        spinner $! "${LANG[WAITING]}"
        sleep 5
        docker compose up -d > /dev/null 2>&1 &
        spinner $! "${LANG[WAITING]}"
        sleep 1
        docker image prune -f > /dev/null 2>&1
        echo -e "${COLOR_GREEN}${LANG[UPDATE_SUCCESS1]}${COLOR_RESET}"
    else
        echo -e "${COLOR_YELLOW}${LANG[NO_UPDATE]}${COLOR_RESET}"
    fi
}

view_logs() {
    local dir=""
    if [ -d "/opt/remnawave" ]; then
        dir="/opt/remnawave"
    elif [ -d "/opt/remnanode" ]; then
        dir="/opt/remnanode"
    else
        echo -e "${COLOR_RED}${LANG[DIR_NOT_FOUND]}${COLOR_RESET}"
        exit 1
    fi

    cd "$dir" || { echo -e "${COLOR_RED}${LANG[CHANGE_DIR_FAILED]} $dir${COLOR_RESET}"; exit 1; }

    if ! docker ps -q --filter "ancestor=remnawave/backend:latest" | grep -q . && ! docker ps -q --filter "ancestor=remnawave/node:latest" | grep -q . && ! docker ps -q --filter "ancestor=remnawave/backend:2" | grep -q .; then
        echo -e "${COLOR_RED}${LANG[CONTAINER_NOT_RUNNING]}${COLOR_RESET}"
        exit 1
    fi

    echo -e "${COLOR_YELLOW}${LANG[VIEW_LOGS]}${COLOR_RESET}"
    docker compose logs -f -t
}

setup_two_node_cascade() {
    local domain_url="127.0.0.1:3000"
    local token=""

    if ! ensure_manage_panel_api_loaded; then
        echo -e "${COLOR_RED}${LANG[CASCADE_TOKEN_ERROR]}${COLOR_RESET}"
        return 1
    fi

    echo -e "${COLOR_YELLOW}${LANG[CASCADE_CONFIRM]}${COLOR_RESET}"
    read confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${COLOR_YELLOW}${LANG[EXIT]}${COLOR_RESET}"
        return 0
    fi

    echo -e "${COLOR_YELLOW}${LANG[CASCADE_START]}${COLOR_RESET}"
    if ! get_panel_token; then
        echo -e "${COLOR_RED}${LANG[CASCADE_TOKEN_ERROR]}${COLOR_RESET}"
        return 1
    fi
    token=$(cat "$TOKEN_FILE")

    local nodes_response active_nodes
    nodes_response=$(make_api_request "GET" "http://$domain_url/api/nodes" "$token")
    if [ -z "$nodes_response" ] || ! echo "$nodes_response" | jq -e '.response | type == "array"' > /dev/null 2>&1; then
        echo -e "${COLOR_RED}${LANG[CASCADE_ERROR]}: nodes response is invalid${COLOR_RESET}"
        return 1
    fi

    active_nodes=$(echo "$nodes_response" | jq -c '{response:[.response[] | select(.isDisabled != true)]}')
    if [ "$(echo "$active_nodes" | jq -r '.response | length')" -lt 2 ]; then
        echo -e "${COLOR_RED}${LANG[CASCADE_NODES_NOT_FOUND]}${COLOR_RESET}"
        return 1
    fi

    echo -e "${COLOR_YELLOW}${LANG[CASCADE_NODES_LIST]}${COLOR_RESET}"
    echo "$active_nodes" | jq -r '.response[] | "- \(.name) [\(.address)]"'

    local first_node_name second_node_name
    reading "${LANG[CASCADE_SELECT_FIRST_NODE]}" first_node_name
    reading "${LANG[CASCADE_SELECT_SECOND_NODE]}" second_node_name

    if [ -z "$first_node_name" ] || [ -z "$second_node_name" ]; then
        echo -e "${COLOR_RED}${LANG[CASCADE_NODE_NOT_FOUND]}${COLOR_RESET}"
        return 1
    fi

    if [ "$first_node_name" = "$second_node_name" ]; then
        echo -e "${COLOR_RED}${LANG[CASCADE_SAME_NODE_ERROR]}${COLOR_RESET}"
        return 1
    fi

    local first_node_json second_node_json
    first_node_json=$(echo "$active_nodes" | jq -c --arg name "$first_node_name" '.response[] | select(.name == $name)' | head -n1)
    second_node_json=$(echo "$active_nodes" | jq -c --arg name "$second_node_name" '.response[] | select(.name == $name)' | head -n1)

    if [ -z "$first_node_json" ] || [ -z "$second_node_json" ]; then
        echo -e "${COLOR_RED}${LANG[CASCADE_NODE_NOT_FOUND]}${COLOR_RESET}"
        return 1
    fi

    local first_node_uuid second_node_uuid first_name second_name first_address second_address
    local first_profile_uuid second_profile_uuid first_inbound_uuid second_inbound_uuid first_inbound_tag second_inbound_tag

    first_node_uuid=$(echo "$first_node_json" | jq -r '.uuid')
    second_node_uuid=$(echo "$second_node_json" | jq -r '.uuid')
    first_name=$(echo "$first_node_json" | jq -r '.name')
    second_name=$(echo "$second_node_json" | jq -r '.name')
    first_address=$(echo "$first_node_json" | jq -r '.address')
    second_address=$(echo "$second_node_json" | jq -r '.address')
    first_profile_uuid=$(echo "$first_node_json" | jq -r '.configProfile.activeConfigProfileUuid')
    second_profile_uuid=$(echo "$second_node_json" | jq -r '.configProfile.activeConfigProfileUuid')
    first_inbound_uuid=$(echo "$first_node_json" | jq -r '.configProfile.activeInbounds[0].uuid')
    second_inbound_uuid=$(echo "$second_node_json" | jq -r '.configProfile.activeInbounds[0].uuid')
    first_inbound_tag=$(echo "$first_node_json" | jq -r '.configProfile.activeInbounds[0].tag')
    second_inbound_tag=$(echo "$second_node_json" | jq -r '.configProfile.activeInbounds[0].tag')

    if [ -z "$first_node_uuid" ] || [ "$first_node_uuid" = "null" ] || \
       [ -z "$second_node_uuid" ] || [ "$second_node_uuid" = "null" ]; then
        echo -e "${COLOR_RED}${LANG[CASCADE_NODE_NOT_FOUND]}${COLOR_RESET}"
        return 1
    fi

    if [ -z "$first_profile_uuid" ] || [ "$first_profile_uuid" = "null" ] || \
       [ -z "$second_profile_uuid" ] || [ "$second_profile_uuid" = "null" ] || \
       [ -z "$first_inbound_uuid" ] || [ "$first_inbound_uuid" = "null" ] || \
       [ -z "$second_inbound_uuid" ] || [ "$second_inbound_uuid" = "null" ] || \
       [ -z "$first_inbound_tag" ] || [ "$first_inbound_tag" = "null" ] || \
       [ -z "$second_inbound_tag" ] || [ "$second_inbound_tag" = "null" ]; then
        echo -e "${COLOR_RED}${LANG[CASCADE_MISSING_PROFILE]}${COLOR_RESET}"
        return 1
    fi

    local raw_suffix chain_suffix suffix_hash suffix_short suffix_lc
    raw_suffix="${first_name}_${second_name}"
    chain_suffix=$(echo "$raw_suffix" | tr '[:lower:]' '[:upper:]' | sed -E 's/[^A-Z0-9]+/_/g; s/^_+//; s/_+$//; s/_{2,}/_/g')
    if [ -z "$chain_suffix" ]; then
        chain_suffix="CHAIN"
    fi
    suffix_hash=$(printf '%s' "$chain_suffix" | sha256sum | awk '{print substr($1,1,6)}')
    suffix_short=$(echo "$chain_suffix" | cut -c1-12)
    chain_suffix="${suffix_short}_${suffix_hash}"
    suffix_lc=$(echo "$chain_suffix" | tr '[:upper:]' '[:lower:]')
    echo -e "${COLOR_GREEN}${LANG[CASCADE_CHAIN_ID]}: ${chain_suffix}${COLOR_RESET}"

    local squad_name service_username outbound_tag
    squad_name="SQ-BR-${chain_suffix}"
    service_username="svc_br_${suffix_lc}"
    outbound_tag="OUT-${chain_suffix}-CASCADE"

    local squads_response squad_uuid squad_payload squad_update_payload squad_create_response squad_patch_response
    squads_response=$(make_api_request "GET" "http://$domain_url/api/internal-squads" "$token")
    if [ -z "$squads_response" ] || ! echo "$squads_response" | jq -e '.response.internalSquads | type == "array"' > /dev/null 2>&1; then
        echo -e "${COLOR_RED}${LANG[CASCADE_ERROR]}: squads response is invalid${COLOR_RESET}"
        return 1
    fi

    squad_uuid=$(echo "$squads_response" | jq -r --arg name "$squad_name" '.response.internalSquads[] | select(.name == $name) | .uuid' | head -n1)
    if [ -z "$squad_uuid" ] || [ "$squad_uuid" = "null" ]; then
        squad_payload=$(jq -n --arg name "$squad_name" --arg inbound "$second_inbound_uuid" '{name: $name, inbounds: [$inbound]}')
        squad_create_response=$(make_api_request "POST" "http://$domain_url/api/internal-squads" "$token" "$squad_payload")
        squad_uuid=$(echo "$squad_create_response" | jq -r '.response.uuid')
        if [ -z "$squad_uuid" ] || [ "$squad_uuid" = "null" ]; then
            echo -e "${COLOR_RED}${LANG[CASCADE_ERROR]}: failed to create bridge squad${COLOR_RESET}"
            return 1
        fi
    else
        local squad_inbounds updated_inbounds
        squad_inbounds=$(echo "$squads_response" | jq -c --arg uuid "$squad_uuid" '.response.internalSquads[] | select(.uuid == $uuid) | [.inbounds[].uuid]')
        updated_inbounds=$(jq -n --argjson existing "${squad_inbounds:-[]}" --arg inbound "$second_inbound_uuid" '$existing + [$inbound] | unique')
        squad_update_payload=$(jq -n --arg uuid "$squad_uuid" --argjson inbounds "$updated_inbounds" '{uuid: $uuid, inbounds: $inbounds}')
        squad_patch_response=$(make_api_request "PATCH" "http://$domain_url/api/internal-squads" "$token" "$squad_update_payload")
        if ! echo "$squad_patch_response" | jq -e '.response.uuid' > /dev/null 2>&1; then
            echo -e "${COLOR_RED}${LANG[CASCADE_ERROR]}: failed to update bridge squad${COLOR_RESET}"
            return 1
        fi
    fi
    echo -e "${COLOR_GREEN}${LANG[CASCADE_SQUAD_READY]}: $squad_uuid${COLOR_RESET}"

    local users_response service_user_uuid service_vless_uuid user_payload user_patch_payload user_create_response user_patch_response
    users_response=$(make_api_request "GET" "http://$domain_url/api/users" "$token")
    if [ -z "$users_response" ] || ! echo "$users_response" | jq -e '.response.users | type == "array"' > /dev/null 2>&1; then
        echo -e "${COLOR_RED}${LANG[CASCADE_ERROR]}: users response is invalid${COLOR_RESET}"
        return 1
    fi

    service_user_uuid=$(echo "$users_response" | jq -r --arg username "$service_username" '.response.users[] | select(.username == $username) | .uuid' | head -n1)
    service_vless_uuid=$(echo "$users_response" | jq -r --arg username "$service_username" '.response.users[] | select(.username == $username) | .vlessUuid' | head -n1)

    if [ -z "$service_user_uuid" ] || [ "$service_user_uuid" = "null" ]; then
        user_payload=$(jq -n \
            --arg username "$service_username" \
            --arg expireAt "2099-12-31T23:59:59.000Z" \
            --arg squad "$squad_uuid" \
            '{username: $username, status: "ACTIVE", trafficLimitBytes: 0, trafficLimitStrategy: "NO_RESET", expireAt: $expireAt, activeInternalSquads: [$squad]}')
        user_create_response=$(make_api_request "POST" "http://$domain_url/api/users" "$token" "$user_payload")
        service_user_uuid=$(echo "$user_create_response" | jq -r '.response.uuid')
        service_vless_uuid=$(echo "$user_create_response" | jq -r '.response.vlessUuid')
        if [ -z "$service_user_uuid" ] || [ "$service_user_uuid" = "null" ] || \
           [ -z "$service_vless_uuid" ] || [ "$service_vless_uuid" = "null" ]; then
            echo -e "${COLOR_RED}${LANG[CASCADE_ERROR]}: failed to create service user${COLOR_RESET}"
            return 1
        fi
    else
        user_patch_payload=$(jq -n --arg uuid "$service_user_uuid" --arg squad "$squad_uuid" '{uuid: $uuid, activeInternalSquads: [$squad]}')
        user_patch_response=$(make_api_request "PATCH" "http://$domain_url/api/users" "$token" "$user_patch_payload")
        if ! echo "$user_patch_response" | jq -e '.response.uuid' > /dev/null 2>&1; then
            echo -e "${COLOR_RED}${LANG[CASCADE_ERROR]}: failed to update service user${COLOR_RESET}"
            return 1
        fi
    fi

    if [ -z "$service_vless_uuid" ] || [ "$service_vless_uuid" = "null" ]; then
        echo -e "${COLOR_RED}${LANG[CASCADE_ERROR]}: failed to get service user UUID${COLOR_RESET}"
        return 1
    fi
    echo -e "${COLOR_GREEN}${LANG[CASCADE_USER_READY]}: ${service_username}${COLOR_RESET}"

    local keys_response second_private_key second_public_key short_id
    keys_response=$(make_api_request "GET" "http://$domain_url/api/system/tools/x25519/generate" "$token")
    second_private_key=$(echo "$keys_response" | jq -r '.response.keypairs[0].privateKey')
    second_public_key=$(echo "$keys_response" | jq -r '.response.keypairs[0].publicKey')
    short_id=$(openssl rand -hex 8)
    if [ -z "$second_private_key" ] || [ "$second_private_key" = "null" ] || \
       [ -z "$second_public_key" ] || [ "$second_public_key" = "null" ]; then
        echo -e "${COLOR_RED}${LANG[CASCADE_ERROR]}: failed to generate reality keypair${COLOR_RESET}"
        return 1
    fi
    echo -e "${COLOR_GREEN}${LANG[CASCADE_KEYS_READY]}${COLOR_RESET}"

    local second_profile_response second_config second_config_updated second_patch_payload second_patch_response
    second_profile_response=$(make_api_request "GET" "http://$domain_url/api/config-profiles/$second_profile_uuid" "$token")
    second_config=$(echo "$second_profile_response" | jq -c '.response.config')
    if [ -z "$second_config" ] || [ "$second_config" = "null" ]; then
        echo -e "${COLOR_RED}${LANG[CASCADE_ERROR]}: failed to load second profile config${COLOR_RESET}"
        return 1
    fi

    second_config_updated=$(echo "$second_config" | jq \
        --arg tag "$second_inbound_tag" \
        --arg privateKey "$second_private_key" \
        --arg shortId "$short_id" \
        --arg serverName "$second_address" '
        .inbounds |= map(
            if .tag == $tag then
                .streamSettings.network = "tcp"
                | .streamSettings.security = "reality"
                | (.streamSettings.realitySettings //= {})
                | .streamSettings.realitySettings.privateKey = $privateKey
                | .streamSettings.realitySettings.shortIds = [$shortId]
                | .streamSettings.realitySettings.serverNames = [$serverName]
                | .streamSettings.realitySettings.show = false
                | .streamSettings.realitySettings.xver = (.streamSettings.realitySettings.xver // 1)
                | .streamSettings.realitySettings.spiderX = (.streamSettings.realitySettings.spiderX // "")
            else . end
        )
    ')
    second_patch_payload=$(jq -n --arg uuid "$second_profile_uuid" --argjson config "$second_config_updated" '{uuid: $uuid, config: $config}')
    second_patch_response=$(make_api_request "PATCH" "http://$domain_url/api/config-profiles" "$token" "$second_patch_payload")
    if ! echo "$second_patch_response" | jq -e '.response.uuid' > /dev/null 2>&1; then
        echo -e "${COLOR_RED}${LANG[CASCADE_ERROR]}: failed to update second profile${COLOR_RESET}"
        return 1
    fi
    echo -e "${COLOR_GREEN}${LANG[CASCADE_SECOND_PROFILE_UPDATED]}: $second_name${COLOR_RESET}"

    local first_profile_response first_config first_config_updated first_patch_payload first_patch_response
    first_profile_response=$(make_api_request "GET" "http://$domain_url/api/config-profiles/$first_profile_uuid" "$token")
    first_config=$(echo "$first_profile_response" | jq -c '.response.config')
    if [ -z "$first_config" ] || [ "$first_config" = "null" ]; then
        echo -e "${COLOR_RED}${LANG[CASCADE_ERROR]}: failed to load first profile config${COLOR_RESET}"
        return 1
    fi

    first_config_updated=$(echo "$first_config" | jq \
        --arg serviceUuid "$service_vless_uuid" \
        --arg secondAddr "$second_address" \
        --arg shortId "$short_id" \
        --arg secondPublicKey "$second_public_key" \
        --arg firstTag "$first_inbound_tag" \
        --arg outboundTag "$outbound_tag" '
        (.outbounds //= [])
        | (.routing //= {})
        | (.routing.rules //= [])
        | .outbounds = (
            [.outbounds[] | select(.tag != $outboundTag)] + [
                {
                    "tag": $outboundTag,
                    "protocol": "vless",
                    "settings": {
                        "vnext": [
                            {
                                "address": $secondAddr,
                                "port": 443,
                                "users": [
                                    {
                                        "id": $serviceUuid,
                                        "encryption": "none",
                                        "flow": "xtls-rprx-vision"
                                    }
                                ]
                            }
                        ]
                    },
                    "streamSettings": {
                        "network": "tcp",
                        "security": "reality",
                        "realitySettings": {
                            "serverName": $secondAddr,
                            "fingerprint": "chrome",
                            "publicKey": $secondPublicKey,
                            "password": $secondPublicKey,
                            "shortId": $shortId,
                            "spiderX": ""
                        }
                    }
                }
            ]
        )
        | .routing.rules = (
            [{"type": "field", "inboundTag": [$firstTag], "outboundTag": $outboundTag}]
            + [.routing.rules[] | select(.outboundTag != $outboundTag)]
        )
    ')
    first_patch_payload=$(jq -n --arg uuid "$first_profile_uuid" --argjson config "$first_config_updated" '{uuid: $uuid, config: $config}')
    first_patch_response=$(make_api_request "PATCH" "http://$domain_url/api/config-profiles" "$token" "$first_patch_payload")
    if ! echo "$first_patch_response" | jq -e '.response.uuid' > /dev/null 2>&1; then
        echo -e "${COLOR_RED}${LANG[CASCADE_ERROR]}: failed to update first profile${COLOR_RESET}"
        return 1
    fi
    echo -e "${COLOR_GREEN}${LANG[CASCADE_FIRST_PROFILE_UPDATED]}: $first_name${COLOR_RESET}"

    local restart_second_response restart_first_response
    restart_second_response=$(make_api_request "POST" "http://$domain_url/api/nodes/$second_node_uuid/actions/restart" "$token" "{}")
    restart_first_response=$(make_api_request "POST" "http://$domain_url/api/nodes/$first_node_uuid/actions/restart" "$token" "{}")
    if ! echo "$restart_second_response" | jq -e '.response.eventSent == true' > /dev/null 2>&1 || \
       ! echo "$restart_first_response" | jq -e '.response.eventSent == true' > /dev/null 2>&1; then
        echo -e "${COLOR_RED}${LANG[CASCADE_ERROR]}: failed to restart selected nodes${COLOR_RESET}"
        return 1
    fi

    echo -e "${COLOR_GREEN}${LANG[CASCADE_NODES_RESTARTED]}${COLOR_RESET}"
    echo -e "${COLOR_GREEN}${LANG[CASCADE_DONE]}${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}${LANG[CASCADE_VALIDATE]}${COLOR_RESET}"
    return 0
}

#Manage Panel Access
show_panel_access() {
    echo -e ""
    echo -e "${COLOR_GREEN}${LANG[MENU_9]}${COLOR_RESET}"
    echo -e ""
    echo -e "${COLOR_YELLOW}1. ${LANG[PORT_8443_OPEN]}${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}2. ${LANG[PORT_8443_CLOSE]}${COLOR_RESET}"
    echo -e ""
    echo -e "${COLOR_YELLOW}0. ${LANG[EXIT]}${COLOR_RESET}"
    echo -e ""
}

manage_panel_access() {
    show_panel_access
    reading "${LANG[IPV6_PROMPT]}" ACCESS_OPTION
    case $ACCESS_OPTION in
        1)
            open_panel_access
            ;;
        2)
            close_panel_access
            ;;
        0)
            echo -e "${COLOR_YELLOW}${LANG[EXIT]}${COLOR_RESET}"
            sleep 2
            log_clear
            remnawave_reverse
            ;;
        *)
            echo -e "${COLOR_YELLOW}${LANG[IPV6_INVALID_CHOICE]}${COLOR_RESET}"
            ;;
    esac
    sleep 2
    log_clear
    manage_panel_access
}

open_panel_access() {
    local dir=""
    if [ -d "/opt/remnawave" ]; then
        dir="/opt/remnawave"
    elif [ -d "/opt/remnanode" ]; then
        dir="/opt/remnanode"
    else
        echo -e "${COLOR_RED}${LANG[DIR_NOT_FOUND]}${COLOR_RESET}"
        exit 1
    fi

    cd "$dir" || { echo -e "${COLOR_RED}${LANG[CHANGE_DIR_FAILED]} $dir${COLOR_RESET}"; exit 1; }

    local webserver=""
    if [ -f "nginx.conf" ]; then
        webserver="nginx"
    elif [ -f "Caddyfile" ]; then
        webserver="caddy"
    else
        echo -e "${COLOR_RED}${LANG[CONFIG_NOT_FOUND]}${COLOR_RESET}"
        exit 1
    fi

    if [ "$webserver" = "nginx" ]; then
        PANEL_DOMAIN=$(grep -B 20 "proxy_pass http://remnawave" "$dir/nginx.conf" | grep "server_name" | grep -v "server_name _" | awk '{print $2}' | sed 's/;//' | head -n 1)

        cookie_line=$(grep -A 2 "map \$http_cookie \$auth_cookie" "$dir/nginx.conf" | grep "~*\w\+.*=")
        cookies_random1=$(echo "$cookie_line" | grep -oP '~*\K\w+(?==)')
        cookies_random2=$(echo "$cookie_line" | grep -oP '=\K\w+(?=")')

        if [ -z "$PANEL_DOMAIN" ] || [ -z "$cookies_random1" ] || [ -z "$cookies_random2" ]; then
            echo -e "${COLOR_RED}${LANG[NGINX_CONF_ERROR]}${COLOR_RESET}"
            exit 1
        fi

        if command -v ss >/dev/null 2>&1; then
            if ss -tuln | grep -q ":8443"; then
                echo -e "${COLOR_RED}${LANG[PORT_8443_IN_USE]}${COLOR_RESET}"
                exit 1
            fi
        elif command -v netstat >/dev/null 2>&1; then
            if netstat -tuln | grep -q ":8443"; then
                echo -e "${COLOR_RED}${LANG[PORT_8443_IN_USE]}${COLOR_RESET}"
                exit 1
            fi
        else
            echo -e "${COLOR_RED}${LANG[NO_PORT_CHECK_TOOLS]}${COLOR_RESET}"
            exit 1
        fi

        sed -i "/server_name $PANEL_DOMAIN;/,/}/{/^[[:space:]]*$/d; s/listen 8443 ssl;//}" "$dir/nginx.conf"
        sed -i "/server_name $PANEL_DOMAIN;/a \    listen 8443 ssl;" "$dir/nginx.conf"
        if [ $? -ne 0 ]; then
            echo -e "${COLOR_RED}${LANG[NGINX_CONF_MODIFY_FAILED]}${COLOR_RESET}"
            exit 1
        fi

        docker compose down remnawave-nginx > /dev/null 2>&1 &
        spinner $! "${LANG[WAITING]}"

        docker compose up -d remnawave-nginx > /dev/null 2>&1 &
        spinner $! "${LANG[WAITING]}"

        ufw allow from 0.0.0.0/0 to any port 8443 proto tcp > /dev/null 2>&1
        ufw reload > /dev/null 2>&1
        sleep 1

        local panel_link="https://${PANEL_DOMAIN}:8443/auth/login?${cookies_random1}=${cookies_random2}"
        echo -e "${COLOR_YELLOW}${LANG[OPEN_PANEL_LINK]}${COLOR_RESET}"
        echo -e "${COLOR_WHITE}${panel_link}${COLOR_RESET}"
        echo -e "${COLOR_RED}${LANG[PORT_8443_WARNING]}${COLOR_RESET}"
    elif [ "$webserver" = "caddy" ]; then
        PANEL_DOMAIN=$(grep 'PANEL_DOMAIN=' "$dir/docker-compose.yml" | head -n 1 | sed 's/.*PANEL_DOMAIN=//; s/[[:space:]]*$//')

        if [ -z "$PANEL_DOMAIN" ]; then
            echo -e "${COLOR_RED}${LANG[CADDY_CONF_ERROR]}${COLOR_RESET}"
            exit 1
        fi

        if grep -q "https://{\$PANEL_DOMAIN}:8443 {" "$dir/Caddyfile"; then
            echo -e "${COLOR_YELLOW}${LANG[PORT_8443_ALREADY_CONFIGURED]}${COLOR_RESET}"
            return 0
        fi

        if command -v ss >/dev/null 2>&1; then
            if ss -tuln | grep -q ":8443"; then
                echo -e "${COLOR_RED}${LANG[PORT_8443_IN_USE]}${COLOR_RESET}"
                exit 1
            fi
        elif command -v netstat >/dev/null 2>&1; then
            if netstat -tuln | grep -q ":8443"; then
                echo -e "${COLOR_RED}${LANG[PORT_8443_IN_USE]}${COLOR_RESET}"
                exit 1
            fi
        else
            echo -e "${COLOR_RED}${LANG[NO_PORT_CHECK_TOOLS]}${COLOR_RESET}"
            exit 1
        fi

        sed -i "s|redir https://{\$PANEL_DOMAIN}{uri} permanent|redir https://{\$PANEL_DOMAIN}:8443{uri} permanent|g" "$dir/Caddyfile"

        sed -i "s|https://{\$PANEL_DOMAIN} {|https://{\$PANEL_DOMAIN}:8443 {|g" "$dir/Caddyfile"
        sed -i "/https:\/\/{\$PANEL_DOMAIN}:8443 {/,/^}/ { /bind unix\/{\$CADDY_SOCKET_PATH}/d }" "$dir/Caddyfile"

        docker compose down remnawave-caddy > /dev/null 2>&1 &
        spinner $! "${LANG[WAITING]}"

        docker compose up -d remnawave-caddy > /dev/null 2>&1 &
        spinner $! "${LANG[WAITING]}"

        ufw allow from 0.0.0.0/0 to any port 8443 proto tcp > /dev/null 2>&1
        ufw reload > /dev/null 2>&1
        sleep 1

        local cookie_line=$(grep 'header +Set-Cookie' "$dir/Caddyfile" | head -n 1)
        local cookies_random1=$(echo "$cookie_line" | grep -oP 'Set-Cookie "\K[^=]+')
        local cookies_random2=$(echo "$cookie_line" | grep -oP 'Set-Cookie "[^=]+=\K[^;]+')

        local panel_link="https://${PANEL_DOMAIN}:8443/auth/login"
        if [ -n "$cookies_random1" ] && [ -n "$cookies_random2" ]; then
            panel_link="${panel_link}?${cookies_random1}=${cookies_random2}"
        fi
        echo -e "${COLOR_YELLOW}${LANG[OPEN_PANEL_LINK]}${COLOR_RESET}"
        echo -e "${COLOR_WHITE}${panel_link}${COLOR_RESET}"
        echo -e "${COLOR_RED}${LANG[PORT_8443_WARNING]}${COLOR_RESET}"
    fi
}

close_panel_access() {
    local dir=""
    if [ -d "/opt/remnawave" ]; then
        dir="/opt/remnawave"
    elif [ -d "/opt/remnanode" ]; then
        dir="/opt/remnanode"
    else
        echo -e "${COLOR_RED}${LANG[DIR_NOT_FOUND]}${COLOR_RESET}"
        exit 1
    fi

    cd "$dir" || { echo -e "${COLOR_RED}${LANG[CHANGE_DIR_FAILED]} $dir${COLOR_RESET}"; exit 1; }

    echo -e "${COLOR_YELLOW}${LANG[PORT_8443_CLOSE]}${COLOR_RESET}"

    local webserver=""
    if [ -f "nginx.conf" ]; then
        webserver="nginx"
    elif [ -f "Caddyfile" ]; then
        webserver="caddy"
    else
        echo -e "${COLOR_RED}${LANG[CONFIG_NOT_FOUND]}${COLOR_RESET}"
        exit 1
    fi

    if [ "$webserver" = "nginx" ]; then
        PANEL_DOMAIN=$(grep -B 20 "proxy_pass http://remnawave" "$dir/nginx.conf" | grep "server_name" | grep -v "server_name _" | awk '{print $2}' | sed 's/;//' | head -n 1)

        if [ -z "$PANEL_DOMAIN" ]; then
            echo -e "${COLOR_RED}${LANG[NGINX_CONF_ERROR]}${COLOR_RESET}"
            exit 1
        fi

        if grep -A 10 "server_name $PANEL_DOMAIN;" "$dir/nginx.conf" | grep -q "listen 8443 ssl;"; then
            sed -i "/server_name $PANEL_DOMAIN;/,/}/{/^[[:space:]]*$/d; s/listen 8443 ssl;//}" "$dir/nginx.conf"
            if [ $? -ne 0 ]; then
                echo -e "${COLOR_RED}${LANG[NGINX_CONF_MODIFY_FAILED]}${COLOR_RESET}"
                exit 1
            fi

            docker compose down remnawave-nginx > /dev/null 2>&1 &
            spinner $! "${LANG[WAITING]}"
            docker compose up -d remnawave-nginx > /dev/null 2>&1 &
            spinner $! "${LANG[WAITING]}"
        else
            echo -e "${COLOR_YELLOW}${LANG[PORT_8443_NOT_CONFIGURED]}${COLOR_RESET}"
        fi

        if ufw status | grep -q "8443.*ALLOW"; then
            ufw delete allow from 0.0.0.0/0 to any port 8443 proto tcp > /dev/null 2>&1
            ufw reload > /dev/null 2>&1
            if [ $? -ne 0 ]; then
                echo -e "${COLOR_RED}${LANG[UFW_RELOAD_FAILED]}${COLOR_RESET}"
                exit 1
            fi
            echo -e "${COLOR_GREEN}${LANG[PORT_8443_CLOSED]}${COLOR_RESET}"
        else
            echo -e "${COLOR_YELLOW}${LANG[PORT_8443_ALREADY_CLOSED]}${COLOR_RESET}"
        fi
    elif [ "$webserver" = "caddy" ]; then
        PANEL_DOMAIN=$(grep 'PANEL_DOMAIN=' "$dir/docker-compose.yml" | head -n 1 | sed 's/.*PANEL_DOMAIN=//; s/[[:space:]]*$//')

        if [ -z "$PANEL_DOMAIN" ]; then
            echo -e "${COLOR_RED}${LANG[CADDY_CONF_ERROR]}${COLOR_RESET}"
            exit 1
        fi

        if grep -q "https://{\$PANEL_DOMAIN}:8443 {" "$dir/Caddyfile"; then
            sed -i "s|https://{\$PANEL_DOMAIN}:8443 {|https://{\$PANEL_DOMAIN} {|g" "$dir/Caddyfile"

            sed -i "/https:\/\/{\$PANEL_DOMAIN} {/a \    bind unix/{\$CADDY_SOCKET_PATH}" "$dir/Caddyfile"

            sed -i "s|redir https://{\$PANEL_DOMAIN}:8443{uri} permanent|redir https://{\$PANEL_DOMAIN}{uri} permanent|g" "$dir/Caddyfile"

            docker compose down remnawave-caddy > /dev/null 2>&1 &
            spinner $! "${LANG[WAITING]}"
            docker compose up -d remnawave-caddy > /dev/null 2>&1 &
            spinner $! "${LANG[WAITING]}"
        else
            echo -e "${COLOR_YELLOW}${LANG[PORT_8443_NOT_CONFIGURED]}${COLOR_RESET}"
        fi

        if ufw status | grep -q "8443.*ALLOW"; then
            ufw delete allow from 0.0.0.0/0 to any port 8443 proto tcp > /dev/null 2>&1
            ufw reload > /dev/null 2>&1
            if [ $? -ne 0 ]; then
                echo -e "${COLOR_RED}${LANG[UFW_RELOAD_FAILED]}${COLOR_RESET}"
                exit 1
            fi
            echo -e "${COLOR_GREEN}${LANG[PORT_8443_CLOSED]}${COLOR_RESET}"
        else
            echo -e "${COLOR_YELLOW}${LANG[PORT_8443_ALREADY_CLOSED]}${COLOR_RESET}"
        fi
    fi
}
