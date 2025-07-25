
;; title: Nft-onwership
;; version:
;; summary:
;; description:
;; NFT Ownership and Transfer Contract with Royalties
;; This contract implements SIP-009 NFT standard with royalty support

(define-non-fungible-token nft-asset uint)

;; Data storage
(define-map token-metadata uint {uri: (string-utf8 256), creator: principal})
(define-map royalty-settings uint {percentage: uint, recipient: principal})
(define-map token-count principal uint)

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-token-owner (err u101))
(define-constant err-invalid-token (err u102))
(define-constant err-invalid-royalty (err u103))
(define-constant err-unauthorized (err u104))

;; Variables
(define-data-var last-token-id uint u0)

;; SIP-009 NFT trait implementation
(impl-trait 'SP2PABAF9FTAJYNFZH93XENAJ8FVY99RRM50D2JG9.nft-trait.nft-trait)

(define-read-only (get-last-token-id)
  (ok (var-get last-token-id))
)

(define-read-only (get-token-uri (token-id uint))
  (match (map-get? token-metadata token-id)
    metadata (ok (get uri metadata))
    (err err-invalid-token)
  )
)

(define-read-only (get-owner (token-id uint))
  (ok (nft-get-owner? nft-asset token-id))
)

(define-read-only (get-royalty-info (token-id uint))
  (match (map-get? royalty-settings token-id)
    royalty (ok royalty)
    (err err-invalid-token)
  )
)

;; Mint new NFT
(define-public (mint (recipient principal) (token-uri (string-utf8 256)) (royalty-percentage uint))
  (let
    (
      (token-id (+ (var-get last-token-id) u1))
      (current-count (default-to u0 (map-get? token-count recipient)))
    )
    ;; Validate royalty percentage (must be between 0 and 50%)
    (asserts! (<= royalty-percentage u5000) (err err-invalid-royalty))
    
    ;; Mint the NFT
    (try! (nft-mint? nft-asset token-id recipient))
    
    ;; Store metadata and royalty info
    (map-set token-metadata token-id {uri: token-uri, creator: tx-sender})
    (map-set royalty-settings token-id {percentage: royalty-percentage, recipient: tx-sender})
    (map-set token-count recipient (+ current-count u1))
    
    ;; Update last token ID
    (var-set last-token-id token-id)
    
    (ok token-id)
  )
)

;; Mint NFT for winning bid
(define-public (mint-for-winning-bid (recipient principal) (token-uri (string-utf8 256)) (royalty-percentage uint))
  (begin
    ;; Only contract owner can mint for winning bids
    (asserts! (is-eq tx-sender contract-owner) (err err-owner-only))
    (try! (mint recipient token-uri royalty-percentage))
    (ok true)
  )
)

;; Transfer NFT
(define-public (transfer (token-id uint) (sender principal) (recipient principal))
  (begin
    ;; Check if sender is the token owner
    (asserts! (is-eq (some sender) (nft-get-owner? nft-asset token-id)) (err err-not-token-owner))
    ;; Check if sender is the tx-sender or approved
    (asserts! (is-eq tx-sender sender) (err err-unauthorized))
    
    ;; Update token counts
    (let
      (
        (sender-count (default-to u0 (map-get? token-count sender)))
        (recipient-count (default-to u0 (map-get? token-count recipient)))
      )
      (map-set token-count sender (- sender-count u1))
      (map-set token-count recipient (+ recipient-count u1))
    )
    
    ;; Transfer the NFT
    (try! (nft-transfer? nft-asset token-id sender recipient))
    (ok true)
  )
)

;; Transfer with royalty payment
(define-public (transfer-with-royalty (token-id uint) (sender principal) (recipient principal) (price uint))
  (let
    (
      (royalty-info (unwrap! (map-get? royalty-settings token-id) (err err-invalid-token)))
      (royalty-amount (/ (* price (get percentage royalty-info)) u10000))
      (seller-amount (- price royalty-amount))
      (royalty-recipient (get recipient royalty-info))
    )
    ;; Check if sender is the token owner
    (asserts! (is-eq (some sender) (nft-get-owner? nft-asset token-id)) (err err-not-token-owner))
    ;; Check if sender is the tx-sender or approved
    (asserts! (is-eq tx-sender sender) (err err-unauthorized))
    
    ;; Transfer payment with royalty
    (try! (stx-transfer? royalty-amount tx-sender royalty-recipient))
    (try! (stx-transfer? seller-amount tx-sender sender))
    
    ;; Transfer the NFT
    (try! (transfer token-id sender recipient))
    (ok true)
  )
)

;; Get token count for an address
(define-read-only (get-token-count (owner principal))
  (default-to u0 (map-get? token-count owner))
)

;; Update royalty settings (only creator can update)
(define-public (update-royalty (token-id uint) (new-percentage uint) (new-recipient (optional principal)))
  (let
    (
      (metadata (unwrap! (map-get? token-metadata token-id) (err err-invalid-token)))
      (current-royalty (unwrap! (map-get? royalty-settings token-id) (err err-invalid-token)))
      (recipient (default (get recipient current-royalty) new-recipient))
    )
    ;; Only creator can update royalty
    (asserts! (is-eq tx-sender (get creator metadata)) (err err-unauthorized))
    ;; Validate royalty percentage
    (asserts! (<= new-percentage u5000) (err err-invalid-royalty))
    
    ;; Update royalty settings
    (map-set royalty-settings token-id {percentage: new-percentage, recipient: recipient})
    (ok true)
  )
)