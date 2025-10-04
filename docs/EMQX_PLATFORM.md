# EMQX IoT Platform Documentation

## Overview

The Thermalog server uses **EMQX Platform 5.8.8** as a comprehensive IoT platform for managing MQTT connections, device authentication, and real-time temperature data from IoT devices.

### Architecture

```
IoT Devices (ESP32, etc.)
        ↓ MQTT (TLS 8883)
   EMQX Broker 5.8.8
        ↓
PostgreSQL 15 + TimescaleDB
        ↓
Provisioning Service (Node.js)
        ↓
Main Thermalog Backend
```

## Components

### 1. EMQX Broker
- **Version**: 5.8.8 (latest stable)
- **Protocol**: MQTT 3.1.1 / 5.0
- **Ports**:
  - 1883 - MQTT (plaintext, local only)
  - 8883 - MQTTS (TLS/SSL for production)
  - 18083 - Dashboard (HTTP)
- **Features**:
  - Device authentication via PostgreSQL
  - Rule engine for data processing
  - Real-time message routing
  - Built-in monitoring and metrics

### 2. PostgreSQL 15 + TimescaleDB
- **Database**: `iot_platform`
- **Purpose**: Device credentials, authentication, time-series temperature data
- **Port**: 5432 (internal Docker network)
- **Key Tables**:
  - `device_credentials` - Device authentication
  - `temperature_readings` - Time-series data (TimescaleDB hypertable)
  - `device_metadata` - Device information

### 3. Provisioning Service
- **Technology**: Node.js Express API
- **Purpose**: Device registration, credential management
- **Port**: 3002 (internal)
- **Features**:
  - Device registration API
  - Credential generation
  - Device lifecycle management

## Docker Containers

```yaml
# /root/emqx-platform/docker-compose.yml
services:
  iot-postgres:
    image: timescale/timescaledb:latest-pg15
    restart: always
    ports:
      - "5432:5432"
    volumes:
      - postgres-data:/var/lib/postgresql/data

  emqx:
    image: emqx/emqx:5.8.8
    restart: always
    ports:
      - "1883:1883"
      - "8883:8883"
      - "18083:18083"
    volumes:
      - emqx-data:/opt/emqx/data
      - emqx-log:/opt/emqx/log

  provisioning-service:
    build: ./provisioning-service
    restart: always
    ports:
      - "3002:3002"
    environment:
      - DATABASE_URL=postgresql://iotadmin:password@iot-postgres:5432/iot_platform
```

## Systemd Service

**File**: `/etc/systemd/system/emqx-platform.service`

```ini
[Unit]
Description=EMQX IoT Platform
Requires=docker.service
After=docker.service

[Service]
Type=forking
RemainAfterExit=yes
WorkingDirectory=/root/emqx-platform
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
Restart=always
User=root

[Install]
WantedBy=multi-user.target
```

## Device Authentication Flow

1. **Device Registration**:
   ```bash
   POST /api/devices/register
   {
     "deviceId": "ESP32_001",
     "deviceName": "Kitchen Sensor"
   }
   ```

2. **Credential Generation**:
   - Service generates unique username/password
   - Stores in PostgreSQL `device_credentials` table
   - Returns credentials to administrator

3. **MQTT Connection**:
   ```bash
   # Device connects with credentials
   mosquitto_pub -h dashboard.thermalog.com.au -p 8883 \
     -u ESP32_001 -P <generated_password> \
     -t "devices/ESP32_001/temperature" \
     -m '{"temp": 22.5, "humidity": 45}' \
     --cafile /etc/ssl/certs/ca-certificates.crt
   ```

4. **EMQX Validates**:
   - Queries PostgreSQL for device credentials
   - Authenticates device
   - Allows/denies connection

## MQTT Topics

### Device → Server
- `devices/{deviceId}/temperature` - Temperature readings
- `devices/{deviceId}/status` - Device status updates
- `devices/{deviceId}/heartbeat` - Keep-alive messages

### Server → Device
- `devices/{deviceId}/config` - Configuration updates
- `devices/{deviceId}/command` - Remote commands

## Management

### EMQX Dashboard
Access: `http://SERVER_IP:18083`
- Default credentials: `admin` / `public`
- Features:
  - Real-time connections monitor
  - Message flow visualization
  - Rule engine configuration
  - Client management

### Common Commands

```bash
# Check EMQX status
docker exec emqx emqx ctl status

# List connected clients
docker exec emqx emqx ctl clients list

# Check cluster status
docker exec emqx emqx ctl cluster status

# View EMQX configuration
docker exec emqx emqx ctl conf show

# Reload configuration
docker exec emqx emqx ctl conf reload
```

### Database Management

```bash
# Connect to IoT PostgreSQL
docker exec -it iot-postgres psql -U iotadmin -d iot_platform

# View device credentials
SELECT * FROM device_credentials;

# View recent temperature readings
SELECT * FROM temperature_readings ORDER BY time DESC LIMIT 10;

# Check TimescaleDB hypertables
SELECT * FROM timescaledb_information.hypertables;
```

## Monitoring

### Health Checks
```bash
# EMQX API status
curl http://localhost:18083/api/v5/status

# PostgreSQL connection
docker exec iot-postgres pg_isready -U iotadmin

# Check active connections
docker exec emqx emqx ctl listeners
```

### Logs
```bash
# EMQX logs
docker logs emqx --tail=100 -f

# PostgreSQL logs
docker logs iot-postgres --tail=100 -f

# Provisioning service logs
docker logs provisioning-service --tail=100 -f
```

## Backup & Recovery

### Database Backup
Included in main backup script:
```bash
# Backup is automated daily
# Manual backup:
docker exec iot-postgres pg_dump -U iotadmin iot_platform > iot_backup.sql
```

### EMQX Configuration Backup
```bash
# Export EMQX configuration
docker exec emqx emqx ctl conf export > emqx_config.json

# Configuration is also backed up in Docker volume
# Volume: emqx-platform_emqx-data
```

## Troubleshooting

### Device Cannot Connect
1. Check device credentials in database
2. Verify EMQX authentication configuration
3. Check network connectivity to port 8883
4. Verify TLS certificates are valid

### Data Not Being Stored
1. Check PostgreSQL container is running
2. Verify database connection from EMQX
3. Check EMQX rule engine configuration
4. Review PostgreSQL logs for errors

### High Memory Usage
1. Review number of connected devices
2. Check message retention settings
3. Review EMQX queue sizes
4. Consider scaling PostgreSQL resources

## Integration with Main App

The EMQX Platform integrates with the main Thermalog application:

1. **Data Flow**: Temperature data flows through EMQX → PostgreSQL → Main Backend
2. **API Integration**: Provisioning service provides APIs for device management
3. **Authentication**: Unified authentication system across platforms
4. **Monitoring**: Integrated with Uptime Kuma monitoring system

## Security Considerations

- **TLS/SSL**: All production MQTT connections use port 8883 with TLS
- **Authentication**: PostgreSQL-based credential validation
- **Network Isolation**: Containers communicate via internal Docker network
- **Firewall**: Only necessary ports exposed to external network
- **Credentials**: Strong passwords generated for all devices

## Performance

### Capacity
- **Concurrent Connections**: 10,000+ devices (EMQX limit)
- **Message Throughput**: 100,000+ messages/second
- **Data Retention**: TimescaleDB optimized for time-series data

### Optimization
- TimescaleDB compression for historical data
- Message queue tuning for high throughput
- Connection pooling for PostgreSQL
- Regular database maintenance and vacuuming

## References

- EMQX Documentation: https://www.emqx.io/docs/en/v5.8/
- TimescaleDB Documentation: https://docs.timescale.com/
- MQTT Protocol: https://mqtt.org/

---

For deployment instructions, see [DEPLOYMENT_GUIDE.md](../DEPLOYMENT_GUIDE.md)
For troubleshooting, see [troubleshooting.md](troubleshooting.md)
