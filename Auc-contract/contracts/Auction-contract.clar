;; auction-contract.clar
;; Comprehensive auction system supporting multiple auction types and features

;; Constants and Error Codes
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-invalid-auction (err u101))
(define-constant err-auction-ended (err u102))
(define-constant err-auction-not-started (err u103))
(define-constant err-bid-too-low (err u104))
(define-constant err-invalid-duration (err u105))
(define-constant err-auction-not-ended (err u106))
(define-constant err-already-claimed (err u107))
(define-constant err-unauthorized (err u108))
(define-constant err-invalid-price (err u109))
(define-constant err-flash-auction-expired (err u110))
(define-constant err-low-balance (err u111))

;; Data Variables
(define-data-var minimum-duration uint u300) ;; 5 minutes minimum
(define-data-var maximum-duration uint u604800) ;; 1 week maximum
(define-data-var minimum-bid-increment uint u1000000) ;; Minimum bid increment (in micro-STX)
(define-data-var flash-auction-duration uint u300) ;; 5 minutes for flash auctions

;; Auction Types
(define-constant AUCTION-TYPE-ENGLISH u1)
(define-constant AUCTION-TYPE-DUTCH u2)
(define-constant AUCTION-TYPE-FLASH u3)

;; Auction Status
(define-constant STATUS-ACTIVE u1)
(define-constant STATUS-ENDED u2)
(define-constant STATUS-CLAIMED u3)

;; Auction Data Structure
(define-map auctions uint {
    auction-type: uint,
    seller: principal,
    start-time: uint,
    end-time: uint,
    start-price: uint,
    current-price: uint,
    min-price: uint,
    highest-bidder: (optional principal),
    highest-bid: uint,
    status: uint,
    item-id: uint,
    auto-bid-enabled: bool,
    price-decrement: uint  ;; For Dutch auctions
})

;; Proxy Bidding Data
(define-map proxy-bids { auction-id: uint, bidder: principal } {
    max-bid: uint,
    auto-increment: uint
})

;; Auction Counter
(define-data-var auction-counter uint u0)

;; Price Adjustment Data
(define-map price-adjustments uint {
    last-adjustment: uint,
    adjustment-rate: uint,
    min-price: uint
})

;; Bid History
(define-map bid-history uint (list 50 {
    bidder: principal,
    amount: uint,
    time: uint
}))

;; Private Functions

(define-private (validate-auction-duration (duration uint))
    (let (
        (min-duration (var-get minimum-duration))
        (max-duration (var-get maximum-duration))
    )
    (and (>= duration min-duration) (<= duration max-duration))))

(define-private (validate-bid (auction-id uint) (bid-amount uint))
    (let (
        (auction (unwrap-panic (map-get? auctions auction-id)))
        (current-time (unwrap-panic (get-block-info? time u0)))
        (min-increment (var-get minimum-bid-increment))
    )
    (and 
        (is-eq (get status auction) STATUS-ACTIVE)
        (>= bid-amount (+ (get highest-bid auction) min-increment))
        (>= bid-amount (get min-price auction))
        (< current-time (get end-time auction))
        (>= current-time (get start-time auction)))))

(define-private (record-bid (auction-id uint) (bidder principal) (amount uint))
    (let (
        (current-time (unwrap-panic (get-block-info? time u0)))
        (current-history (default-to (list) (map-get? bid-history auction-id)))
        (new-bid {
            bidder: bidder,
            amount: amount,
            time: current-time
        })
    )
    (map-set bid-history
        auction-id
        (unwrap-panic (as-max-len? (append current-history new-bid) u50)))))

(define-private (calculate-dutch-price (auction-id uint))
    (let (
        (auction (unwrap-panic (map-get? auctions auction-id)))
        (current-time (unwrap-panic (get-block-info? time u0)))
        (time-elapsed (- current-time (get start-time auction)))
        (price-drop (* time-elapsed (get price-decrement auction)))
        (calculated-price (- (get start-price auction) price-drop))
    )
    (if (< calculated-price (get min-price auction))
        (get min-price auction)
        calculated-price)))

(define-private (check-and-process-auto-bids (auction-id uint))
    (let (
        (auction (unwrap-panic (map-get? auctions auction-id)))
    )
    (if (get auto-bid-enabled auction)
        (process-auto-bids auction-id)
        true)))

(define-private (process-auto-bids (auction-id uint))
    (let (
        (auction (unwrap-panic (map-get? auctions auction-id)))
        (current-price (get current-price auction))
    )
    true)) ;; Implement auto-bid logic here

;; Public Functions

;; Create Auction
(define-public (create-auction (
        auction-type uint)
        (duration uint)
        (start-price uint)
        (min-price uint)
        (item-id uint)
        (auto-bid-enabled bool))
    (let (
        (auction-id (+ (var-get auction-counter) u1))
        (current-time (unwrap! (get-block-info? time u0) (err err-invalid-auction)))
        (end-time (+ current-time duration))
        (price-decrement (if (is-eq auction-type AUCTION-TYPE-DUTCH)
            (/ (- start-price min-price) duration)
            u0))
    )
    (asserts! (validate-auction-duration duration) (err err-invalid-duration))
    (asserts! (> start-price u0) (err err-invalid-price))
    (asserts! (<= min-price start-price) (err err-invalid-price))
    
    (map-set auctions auction-id {
        auction-type: auction-type,
        seller: tx-sender,
        start-time: current-time,
        end-time: end-time,
        start-price: start-price,
        current-price: start-price,
        min-price: min-price,
        highest-bidder: none,
        highest-bid: u0,
        status: STATUS-ACTIVE,
        item-id: item-id,
        auto-bid-enabled: auto-bid-enabled,
        price-decrement: price-decrement
    })
    
    (var-set auction-counter auction-id)
    (ok auction-id)))

;; Place Bid
(define-public (place-bid (auction-id uint) (bid-amount uint))
    (let (
        (auction (unwrap! (map-get? auctions auction-id) (err err-invalid-auction)))
    )
    (asserts! (validate-bid auction-id bid-amount) (err err-bid-too-low))
    
    ;; Update auction
    (map-set auctions auction-id (merge auction {
        highest-bidder: (some tx-sender),
        highest-bid: bid-amount,
        current-price: bid-amount
    }))
    
    ;; Record bid in history
    (record-bid auction-id tx-sender bid-amount)
    
    ;; Process auto-bids if enabled
    (check-and-process-auto-bids auction-id)
    
    (ok true)))

;; Set Auto-Bid
(define-public (set-auto-bid (auction-id uint) (max-bid uint) (increment uint))
    (let (
        (auction (unwrap! (map-get? auctions auction-id) (err err-invalid-auction)))
    )
    (asserts! (get auto-bid-enabled auction) (err err-unauthorized))
    (asserts! (>= max-bid (+ (get current-price auction) increment)) (err err-bid-too-low))
    
    (map-set proxy-bids { auction-id: auction-id, bidder: tx-sender } {
        max-bid: max-bid,
        auto-increment: increment
    })
    (ok true)))

;; End Auction
(define-public (end-auction (auction-id uint))
    (let (
        (auction (unwrap! (map-get? auctions auction-id) (err err-invalid-auction)))
        (current-time (unwrap! (get-block-info? time u0) (err err-invalid-auction)))
    )
    (asserts! (or 
        (>= current-time (get end-time auction))
        (is-eq tx-sender (get seller auction))) (err err-auction-not-ended))
    (asserts! (is-eq (get status auction) STATUS-ACTIVE) (err err-auction-ended))
    
    (map-set auctions auction-id (merge auction {
        status: STATUS-ENDED,
        current-price: (if (is-eq (get auction-type auction) AUCTION-TYPE-DUTCH)
            (calculate-dutch-price auction-id)
            (get current-price auction))
    }))
    (ok true)))

;; Claim Item
(define-public (claim-item (auction-id uint))
    (let (
        (auction (unwrap! (map-get? auctions auction-id) (err err-invalid-auction)))
    )
    (asserts! (is-eq (get status auction) STATUS-ENDED) (err err-auction-not-ended))
    (asserts! (is-eq (some tx-sender) (get highest-bidder auction)) (err err-unauthorized))
    
    (map-set auctions auction-id (merge auction {
        status: STATUS-CLAIMED
    }))
    (ok true)))

;; Create Flash Auction
(define-public (create-flash-auction (
        start-price uint)
        (min-price uint)
        (item-id uint))
    (let (
        (duration (var-get flash-auction-duration))
    )
    (try! (create-auction AUCTION-TYPE-FLASH duration start-price min-price item-id true))
    (ok true)))

;; Read-Only Functions

(define-read-only (get-auction (auction-id uint))
    (map-get? auctions auction-id))

(define-read-only (get-current-price (auction-id uint))
    (let (
        (auction (unwrap! (map-get? auctions auction-id) (err err-invalid-auction)))
    )
    (ok (if (is-eq (get auction-type auction) AUCTION-TYPE-DUTCH)
        (calculate-dutch-price auction-id)
        (get current-price auction)))))

(define-read-only (get-auto-bid (auction-id uint) (bidder principal))
    (map-get? proxy-bids { auction-id: auction-id, bidder: bidder }))

(define-read-only (get-auction-status (auction-id uint))
    (ok (get status (unwrap! (map-get? auctions auction-id) (err err-invalid-auction)))))

(define-read-only (get-bid-history (auction-id uint))
    (default-to (list) (map-get? bid-history auction-id)))

(define-read-only (get-auction-time-remaining (auction-id uint))
    (let (
        (auction (unwrap! (map-get? auctions auction-id) (err err-invalid-auction)))
        (current-time (unwrap! (get-block-info? time u0) (err err-invalid-auction)))
    )
    (if (>= current-time (get end-time auction))
        (ok u0)
        (ok (- (get end-time auction) current-time)))))