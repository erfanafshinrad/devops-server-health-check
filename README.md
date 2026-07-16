# DevOps Server Health Check

A lightweight Bash script for checking the health of Linux servers.

It provides a quick overview of CPU usage, memory usage, disk utilization,
load average, critical services, and Docker containers.

## Features

- CPU usage monitoring
- Memory usage monitoring
- Disk utilization checks
- System load averages
- Nginx and SSH service checks
- Docker availability and container status
- Configurable warning thresholds
- No external dependencies

## Requirements

- Linux
- Bash
- Standard Linux utilities such as `awk`, `df`, `free`, and `top`
- Optional: Docker and systemd

## Installation

Clone the repository:

```bash
git clone https://github.com/erfanafshinrad/devops-server-health-check.git
cd devops-server-health-check
```

Make the script executable:

```bash
chmod +x health-check.sh
```

Run it:

```bash
./health-check.sh
```

## Custom warning thresholds

The default thresholds are:

- CPU: 80%
- Memory: 80%
- Disk: 85%

You can override them using environment variables:

```bash
CPU_WARNING=70 MEMORY_WARNING=75 DISK_WARNING=80 ./health-check.sh
```

## Example use with Cron

Run the health check every hour and store the output:

```cron
0 * * * * /path/to/health-check.sh >> /var/log/server-health.log 2>&1
```

## Roadmap

- JSON output mode
- Telegram and email notifications
- Configuration file support
- Automated tests
- Support for additional Linux services

## Contributing

Contributions, bug reports, and feature requests are welcome.

## License

This project is available under the MIT License.
