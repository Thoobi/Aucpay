
;; title: user
;; version:
;; summary:
;; description:

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
    name: (string-ascii 50),
    email: (string-ascii 50),
    bio: (string-ascii 280)
  }
)

;; Define variables
(define-data-var user-count uint u0)

;; User registration
(define-public (register-user (name (string-ascii 50)) (email (string-ascii 50)))
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
      { name: name, email: email, bio: "" }
    )
    (var-set user-count (+ (var-get user-count) u1))
    (ok true)
  )
)

;; Update user profile
(define-public (update-profile (name (string-ascii 50)) (email (string-ascii 50)) (bio (string-ascii 280)))
  (let
    ((user (unwrap! (map-get? users { address: tx-sender }) (err err-not-registered))))
    (map-set user-profiles
      { address: tx-sender }
      { name: name, email: email, bio: bio }
    )
    (ok true)
  )
)

;; KYC verification (only contract owner can do this)
(define-public (verify-kyc (user principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) (err err-not-owner))
    (match (map-get? users { address: user })
      existing-user (ok (map-set users
        { address: user }
        (merge existing-user { kyc-verified: true })
      ))
      (err err-not-registered)
    )
  )
)

;; Update user reputation
(define-public (update-reputation (user principal) (change uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) (err err-not-owner))
    (match (map-get? users { address: user })
      existing-user 
        (let
          ((new-reputation (+ (get reputation existing-user) change)))
          (ok (map-set users
            { address: user }
            (merge existing-user { reputation: (if (< new-reputation u0) u0 new-reputation) })
          ))
        )
      (err err-not-registered)
    )
  )
)

;; Update membership tier
(define-public (update-membership-tier (new-tier uint))
  (let
    ((user (unwrap! (map-get? users { address: tx-sender }) (err err-not-registered))))
    (asserts! (<= new-tier u3) (err err-invalid-tier))
    (ok (map-set users
      { address: tx-sender }
      (merge user { membership-tier: new-tier })
    ))
  )
)

;; Update token balance
(define-public (update-token-balance (change uint))
  (let
    ((user (unwrap! (map-get? users { address: tx-sender }) (err err-not-registered))))
    (let
      ((new-balance (+ (get token-balance user) change)))
      (ok (map-set users
        { address: tx-sender }
        (merge user { token-balance: (if (< new-balance u0) u0 new-balance) })
      ))
    )
  )
)

;; Check if user has access to high-value auctions
(define-read-only (has-high-value-auction-access (user principal))
  (match (map-get? users { address: user })
    existing-user (and
      (get kyc-verified existing-user)
      (>= (get reputation existing-user) u100)
      (>= (get membership-tier existing-user) u2)
    )
    false
  )
)

;; Get user details
(define-read-only (get-user-details (user principal))
  (map-get? users { address: user })
)

;; Get user profile
(define-read-only (get-user-profile (user principal))
  (map-get? user-profiles { address: user })
)

;; Get total number of registered users
(define-read-only (get-user-count)
  (var-get user-count)
)