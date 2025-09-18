;; vendor-registry.clar - Food Aid Vendor Registration and Management System
;; Manages verified vendors authorized to accept food aid coupons

;; =============================================================================
;; CONSTANTS
;; =============================================================================

(define-constant CONTRACT-ADMIN tx-sender)
(define-constant ERR-UNAUTHORIZED (err u200))
(define-constant ERR-VENDOR-NOT-FOUND (err u201))
(define-constant ERR-VENDOR-ALREADY-REGISTERED (err u202))
(define-constant ERR-VENDOR-NOT-VERIFIED (err u203))
(define-constant ERR-INVALID-VENDOR-DATA (err u204))
(define-constant ERR-VENDOR-SUSPENDED (err u205))
(define-constant ERR-INVALID-LOCATION (err u206))
(define-constant ERR-INVALID-CATEGORIES (err u207))
(define-constant ERR-CONTRACT-NOT-INITIALIZED (err u208))
(define-constant ERR-INSUFFICIENT-RATING (err u209))

;; Vendor status constants
(define-constant STATUS-PENDING u0)
(define-constant STATUS-VERIFIED u1)
(define-constant STATUS-SUSPENDED u2)
(define-constant STATUS-REJECTED u3)

;; Performance rating constants
(define-constant MIN-RATING u1)
(define-constant MAX-RATING u5)
(define-constant DEFAULT-RATING u3)

;; Location constants (simplified geographic regions)
(define-constant REGION-NORTH u1)
(define-constant REGION-SOUTH u2)
(define-constant REGION-EAST u3)
(define-constant REGION-WEST u4)
(define-constant REGION-CENTRAL u5)

;; Food category constants (matching coupon categories)
(define-constant CATEGORY-GRAINS u1)
(define-constant CATEGORY-PROTEINS u2)
(define-constant CATEGORY-VEGETABLES u3)
(define-constant CATEGORY-FRUITS u4)
(define-constant CATEGORY-DAIRY u5)
(define-constant CATEGORY-GENERAL u6)

;; =============================================================================
;; DATA VARIABLES
;; =============================================================================

(define-data-var contract-initialized bool false)
(define-data-var total-vendors uint u0)
(define-data-var verified-vendors-count uint u0)
(define-data-var next-vendor-id uint u1)
(define-data-var authorized-verifiers-count uint u0)

;; =============================================================================
;; DATA MAPS
;; =============================================================================

;; Authorized verifiers (can approve/suspend vendors)
(define-map authorized-verifiers principal bool)

;; Vendor registry with comprehensive information
(define-map vendors
    principal
    {
        vendor-id: uint,
        name: (string-utf8 100),
        business-type: (string-utf8 50),
        location-region: uint,
        address: (string-utf8 200),
        contact-info: (string-utf8 100),
        registration-date: uint,
        status: uint,
        verified-by: principal,
        verification-date: uint,
        supported-categories: (list 6 uint),
        performance-rating: uint,
        compliance-score: uint,
        total-redemptions: uint,
        total-value-processed: uint,
        last-activity: uint
    }
)

;; Vendor performance metrics
(define-map vendor-performance
    principal
    {
        successful-transactions: uint,
        failed-transactions: uint,
        average-processing-time: uint,
        customer-satisfaction: uint,
        compliance-violations: uint,
        last-inspection: uint,
        inspection-score: uint
    }
)

;; Regional vendor statistics
(define-map regional-statistics
    uint ;; region
    {
        total-vendors: uint,
        verified-vendors: uint,
        total-redemptions: uint,
        average-rating: uint,
        last-updated: uint
    }
)

;; Category availability by vendor
(define-map vendor-category-availability
    { vendor: principal, category: uint }
    {
        is-available: bool,
        stock-level: uint, ;; 0-100 percentage
        last-updated: uint,
        price-competitiveness: uint ;; 1-5 rating
    }
)

;; Vendor application queue
(define-map vendor-applications
    principal
    {
        application-date: uint,
        submitted-documents: (string-utf8 500),
        verification-notes: (string-utf8 300),
        reviewer: (optional principal),
        review-deadline: uint
    }
)

;; =============================================================================
;; PRIVATE FUNCTIONS
;; =============================================================================

(define-private (is-valid-region (region uint))
    (and (>= region REGION-NORTH) (<= region REGION-CENTRAL))
)

(define-private (is-valid-status (status uint))
    (and (>= status STATUS-PENDING) (<= status STATUS-REJECTED))
)

(define-private (is-valid-rating (rating uint))
    (and (>= rating MIN-RATING) (<= rating MAX-RATING))
)

(define-private (is-valid-principal (principal-to-check principal))
    (not (is-eq principal-to-check 'SP000000000000000000002Q6VF78))
)

(define-private (calculate-compliance-score (successful uint) (failed uint) (violations uint))
    (let (
        (total-transactions (+ successful failed))
        (success-rate (if (> total-transactions u0) (/ (* successful u100) total-transactions) u100))
        (violation-penalty (* violations u5))
    )
        (if (>= success-rate violation-penalty)
            (- success-rate violation-penalty)
            u0
        )
    )
)

(define-private (update-regional-stats (region uint) (vendor-count-change int) (verified-change int))
    (let (
        (current-stats (default-to 
            { total-vendors: u0, verified-vendors: u0, total-redemptions: u0, average-rating: DEFAULT-RATING, last-updated: u0 }
            (map-get? regional-statistics region)
        ))
        (new-total (if (>= vendor-count-change 0) 
                      (+ (get total-vendors current-stats) (to-uint vendor-count-change))
                      (- (get total-vendors current-stats) (to-uint (* vendor-count-change -1)))))
        (new-verified (if (>= verified-change 0)
                         (+ (get verified-vendors current-stats) (to-uint verified-change))
                         (- (get verified-vendors current-stats) (to-uint (* verified-change -1)))))
    )
        (map-set regional-statistics region
            (merge current-stats {
                total-vendors: new-total,
                verified-vendors: new-verified,
                last-updated: burn-block-height
            })
        )
    )
)

;; =============================================================================
;; READ-ONLY FUNCTIONS
;; =============================================================================

(define-read-only (get-vendor-info (vendor principal))
    (map-get? vendors vendor)
)

(define-read-only (get-vendor-performance (vendor principal))
    (map-get? vendor-performance vendor)
)

(define-read-only (is-vendor-verified (vendor principal))
    (match (map-get? vendors vendor)
        some-vendor (is-eq (get status some-vendor) STATUS-VERIFIED)
        false
    )
)

(define-read-only (is-authorized-verifier (verifier principal))
    (default-to false (map-get? authorized-verifiers verifier))
)

(define-read-only (get-regional-stats (region uint))
    (map-get? regional-statistics region)
)

(define-read-only (get-vendor-category-status (vendor principal) (category uint))
    (map-get? vendor-category-availability { vendor: vendor, category: category })
)

(define-read-only (get-contract-statistics)
    {
        total-vendors: (var-get total-vendors),
        verified-vendors: (var-get verified-vendors-count),
        authorized-verifiers: (var-get authorized-verifiers-count),
        next-vendor-id: (var-get next-vendor-id),
        contract-initialized: (var-get contract-initialized)
    }
)

(define-read-only (can-vendor-accept-category (vendor principal) (category uint))
    (match (map-get? vendors vendor)
        some-vendor 
            (and 
                (is-eq (get status some-vendor) STATUS-VERIFIED)
                (is-some (index-of (get supported-categories some-vendor) category))
            )
        false
    )
)

;; =============================================================================
;; PUBLIC FUNCTIONS - ADMINISTRATION
;; =============================================================================

(define-public (initialize-contract)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-ADMIN) ERR-UNAUTHORIZED)
        (asserts! (not (var-get contract-initialized)) ERR-UNAUTHORIZED)
        (var-set contract-initialized true)
        (map-set authorized-verifiers CONTRACT-ADMIN true)
        (var-set authorized-verifiers-count u1)
        (print { event: "contract-initialized", admin: CONTRACT-ADMIN })
        (ok true)
    )
)

(define-public (authorize-verifier (verifier principal))
    (begin
        (asserts! (var-get contract-initialized) ERR-CONTRACT-NOT-INITIALIZED)
        (asserts! (is-eq tx-sender CONTRACT-ADMIN) ERR-UNAUTHORIZED)
        (asserts! (is-valid-principal verifier) ERR-INVALID-VENDOR-DATA)
        (map-set authorized-verifiers verifier true)
        (var-set authorized-verifiers-count (+ (var-get authorized-verifiers-count) u1))
        (print { event: "verifier-authorized", verifier: verifier })
        (ok true)
    )
)

;; =============================================================================
;; PUBLIC FUNCTIONS - VENDOR MANAGEMENT
;; =============================================================================

(define-public (register-vendor (name (string-utf8 100)) (business-type (string-utf8 50)) (region uint) (address (string-utf8 200)) (contact (string-utf8 100)) (categories (list 6 uint)))
    (let (
        (vendor-id (var-get next-vendor-id))
    )
        (asserts! (var-get contract-initialized) ERR-CONTRACT-NOT-INITIALIZED)
        (asserts! (is-none (map-get? vendors tx-sender)) ERR-VENDOR-ALREADY-REGISTERED)
        (asserts! (is-valid-region region) ERR-INVALID-LOCATION)
        (asserts! (> (len name) u0) ERR-INVALID-VENDOR-DATA)
        (asserts! (> (len categories) u0) ERR-INVALID-CATEGORIES)
        
        ;; Create vendor record
        (map-set vendors tx-sender {
            vendor-id: vendor-id,
            name: name,
            business-type: business-type,
            location-region: region,
            address: address,
            contact-info: contact,
            registration-date: burn-block-height,
            status: STATUS-PENDING,
            verified-by: 'SP000000000000000000002Q6VF78,
            verification-date: u0,
            supported-categories: categories,
            performance-rating: DEFAULT-RATING,
            compliance-score: u100,
            total-redemptions: u0,
            total-value-processed: u0,
            last-activity: burn-block-height
        })
        
        ;; Initialize performance metrics
        (map-set vendor-performance tx-sender {
            successful-transactions: u0,
            failed-transactions: u0,
            average-processing-time: u0,
            customer-satisfaction: DEFAULT-RATING,
            compliance-violations: u0,
            last-inspection: u0,
            inspection-score: u100
        })
        
        ;; Update statistics
        (var-set next-vendor-id (+ vendor-id u1))
        (var-set total-vendors (+ (var-get total-vendors) u1))
        (update-regional-stats region 1 0)
        
        (print {
            event: "vendor-registered",
            vendor: tx-sender,
            vendor-id: vendor-id,
            name: name,
            region: region
        })
        (ok vendor-id)
    )
)

(define-public (verify-vendor (vendor principal) (verification-notes (string-utf8 300)))
    (let (
        (vendor-data (unwrap! (map-get? vendors vendor) ERR-VENDOR-NOT-FOUND))
        (region (get location-region vendor-data))
    )
        (asserts! (var-get contract-initialized) ERR-CONTRACT-NOT-INITIALIZED)
        (asserts! (is-authorized-verifier tx-sender) ERR-UNAUTHORIZED)
        (asserts! (is-eq (get status vendor-data) STATUS-PENDING) ERR-INVALID-VENDOR-DATA)
        
        ;; Update vendor status to verified
        (map-set vendors vendor
            (merge vendor-data {
                status: STATUS-VERIFIED,
                verified-by: tx-sender,
                verification-date: burn-block-height
            })
        )
        
        ;; Update statistics
        (var-set verified-vendors-count (+ (var-get verified-vendors-count) u1))
        (update-regional-stats region 0 1)
        
        (print {
            event: "vendor-verified",
            vendor: vendor,
            verifier: tx-sender,
            verification-date: burn-block-height
        })
        (ok true)
    )
)

(define-public (suspend-vendor (vendor principal) (reason (string-utf8 200)))
    (let (
        (vendor-data (unwrap! (map-get? vendors vendor) ERR-VENDOR-NOT-FOUND))
        (region (get location-region vendor-data))
    )
        (asserts! (var-get contract-initialized) ERR-CONTRACT-NOT-INITIALIZED)
        (asserts! (is-authorized-verifier tx-sender) ERR-UNAUTHORIZED)
        (asserts! (is-eq (get status vendor-data) STATUS-VERIFIED) ERR-VENDOR-NOT-VERIFIED)
        
        ;; Update vendor status to suspended
        (map-set vendors vendor
            (merge vendor-data {
                status: STATUS-SUSPENDED,
                last-activity: burn-block-height
            })
        )
        
        ;; Update statistics
        (var-set verified-vendors-count (- (var-get verified-vendors-count) u1))
        (update-regional-stats region 0 -1)
        
        (print {
            event: "vendor-suspended",
            vendor: vendor,
            suspended-by: tx-sender,
            reason: reason
        })
        (ok true)
    )
)

(define-public (update-vendor-performance (vendor principal) (successful-tx uint) (failed-tx uint) (processing-time uint) (satisfaction uint))
    (let (
        (vendor-data (unwrap! (map-get? vendors vendor) ERR-VENDOR-NOT-FOUND))
        (current-perf (unwrap! (map-get? vendor-performance vendor) ERR-VENDOR-NOT-FOUND))
        (new-compliance (calculate-compliance-score successful-tx failed-tx (get compliance-violations current-perf)))
    )
        (asserts! (var-get contract-initialized) ERR-CONTRACT-NOT-INITIALIZED)
        (asserts! (is-authorized-verifier tx-sender) ERR-UNAUTHORIZED)
        (asserts! (is-valid-rating satisfaction) ERR-INVALID-VENDOR-DATA)
        
        ;; Update performance metrics
        (map-set vendor-performance vendor
            (merge current-perf {
                successful-transactions: (+ (get successful-transactions current-perf) successful-tx),
                failed-transactions: (+ (get failed-transactions current-perf) failed-tx),
                average-processing-time: processing-time,
                customer-satisfaction: satisfaction
            })
        )
        
        ;; Update vendor compliance score
        (map-set vendors vendor
            (merge vendor-data {
                compliance-score: new-compliance,
                performance-rating: satisfaction,
                last-activity: burn-block-height
            })
        )
        
        (print {
            event: "vendor-performance-updated",
            vendor: vendor,
            compliance-score: new-compliance,
            satisfaction: satisfaction
        })
        (ok true)
    )
)

(define-public (update-category-availability (category uint) (available bool) (stock-level uint) (competitiveness uint))
    (let (
        (vendor-data (unwrap! (map-get? vendors tx-sender) ERR-VENDOR-NOT-FOUND))
    )
        (asserts! (var-get contract-initialized) ERR-CONTRACT-NOT-INITIALIZED)
        (asserts! (is-eq (get status vendor-data) STATUS-VERIFIED) ERR-VENDOR-NOT-VERIFIED)
        (asserts! (is-some (index-of (get supported-categories vendor-data) category)) ERR-INVALID-CATEGORIES)
        (asserts! (<= stock-level u100) ERR-INVALID-VENDOR-DATA)
        (asserts! (is-valid-rating competitiveness) ERR-INVALID-VENDOR-DATA)
        
        (map-set vendor-category-availability { vendor: tx-sender, category: category } {
            is-available: available,
            stock-level: stock-level,
            last-updated: burn-block-height,
            price-competitiveness: competitiveness
        })
        
        (print {
            event: "category-availability-updated",
            vendor: tx-sender,
            category: category,
            available: available,
            stock-level: stock-level
        })
        (ok true)
    )
)
