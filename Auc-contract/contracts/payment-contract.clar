;; Payment and Escrow Contract
;; Handles auctions, payments, fees, royalties, and rewards

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant PLATFORM_FEE u050) ;; 5% platform fee
(define-constant MIN_ESCROW_AMOUNT u1000000) ;; Minimum amount for escrow
(define-constant REFERRAL_REWARD_RATE u010) ;; 1% referral reward

;; Error codes
(define-constant ERR_UNAUTHORIZED u1)
(define-constant ERR_INVALID_AMOUNT u2)
(define-constant ERR_INSUFFICIENT_FUNDS u3)
(define-constant ERR_AUCTION_INACTIVE u4)
(define-constant ERR_INVALID_TOKEN u5)

;; Data maps
(define-map auctions
    { auction-id: uint }
    {
        seller: principal,
        highest-bid: uint,
        highest-bidder: (optional principal),
        end-block: uint,
        token-type: (string-ascii 10),
        status: (string-ascii 10),
        escrow-amount: uint
    }
)

(define-map user-balances
    { user: principal, token: (string-ascii 10) }
    { balance: uint }
)

(define-map referral-info
    { user: principal }
    {
        referrer: (optional principal),
        total-rewards: uint
    }
)

(define-map lending-positions
    { user: principal }
    {
        borrowed-amount: uint,
        collateral-amount: uint,
        loan-start: uint,
        interest-rate: uint
    }
)

;; Public functions

;; Create new auction
(define-public (create-auction (auction-id uint) (end-block uint) (token-type (string-ascii 10)) (min-bid uint))
    (let
        (
            (seller tx-sender)
        )
        (asserts! (> end-block block-height) (err ERR_INVALID_AMOUNT))
        (map-set auctions
            { auction-id: auction-id }
            {
                seller: seller,
                highest-bid: min-bid,
                highest-bidder: none,
                end-block: end-block,
                token-type: token-type,
                status: "active",
                escrow-amount: u0
            }
        )
        (ok true)
    )
)

;; Place bid
(define-public (place-bid (auction-id uint) (bid-amount uint))
    (let
        (
            (auction (unwrap! (map-get? auctions { auction-id: auction-id }) (err ERR_AUCTION_INACTIVE)))
            (bidder tx-sender)
        )
        (asserts! (> bid-amount (get highest-bid auction)) (err ERR_INVALID_AMOUNT))
        (asserts! (< block-height (get end-block auction)) (err ERR_AUCTION_INACTIVE))
        
        ;; Handle escrow
        (try! (process-escrow auction-id bid-amount bidder))
        
        ;; Update auction
        (map-set auctions
            { auction-id: auction-id }
            (merge auction {
                highest-bid: bid-amount,
                highest-bidder: (some bidder)
            })
        )
        (ok true)
    )
)

;; Process escrow
(define-private (process-escrow (auction-id uint) (amount uint) (bidder principal))
    (let
        (
            (auction (unwrap! (map-get? auctions { auction-id: auction-id }) (err ERR_AUCTION_INACTIVE)))
            (platform-fee (mul-down amount PLATFORM_FEE))
        )
        ;; Transfer funds to escrow
        (try! (stx-transfer? amount bidder (as-contract tx-sender)))
        
        ;; Update escrow amount
        (map-set auctions
            { auction-id: auction-id }
            (merge auction {
                escrow-amount: (+ (get escrow-amount auction) amount)
            })
        )
        (ok true)
    )
)

;; Finalize auction
(define-public (finalize-auction (auction-id uint))
    (let
        (
            (auction (unwrap! (map-get? auctions { auction-id: auction-id }) (err ERR_AUCTION_INACTIVE)))
            (winner (unwrap! (get highest-bidder auction) (err ERR_INVALID_AMOUNT)))
            (final-amount (get highest-bid auction))
            (platform-fee (mul-down final-amount PLATFORM_FEE))
            (seller-amount (- final-amount platform-fee))
        )
        (asserts! (>= block-height (get end-block auction)) (err ERR_AUCTION_INACTIVE))
        
        ;; Transfer funds from escrow
        (try! (as-contract (stx-transfer? platform-fee tx-sender CONTRACT_OWNER)))
        (try! (as-contract (stx-transfer? seller-amount tx-sender (get seller auction))))
        
        ;; Process referral rewards if applicable
        (try! (process-referral-reward winner final-amount))
        
        ;; Update auction status
        (map-set auctions
            { auction-id: auction-id }
            (merge auction {
                status: "completed"
            })
        )
        (ok true)
    )
)

;; Lending functions

;; Take loan
(define-public (take-loan (amount uint) (collateral uint))
    (let
        (
            (borrower tx-sender)
            (interest-rate u050) ;; 5% interest rate
        )
        (asserts! (>= (* collateral u2) amount) (err ERR_INSUFFICIENT_FUNDS))
        
        ;; Transfer collateral
        (try! (stx-transfer? collateral borrower (as-contract tx-sender)))
        
        ;; Record loan
        (map-set lending-positions
            { user: borrower }
            {
                borrowed-amount: amount,
                collateral-amount: collateral,
                loan-start: block-height,
                interest-rate: interest-rate
            }
        )
        
        ;; Transfer loan amount
        (try! (as-contract (stx-transfer? amount tx-sender borrower)))
        (ok true)
    )
)

;; Repay loan
(define-public (repay-loan)
    (let
        (
            (borrower tx-sender)
            (loan (unwrap! (map-get? lending-positions { user: borrower }) (err ERR_INVALID_AMOUNT)))
            (interest (calculate-interest (get borrowed-amount loan) (get interest-rate loan) (- block-height (get loan-start loan))))
            (total-repayment (+ (get borrowed-amount loan) interest))
        )
        ;; Transfer repayment
        (try! (stx-transfer? total-repayment borrower (as-contract tx-sender)))
        
        ;; Return collateral
        (try! (as-contract (stx-transfer? (get collateral-amount loan) tx-sender borrower)))
        
        ;; Clear loan
        (map-delete lending-positions { user: borrower })
        (ok true)
    )
)

;; Referral functions

;; Register referral
(define-public (register-referral (referrer principal))
    (let
        (
            (user tx-sender)
        )
        (map-set referral-info
            { user: user }
            {
                referrer: (some referrer),
                total-rewards: u0
            }
        )
        (ok true)
    )
)


;; Process referral reward
(define-private (process-referral-reward (user principal) (amount uint))
    (let
        (
            (referral (map-get? referral-info { user: user }))
            (reward-amount (mul-down amount REFERRAL_REWARD_RATE))
        )
        (match referral
            referral-data (match (get referrer referral-data)
                referrer-principal (begin
                    (try! (as-contract (stx-transfer? reward-amount tx-sender referrer-principal)))
                    (ok true)
                )
                (ok true)  ;; No referrer case
            )
            (ok true)  ;; No referral data case
        )
    )
)


;; Helper functions

;; Calculate interest
(define-private (calculate-interest (principal uint) (rate uint) (blocks uint))
    (let
        (
            (interest-per-block (mul-down principal (div-down rate u10000)))
        )
        (* interest-per-block blocks)
    )
)

;; Multiply with decimal
(define-private (mul-down (a uint) (b uint))
    (/ (* a b) u1000)
)

;; Divide with decimal
(define-private (div-down (a uint) (b uint))
    (* a (/ u1000 b))
)