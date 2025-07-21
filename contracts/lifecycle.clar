;; Digital Asset Provenance & Lifecycle Management

;; Constants
(define-constant nexus-admin tx-sender)
(define-constant ERR_UNAUTHORIZED_ACCESS (err u1))
(define-constant ERR_ASSET_NOT_FOUND (err u2))
(define-constant ERR_INVALID_LIFECYCLE_TRANSITION (err u3))
(define-constant ERR_ASSET_ALREADY_REGISTERED (err u4))
(define-constant ERR_INVALID_INPUT_DATA (err u5))

;; Data Variables
(define-data-var minimum-authenticity-threshold uint u60)

;; Principal Maps
(define-map nexus-participants
    principal
    {
        participant-role: (string-ascii 20),
        participant-active: bool,
        reputation-rating: uint
    }
)

;; Asset Structure
(define-map digital-assets
    uint  ;; asset-id
    {
        asset-title: (string-ascii 50),
        genesis-creator: principal,
        active-custodian: principal,
        lifecycle-phase: (string-ascii 20),
        authenticity-rating: uint,
        genesis-timestamp: uint,
        current-coordinates: (string-ascii 100),
        market-valuation: uint,
        authenticity-confirmed: bool
    }
)

;; Provenance Trail
(define-map provenance-ledger
    {asset-id: uint, event-id: uint}
    {
        origin-participant: principal,
        destination-participant: principal,
        event-category: (string-ascii 20),
        event-timestamp: uint,
        event-metadata: (string-ascii 200)
    }
)

;; Counter for event IDs
(define-data-var total-events uint u0)

;; Read-only functions
(define-read-only (fetch-asset-profile (asset-id uint))
    (map-get? digital-assets asset-id)
)

(define-read-only (fetch-participant-profile (participant-address principal))
    (map-get? nexus-participants participant-address)
)

(define-read-only (fetch-provenance-event (asset-id uint) (event-id uint))
    (map-get? provenance-ledger {asset-id: asset-id, event-id: event-id})
)

;; Internal Functions
(define-private (verify-participant-status (participant-address principal))
    (let ((participant-data (unwrap! (map-get? nexus-participants participant-address) false)))
        (get participant-active participant-data)
    )
)

(define-private (generate-next-event-id)
    (begin
        (var-set total-events (+ (var-get total-events) u1))
        (var-get total-events)
    )
)

;; Input validation functions
(define-private (validate-compact-string (input (string-ascii 20)))
    (and (>= (len input) u1) (<= (len input) u20))
)

(define-private (validate-standard-string (input (string-ascii 50)))
    (and (>= (len input) u1) (<= (len input) u50))
)

(define-private (validate-extended-string (input (string-ascii 100)))
    (and (>= (len input) u1) (<= (len input) u100))
)

(define-private (validate-detailed-string (input (string-ascii 200)))
    (and (>= (len input) u1) (<= (len input) u200))
)

(define-private (validate-numeric-input (input uint))
    (< input u340282366920938463463374607431768211455)  ;; Max uint value
)

;; Administrative Functions
(define-public (onboard-participant (participant-address principal) (role-designation (string-ascii 20)))
    (begin
        (asserts! (is-eq tx-sender nexus-admin) ERR_UNAUTHORIZED_ACCESS)
        (asserts! (is-none (map-get? nexus-participants participant-address)) ERR_ASSET_ALREADY_REGISTERED)
        (asserts! (validate-compact-string role-designation) ERR_INVALID_INPUT_DATA)
        (ok (map-set nexus-participants 
            participant-address
            {
                participant-role: role-designation,
                participant-active: true,
                reputation-rating: u100
            }
        ))
    )
)

(define-public (modify-participant-status (participant-address principal) (active-status bool))
    (begin
        (asserts! (is-eq tx-sender nexus-admin) ERR_UNAUTHORIZED_ACCESS)
        (asserts! (is-some (map-get? nexus-participants participant-address)) ERR_UNAUTHORIZED_ACCESS)
        (ok (map-set nexus-participants 
            participant-address
            (merge (unwrap-panic (map-get? nexus-participants participant-address))
                  {participant-active: active-status})
        ))
    )
)

;; Asset Management Functions
(define-public (mint-digital-asset 
    (asset-id uint)
    (asset-title (string-ascii 50))
    (initial-coordinates (string-ascii 100))
    (initial-valuation uint))
    (let ((minting-participant tx-sender))
        (begin
            (asserts! (verify-participant-status minting-participant) ERR_UNAUTHORIZED_ACCESS)
            (asserts! (is-none (map-get? digital-assets asset-id)) ERR_ASSET_ALREADY_REGISTERED)
            (asserts! (validate-numeric-input asset-id) ERR_INVALID_INPUT_DATA)
            (asserts! (validate-standard-string asset-title) ERR_INVALID_INPUT_DATA)
            (asserts! (validate-extended-string initial-coordinates) ERR_INVALID_INPUT_DATA)
            (asserts! (validate-numeric-input initial-valuation) ERR_INVALID_INPUT_DATA)
            (ok (map-set digital-assets
                asset-id
                {
                    asset-title: asset-title,
                    genesis-creator: minting-participant,
                    active-custodian: minting-participant,
                    lifecycle-phase: "genesis",
                    authenticity-rating: u100,
                    genesis-timestamp: block-height,
                    current-coordinates: initial-coordinates,
                    market-valuation: initial-valuation,
                    authenticity-confirmed: false
                }
            ))
        )
    )
)

(define-public (evolve-lifecycle-phase 
    (asset-id uint)
    (next-phase (string-ascii 20))
    (transition-notes (string-ascii 200)))
    (let (
        (evolving-participant tx-sender)
        (asset-data (unwrap! (map-get? digital-assets asset-id) ERR_ASSET_NOT_FOUND))
        )
        (begin
            (asserts! (verify-participant-status evolving-participant) ERR_UNAUTHORIZED_ACCESS)
            (asserts! (is-eq (get active-custodian asset-data) evolving-participant) ERR_UNAUTHORIZED_ACCESS)
            (asserts! (validate-numeric-input asset-id) ERR_INVALID_INPUT_DATA)
            (asserts! (validate-compact-string next-phase) ERR_INVALID_INPUT_DATA)
            (asserts! (validate-detailed-string transition-notes) ERR_INVALID_INPUT_DATA)
            (map-set digital-assets
                asset-id
                (merge asset-data {lifecycle-phase: next-phase})
            )
            (map-set provenance-ledger
                {asset-id: asset-id, event-id: (generate-next-event-id)}
                {
                    origin-participant: evolving-participant,
                    destination-participant: evolving-participant,
                    event-category: next-phase,
                    event-timestamp: block-height,
                    event-metadata: transition-notes
                }
            )
            (ok true)
        )
    )
)

(define-public (transfer-custodianship
    (asset-id uint)
    (next-custodian principal)
    (handover-details (string-ascii 200)))
    (let (
        (current-custodian tx-sender)
        (asset-data (unwrap! (map-get? digital-assets asset-id) ERR_ASSET_NOT_FOUND))
        )
        (begin
            (asserts! (verify-participant-status current-custodian) ERR_UNAUTHORIZED_ACCESS)
            (asserts! (verify-participant-status next-custodian) ERR_UNAUTHORIZED_ACCESS)
            (asserts! (is-eq (get active-custodian asset-data) current-custodian) ERR_UNAUTHORIZED_ACCESS)
            (asserts! (validate-numeric-input asset-id) ERR_INVALID_INPUT_DATA)
            (asserts! (validate-detailed-string handover-details) ERR_INVALID_INPUT_DATA)
            (map-set digital-assets
                asset-id
                (merge asset-data {
                    active-custodian: next-custodian,
                    lifecycle-phase: "custody-transferred"
                })
            )
            (map-set provenance-ledger
                {asset-id: asset-id, event-id: (generate-next-event-id)}
                {
                    origin-participant: current-custodian,
                    destination-participant: next-custodian,
                    event-category: "custody-handover",
                    event-timestamp: block-height,
                    event-metadata: handover-details
                }
            )
            (ok true)
        )
    )
)

(define-public (certify-authenticity
    (asset-id uint)
    (authenticity-score uint)
    (certification-notes (string-ascii 200)))
    (let (
        (certifying-authority tx-sender)
        (asset-data (unwrap! (map-get? digital-assets asset-id) ERR_ASSET_NOT_FOUND))
        )
        (begin
            (asserts! (verify-participant-status certifying-authority) ERR_UNAUTHORIZED_ACCESS)
            (asserts! (validate-numeric-input asset-id) ERR_INVALID_INPUT_DATA)
            (asserts! (<= authenticity-score u100) ERR_INVALID_INPUT_DATA)
            (asserts! (validate-detailed-string certification-notes) ERR_INVALID_INPUT_DATA)
            (map-set digital-assets
                asset-id
                (merge asset-data {
                    authenticity-rating: authenticity-score,
                    authenticity-confirmed: (>= authenticity-score (var-get minimum-authenticity-threshold))
                })
            )
            (map-set provenance-ledger
                {asset-id: asset-id, event-id: (generate-next-event-id)}
                {
                    origin-participant: certifying-authority,
                    destination-participant: certifying-authority,
                    event-category: "authenticity-audit",
                    event-timestamp: block-height,
                    event-metadata: certification-notes
                }
            )
            (ok true)
        )
    )
)

(define-public (relocate-asset
    (asset-id uint)
    (new-coordinates (string-ascii 100))
    (relocation-notes (string-ascii 200)))
    (let (
        (relocating-participant tx-sender)
        (asset-data (unwrap! (map-get? digital-assets asset-id) ERR_ASSET_NOT_FOUND))
        )
        (begin
            (asserts! (verify-participant-status relocating-participant) ERR_UNAUTHORIZED_ACCESS)
            (asserts! (is-eq (get active-custodian asset-data) relocating-participant) ERR_UNAUTHORIZED_ACCESS)
            (asserts! (validate-numeric-input asset-id) ERR_INVALID_INPUT_DATA)
            (asserts! (validate-extended-string new-coordinates) ERR_INVALID_INPUT_DATA)
            (asserts! (validate-detailed-string relocation-notes) ERR_INVALID_INPUT_DATA)
            (map-set digital-assets
                asset-id
                (merge asset-data {current-coordinates: new-coordinates})
            )
            (map-set provenance-ledger
                {asset-id: asset-id, event-id: (generate-next-event-id)}
                {
                    origin-participant: relocating-participant,
                    destination-participant: relocating-participant,
                    event-category: "coordinates-update",
                    event-timestamp: block-height,
                    event-metadata: relocation-notes
                }
            )
            (ok true)
        )
    )
)