#!/usr/bin/env bash

set -u

CPU_WARNING="${CPU_WARNING:-80}"
MEMORY_WARNING="${MEMORY_WARNING:-80}"
DISK_WARNING="${DISK_WARNING:-85}"

print_header() {
    printf "\n========================================\n"
    printf " Linux Server Health Check\n"
    printf " Host: %s\n" "$(hostname)"
    printf " Date: %s\n" "$(date)"
    printf "========================================\n\n"
}

print_status() {
    local status="$1"
    local message="$2"

    if [[ "$status" == "OK" ]]; then
        printf "[OK]      %s\n" "$message"
    elif [[ "$status" == "WARNING" ]]; then
        printf "[WARNING] %s\n" "$message"
    else
        printf "[INFO]    %s\n" "$message"
    fi
}

check_cpu() {
    local usage

    usage=$(top -bn1 | awk '/Cpu\(s\)/ {
        idle = $8
        printf "%.0f", 100 - idle
    }')

    if [[ -z "$usage" ]]; then
        print_status "INFO" "CPU usage could not be detected."
        return
    fi

    if (( usage >= CPU_WARNING )); then
        print_status "WARNING" "CPU usage is ${usage}% (threshold: ${CPU_WARNING}%)."
    else
        print_status "OK" "CPU usage is ${usage}%."
    fi
}

check_memory() {
    local usage

    usage=$(free | awk '/Mem:/ {
        printf "%.0f", ($3 / $2) * 100
    }')

    if (( usage >= MEMORY_WARNING )); then
        print_status "WARNING" "Memory usage is ${usage}% (threshold: ${MEMORY_WARNING}%)."
    else
        print_status "OK" "Memory usage is ${usage}%."
    fi
}

check_disk() {
    local filesystem usage mount_point percentage

    while read -r filesystem usage mount_point; do
        percentage="${usage%\%}"

        if (( percentage >= DISK_WARNING )); then
            print_status "WARNING" \
                "Disk ${filesystem} mounted on ${mount_point} is ${usage} full."
        else
            print_status "OK" \
                "Disk ${filesystem} mounted on ${mount_point} is ${usage} full."
        fi
    done < <(df -P -x tmpfs -x devtmpfs | awk 'NR > 1 {print $1, $5, $6}')
}

check_load_average() {
    local load
    load=$(awk '{print $1, $2, $3}' /proc/loadavg)
    print_status "INFO" "Load average: ${load}."
}

check_service() {
    local service="$1"

    if ! command -v systemctl >/dev/null 2>&1; then
        print_status "INFO" "systemctl is unavailable; skipped ${service} check."
        return
    fi

    if ! systemctl list-unit-files "${service}.service" \
        >/dev/null 2>&1; then
        print_status "INFO" "${service} is not installed."
        return
    fi

    if systemctl is-active --quiet "$service"; then
        print_status "OK" "${service} service is running."
    else
        print_status "WARNING" "${service} service is not running."
    fi
}

check_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        print_status "INFO" "Docker is not installed."
        return
    fi

    if ! docker info >/dev/null 2>&1; then
        print_status "WARNING" "Docker is installed but unavailable."
        return
    fi

    local running stopped

    running=$(docker ps -q | wc -l | tr -d ' ')
    stopped=$(docker ps -aq --filter status=exited | wc -l | tr -d ' ')

    print_status "OK" "Docker is available; ${running} container(s) running."

    if (( stopped > 0 )); then
        print_status "WARNING" "${stopped} Docker container(s) have stopped."
    else
        print_status "OK" "No stopped Docker containers found."
    fi
}

main() {
    print_header
    check_cpu
    check_memory
    check_load_average
    check_disk
    check_service "nginx"
    check_service "ssh"
    check_docker
    printf "\nHealth check completed.\n"
}

main "$@"
