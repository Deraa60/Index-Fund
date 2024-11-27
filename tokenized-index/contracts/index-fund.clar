;; Decentralized Index Fund Contract
;; Implements token management, rebalancing, and fee mechanisms

;; Error codes
(define-constant ERROR-NOT-AUTHORIZED (err u100))
(define-constant ERROR-INVALID-DEPOSIT-AMOUNT (err u101))
(define-constant ERROR-INSUFFICIENT-USER-BALANCE (err u102))
(define-constant ERROR-UNSUPPORTED-TOKEN (err u103))
(define-constant ERROR-REBALANCE-THRESHOLD-NOT-MET (err u104))

;; Constants
(define-constant INDEX-FUND-OWNER tx-sender)
(define-constant ANNUAL-MANAGEMENT-FEE-BASIS-POINTS u30) ;; 0.3% annual management fee
(define-constant PORTFOLIO-REBALANCE-THRESHOLD-BPS u500) ;; 5% deviation threshold
(define-constant MAXIMUM_SUPPORTED_TOKENS u10) ;; Maximum number of tokens in the index

;; Data vars
(define-data-var previous-rebalance-block-height uint u0)
(define-data-var index-fund-total-supply uint u0)
(define-data-var contract-operations-paused bool false)

;; Data maps
(define-map user-token-balances principal uint)
(define-map target-token-allocation-weights (string-ascii 32) uint)
(define-map supported-token-list (string-ascii 32) bool)
(define-map current-token-market-prices (string-ascii 32) uint)

;; Private functions
(define-private (is-index-fund-owner)
    (is-eq tx-sender INDEX-FUND-OWNER))

(define-private (calculate-management-fee (withdrawal-amount uint))
    (let ((blocks-elapsed-since-rebalance (- block-height (var-get previous-rebalance-block-height))))
        (/ (* withdrawal-amount ANNUAL-MANAGEMENT-FEE-BASIS-POINTS blocks-elapsed-since-rebalance) 
           (* u10000 u52560))))

(define-private (get-token-target-weight (token-identifier (string-ascii 32)))
    (default-to u0 (map-get? target-token-allocation-weights token-identifier)))

;; Public functions
(define-public (add-token-to-index (token-identifier (string-ascii 32)) (allocation-weight uint))
    (begin
        (asserts! (is-index-fund-owner) ERROR-NOT-AUTHORIZED)
        (asserts! (< (len (get-supported-tokens)) MAXIMUM_SUPPORTED_TOKENS) ERROR-UNSUPPORTED-TOKEN)
        (map-set supported-token-list token-identifier true)
        (map-set target-token-allocation-weights token-identifier allocation-weight)
        (ok true)))

(define-public (deposit-tokens (token-identifier (string-ascii 32)) (deposit-amount uint))
    (begin
        (asserts! (not (var-get contract-operations-paused)) ERROR-NOT-AUTHORIZED)
        (asserts! (> deposit-amount u0) ERROR-INVALID-DEPOSIT-AMOUNT)
        (asserts! (default-to false (map-get? supported-token-list token-identifier)) ERROR-UNSUPPORTED-TOKEN)
        
        ;; Transfer tokens to contract
        (try! (contract-call? .token-contract transfer deposit-amount tx-sender (as-contract tx-sender)))
        
        ;; Update user balance
        (let ((user-current-balance (default-to u0 (map-get? user-token-balances tx-sender))))
            (map-set user-token-balances tx-sender (+ user-current-balance deposit-amount)))
        
        (var-set index-fund-total-supply (+ (var-get index-fund-total-supply) deposit-amount))
        (ok true)))

(define-public (withdraw-tokens (token-identifier (string-ascii 32)) (withdrawal-amount uint))
    (begin
        (asserts! (not (var-get contract-operations-paused)) ERROR-NOT-AUTHORIZED)
        (asserts! (> withdrawal-amount u0) ERROR-INVALID-DEPOSIT-AMOUNT)
        (asserts! (default-to false (map-get? supported-token-list token-identifier)) ERROR-UNSUPPORTED-TOKEN)
        
        (let ((user-current-balance (default-to u0 (map-get? user-token-balances tx-sender))))
            (asserts! (>= user-current-balance withdrawal-amount) ERROR-INSUFFICIENT-USER-BALANCE)
            
            ;; Calculate and deduct management fee
            (let ((management-fee (calculate-management-fee withdrawal-amount))
                  (net-withdrawal-amount (- withdrawal-amount management-fee)))
                
                ;; Transfer tokens to user
                (try! (as-contract (contract-call? .token-contract transfer 
                    net-withdrawal-amount (as-contract tx-sender) tx-sender)))
                
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
            (asserts! (> total-portfolio-deviation PORTFOLIO-REBALANCE-THRESHOLD-BPS) 
                     ERROR-REBALANCE-THRESHOLD-NOT-MET)
            
            ;; Perform rebalancing
            (var-set previous-rebalance-block-height block-height)
            (try! (execute-portfolio-rebalance))
            (ok true))))

(define-private (calculate-total-portfolio-deviation)
    (let ((supported-tokens (get-supported-tokens)))
        (fold + 
            (map calculate-token-weight-deviation supported-tokens)
            u0)))

(define-private (calculate-token-weight-deviation (token-identifier (string-ascii 32)))
    (let ((target-allocation-weight (get-token-target-weight token-identifier))
          (current-allocation-weight (get-current-token-weight token-identifier)))
        (abs (- target-allocation-weight current-allocation-weight))))

(define-private (execute-portfolio-rebalance)
    (begin
        ;; Implement rebalancing logic here
        ;; This would involve selling/buying tokens to match target weights
        (ok true)))

;; Read-only functions
(define-read-only (get-user-balance (user-address principal))
    (default-to u0 (map-get? user-token-balances user-address)))

(define-read-only (get-token-allocation-weight (token-identifier (string-ascii 32)))
    (get-token-target-weight token-identifier))

(define-read-only (get-supported-tokens)
    (filter supported-token-list (map-keys supported-token-list)))

(define-read-only (get-index-fund-total-supply)
    (var-get index-fund-total-supply))

;; Admin functions
(define-public (update-token-market-price (token-identifier (string-ascii 32)) (market-price uint))
    (begin
        (asserts! (is-index-fund-owner) ERROR-NOT-AUTHORIZED)
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