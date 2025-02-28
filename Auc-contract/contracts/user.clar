;; User Contract

;; Define constants
(define-constant contract-owner tx-sender)
(define-constant err-not-owner (err u100))
(define-constant err-already-registered (err u101))
(define-constant err-not-registered (err u102))
(define-constant err-not-kyc-verified (err u103))
(define-constant err-invalid-tier (err u104))

;; Define data maps
(define-map users
  { address: principal }
  {
    reputation: uint,
    kyc-verified: bool,
    membership-tier: uint,
    token-balance: uint
  }
)

(define-map user-profiles
  { address: principal }
  {
    name: (string-ascii 64),
    email: (string-ascii 64)
  }
)

;; Define variables
(define-data-var user-count uint u0)

;; User registration
(define-public (register-user (name (string-ascii 64)) (email (string-ascii 64)))
  (let
    ((user (default-to
      { reputation: u0, kyc-verified: false, membership-tier: u0, token-balance: u0 }
      (map-get? users { address: tx-sender }))))
    (asserts! (is-eq (get reputation user) u0) (err err-already-registered))
    (map-set users
      { address: tx-sender }
      { reputation: u0, kyc-verified: false, membership-tier: u0, token-balance: u0 }
    )
    (map-set user-profiles
      { address: tx-sender }
      { name: name, email: email }
    )
    (var-set user-count (+ (var-get user-count) u1))
    (ok true)
  )
)

;; Update user profile
(define-public (update-profile (name (string-ascii 64)) (email (string-ascii 64)))
  (let
    ((user (unwrap! (map-get? users { address: tx-sender }) (err err-not-registered))))
    (map-set user-profiles
      { address: tx-sender }
      { name: name, email: email }
    )
    (ok true)
  )
)

;; KYC/AML verification (only contract owner can do this)
(define-public (set-kyc-status (user principal) (status bool))
  (begin
    (asserts! (is-eq tx-sender contract-owner) (err err-not-owner))
    (match (map-get? users { address: user })
      existing-data (ok (map-set users
        { address: user }
        (merge existing-data { kyc-verified: status })
      ))
      (err err-not-registered)
    )
  )
)