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
(define-constant err-mint-failed (err u105))
(define-constant err-transfer-failed (err u106))
(define-constant err-payment-failed (err u107))

;; Variables
(define-data-var last-token-id uint u0)

;; NFT contract without trait implementation

(define-read-only (get-last-token-id)
  (ok (var-get last-token-id))
)

(define-read-only (get-token-uri (token-id uint))
  (match (map-get? token-metadata token-id)
    metadata (ok (some (get uri metadata)))
    (ok none)
  )
)

(define-read-only (get-owner (token-id uint))
  (ok (nft-get-owner? nft-asset token-id))
)

(define-read-only (get-royalty-info (token-id uint))
  (match (map-get? royalty-settings token-id)
    royalty (ok (some royalty))
    (ok none)
  )
)

;; Internal helper to update token counts safely
(define-private (update-token-counts (from principal) (to principal))
  (let
    (
      (from-count (default-to u0 (map-get? token-count from)))
      (to-count (default-to u0 (map-get? token-count to)))
    )
    ;; Ensure from has tokens to transfer
    (asserts! (> from-count u0) err-not-token-owner)
    ;; Update counts
    (map-set token-count from (- from-count u1))
    (map-set token-count to (+ to-count u1))
    (ok true)
  )
)

;; Mint new NFT
(define-public (mint (recipient principal) (token-uri (string-utf8 256)) (royalty-percentage uint))
  (begin
    ;; Validate royalty percentage (must be between 0 and 50% = 5000 basis points)
    (asserts! (<= royalty-percentage u5000) err-invalid-royalty)
    
    (let
      (
        (token-id (+ (var-get last-token-id) u1))
        (current-count (default-to u0 (map-get? token-count recipient)))
      )
      ;; Mint the NFT
      (unwrap! (nft-mint? nft-asset token-id recipient) err-mint-failed)
      
      ;; Store metadata and royalty info
      (map-set token-metadata token-id {uri: token-uri, creator: tx-sender})
      (map-set royalty-settings token-id {percentage: royalty-percentage, recipient: tx-sender})
      (map-set token-count recipient (+ current-count u1))
      
      ;; Update last token ID
      (var-set last-token-id token-id)
      
      (ok token-id)
    )
  )
)

;; Mint NFT for winning bid (only contract owner)
(define-public (mint-for-winning-bid (recipient principal) (token-uri (string-utf8 256)) (royalty-percentage uint))
  (begin
    ;; Only contract owner can mint for winning bids
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (mint recipient token-uri royalty-percentage)
  )
)

;; Transfer NFT
(define-public (transfer (token-id uint) (sender principal) (recipient principal))
  (begin
    ;; Check if token exists and sender owns it
    (asserts! (is-eq (some sender) (nft-get-owner? nft-asset token-id)) err-not-token-owner)
    ;; Check if sender is the tx-sender (authorization)
    (asserts! (is-eq tx-sender sender) err-unauthorized)
    
    ;; Update token counts
    (unwrap! (update-token-counts sender recipient) err-transfer-failed)
    
    ;; Transfer the NFT
    (unwrap! (nft-transfer? nft-asset token-id sender recipient) err-transfer-failed)
    (ok true)
  )
)

;; Transfer with royalty payment
(define-public (transfer-with-royalty (token-id uint) (sender principal) (recipient principal) (price uint))
  (let
    (
      (royalty-info (unwrap! (map-get? royalty-settings token-id) err-invalid-token))
      (royalty-amount (/ (* price (get percentage royalty-info)) u10000))
      (seller-amount (- price royalty-amount))
      (royalty-recipient (get recipient royalty-info))
    )
    ;; Check if token exists and sender owns it
    (asserts! (is-eq (some sender) (nft-get-owner? nft-asset token-id)) err-not-token-owner)
    ;; Check if sender is the tx-sender
    (asserts! (is-eq tx-sender sender) err-unauthorized)
    ;; Ensure price is sufficient to cover royalty
    (asserts! (>= price royalty-amount) err-invalid-royalty)
    
    ;; Transfer royalty payment to creator (if royalty > 0)
    (if (> royalty-amount u0)
      (unwrap! (stx-transfer? royalty-amount tx-sender royalty-recipient) err-payment-failed)
      true
    )
    
    ;; Transfer remaining amount to seller (if any)
    (if (> seller-amount u0)
      (unwrap! (stx-transfer? seller-amount tx-sender sender) err-payment-failed)
      true
    )
    
    ;; Transfer the NFT
    (unwrap! (transfer token-id sender recipient) err-transfer-failed)
    (ok true)
  )
)

;; Get token count for an address
(define-read-only (get-token-count (owner principal))
  (default-to u0 (map-get? token-count owner))
)

;; Update royalty settings (only creator can update)
(define-public (update-royalty (token-id uint) (new-percentage uint) (new-recipient (optional principal)))
  (begin
    ;; Validate royalty percentage (max 50%)
    (asserts! (<= new-percentage u5000) err-invalid-royalty)
    
    (let
      (
        (metadata (unwrap! (map-get? token-metadata token-id) err-invalid-token))
        (current-royalty (unwrap! (map-get? royalty-settings token-id) err-invalid-token))
        (recipient (default-to (get recipient current-royalty) new-recipient))
      )
      ;; Only creator can update royalty
      (asserts! (is-eq tx-sender (get creator metadata)) err-unauthorized)
      
      ;; Update royalty settings
      (map-set royalty-settings token-id {percentage: new-percentage, recipient: recipient})
      (ok true)
    )
  )
)

;; Get token metadata
(define-read-only (get-token-metadata (token-id uint))
  (map-get? token-metadata token-id)
)

;; Check if token exists
(define-read-only (token-exists (token-id uint))
  (is-some (nft-get-owner? nft-asset token-id))
)