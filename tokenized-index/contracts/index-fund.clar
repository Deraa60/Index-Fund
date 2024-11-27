;; Multi-Token Index Fund Smart Contract

;; Define SIP-010 Fungible Token trait
(define-trait sip-010-trait
  (
    ;; Transfer from the caller to a new principal
    (transfer (uint principal principal (optional (buff 34))) (response bool uint))

    ;; The human readable name of the token
    (get-name () (response (string-ascii 32) uint))

    ;; The ticker symbol, or empty if none
    (get-symbol () (response (string-ascii 32) uint))

    ;; The number of decimals used, e.g. 6 would mean 1_000_000 represents 1 token
    (get-decimals () (response uint uint))

    ;; The balance of the passed principal
    (get-balance (principal) (response uint uint))

    ;; The current total supply (which does not need to be a constant)
    (get-total-supply () (response uint uint))

    ;; Optional URI for off-chain metadata
    (get-token-uri () (response (optional (string-utf8 256)) uint))
  )
)

;; Token contract references - using shorter principal format
(define-constant token-contract 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.my-token)

;; Error codes
(define-constant ERROR-NOT-AUTHORIZED (err u100))
(define-constant ERROR-INVALID-DEPOSIT-AMOUNT (err u101))
(define-constant ERROR-INSUFFICIENT-USER-BALANCE (err u102))
(define-constant ERROR-UNSUPPORTED-TOKEN (err u103))
(define-constant ERROR-REBALANCE-THRESHOLD-NOT-MET (err u104))
(define-constant ERROR-REBALANCE-FAILED (err u105))
(define-constant ERROR-INVALID-TOKEN-IDENTIFIER (err u106))
(define-constant ERROR-INVALID-ALLOCATION-WEIGHT (err u107))
(define-constant ERROR-INVALID-MARKET-PRICE (err u108))
(define-constant ERROR-INVALID-TOKEN-CONTRACT (err u109))

;; Constants
(define-constant INDEX-FUND-OWNER tx-sender)
(define-constant ANNUAL-MANAGEMENT-FEE-BASIS-POINTS u30) ;; 0.3% annual management fee
(define-constant PORTFOLIO-REBALANCE-THRESHOLD-BPS u500) ;; 5% deviation threshold
(define-constant MAXIMUM-SUPPORTED-TOKENS u10) ;; Maximum number of tokens in the index

;; Data vars
(define-data-var previous-rebalance-block-height uint u0)
(define-data-var index-fund-total-supply uint u0)
(define-data-var contract-operations-paused bool false)
(define-data-var supported-tokens-list (list 10 (string-ascii 32)) (list))

;; Data maps
(define-map user-token-balances principal uint)
(define-map target-token-allocation-weights (string-ascii 32) uint)
(define-map supported-token-list (string-ascii 32) bool)
(define-map current-token-market-prices (string-ascii 32) uint)
(define-map token-contract-map (string-ascii 32) principal)

;; Private functions
(define-private (absolute-value (n int))
    (if (< n 0)
        (* n -1)
        n))

(define-private (is-index-fund-owner)
    (is-eq tx-sender INDEX-FUND-OWNER))

(define-private (calculate-management-fee (withdrawal-amount uint))
    (let ((blocks-elapsed-since-rebalance (- block-height (var-get previous-rebalance-block-height))))
        (/ (* withdrawal-amount ANNUAL-MANAGEMENT-FEE-BASIS-POINTS blocks-elapsed-since-rebalance) 
           (* u10000 u52560))))

(define-private (get-token-target-weight (token-identifier (string-ascii 32)))
    (default-to u0 (map-get? target-token-allocation-weights token-identifier)))

(define-private (is-token-supported (token-identifier (string-ascii 32)))
    (default-to false (map-get? supported-token-list token-identifier)))

(define-private (get-token-contract (token-identifier (string-ascii 32)))
    (default-to token-contract (map-get? token-contract-map token-identifier)))

;; Public functions
(define-public (add-token-to-index 
    (token-identifier (string-ascii 32)) 
    (allocation-weight uint)
    (token-contract-id <sip-010-trait>))
    (begin
        (asserts! (is-index-fund-owner) ERROR-NOT-AUTHORIZED)
        (asserts! (< (len (var-get supported-tokens-list)) MAXIMUM-SUPPORTED-TOKENS) ERROR-UNSUPPORTED-TOKEN)
        (asserts! (is-none (map-get? supported-token-list token-identifier)) ERROR-INVALID-TOKEN-IDENTIFIER)
        (asserts! (> allocation-weight u0) ERROR-INVALID-ALLOCATION-WEIGHT)
        (asserts! (not (is-eq (contract-of token-contract-id) (as-contract tx-sender))) ERROR-INVALID-TOKEN-CONTRACT)
        (map-set supported-token-list token-identifier true)
        (map-set target-token-allocation-weights token-identifier allocation-weight)
        (map-set token-contract-map token-identifier (contract-of token-contract-id))
        (var-set supported-tokens-list (unwrap! (as-max-len? (append (var-get supported-tokens-list) token-identifier) u10) ERROR-UNSUPPORTED-TOKEN))
        (ok true)))

(define-public (deposit-tokens (token-identifier (string-ascii 32)) (token-contract-instance <sip-010-trait>) (deposit-amount uint))
    (begin
        (asserts! (not (var-get contract-operations-paused)) ERROR-NOT-AUTHORIZED)
        (asserts! (> deposit-amount u0) ERROR-INVALID-DEPOSIT-AMOUNT)
        (asserts! (is-token-supported token-identifier) ERROR-UNSUPPORTED-TOKEN)
        (asserts! (is-eq (contract-of token-contract-instance) (get-token-contract token-identifier)) ERROR-UNSUPPORTED-TOKEN)
        
        ;; Transfer tokens to contract
        (try! (contract-call? token-contract-instance transfer 
            deposit-amount 
            tx-sender 
            (as-contract tx-sender)
            none))  ;; Adding memo parameter as none
        
        ;; Update user balance
        (let ((user-current-balance (default-to u0 (map-get? user-token-balances tx-sender))))
            (map-set user-token-balances tx-sender (+ user-current-balance deposit-amount)))
        
        (var-set index-fund-total-supply (+ (var-get index-fund-total-supply) deposit-amount))
        (ok true)))

(define-public (withdraw-tokens (token-identifier (string-ascii 32)) (token-contract-instance <sip-010-trait>) (withdrawal-amount uint))
    (begin
        (asserts! (not (var-get contract-operations-paused)) ERROR-NOT-AUTHORIZED)
        (asserts! (> withdrawal-amount u0) ERROR-INVALID-DEPOSIT-AMOUNT)
        (asserts! (is-token-supported token-identifier) ERROR-UNSUPPORTED-TOKEN)
        (asserts! (is-eq (contract-of token-contract-instance) (get-token-contract token-identifier)) ERROR-UNSUPPORTED-TOKEN)
        
        (let ((user-current-balance (default-to u0 (map-get? user-token-balances tx-sender))))
            (asserts! (>= user-current-balance withdrawal-amount) ERROR-INSUFFICIENT-USER-BALANCE)
            
            ;; Calculate and deduct management fee
            (let ((management-fee (calculate-management-fee withdrawal-amount))
                  (net-withdrawal-amount (- withdrawal-amount management-fee)))
                
                ;; Transfer tokens to user
                (try! (as-contract (contract-call? token-contract-instance transfer 
                    net-withdrawal-amount 
                    (as-contract tx-sender) 
                    tx-sender
                    none)))  ;; Adding memo parameter as none
                
                ;; Update balances
                (map-set user-token-balances tx-sender (- user-current-balance withdrawal-amount))
                (var-set index-fund-total-supply (- (var-get index-fund-total-supply) withdrawal-amount))
                (ok true)))))

(define-public (rebalance-portfolio)
    (begin
        (asserts! (not (var-get contract-operations-paused)) ERROR-NOT-AUTHORIZED)
        (asserts! (is-index-fund-owner) ERROR-NOT-AUTHORIZED)
        
        ;; Check if rebalancing is needed
        (let ((total-portfolio-deviation (calculate-total-portfolio-deviation)))
            (if (> total-portfolio-deviation PORTFOLIO-REBALANCE-THRESHOLD-BPS)
                (begin
                    (var-set previous-rebalance-block-height block-height)
                    (execute-portfolio-rebalance))
                ERROR-REBALANCE-THRESHOLD-NOT-MET))))

(define-private (calculate-total-portfolio-deviation)
    (let ((supported-tokens (var-get supported-tokens-list)))
        (fold + 
            (map calculate-token-weight-deviation supported-tokens)
            u0)))

(define-private (calculate-token-weight-deviation (token-identifier (string-ascii 32)))
    (let ((target-allocation-weight (get-token-target-weight token-identifier))
          (current-allocation-weight (get-current-token-weight token-identifier)))
        (to-uint (absolute-value (- (to-int target-allocation-weight) (to-int current-allocation-weight))))))

(define-private (get-current-token-weight (token-identifier (string-ascii 32)))
    (let ((token-price (default-to u0 (map-get? current-token-market-prices token-identifier)))
          (token-balance (default-to u0 (map-get? user-token-balances tx-sender))))
        (/ (* token-balance token-price) (var-get index-fund-total-supply))))

(define-private (execute-portfolio-rebalance)
    (begin
        (ok true)))

;; Read-only functions
(define-read-only (get-user-balance (user-address principal))
    (default-to u0 (map-get? user-token-balances user-address)))

(define-read-only (get-token-allocation-weight (token-identifier (string-ascii 32)))
    (get-token-target-weight token-identifier))

(define-read-only (get-supported-tokens)
    (var-get supported-tokens-list))

(define-read-only (get-index-fund-total-supply)
    (var-get index-fund-total-supply))

;; Admin functions
(define-public (update-token-market-price (token-identifier (string-ascii 32)) (market-price uint))
    (begin
        (asserts! (is-index-fund-owner) ERROR-NOT-AUTHORIZED)
        (asserts! (is-token-supported token-identifier) ERROR-UNSUPPORTED-TOKEN)
        (asserts! (> market-price u0) ERROR-INVALID-MARKET-PRICE)
        (map-set current-token-market-prices token-identifier market-price)
        (ok true)))

(define-public (pause-contract-operations)
    (begin
        (asserts! (is-index-fund-owner) ERROR-NOT-AUTHORIZED)
        (var-set contract-operations-paused true)
        (ok true)))

(define-public (resume-contract-operations)
    (begin
        (asserts! (is-index-fund-owner) ERROR-NOT-AUTHORIZED)
        (var-set contract-operations-paused false)
        (ok true)))