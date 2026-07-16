#!/usr/bin/env bash

set -u

CPU_WARNING="${CPU_WARNING:-80}"
MEMORY_WARNING="${MEMORY_WARNING:-80}"
DISK_WARNING="${DISK_WARNING:-85}"

OUTPUT_FORMAT="text"

for arg in "$@"; do
    case "$arg" in
        --json)
            OUTPUT_FORMAT="json"
            ;;
        --help|-h)
            cat <<'EOF'
Usage:
  ./health-check.sh
  ./health-check.sh --json

Options:
  --json    Print results as JSON
  --help    Show this help message
EOF
            exit 0
            ;;
        *)
            printf "Unknown option: %s\n" "$arg" >&2
            exit 1
            ;;
    esac
done

json_escape() {
    local value="$1"

    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/\\n}
    value=${value//$'\r'/\\r}
    value=${value//$'\t'/\\t}

    printf '%s' "$value"
}

get_cpu_usage() {
    top -bn1 | awk '/Cpu\(s\)/ {
        idle = $8
        printf "%.0f", 100 - idle
    }'
}

get_memory_usage() {
    free | awk '/Mem:/ {
        if ($2 > 0) {
            printf "%.0f", ($3 / $2) * 100
        } else {
            print "0"
        }
    }'
}

get_load_average() {
    awk '{print $1, $2, $3}' /proc/loadavg
}

get_service_status() {
    local service="$1"

    if ! command -v systemctl >/dev/null 2>&1; then
        printf "unavailable"
        return
    fi

    if ! systemctl list-unit-files "${service}.service" \
        --no-legend 2>/dev/null | grep -q "^${service}.service"; then
        printf "not_installed"
        return
    fi

    if systemctl is-active --quiet "$service"; then
        printf "running"
    else
        printf "stopped"
    fi
}

get_docker_status() {
    if ! command -v docker >/dev/null 2>&1; then
        printf "not_installed"
        return
    fi

    if ! docker info >/dev/null 2>&1; then
        printf "unavailable"
        return
    fi

    printf "running"
}

print_text_status() {
    local status="$1"
    local message="$2"

    case "$status" in
        ok)
            printf "[OK]      %s\n" "$message"
            ;;
        warning)
            printf "[WARNING] %s\n" "$message"
            ;;
        *)
            printf "[INFO]    %s\n" "$message"
            ;;
    esac
}

print_text_output() {
    local hostname_value
    local date_value
    local cpu_usage
    local memory_usage
    local load_average
    local nginx_status
    local ssh_status
    local docker_status
    local running_containers=0
    local stopped_containers=0

    hostname_value=$(hostname)
    date_value=$(date --iso-8601=seconds 2>/dev/null || date)
    cpu_usage=$(get_cpu_usage)
    memory_usage=$(get_memory_usage)
    load_average=$(get_load_average)
    nginx_status=$(get_service_status "nginx")
    ssh_status=$(get_service_status "ssh")
    docker_status=$(get_docker_status)

    printf "\n========================================\n"
    printf " Linux Server Health Check\n"
    printf " Host: %s\n" "$hostname_value"
    printf " Date: %s\n" "$date_value"
    printf "========================================\n\n"

    if [[ -z "$cpu_usage" ]]; then
        print_text_status "info" "CPU usage could not be detected."
    elif (( cpu_usage >= CPU_WARNING )); then
        print_text_status "warning" \
            "CPU usage is ${cpu_usage}% (threshold: ${CPU_WARNING}%)."
    else
        print_text_status "ok" "CPU usage is ${cpu_usage}%."
    fi

    if (( memory_usage >= MEMORY_WARNING )); then
        print_text_status "warning" \
            "Memory usage is ${memory_usage}% (threshold: ${MEMORY_WARNING}%)."
    else
        print_text_status "ok" "Memory usage is ${memory_usage}%."
    fi

    print_text_status "info" "Load average: ${load_average}."

    while read -r filesystem usage mount_point; do
        local percentage
        percentage="${usage%\%}"

        if (( percentage >= DISK_WARNING )); then
            print_text_status "warning" \
                "Disk ${filesystem} mounted on ${mount_point} is ${usage} full."
        else
            print_text_status "ok" \
                "Disk ${filesystem} mounted on ${mount_point} is ${usage} full."
        fi
    done < <(df -P -x tmpfs -x devtmpfs | awk 'NR > 1 {print $1, $5, $6}')

    case "$nginx_status" in
        running)
            print_text_status "ok" "Nginx service is running."
            ;;
        stopped)
            print_text_status "warning" "Nginx service is not running."
            ;;
        not_installed)
            print_text_status "info" "Nginx is not installed."
            ;;
        *)
            print_text_status "info" "Nginx status could not be checked."
            ;;
    esac

    case "$ssh_status" in
        running)
            print_text_status "ok" "SSH service is running."
            ;;
        stopped)
            print_text_status "warning" "SSH service is not running."
            ;;
        not_installed)
            print_text_status "info" "SSH service is not installed."
            ;;
        *)
            print_text_status "info" "SSH service status could not be checked."
            ;;
    esac

    if [[ "$docker_status" == "running" ]]; then
        running_containers=$(docker ps -q | wc -l | tr -d ' ')
        stopped_containers=$(
            docker ps -aq --filter status=exited |
                wc -l |
                tr -d ' '
        )

        print_text_status "ok" \
            "Docker is available; ${running_containers} container(s) running."

        if (( stopped_containers > 0 )); then
            print_text_status "warning" \
                "${stopped_containers} Docker container(s) have stopped."
        else
            print_text_status "ok" "No stopped Docker containers found."
        fi
    elif [[ "$docker_status" == "not_installed" ]]; then
        print_text_status "info" "Docker is not installed."
    else
        print_text_status "warning" "Docker is installed but unavailable."
    fi

    printf "\nHealth check completed.\n"
}

print_json_output() {
    local hostname_value
    local date_value
    local cpu_usage
    local memory_usage
    local load_1
    local load_5
    local load_15
    local nginx_status
    local ssh_status
    local docker_status
    local running_containers=0
    local stopped_containers=0
    local overall_status="ok"
    local first_disk=true

    hostname_value=$(hostname)
    date_value=$(date --iso-8601=seconds 2>/dev/null || date)
    cpu_usage=$(get_cpu_usage)
    memory_usage=$(get_memory_usage)

    read -r load_1 load_5 load_15 < /proc/loadavg

    nginx_status=$(get_service_status "nginx")
    ssh_status=$(get_service_status "ssh")
    docker_status=$(get_docker_status)

    if [[ -z "$cpu_usage" ]]; then
        cpu_usage=0
    fi

    if (( cpu_usage >= CPU_WARNING )); then
        overall_status="warning"
    fi

    if (( memory_usage >= MEMORY_WARNING )); then
        overall_status="warning"
    fi

    if [[ "$nginx_status" == "stopped" || "$ssh_status" == "stopped" ]]; then
        overall_status="warning"
    fi

    if [[ "$docker_status" == "running" ]]; then
        running_containers=$(docker ps -q | wc -l | tr -d ' ')
        stopped_containers=$(
            docker ps -aq --filter status=exited |
                wc -l |
                tr -d ' '
        )

        if (( stopped_containers > 0 )); then
            overall_status="warning"
        fi
    elif [[ "$docker_status" == "unavailable" ]]; then
        overall_status="warning"
    fi

    printf '{\n'
    printf '  "hostname": "%s",\n' "$(json_escape "$hostname_value")"
    printf '  "timestamp": "%s",\n' "$(json_escape "$date_value")"
    printf '  "overall_status": "%s",\n' "$overall_status"

    printf '  "thresholds": {\n'
    printf '    "cpu_percent": %s,\n' "$CPU_WARNING"
    printf '    "memory_percent": %s,\n' "$MEMORY_WARNING"
    printf '    "disk_percent": %s\n' "$DISK_WARNING"
    printf '  },\n'

    printf '  "cpu": {\n'
    printf '    "usage_percent": %s,\n' "$cpu_usage"
    if (( cpu_usage >= CPU_WARNING )); then
        printf '    "status": "warning"\n'
    else
        printf '    "status": "ok"\n'
    fi
    printf '  },\n'

    printf '  "memory": {\n'
    printf '    "usage_percent": %s,\n' "$memory_usage"
    if (( memory_usage >= MEMORY_WARNING )); then
        printf '    "status": "warning"\n'
    else
        printf '    "status": "ok"\n'
    fi
    printf '  },\n'

    printf '  "load_average": {\n'
    printf '    "one_minute": %s,\n' "$load_1"
    printf '    "five_minutes": %s,\n' "$load_5"
    printf '    "fifteen_minutes": %s\n' "$load_15"
    printf '  },\n'

    printf '  "disks": [\n'

    while read -r filesystem usage mount_point; do
        local percentage
        local disk_status="ok"

        percentage="${usage%\%}"

        if (( percentage >= DISK_WARNING )); then
            disk_status="warning"
            overall_status="warning"
        fi

        if [[ "$first_disk" == true ]]; then
            first_disk=false
        else
            printf ',\n'
        fi

        printf '    {\n'
        printf '      "filesystem": "%s",\n' \
            "$(json_escape "$filesystem")"
        printf '      "mount_point": "%s",\n' \
            "$(json_escape "$mount_point")"
        printf '      "usage_percent": %s,\n' "$percentage"
        printf '      "status": "%s"\n' "$disk_status"
        printf '    }'
    done < <(df -P -x tmpfs -x devtmpfs | awk 'NR > 1 {print $1, $5, $6}')

    printf '\n  ],\n'

    printf '  "services": {\n'
    printf '    "nginx": "%s",\n' "$nginx_status"
    printf '    "ssh": "%s"\n' "$ssh_status"
    printf '  },\n'

    printf '  "docker": {\n'
    printf '    "status": "%s",\n' "$docker_status"
    printf '    "running_containers": %s,\n' "$running_containers"
    printf '    "stopped_containers": %s\n' "$stopped_containers"
    printf '  }\n'

    printf '}\n'
}

main() {
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        print_json_output
    else
        print_text_output
    fi
}

main
