
;; title: nft-contract
;; version:
;; summary:
;; description:

;; NFT Ownership and Transfer Contract
;; Implements SIP-009 NFT standard

;; Define the contract owner
(define-constant contract-owner tx-sender)

;; Define error codes
(define-constant err-owner-only (err u100))
(define-constant err-not-token-owner (err u101))
(define-constant err-token-not-found (err u102))
(define-constant err-not-authorized (err u103))

;; Define the NFT token
(define-non-fungible-token nft-token uint)

;; Define royalty percentage (e.g., 5%)
(define-constant royalty-percentage u50)

;; Define maps for token data and ownership
(define-map token-uris {token-id: uint} {uri: (string-ascii 256)})
(define-map token-owners {token-id: uint} {owner: principal})

;; Define variable for last token ID
(define-data-var last-token-id uint u0)

;; SIP-009: Transfer token
(define-public (transfer (token-id uint) (sender principal) (recipient principal))
  (begin
    (asserts! (is-eq tx-sender sender) err-not-authorized)
    (nft-transfer? nft-token token-id sender recipient)
  )
)

;; SIP-009: Get the owner of the specified token ID
(define-read-only (get-owner (token-id uint))
  (ok (unwrap! (nft-get-owner? nft-token token-id) err-token-not-found))
)

;; SIP-009: Get the last token ID
(define-read-only (get-last-token-id)
  (ok (var-get last-token-id))
)

;; SIP-009: Get the token URI
(define-read-only (get-token-uri (token-id uint))
  (ok (get uri (unwrap! (map-get? token-uris {token-id: token-id}) err-token-not-found)))
)

;; Mint new NFT
(define-public (mint (recipient principal) (uri (string-ascii 256)))
  (let
    (
      (token-id (+ (var-get last-token-id) u1))
    )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (try! (nft-mint? nft-token token-id recipient))
    (map-set token-uris {token-id: token-id} {uri: uri})
    (map-set token-owners {token-id: token-id} {owner: recipient})
    (var-set last-token-id token-id)
    (ok token-id)
  )
)

;; Transfer NFT with royalty
(define-public (transfer-with-royalty (token-id uint) (recipient principal) (sale-price uint))
  (let
    (
      (owner (unwrap! (nft-get-owner? nft-token token-id) err-token-not-found))
      (royalty-amount (/ (* sale-price royalty-percentage) u1000))
    )
    (asserts! (is-eq tx-sender owner) err-not-token-owner)
    ;; Transfer royalty to contract owner
    (try! (stx-transfer? royalty-amount tx-sender contract-owner))
    ;; Transfer remaining amount to seller
    (try! (stx-transfer? (- sale-price royalty-amount) tx-sender owner))
    ;; Transfer NFT to new owner
    (try! (nft-transfer? nft-token token-id owner recipient))
    (map-set token-owners {token-id: token-id} {owner: recipient})
    (ok true)
  )
)

;; Get royalty information
(define-read-only (get-royalty-info)
  (ok {percentage: royalty-percentage, recipient: contract-owner})
)
)
