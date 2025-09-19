;; Decentralized Cold Chain Monitoring Smart Contract
;; This contract manages temperature-sensitive logistics and ensures compliance
;; with cold chain requirements for pharmaceutical and food supply chains

;; Contract constants for error handling
(define-constant ERR-UNAUTHORIZED-ACCESS (err u100))
(define-constant ERR-SHIPMENT-NOT-FOUND (err u101))
(define-constant ERR-INVALID-TEMPERATURE (err u102))
(define-constant ERR-SHIPMENT-ALREADY-EXISTS (err u103))
(define-constant ERR-TEMPERATURE-VIOLATION (err u104))
(define-constant ERR-INVALID-TIMESTAMP (err u105))
(define-constant ERR-SHIPMENT-COMPLETED (err u106))
(define-constant ERR-INVALID-THRESHOLD (err u107))
(define-constant ERR-SENSOR-NOT-AUTHORIZED (err u108))
(define-constant ERR-INVALID-STATUS (err u109))

;; Validation constants for temperature ranges (in Celsius * 100 to handle decimals)
(define-constant MIN-TEMPERATURE -8000) ;; -80.00C
(define-constant MAX-TEMPERATURE 6000)  ;; 60.00C
(define-constant MAX-TIMESTAMP u4294967295) ;; Maximum valid timestamp

;; Contract owner for administrative functions
(define-constant CONTRACT-OWNER tx-sender)

;; Shipment status enumeration
(define-constant STATUS-CREATED u0)
(define-constant STATUS-IN-TRANSIT u1)
(define-constant STATUS-DELIVERED u2)
(define-constant STATUS-COMPROMISED u3)

;; Data structure for shipment information
;; Contains all essential shipment details including temperature thresholds
(define-map shipments
  { shipment-id: uint }
  {
    sender: principal,           ;; Address of shipment sender
    receiver: principal,         ;; Address of shipment receiver
    carrier: principal,          ;; Logistics carrier responsible for transport
    product-type: (string-ascii 50), ;; Type of product being shipped
    min-temp: int,              ;; Minimum allowed temperature (Celsius * 100)
    max-temp: int,              ;; Maximum allowed temperature (Celsius * 100)
    created-at: uint,           ;; Shipment creation timestamp
    status: uint,               ;; Current shipment status
    violation-count: uint,      ;; Number of temperature violations
    last-update: uint           ;; Last temperature reading timestamp
  }
)

;; Temperature readings storage with sensor information
;; Stores all temperature data points for complete audit trail
(define-map temperature-readings
  { shipment-id: uint, reading-id: uint }
  {
    temperature: int,           ;; Recorded temperature (Celsius * 100)
    humidity: uint,             ;; Recorded humidity percentage
    timestamp: uint,            ;; When reading was taken
    sensor-id: (string-ascii 32), ;; Unique sensor identifier
    location: (string-ascii 100), ;; Geographic location of reading
    is-violation: bool          ;; Whether this reading violates thresholds
  }
)

;; Counter for generating unique reading IDs per shipment
(define-map reading-counters
  { shipment-id: uint }
  { count: uint }
)

;; Authorized sensors that can submit temperature data
;; Only pre-approved sensors can add readings to maintain data integrity
(define-map authorized-sensors
  { sensor-id: (string-ascii 32) }
  {
    owner: principal,           ;; Sensor owner/operator
    certified: bool,            ;; Whether sensor is certified for cold chain
    last-calibration: uint      ;; Last calibration timestamp
  }
)

;; Global shipment counter for generating unique shipment IDs
(define-data-var next-shipment-id uint u1)

;; Event logging for external monitoring systems
(define-map event-log
  { event-id: uint }
  {
    event-type: (string-ascii 20), ;; Type of event (violation, delivery, etc.)
    shipment-id: uint,
    timestamp: uint,
    data: (string-ascii 200)   ;; Additional event data
  }
)

(define-data-var next-event-id uint u1)

;; Administrative function to authorize new temperature sensors
;; Only contract owner can add sensors to maintain security
(define-public (authorize-sensor (sensor-id (string-ascii 32)) (owner principal))
  (begin
    ;; Verify only contract owner can authorize sensors
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED-ACCESS)
    ;; Add sensor to authorized list with current timestamp
    (map-set authorized-sensors
      { sensor-id: sensor-id }
      {
        owner: owner,
        certified: true,
        last-calibration: block-height ;; Using block height as timestamp proxy
      }
    )
    (ok true)
  )
)

;; Create a new cold chain shipment with temperature requirements
;; Establishes shipment parameters and initializes tracking
(define-public (create-shipment 
  (receiver principal) 
  (carrier principal) 
  (product-type (string-ascii 50))
  (min-temp int)
  (max-temp int))
  (let ((shipment-id (var-get next-shipment-id)))
    ;; Validate temperature thresholds are within acceptable ranges
    (asserts! (and (>= min-temp MIN-TEMPERATURE) (<= max-temp MAX-TEMPERATURE)) ERR-INVALID-THRESHOLD)
    (asserts! (< min-temp max-temp) ERR-INVALID-THRESHOLD)
    ;; Verify shipment doesn't already exist
    (asserts! (is-none (map-get? shipments { shipment-id: shipment-id })) ERR-SHIPMENT-ALREADY-EXISTS)
    
    ;; Create new shipment record
    (map-set shipments
      { shipment-id: shipment-id }
      {
        sender: tx-sender,
        receiver: receiver,
        carrier: carrier,
        product-type: product-type,
        min-temp: min-temp,
        max-temp: max-temp,
        created-at: block-height,
        status: STATUS-CREATED,
        violation-count: u0,
        last-update: block-height
      }
    )
    
    ;; Initialize reading counter for this shipment
    (map-set reading-counters
      { shipment-id: shipment-id }
      { count: u0 }
    )
    
    ;; Increment global shipment counter
    (var-set next-shipment-id (+ shipment-id u1))
    
    ;; Log shipment creation event and check response
    (unwrap! (log-event "SHIPMENT_CREATED" shipment-id "New shipment initialized") ERR-UNAUTHORIZED-ACCESS)
    
    (ok shipment-id)
  )
)

;; Record temperature reading from authorized sensor
;; Core function for maintaining cold chain compliance
(define-public (add-temperature-reading 
  (shipment-id uint)
  (temperature int)
  (humidity uint)
  (sensor-id (string-ascii 32))
  (location (string-ascii 100)))
  (let (
    (shipment (unwrap! (map-get? shipments { shipment-id: shipment-id }) ERR-SHIPMENT-NOT-FOUND))
    (sensor (unwrap! (map-get? authorized-sensors { sensor-id: sensor-id }) ERR-SENSOR-NOT-AUTHORIZED))
    (reading-counter (default-to { count: u0 } (map-get? reading-counters { shipment-id: shipment-id })))
    (reading-id (get count reading-counter))
    (is-violation (or (< temperature (get min-temp shipment)) (> temperature (get max-temp shipment))))
  )
    ;; Validate sensor is authorized and temperature is in valid range
    (asserts! (get certified sensor) ERR-SENSOR-NOT-AUTHORIZED)
    (asserts! (and (>= temperature MIN-TEMPERATURE) (<= temperature MAX-TEMPERATURE)) ERR-INVALID-TEMPERATURE)
    ;; Ensure shipment is not already completed
    (asserts! (< (get status shipment) STATUS-DELIVERED) ERR-SHIPMENT-COMPLETED)
    
    ;; Store temperature reading with all metadata
    (map-set temperature-readings
      { shipment-id: shipment-id, reading-id: reading-id }
      {
        temperature: temperature,
        humidity: humidity,
        timestamp: block-height,
        sensor-id: sensor-id,
        location: location,
        is-violation: is-violation
      }
    )
    
    ;; Update reading counter
    (map-set reading-counters
      { shipment-id: shipment-id }
      { count: (+ reading-id u1) }
    )
    
    ;; Update shipment with latest information
    (map-set shipments
      { shipment-id: shipment-id }
      (merge shipment {
        last-update: block-height,
        violation-count: (if is-violation 
          (+ (get violation-count shipment) u1)
          (get violation-count shipment)
        ),
        status: (if is-violation STATUS-COMPROMISED (get status shipment))
      })
    )
    
    ;; Log temperature violation if detected
    (if is-violation
      (begin
        (unwrap! (log-event "TEMP_VIOLATION" shipment-id 
          (concat "Temp: " (int-to-string temperature))) ERR-UNAUTHORIZED-ACCESS)
        (ok reading-id)
      )
      (ok reading-id)
    )
  )
)

;; Update shipment status during logistics process
;; Allows authorized parties to update delivery status
(define-public (update-shipment-status (shipment-id uint) (new-status uint))
  (let ((shipment (unwrap! (map-get? shipments { shipment-id: shipment-id }) ERR-SHIPMENT-NOT-FOUND)))
    ;; Verify caller is authorized to update status
    (asserts! (or 
      (is-eq tx-sender (get sender shipment))
      (is-eq tx-sender (get receiver shipment))
      (is-eq tx-sender (get carrier shipment))
    ) ERR-UNAUTHORIZED-ACCESS)
    
    ;; Validate status value is within acceptable range
    (asserts! (<= new-status STATUS-COMPROMISED) ERR-INVALID-STATUS)
    
    ;; Update shipment status
    (map-set shipments
      { shipment-id: shipment-id }
      (merge shipment { 
        status: new-status,
        last-update: block-height
      })
    )
    
    ;; Log status change event and check response
    (unwrap! (log-event "STATUS_UPDATE" shipment-id 
      (concat "New status: " (uint-to-ascii new-status))) ERR-UNAUTHORIZED-ACCESS)
    
    (ok true)
  )
)

;; Retrieve complete shipment information
;; Public read-only function for shipment details
(define-read-only (get-shipment (shipment-id uint))
  (map-get? shipments { shipment-id: shipment-id })
)

;; Get specific temperature reading by shipment and reading ID
;; Allows detailed audit of temperature history
(define-read-only (get-temperature-reading (shipment-id uint) (reading-id uint))
  (map-get? temperature-readings { shipment-id: shipment-id, reading-id: reading-id })
)

;; Check if shipment has any temperature violations
;; Quick compliance check for quality assurance
(define-read-only (has-temperature-violations (shipment-id uint))
  (match (map-get? shipments { shipment-id: shipment-id })
    shipment (ok (> (get violation-count shipment) u0))
    ERR-SHIPMENT-NOT-FOUND
  )
)

;; Get total number of temperature readings for a shipment
;; Useful for pagination and data analysis
(define-read-only (get-reading-count (shipment-id uint))
  (match (map-get? reading-counters { shipment-id: shipment-id })
    counter (ok (get count counter))
    (ok u0)
  )
)

;; Verify sensor authorization status
;; Check if sensor is authorized to submit readings
(define-read-only (is-sensor-authorized (sensor-id (string-ascii 32)))
  (match (map-get? authorized-sensors { sensor-id: sensor-id })
    sensor (ok (get certified sensor))
    (ok false)
  )
)

;; Calculate compliance percentage for a shipment
;; Returns percentage of readings that were within acceptable range
(define-read-only (get-compliance-percentage (shipment-id uint))
  (let (
    (shipment (unwrap! (map-get? shipments { shipment-id: shipment-id }) ERR-SHIPMENT-NOT-FOUND))
    (total-readings (unwrap-panic (get-reading-count shipment-id)))
    (violations (get violation-count shipment))
  )
    (if (is-eq total-readings u0)
      (ok u100) ;; 100% compliance if no readings yet
      (ok (/ (* (- total-readings violations) u100) total-readings))
    )
  )
)

;; Internal helper function to log events for external monitoring
;; Creates audit trail for important contract events
(define-private (log-event (event-type (string-ascii 20)) (shipment-id uint) (data (string-ascii 200)))
  (let ((event-id (var-get next-event-id)))
    (map-set event-log
      { event-id: event-id }
      {
        event-type: event-type,
        shipment-id: shipment-id,
        timestamp: block-height,
        data: data
      }
    )
    (var-set next-event-id (+ event-id u1))
    (ok event-id)
  )
)

;; Helper function to convert uint to ASCII string
;; Used for event logging and data concatenation
(define-read-only (uint-to-ascii (value uint))
  (if (is-eq value u0) "0"
    (if (is-eq value u1) "1"
      (if (is-eq value u2) "2"
        (if (is-eq value u3) "3"
          (if (is-eq value u4) "4"
            (if (is-eq value u5) "5"
              (if (is-eq value u6) "6"
                (if (is-eq value u7) "7"
                  (if (is-eq value u8) "8"
                    (if (is-eq value u9) "9"
                      "N" ;; For values > 9, return "N"
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  )
)

;; Helper function to convert int to ASCII string
;; Used for logging temperature values
(define-read-only (int-to-string (value int))
  (if (>= value 0)
    (uint-to-ascii (to-uint value))
    (concat "-" (uint-to-ascii (to-uint (* value -1))))
  )
)

;; Emergency function to revoke sensor authorization
;; Allows contract owner to disable compromised sensors
(define-public (revoke-sensor-authorization (sensor-id (string-ascii 32)))
  (begin
    ;; Only contract owner can revoke sensor authorization
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED-ACCESS)
    
    ;; Update sensor certification status
    (match (map-get? authorized-sensors { sensor-id: sensor-id })
      sensor (begin
        (map-set authorized-sensors
          { sensor-id: sensor-id }
          (merge sensor { certified: false })
        )
        (ok true)
      )
      ERR-SENSOR-NOT-AUTHORIZED
    )
  )
)

;; Get event log entry by ID for audit purposes
;; Provides access to historical events
(define-read-only (get-event (event-id uint))
  (map-get? event-log { event-id: event-id })
)