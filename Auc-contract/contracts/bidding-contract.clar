;; Aucpay Bidding Contract
;; Handles bid placement, validation, and tracking for auction events

;; ===================================
;; CONSTANTS & ERROR CODES
;; ===================================

(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-AUCTION-NOT-FOUND (err u101))
(define-constant ERR-AUCTION-NOT-ACTIVE (err u102))
(define-constant ERR-AUCTION-ENDED (err u103))
(define-constant ERR-BID-TOO-LOW (err u104))
(define-constant ERR-INSUFFICIENT-FUNDS (err u105))
(define-constant ERR-SELF-BID (err u106))
(define-constant ERR-TRANSFER-FAILED (err u107))
(define-constant ERR-REFUND-FAILED (err u108))
(define-constant ERR-INVALID-AUCTION-ID (err u109))
(define-constant ERR-USER-BLACKLISTED (err u110))
(define-constant ERR-BID-INCREMENT-TOO-SMALL (err u111))

;; Minimum bid increment percentage (5% = 500 basis points)
(define-constant MIN-BID-INCREMENT u500)
(define-constant BASIS-POINTS u10000)

;; ===================================
;; DATA STRUCTURES
;; ===================================

;; Individual bid structure
(define-map bids
  { auction-id: uint, bid-id: uint }
  {
    bidder: principal,
    amount: uint,
    timestamp: uint,
    block-height: uint,
    is-active: bool,
    refunded: bool
  }
)

;; Auction bidding state
(define-map auction-bidding-state
  { auction-id: uint }
  {
    highest-bid: uint,
    highest-bidder: principal,
    total-bids: uint,
    last-bid-time: uint,
    reserve-met: bool,
    bid-increment: uint
  }
)

;; User bidding history
(define-map user-bid-history
  { user: principal, auction-id: uint }
  {
    total-bids: uint,
    highest-bid: uint,
    last-bid-time: uint,
    is-highest-bidder: bool
  }
)

;; Bid counter for unique bid IDs
(define-data-var bid-counter uint u0)

;; Contract pause state
(define-data-var contract-paused bool false)

;; Authorized contracts that can interact with this contract
(define-map authorized-contracts principal bool)

;; ===================================
;; AUTHORIZATION & ACCESS CONTROL
;; ===================================

(define-private (is-contract-owner)
  (is-eq tx-sender CONTRACT-OWNER)
)

(define-private (is-authorized-contract)
  (default-to false (map-get? authorized-contracts tx-sender))
)

(define-private (is-contract-active)
  (not (var-get contract-paused))
)

;; ===================================
;; EXTERNAL CONTRACT INTEGRATION
;; ===================================

;; Check if auction exists and is active (integrate with auction-contract)
(define-private (is-auction-active (auction-id uint))
  ;; This would integrate with your auction-contract.clar
  ;; For now, we'll use a placeholder that assumes auction exists
  ;; Replace with actual contract call: (contract-call? .auction-contract is-auction-active auction-id)
  true
)

;; Get auction details (integrate with auction-contract)
(define-private (get-auction-details (auction-id uint))
  ;; This would integrate with your auction-contract.clar
  ;; Replace with actual contract call: (contract-call? .auction-contract get-auction-details auction-id)
  (some {
    end-time: u999999999,
    reserve-price: u1000000,
    organizer: CONTRACT-OWNER,
    status: "active"
  })
)

;; Check if user is blacklisted (integrate with user-contract)
(define-private (is-user-blacklisted (user principal))
  ;; This would integrate with your user-contract.clar
  ;; Replace with actual contract call: (contract-call? .user-contract is-blacklisted user)
  false
)

;; ===================================
;; PRIVATE HELPER FUNCTIONS
;; ===================================

(define-private (calculate-minimum-bid (current-highest uint))
  (if (is-eq current-highest u0)
    u1000000 ;; Minimum starting bid (1 STX in microSTX)
    (+ current-highest 
       (/ (* current-highest MIN-BID-INCREMENT) BASIS-POINTS))
  )
)

(define-private (get-next-bid-id)
  (let ((current-id (var-get bid-counter)))
    (var-set bid-counter (+ current-id u1))
    (+ current-id u1)
  )
)

(define-private (refund-previous-bidder (auction-id uint) (previous-bidder principal) (amount uint))
  (if (and (> amount u0) (not (is-eq previous-bidder tx-sender)))
    (match (stx-transfer? amount (as-contract tx-sender) previous-bidder)
      success true
      error false
    )
    true
  )
)

(define-private (update-auction-bidding-state (auction-id uint) (new-bid uint) (bidder principal))
  (let (
    (current-state (default-to 
      { highest-bid: u0, highest-bidder: tx-sender, total-bids: u0, 
        last-bid-time: u0, reserve-met: false, bid-increment: u0 }
      (map-get? auction-bidding-state { auction-id: auction-id })
    ))
    (auction-details (unwrap-panic (get-auction-details auction-id)))
  )
    (map-set auction-bidding-state
      { auction-id: auction-id }
      {
        highest-bid: new-bid,
        highest-bidder: bidder,
        total-bids: (+ (get total-bids current-state) u1),
        last-bid-time: stacks-block-height,
        reserve-met: (>= new-bid (get reserve-price auction-details)),
        bid-increment: (- new-bid (get highest-bid current-state))
      }
    )
  )
)

(define-private (update-user-bid-history (user principal) (auction-id uint) (bid-amount uint))
  (let (
    (current-history (default-to 
      { total-bids: u0, highest-bid: u0, last-bid-time: u0, is-highest-bidder: false }
      (map-get? user-bid-history { user: user, auction-id: auction-id })
    ))
  )
    (map-set user-bid-history
      { user: user, auction-id: auction-id }
      {
        total-bids: (+ (get total-bids current-history) u1),
        highest-bid: (if (> bid-amount (get highest-bid current-history)) 
                       bid-amount 
                       (get highest-bid current-history)),
        last-bid-time: stacks-block-height,
        is-highest-bidder: true
      }
    )
  )
)

;; ===================================
;; PUBLIC FUNCTIONS
;; ===================================

;; Place a bid on an auction
(define-public (place-bid (auction-id uint) (bid-amount uint))
  (let (
    (bid-id (get-next-bid-id))
    (current-state (default-to 
      { highest-bid: u0, highest-bidder: tx-sender, total-bids: u0, 
        last-bid-time: u0, reserve-met: false, bid-increment: u0 }
      (map-get? auction-bidding-state { auction-id: auction-id })
    ))
    (minimum-bid (calculate-minimum-bid (get highest-bid current-state)))
    (previous-bidder (get highest-bidder current-state))
    (previous-bid (get highest-bid current-state))
  )
    ;; Validation checks
    (asserts! (is-contract-active) ERR-NOT-AUTHORIZED)
    (asserts! (> auction-id u0) ERR-INVALID-AUCTION-ID)
    (asserts! (is-auction-active auction-id) ERR-AUCTION-NOT-ACTIVE)
    (asserts! (not (is-user-blacklisted tx-sender)) ERR-USER-BLACKLISTED)
    (asserts! (not (is-eq tx-sender previous-bidder)) ERR-SELF-BID)
    (asserts! (>= bid-amount minimum-bid) ERR-BID-TOO-LOW)
    (asserts! (>= (stx-get-balance tx-sender) bid-amount) ERR-INSUFFICIENT-FUNDS)
    
    ;; Transfer bid amount to contract
    (match (stx-transfer? bid-amount tx-sender (as-contract tx-sender))
      success 
        (begin
          ;; Refund previous bidder if exists
          (if (and (> previous-bid u0) (not (is-eq previous-bidder tx-sender)))
            (asserts! (refund-previous-bidder auction-id previous-bidder previous-bid) ERR-REFUND-FAILED)
            true
          )
          
          ;; Record the bid
          (map-set bids
            { auction-id: auction-id, bid-id: bid-id }
            {
              bidder: tx-sender,
              amount: bid-amount,
              timestamp: stacks-block-height,
              block-height: stacks-block-height,
              is-active: true,
              refunded: false
            }
          )
          
          ;; Update auction state
          (update-auction-bidding-state auction-id bid-amount tx-sender)
          
          ;; Update user history
          (update-user-bid-history tx-sender auction-id bid-amount)
          
          ;; Mark previous bidder as no longer highest
          (if (> previous-bid u0)
            (map-set user-bid-history
              { user: previous-bidder, auction-id: auction-id }
              (merge 
                (default-to 
                  { total-bids: u0, highest-bid: u0, last-bid-time: u0, is-highest-bidder: false }
                  (map-get? user-bid-history { user: previous-bidder, auction-id: auction-id })
                )
                { is-highest-bidder: false }
              )
            )
            true
          )
          
          (ok { bid-id: bid-id, amount: bid-amount, position: "highest" })
        )
      error ERR-TRANSFER-FAILED
    )
  )
)

;; Emergency bid withdrawal (only for non-highest bidders in specific cases)
(define-public (emergency-withdraw-bid (auction-id uint) (bid-id uint))
  (let (
    (bid-data (unwrap! (map-get? bids { auction-id: auction-id, bid-id: bid-id }) ERR-AUCTION-NOT-FOUND))
    (current-state (unwrap! (map-get? auction-bidding-state { auction-id: auction-id }) ERR-AUCTION-NOT-FOUND))
  )
    (asserts! (is-eq (get bidder bid-data) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (not (is-eq tx-sender (get highest-bidder current-state))) ERR-NOT-AUTHORIZED)
    (asserts! (get is-active bid-data) ERR-NOT-AUTHORIZED)
    (asserts! (not (get refunded bid-data)) ERR-NOT-AUTHORIZED)
    
    ;; Transfer bid back to bidder
    (match (as-contract (stx-transfer? (get amount bid-data) tx-sender (get bidder bid-data)))
      success 
        (begin
          ;; Mark bid as refunded
          (map-set bids
            { auction-id: auction-id, bid-id: bid-id }
            (merge bid-data { is-active: false, refunded: true })
          )
          (ok true)
        )
      error ERR-TRANSFER-FAILED
    )
  )
)

;; ===================================
;; ADMIN FUNCTIONS
;; ===================================

(define-public (set-contract-pause (paused bool))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (var-set contract-paused paused)
    (ok paused)
  )
)

(define-public (authorize-contract (contract principal))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (map-set authorized-contracts contract true)
    (ok true)
  )
)

(define-public (revoke-contract-authorization (contract principal))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (map-delete authorized-contracts contract)
    (ok true)
  )
)

;; ===================================
;; READ-ONLY FUNCTIONS
;; ===================================

(define-read-only (get-bid-details (auction-id uint) (bid-id uint))
  (map-get? bids { auction-id: auction-id, bid-id: bid-id })
)

(define-read-only (get-auction-bidding-state (auction-id uint))
  (map-get? auction-bidding-state { auction-id: auction-id })
)

(define-read-only (get-user-bid-history (user principal) (auction-id uint))
  (map-get? user-bid-history { user: user, auction-id: auction-id })
)

(define-read-only (get-highest-bid (auction-id uint))
  (match (map-get? auction-bidding-state { auction-id: auction-id })
    state (some (get highest-bid state))
    none
  )
)

(define-read-only (get-highest-bidder (auction-id uint))
  (match (map-get? auction-bidding-state { auction-id: auction-id })
    state (some (get highest-bidder state))
    none
  )
)

(define-read-only (get-total-bids (auction-id uint))
  (match (map-get? auction-bidding-state { auction-id: auction-id })
    state (get total-bids state)
    u0
  )
)

(define-read-only (get-minimum-next-bid (auction-id uint))
  (let (
    (current-highest (default-to u0 (get-highest-bid auction-id)))
  )
    (calculate-minimum-bid current-highest)
  )
)

(define-read-only (is-reserve-met (auction-id uint))
  (match (map-get? auction-bidding-state { auction-id: auction-id })
    state (get reserve-met state)
    false
  )
)

(define-read-only (get-bid-count)
  (var-get bid-counter)
)

(define-read-only (is-user-highest-bidder (user principal) (auction-id uint))
  (match (get-highest-bidder auction-id)
    highest-bidder (is-eq user highest-bidder)
    false
  )
)

;; Get last N bids for an auction (for bid history display)
(define-read-only (get-recent-bids (auction-id uint) (limit uint))
  (let (
    (total-bids (get-total-bids auction-id))
    (start-bid (if (> total-bids limit) (- total-bids limit) u1))
  )
    ;; This is a simplified version - in practice, you'd want to implement
    ;; a more efficient way to retrieve recent bids
    (ok { start: start-bid, total: total-bids })
  )
)

;; ===================================
;; CONTRACT INITIALIZATION
;; ===================================

;; Initialize the contract
(begin
  (var-set bid-counter u0)
  (var-set contract-paused false)
)
