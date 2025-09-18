;; foodaid-coupons.clar - Tokenized Food Aid Coupon System
;; Digital food assistance coupons redeemable at verified vendors

;; =============================================================================
;; CONSTANTS
;; =============================================================================

(define-constant CONTRACT-ADMIN tx-sender)
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-INSUFFICIENT-BALANCE (err u101))
(define-constant ERR-INVALID-AMOUNT (err u102))
(define-constant ERR-COUPON-EXPIRED (err u103))
(define-constant ERR-INVALID-CATEGORY (err u104))
(define-constant ERR-NOT-VERIFIED-VENDOR (err u105))
(define-constant ERR-ALREADY-REDEEMED (err u106))
(define-constant ERR-INVALID-BENEFICIARY (err u107))
(define-constant ERR-ZERO-AMOUNT (err u108))
(define-constant ERR-CONTRACT-NOT-INITIALIZED (err u109))

;; Food category constants
(define-constant CATEGORY-GRAINS u1)
(define-constant CATEGORY-PROTEINS u2)
(define-constant CATEGORY-VEGETABLES u3)
(define-constant CATEGORY-FRUITS u4)
(define-constant CATEGORY-DAIRY u5)
(define-constant CATEGORY-GENERAL u6)

;; Coupon validity period (blocks)
(define-constant DEFAULT-EXPIRY-BLOCKS u4320) ;; ~30 days
(define-constant MAX-COUPON-VALUE u10000) ;; Maximum value per coupon
(define-constant MIN-COUPON-VALUE u100) ;; Minimum value per coupon

;; =============================================================================
;; DATA VARIABLES
;; =============================================================================

(define-data-var contract-initialized bool false)
(define-data-var next-coupon-id uint u1)
(define-data-var total-coupons-issued uint u0)
(define-data-var total-value-redeemed uint u0)
(define-data-var authorized-issuers-count uint u0)

;; =============================================================================
;; DATA MAPS
;; =============================================================================

;; Authorized aid issuers (organizations, government agencies)
(define-map authorized-issuers principal bool)

;; Beneficiary coupon balances by category
(define-map beneficiary-balances
    { beneficiary: principal, category: uint }
    uint
)

;; Individual coupon details
(define-map coupons
    uint ;; coupon-id
    {
        issuer: principal,
        beneficiary: principal,
        value: uint,
        category: uint,
        issued-at: uint,
        expires-at: uint,
        is-redeemed: bool,
        redeemed-at: uint,
        redeemed-by-vendor: principal
    }
)

;; Beneficiary transaction history
(define-map beneficiary-history
    { beneficiary: principal, transaction-id: uint }
    {
        coupon-id: uint,
        transaction-type: (string-ascii 20), ;; "issued" or "redeemed"
        amount: uint,
        category: uint,
        timestamp: uint,
        vendor: (optional principal)
    }
)

;; Vendor redemption statistics
(define-map vendor-redemptions
    principal
    {
        total-redeemed: uint,
        total-value: uint,
        last-redemption: uint,
        redemption-count: uint
    }
)

;; Aid program statistics by issuer
(define-map issuer-statistics
    principal
    {
        total-issued: uint,
        total-value: uint,
        active-coupons: uint,
        beneficiaries-served: uint
    }
)

;; =============================================================================
;; PRIVATE FUNCTIONS
;; =============================================================================

(define-private (is-valid-category (category uint))
    (and (>= category CATEGORY-GRAINS) (<= category CATEGORY-GENERAL))
)

(define-private (is-coupon-expired (expires-at uint))
    (> burn-block-height expires-at)
)

(define-private (is-valid-principal (principal-to-check principal))
    (not (is-eq principal-to-check 'SP000000000000000000002Q6VF78))
)

(define-private (get-beneficiary-balance (beneficiary principal) (category uint))
    (default-to u0 (map-get? beneficiary-balances { beneficiary: beneficiary, category: category }))
)

(define-private (update-beneficiary-balance (beneficiary principal) (category uint) (new-balance uint))
    (map-set beneficiary-balances { beneficiary: beneficiary, category: category } new-balance)
)

(define-private (record-transaction (beneficiary principal) (coupon-id uint) (tx-type (string-ascii 20)) (amount uint) (category uint) (vendor (optional principal)))
    (let (
        (transaction-id (+ (var-get total-coupons-issued) (get-beneficiary-balance beneficiary category)))
    )
        (map-set beneficiary-history
            { beneficiary: beneficiary, transaction-id: transaction-id }
            {
                coupon-id: coupon-id,
                transaction-type: tx-type,
                amount: amount,
                category: category,
                timestamp: burn-block-height,
                vendor: vendor
            }
        )
    )
)

;; =============================================================================
;; READ-ONLY FUNCTIONS
;; =============================================================================

(define-read-only (get-coupon-info (coupon-id uint))
    (map-get? coupons coupon-id)
)

(define-read-only (get-beneficiary-balance-by-category (beneficiary principal) (category uint))
    (get-beneficiary-balance beneficiary category)
)

(define-read-only (get-total-beneficiary-balance (beneficiary principal))
    (+ 
        (get-beneficiary-balance beneficiary CATEGORY-GRAINS)
        (+ (get-beneficiary-balance beneficiary CATEGORY-PROTEINS)
        (+ (get-beneficiary-balance beneficiary CATEGORY-VEGETABLES)
        (+ (get-beneficiary-balance beneficiary CATEGORY-FRUITS)
        (+ (get-beneficiary-balance beneficiary CATEGORY-DAIRY)
           (get-beneficiary-balance beneficiary CATEGORY-GENERAL)))))
    )
)

(define-read-only (is-authorized-issuer (issuer principal))
    (default-to false (map-get? authorized-issuers issuer))
)

(define-read-only (get-vendor-statistics (vendor principal))
    (map-get? vendor-redemptions vendor)
)

(define-read-only (get-issuer-statistics (issuer principal))
    (map-get? issuer-statistics issuer)
)

(define-read-only (get-contract-statistics)
    {
        total-coupons-issued: (var-get total-coupons-issued),
        total-value-redeemed: (var-get total-value-redeemed),
        authorized-issuers-count: (var-get authorized-issuers-count),
        next-coupon-id: (var-get next-coupon-id),
        contract-initialized: (var-get contract-initialized)
    }
)

(define-read-only (is-coupon-valid (coupon-id uint))
    (match (map-get? coupons coupon-id)
        some-coupon 
            (and 
                (not (get is-redeemed some-coupon))
                (not (is-coupon-expired (get expires-at some-coupon)))
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
        (map-set authorized-issuers CONTRACT-ADMIN true)
        (var-set authorized-issuers-count u1)
        (print { event: "contract-initialized", admin: CONTRACT-ADMIN })
        (ok true)
    )
)

(define-public (authorize-issuer (issuer principal))
    (begin
        (asserts! (var-get contract-initialized) ERR-CONTRACT-NOT-INITIALIZED)
        (asserts! (is-eq tx-sender CONTRACT-ADMIN) ERR-UNAUTHORIZED)
        (asserts! (is-valid-principal issuer) ERR-INVALID-BENEFICIARY)
        (map-set authorized-issuers issuer true)
        (var-set authorized-issuers-count (+ (var-get authorized-issuers-count) u1))
        (print { event: "issuer-authorized", issuer: issuer })
        (ok true)
    )
)

;; =============================================================================
;; PUBLIC FUNCTIONS - COUPON MANAGEMENT
;; =============================================================================

(define-public (issue-coupon (beneficiary principal) (value uint) (category uint))
    (let (
        (coupon-id (var-get next-coupon-id))
        (expires-at (+ burn-block-height DEFAULT-EXPIRY-BLOCKS))
        (current-balance (get-beneficiary-balance beneficiary category))
    )
        (asserts! (var-get contract-initialized) ERR-CONTRACT-NOT-INITIALIZED)
        (asserts! (is-authorized-issuer tx-sender) ERR-UNAUTHORIZED)
        (asserts! (is-valid-principal beneficiary) ERR-INVALID-BENEFICIARY)
        (asserts! (and (>= value MIN-COUPON-VALUE) (<= value MAX-COUPON-VALUE)) ERR-INVALID-AMOUNT)
        (asserts! (is-valid-category category) ERR-INVALID-CATEGORY)
        
        ;; Create coupon record
        (map-set coupons coupon-id {
            issuer: tx-sender,
            beneficiary: beneficiary,
            value: value,
            category: category,
            issued-at: burn-block-height,
            expires-at: expires-at,
            is-redeemed: false,
            redeemed-at: u0,
            redeemed-by-vendor: 'SP000000000000000000002Q6VF78
        })
        
        ;; Update beneficiary balance
        (update-beneficiary-balance beneficiary category (+ current-balance value))
        
        ;; Record transaction
        (record-transaction beneficiary coupon-id "issued" value category none)
        
        ;; Update statistics
        (var-set next-coupon-id (+ coupon-id u1))
        (var-set total-coupons-issued (+ (var-get total-coupons-issued) u1))
        
        ;; Update issuer statistics
        (let (
            (issuer-stats (default-to 
                { total-issued: u0, total-value: u0, active-coupons: u0, beneficiaries-served: u0 }
                (map-get? issuer-statistics tx-sender)
            ))
        )
            (map-set issuer-statistics tx-sender
                (merge issuer-stats {
                    total-issued: (+ (get total-issued issuer-stats) u1),
                    total-value: (+ (get total-value issuer-stats) value),
                    active-coupons: (+ (get active-coupons issuer-stats) u1)
                })
            )
        )
        
        (print {
            event: "coupon-issued",
            coupon-id: coupon-id,
            beneficiary: beneficiary,
            value: value,
            category: category,
            expires-at: expires-at
        })
        (ok coupon-id)
    )
)

(define-public (redeem-coupon (coupon-id uint) (vendor principal))
    (let (
        (coupon-data (unwrap! (map-get? coupons coupon-id) ERR-INVALID-AMOUNT))
        (beneficiary (get beneficiary coupon-data))
        (value (get value coupon-data))
        (category (get category coupon-data))
        (current-balance (get-beneficiary-balance beneficiary category))
    )
        (asserts! (var-get contract-initialized) ERR-CONTRACT-NOT-INITIALIZED)
        (asserts! (is-eq tx-sender beneficiary) ERR-UNAUTHORIZED)
        (asserts! (is-valid-principal vendor) ERR-NOT-VERIFIED-VENDOR)
        (asserts! (not (get is-redeemed coupon-data)) ERR-ALREADY-REDEEMED)
        (asserts! (not (is-coupon-expired (get expires-at coupon-data))) ERR-COUPON-EXPIRED)
        (asserts! (>= current-balance value) ERR-INSUFFICIENT-BALANCE)
        
        ;; Mark coupon as redeemed
        (map-set coupons coupon-id
            (merge coupon-data {
                is-redeemed: true,
                redeemed-at: burn-block-height,
                redeemed-by-vendor: vendor
            })
        )
        
        ;; Update beneficiary balance
        (update-beneficiary-balance beneficiary category (- current-balance value))
        
        ;; Record transaction
        (record-transaction beneficiary coupon-id "redeemed" value category (some vendor))
        
        ;; Update global statistics
        (var-set total-value-redeemed (+ (var-get total-value-redeemed) value))
        
        ;; Update vendor statistics
        (let (
            (vendor-stats (default-to
                { total-redeemed: u0, total-value: u0, last-redemption: u0, redemption-count: u0 }
                (map-get? vendor-redemptions vendor)
            ))
        )
            (map-set vendor-redemptions vendor
                (merge vendor-stats {
                    total-redeemed: (+ (get total-redeemed vendor-stats) u1),
                    total-value: (+ (get total-value vendor-stats) value),
                    last-redemption: burn-block-height,
                    redemption-count: (+ (get redemption-count vendor-stats) u1)
                })
            )
        )
        
        (print {
            event: "coupon-redeemed",
            coupon-id: coupon-id,
            beneficiary: beneficiary,
            vendor: vendor,
            value: value,
            category: category
        })
        (ok true)
    )
)

(define-public (batch-issue-coupons (beneficiaries (list 50 principal)) (value uint) (category uint))
    (let (
        (issued-coupons (map issue-single-coupon beneficiaries))
    )
        (asserts! (var-get contract-initialized) ERR-CONTRACT-NOT-INITIALIZED)
        (asserts! (is-authorized-issuer tx-sender) ERR-UNAUTHORIZED)
        (asserts! (and (>= value MIN-COUPON-VALUE) (<= value MAX-COUPON-VALUE)) ERR-INVALID-AMOUNT)
        (asserts! (is-valid-category category) ERR-INVALID-CATEGORY)
        
        (print {
            event: "batch-coupons-issued",
            beneficiary-count: (len beneficiaries),
            value: value,
            category: category
        })
        (ok (len beneficiaries))
    )
)

;; Helper function for batch processing
(define-private (issue-single-coupon (beneficiary principal))
    (issue-coupon beneficiary u1000 CATEGORY-GENERAL) ;; Default values for batch processing
)
