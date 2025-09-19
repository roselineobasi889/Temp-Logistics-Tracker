# Decentralized Cold Chain Monitoring Smart Contract

## Overview

This smart contract provides a comprehensive solution for managing temperature-sensitive logistics in pharmaceutical and food supply chains. Built on the Stacks blockchain using Clarity, it ensures compliance with cold chain requirements through automated monitoring, violation detection, and immutable audit trails.

## Features

- **Temperature Monitoring**: Continuous tracking of temperature and humidity readings
- **Compliance Verification**: Automated detection of temperature threshold violations
- **Sensor Authorization**: Secure management of authorized IoT sensors
- **Shipment Lifecycle**: Complete tracking from creation to delivery
- **Audit Trail**: Immutable record of all events and readings
- **Multi-Party Access**: Controlled access for senders, receivers, and carriers

## Contract Constants

### Error Codes
- `ERR-UNAUTHORIZED-ACCESS (100)`: Unauthorized access attempt
- `ERR-SHIPMENT-NOT-FOUND (101)`: Shipment does not exist
- `ERR-INVALID-TEMPERATURE (102)`: Temperature reading outside valid range
- `ERR-SHIPMENT-ALREADY-EXISTS (103)`: Shipment ID already in use
- `ERR-TEMPERATURE-VIOLATION (104)`: Temperature threshold violation detected
- `ERR-INVALID-TIMESTAMP (105)`: Invalid timestamp provided
- `ERR-SHIPMENT-COMPLETED (106)`: Operation on completed shipment
- `ERR-INVALID-THRESHOLD (107)`: Invalid temperature threshold values
- `ERR-SENSOR-NOT-AUTHORIZED (108)`: Sensor not authorized for readings
- `ERR-INVALID-STATUS (109)`: Invalid shipment status value

### Temperature Limits
- **Minimum Temperature**: -80.00°C (-8000 in contract units)
- **Maximum Temperature**: 60.00°C (6000 in contract units)
- **Temperature Format**: Celsius × 100 (to handle decimal precision)

### Shipment Status Values
- `STATUS-CREATED (0)`: Shipment created but not yet in transit
- `STATUS-IN-TRANSIT (1)`: Shipment is being transported
- `STATUS-DELIVERED (2)`: Shipment has been delivered
- `STATUS-COMPROMISED (3)`: Shipment has temperature violations

## Data Structures

### Shipments Map
Stores complete shipment information including:
- Sender, receiver, and carrier principals
- Product type and temperature thresholds
- Creation timestamp and current status
- Violation count and last update timestamp

### Temperature Readings Map
Records all temperature data points with:
- Temperature and humidity measurements
- Sensor ID and geographic location
- Timestamp and violation status
- Complete audit trail for compliance

### Authorized Sensors Map
Manages IoT sensor authorization including:
- Sensor owner and certification status
- Last calibration timestamp
- Security controls for data integrity

## Public Functions

### Administrative Functions

#### `authorize-sensor`
```clarity
(authorize-sensor (sensor-id (string-ascii 32)) (owner principal))
```
Authorizes a new temperature sensor for data submission. Only the contract owner can execute this function.

#### `revoke-sensor-authorization`
```clarity
(revoke-sensor-authorization (sensor-id (string-ascii 32)))
```
Revokes authorization for a compromised or malfunctioning sensor. Only the contract owner can execute this function.

### Shipment Management

#### `create-shipment`
```clarity
(create-shipment (receiver principal) (carrier principal) (product-type (string-ascii 50)) (min-temp int) (max-temp int))
```
Creates a new cold chain shipment with specified temperature requirements. Returns unique shipment ID.

**Parameters:**
- `receiver`: Principal address of the shipment recipient
- `carrier`: Principal address of the logistics carrier
- `product-type`: Description of the product being shipped (max 50 characters)
- `min-temp`: Minimum acceptable temperature (Celsius × 100)
- `max-temp`: Maximum acceptable temperature (Celsius × 100)

#### `update-shipment-status`
```clarity
(update-shipment-status (shipment-id uint) (new-status uint))
```
Updates the status of a shipment during the logistics process. Can be called by sender, receiver, or carrier.

### Temperature Monitoring

#### `add-temperature-reading`
```clarity
(add-temperature-reading (shipment-id uint) (temperature int) (humidity uint) (sensor-id (string-ascii 32)) (location (string-ascii 100)))
```
Records a new temperature and humidity reading from an authorized sensor.

**Parameters:**
- `shipment-id`: Unique identifier of the shipment
- `temperature`: Recorded temperature (Celsius × 100)
- `humidity`: Recorded humidity percentage
- `sensor-id`: Unique identifier of the reporting sensor
- `location`: Geographic location of the reading

## Read-Only Functions

### Data Retrieval

#### `get-shipment`
```clarity
(get-shipment (shipment-id uint))
```
Returns complete shipment information for the specified ID.

#### `get-temperature-reading`
```clarity
(get-temperature-reading (shipment-id uint) (reading-id uint))
```
Retrieves a specific temperature reading by shipment and reading ID.

#### `get-reading-count`
```clarity
(get-reading-count (shipment-id uint))
```
Returns the total number of temperature readings recorded for a shipment.

### Compliance Monitoring

#### `has-temperature-violations`
```clarity
(has-temperature-violations (shipment-id uint))
```
Checks if a shipment has any recorded temperature violations.

#### `get-compliance-percentage`
```clarity
(get-compliance-percentage (shipment-id uint))
```
Calculates the compliance percentage based on violation count versus total readings.

#### `is-sensor-authorized`
```clarity
(is-sensor-authorized (sensor-id (string-ascii 32)))
```
Verifies if a sensor is currently authorized to submit temperature readings.

### Event Logging

#### `get-event`
```clarity
(get-event (event-id uint))
```
Retrieves event log entries for audit and monitoring purposes.

## Usage Examples

### Setting Up a Cold Chain Shipment

1. **Authorize Sensors** (Contract Owner Only)
```clarity
(contract-call? .cold-chain authorize-sensor "SENSOR001" 'SP1234567890...)
```

2. **Create Shipment**
```clarity
(contract-call? .cold-chain create-shipment 
  'SP-RECEIVER... 
  'SP-CARRIER... 
  "Pfizer COVID Vaccine" 
  -8000    ;; -80.00°C minimum
  -6000)   ;; -60.00°C maximum
```

3. **Record Temperature Readings**
```clarity
(contract-call? .cold-chain add-temperature-reading 
  u1           ;; shipment ID
  -7500        ;; -75.00°C
  u45          ;; 45% humidity
  "SENSOR001"  ;; sensor ID
  "Warehouse A, Lagos")
```

4. **Update Status**
```clarity
(contract-call? .cold-chain update-shipment-status u1 u1) ;; Set to IN-TRANSIT
```

5. **Check Compliance**
```clarity
(contract-call? .cold-chain get-compliance-percentage u1)
```

## Security Features

- **Access Control**: Multi-level authorization for different operations
- **Sensor Authentication**: Only pre-authorized sensors can submit data
- **Data Validation**: Comprehensive input validation and error handling
- **Immutable Records**: All data permanently stored on blockchain
- **Event Logging**: Complete audit trail for regulatory compliance

## Integration Requirements

### IoT Sensor Integration
- Sensors must be pre-authorized by contract owner
- Temperature data should be submitted in Celsius × 100 format
- Include accurate timestamps and location data
- Implement secure communication protocols

### Supply Chain Integration
- Integrate with existing logistics management systems
- Implement real-time monitoring dashboards
- Set up automated alerts for temperature violations
- Provide compliance reporting for regulatory requirements

## Compliance Standards

This contract supports compliance with:
- FDA regulations for pharmaceutical cold chain
- WHO guidelines for vaccine storage and distribution
- HACCP requirements for food safety
- GDP (Good Distribution Practice) standards
- ISO 13485 for medical device quality management