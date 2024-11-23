
;; title: user-contract
;; version:
;; summary:
;; description:

;; User Contract
;; Manages user registration, profiles, KYC/AML verification, and access control

;; Define the contract owner
(define-constant contract-owner tx-sender)

;; Define error codes
(define-constant err-owner-only (err u100))
(define-constant err-already-registered (err u101))
(define-constant err-not-registered (err u102))
(define-constant err-not-kyc-verified (err u103))
(define-constant err-insufficient-reputation (err u104))

;; Define membership tiers
(define-constant tier-bronze u1)
(define-constant tier-silver u2)
(define-constant tier-gold u3)

;; Define the minimum reputation required for each tier
(define-constant min-reputation-silver u100)
(define-constant min-reputation-gold u500)

;; Define user data map
(define-map users
  principal
  {
    registered: bool,
    kyc-verified: bool,
    reputation: uint,
    membership-tier: uint
  }
)

;; Register a new user
(define-public (register-user)
  (let ((caller tx-sender))
    (asserts! (is-none (map-get? users caller)) err-already-registered)
    (ok (map-set users caller {
      registered: true,
      kyc-verified: false,
      reputation: u0,
      membership-tier: tier-bronze
    }))
  )
)

;; Update KYC verification status
(define-public (set-kyc-status (user principal) (status bool))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (is-some (map-get? users user)) err-not-registered)
    (ok (map-set users user
      (merge (unwrap-panic (map-get? users user))
             { kyc-verified: status })))
  )
)

;; Update user reputation
(define-public (update-reputation (user principal) (change uint))
  (let (
    (current-data (unwrap! (map-get? users user) err-not-registered))
    (new-reputation (+ (get reputation current-data) change))
  )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-set users user
      (merge current-data {
        reputation: new-reputation,
        membership-tier: (determine-tier new-reputation)
      })))
  )
)

;; Determine membership tier based on reputation
(define-private (determine-tier (reputation uint))
  (if (>= reputation min-reputation-gold)
    tier-gold
    (if (>= reputation min-reputation-silver)
      tier-silver
      tier-bronze
    )
  )
)

;; Check if a user has access to a specific auction tier
(define-public (has-auction-access (user principal) (required-tier uint))
  (let ((user-data (unwrap! (map-get? users user) err-not-registered)))
    (asserts! (get kyc-verified user-data) err-not-kyc-verified)
    (ok (>= (get membership-tier user-data) required-tier))
  )
)

;; Get user profile
(define-read-only (get-user-profile (user principal))
  (ok (unwrap! (map-get? users user) err-not-registered))
)

;; Check if a user is registered
(define-read-only (is-user-registered (user principal))
  (is-some (map-get? users user))
)

;; Check if a user is KYC verified
(define-read-only (is-user-kyc-verified (user principal))
  (match (map-get? users user)
    user-data (get kyc-verified user-data)
    false
  )
)

;; Get user reputation
(define-read-only (get-user-reputation (user principal))
  (ok (get reputation (unwrap! (map-get? users user) err-not-registered)))
)

;; Get user membership tier
(define-read-only (get-user-membership-tier (user principal))
  (ok (get membership-tier (unwrap! (map-get? users user) err-not-registered)))
)